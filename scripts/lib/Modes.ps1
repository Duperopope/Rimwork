<#
DOWN HERE - Machine a MODES (Phase 2).

Garantit que les agents autonomes ne tournent JAMAIS tous en meme temps.
Un seul MODE actif a la fois (le jeu et le dev ne cohabitent pas) :

  IDLE   -> rien d'autonome (session superviseur)
  DEV    -> le dev IA code le jeu (jeu FERME)         : dev_loop_watchdog
  PLAY   -> l'agent JOUE (jeu OUVERT)                 : game_watchdog + play_agent
  ARENA  -> selection naturelle des LLM (swap modele) : model_arena

Infra TOUJOURS up (hors machine a modes) : llama-server (WSL) + dashboard.

Ce fichier = pure logique + helpers. L'orchestrateur (orchestrator.ps1)
applique en boucle. Le dashboard / set-mode.ps1 ecrivent le mode voulu.
#>

. "$PSScriptRoot\Config.ps1"

# Agents geres par la machine a modes. 'match' = motif sur la CommandLine
# (detecte ET arrete l'agent + ses enfants). 'modes' = ou il doit tourner.
function Get-ModeAgents {
    param($Config = (Get-DownHereConfig))
    return [ordered]@{
        dev   = @{ Match = 'dev_loop';      Script = 'dev_loop_watchdog.ps1'; Args = @();          Modes = @('DEV') }
        game  = @{ Match = 'game_watchdog'; Script = 'game_watchdog.ps1';     Args = @();          Modes = @('PLAY'); KillGame = $true }
        play  = @{ Match = 'play_agent';    Script = 'play_agent.ps1';        Args = @();          Modes = @('PLAY') }
        arena = @{ Match = 'model_arena';   Script = 'model_arena.ps1';       Args = @('-Forever'); Modes = @('ARENA') }
        evolve = @{ Match = 'self_evolve';  Script = 'self_evolve.ps1';       Args = @('-Loop');    Modes = @('EVOLVE') }
        brain  = @{ Match = 'recurse.*Loop'; Script = 'recurse.ps1';          Args = @('-Loop', '-IntervalMin', '5'); Modes = @('EVOLVE') }
    }
}

function Get-DownHereMode {
    param($Config = (Get-DownHereConfig))
    try {
        $m = (Get-Content $Config.ModeFile -Raw -ErrorAction Stop | ConvertFrom-Json).mode
        if ($Config.Modes -contains $m) { return $m }
    } catch {}
    return 'DEV'   # defaut: on continue a developper (jeu ferme), pas tout a la fois
}

function Set-DownHereMode {
    param(
        [Parameter(Mandatory)][string]$Mode,
        $Config = (Get-DownHereConfig)
    )
    $Mode = $Mode.ToUpper()
    if ($Config.Modes -notcontains $Mode) {
        throw "Mode inconnu '$Mode'. Valides: $($Config.Modes -join ', ')"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $Config.ModeFile) | Out-Null
    @{ mode = $Mode; since = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") } |
        ConvertTo-Json -Compress | Set-Content -Path $Config.ModeFile -Encoding utf8
    return $Mode
}

function Test-AgentRunning {
    param([string]$Match)
    $procs = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match $Match }
    return [bool]$procs
}

function Stop-Agent {
    param([hashtable]$Agent)
    Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match $Agent.Match } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($Agent.KillGame) { Stop-GameProcesses }
}

function Stop-GameProcesses {
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(godot|Thrive|Rimwork)' } |
        ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
}

function Start-Agent {
    param([hashtable]$Agent, $Config = (Get-DownHereConfig))
    $path = Join-Path $Config.Paths.Scripts $Agent.Script
    $argList = @('-NoProfile', '-File', $path) + $Agent.Args
    Start-Process pwsh -ArgumentList $argList -WindowStyle Hidden
}

# Coeur: aligne les processus en cours sur le MODE voulu. Retourne la liste des
# actions (START/STOP). -DryRun = calcule et logue SANS rien lancer/arreter
# (utile pour tester la logique).
function Invoke-ModeReconcile {
    param(
        [string]$Mode = (Get-DownHereMode),
        [switch]$DryRun,
        $Config = (Get-DownHereConfig)
    )
    $Mode = $Mode.ToUpper()
    $agents = Get-ModeAgents -Config $Config
    $actions = New-Object System.Collections.Generic.List[string]

    foreach ($name in $agents.Keys) {
        $a = $agents[$name]
        $should = $a.Modes -contains $Mode
        $running = Test-AgentRunning -Match $a.Match
        if ($should -and -not $running) {
            $actions.Add("START $name")
            if (-not $DryRun) { Start-Agent -Agent $a -Config $Config }
        }
        elseif ($running -and -not $should) {
            $actions.Add("STOP $name")
            if (-not $DryRun) { Stop-Agent -Agent $a }
        }
    }

    # Hors PLAY, le jeu ne doit jamais tourner (il partage les 16 Go GPU et
    # affame le LLM). Filet de securite contre un godot orphelin.
    if ($Mode -ne 'PLAY') {
        $game = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(godot|Thrive|Rimwork)' }
        if ($game) {
            $actions.Add("STOP game-orphan")
            if (-not $DryRun) { Stop-GameProcesses }
        }
    }

    return $actions
}
