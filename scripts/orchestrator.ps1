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
$cfg = Get-DownHereConfig
$log = Join-Path $cfg.Paths.Logs 'orchestrator.log'
New-Item -ItemType Directory -Force -Path $cfg.Paths.Logs | Out-Null

function Write-OrchLog([string]$m) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m"
    Add-Content -Path $log -Value $line
    Write-Host $line
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

while ($true) {
    $mode = Get-DownHereMode -Config $cfg
    if ($mode -ne $lastMode) { Write-OrchLog "MODE = $mode"; $lastMode = $mode }

    $actions = Invoke-ModeReconcile -Mode $mode -DryRun:$DryRun -Config $cfg
    foreach ($a in $actions) { Write-OrchLog "  $(if($DryRun){'[dry] '})$a" }

    if ($Once -or $DryRun) { break }
    Start-Sleep -Seconds $PollSeconds
}
