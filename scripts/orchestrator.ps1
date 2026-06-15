<#
DOWN HERE - ORCHESTRATEUR (Phase 2) : l'AUTORITE UNIQUE.

Remplace le lancement "tout en meme temps" de l'ancien startup_all. Lit en
boucle le MODE voulu (scripts/logs/mode.json, ecrit par le dashboard /
set-mode.ps1) et aligne les processus dessus : demarre ce qui doit tourner,
arrete le reste. Garantit qu'un seul mode est actif a la fois.

  pwsh -File orchestrator.ps1            # boucle (defaut)
  pwsh -File orchestrator.ps1 -Once      # une seule reconciliation
  pwsh -File orchestrator.ps1 -DryRun    # logue les actions SANS rien toucher
#>

param(
    [switch]$Once,
    [switch]$DryRun,
    [int]$PollSeconds = 5
)

. "$PSScriptRoot\lib\Modes.ps1"
. "$PSScriptRoot\lib\State.ps1"
. "$PSScriptRoot\lib\Llm.ps1"
$cfg = Get-DownHereConfig
$log = Join-Path $cfg.Paths.Logs 'orchestrator.log'
New-Item -ItemType Directory -Force -Path $cfg.Paths.Logs | Out-Null

function Write-OrchLog([string]$m) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m"
    Add-Content -Path $log -Value $line
    Write-Host $line
}

# Le serveur de prod (port 1234) repond-il vraiment ? (distingue llama-server WSL
# d'un LM Studio qui squatte le port en repondant une erreur).
function Test-LlmUp {
    try {
        $r = Invoke-WebRequest "$($cfg.Llm.BaseUrl)$($cfg.Llm.HealthPath)" -UseBasicParsing -TimeoutSec 4
        return ($r.StatusCode -eq 200 -and $r.Content -match 'ok' -and $r.Content -notmatch 'error')
    } catch { return $false }
}

# SELF-GUARD: une seule instance (deux orchestrateurs se battraient pour
# demarrer/arreter les memes agents en boucle).
$me = $PID
$twins = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'orchestrator' -and $_.ProcessId -ne $me }
if ($twins -and -not $Once -and -not $DryRun) {
    Write-Host "Un orchestrateur tourne deja (pid $($twins[0].ProcessId)) - sortie."
    exit 0
}

Write-OrchLog "Orchestrateur demarre (DryRun=$DryRun, Once=$Once)."
$lastMode = $null
$tick = 0
$lastLlmTry = [datetime]::MinValue

while ($true) {
    $mode = Get-DownHereMode -Config $cfg
    if ($mode -ne $lastMode) { Write-OrchLog "MODE = $mode"; $lastMode = $mode }

    $actions = Invoke-ModeReconcile -Mode $mode -DryRun:$DryRun -Config $cfg
    foreach ($a in $actions) { Write-OrchLog "  $(if($DryRun){'[dry] '})$a" }

    if ($Once -or $DryRun) { break }

    # WATCHDOG LLM : la prod (port 1234, modele champion) doit revenir TOUTE SEULE.
    # ARENA gere ses propres modeles (swap legitime pour benchmarker) -> on n'y
    # touche pas. PAUSED = stop explicite de l'utilisateur -> on respecte. Sinon,
    # si le serveur ne repond pas, on le relance. Cooldown 180s > temps de
    # chargement (~1-2 min) pour ne pas en lancer un 2e pendant qu'il charge.
    if ($mode -ne 'ARENA') {
        $paused = $false
        try { $paused = ((Get-Content (Join-Path $cfg.Paths.Logs 'stack_state.txt') -Raw -ErrorAction Stop).Trim() -eq 'PAUSED') } catch {}
        if (-not $paused -and -not (Test-LlmUp) -and ((Get-Date) - $lastLlmTry).TotalSeconds -gt 180) {
            Write-OrchLog "WATCHDOG: LLM prod hors ligne en mode $mode -> relance (self-heal)."
            try { Start-LlamaServer -Model (Get-DownHereChampion -Config $cfg) } catch { Write-OrchLog "  echec relance LLM: $_" }
            $lastLlmTry = Get-Date
        }
    }

    # Phase 7 (substrat world-model): un snapshot d'etat ~chaque minute
    # (PollSeconds=5 -> 12 ticks) dans logs/state_history.jsonl.
    $tick++
    if ($tick % 12 -eq 0) { try { Add-StateSnapshot -Config $cfg | Out-Null } catch {} }

    # RSI : re-entrainement recursif du world model ~toutes les 30 min, en DEV.
    if ($tick % 360 -eq 0 -and $mode -eq 'DEV') {
        try { Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $cfg.Paths.Scripts 'recurse.ps1') -WindowStyle Hidden } catch {}
    }

    Start-Sleep -Seconds $PollSeconds
}
