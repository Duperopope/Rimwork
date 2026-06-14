<#
DOWN HERE - ETAT CONSOLIDE (Phase 3).

Aujourd'hui l'etat du systeme est eparpille dans une dizaine de fichiers
(health.json, current_item.json, mode.json, stack_state.txt, game.pid, le
DEV_LOG, le ROADMAP, l'historique git...). Ce module fournit UNE seule vue
structuree et documentee : Get-DownHereState.

Consomme par le dashboard (endpoint /state.json) et utilisable en CLI pour
voir l'etat reel en un coup d'oeil :
    . scripts/lib/State.ps1; Get-DownHereState | ConvertTo-Json -Depth 6
#>

. "$PSScriptRoot\Modes.ps1"   # charge aussi Config

function Get-DownHereState {
    param($Config = (Get-DownHereConfig))

    $logs = $Config.Paths.Logs

    # --- helpers locaux ---
    $readJson = {
        param($p)
        try { Get-Content $p -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null }
    }

    # --- LLM vivant ? ---
    $llmAlive = $false
    try {
        $r = Invoke-WebRequest "$($Config.Llm.BaseUrl)$($Config.Llm.HealthPath)" -UseBasicParsing -TimeoutSec 3
        $llmAlive = ($r.StatusCode -eq 200 -and $r.Content -match 'ok' -and $r.Content -notmatch 'error')
    } catch {}

    # --- jeu lance ? ---
    $game = @{ running = $false; pid = $null }
    try {
        $gpid = (Get-Content (Join-Path $Config.Paths.Scripts 'game.pid') -Raw -ErrorAction Stop).Trim()
        if ($gpid -and (Get-Process -Id ([int]$gpid) -ErrorAction SilentlyContinue)) {
            $game = @{ running = $true; pid = [int]$gpid }
        }
    } catch {}

    # --- agents en cours (par la machine a modes) ---
    $agents = [ordered]@{}
    $defs = Get-ModeAgents -Config $Config
    foreach ($name in $defs.Keys) { $agents[$name] = [bool](Test-AgentRunning -Match $defs[$name].Match) }

    # --- roadmap ---
    $roadmap = @{ done = 0; todo = 0; pct = 0 }
    try {
        $rm = Get-Content $Config.Paths.Roadmap -ErrorAction Stop
        $done = @($rm | Select-String '^\s*-\s*\[x\]').Count
        $todo = @($rm | Select-String '^\s*-\s*\[ \]').Count
        $tot = [Math]::Max(1, $done + $todo)
        $roadmap = @{ done = $done; todo = $todo; pct = [math]::Round($done * 100 / $tot) }
    } catch {}

    # --- dev log (rendement du dev IA) ---
    $devlog = @{ kept = 0; reverted = 0 }
    try {
        $dl = Get-Content $Config.Paths.DevLog -ErrorAction Stop
        $devlog = @{
            kept     = @($dl | Select-String 'KEPT|DONE').Count
            reverted = @($dl | Select-String 'REVERTED').Count
        }
    } catch {}

    # --- stack state (pause/run) ---
    $stack = "RUNNING"
    try { $stack = (Get-Content (Join-Path $logs 'stack_state.txt') -Raw -ErrorAction Stop).Trim() } catch {}

    # --- derniers commits ---
    $commits = @()
    try {
        $commits = @(git -C $Config.Root log -5 --format="%h %s" 2>$null)
    } catch {}

    return [pscustomobject]@{
        timestamp   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        mode        = Get-DownHereMode -Config $Config
        stackState  = $stack
        llmAlive    = $llmAlive
        game        = $game
        agents      = $agents
        roadmap     = $roadmap
        devlog      = $devlog
        health      = (& $readJson (Join-Path $logs 'health.json'))
        currentTask = (& $readJson (Join-Path $logs 'current_item.json'))
        lastCommits = $commits
        brain       = $(
            $cs = & $readJson (Join-Path $logs 'wm_champion_spec.json')
            if ($cs) { @{ model = $cs.spec.model; features = @($cs.spec.features).Count; utility = $cs.utility; gain = $cs.gain; gens = $cs.gens } } else { $null }
        )
    }
}

# Phase 7 (substrat world-model) : enregistre un snapshot d'etat en JSONL.
# Une serie temporelle de snapshots = la matiere premiere pour, plus tard,
# entrainer un modele PREDICTIF de l'etat du jeu (vision JEPA). Ce n'est PAS
# le modele : c'est la collecte de donnees honnete qui le rendra possible.
function Add-StateSnapshot {
    param($Config = (Get-DownHereConfig))
    $file = Join-Path $Config.Paths.Logs 'state_history.jsonl'
    (Get-DownHereState -Config $Config) | ConvertTo-Json -Depth 6 -Compress |
        Add-Content -Path $file -Encoding utf8
    return $file
}
