<#
DOWN HERE - BOUCLE COMPLETE AUTONOME (meta-orchestrateur).

Les modes sont MUTUELLEMENT EXCLUSIFS (le jeu et le dev se partagent les 16 Go GPU).
Ce script fait ALTERNER les phases pour fermer le cycle, sans humain :

  PLAY  -> l'agent JOUE (pilote par le world model), perçoit/evite la toxine,
           apprend la dynamique reelle, et play_report remonte bugs + friction.
  DEV   -> la boucle de dev CORRIGE/AMELIORE le jeu (ROADMAP, qui recoit les
           remontees du jeu via play_report -ToRoadmap).
  (ARENA -> de temps en temps, re-verifie qu'on tourne avec le meilleur modele.)

L'orchestrateur (deja lance) applique le mode ecrit dans mode.json ; ici on ne fait
que SEQUENCER les modes dans le temps. Reagit a "Arreter" (stack_state=PAUSED).

  pwsh -File scripts\auto_cycle.ps1 -Loop
  pwsh -File scripts\auto_cycle.ps1 -Loop -PlayMin 25 -DevMin 35 -ArenaEvery 6
#>
param(
    [int]$PlayMin = 20,        # duree d'une phase de JEU
    [int]$DevMin = 40,         # duree d'une phase de DEV
    [int]$ArenaEvery = 0,      # toutes les N boucles, glisser une phase ARENA (0 = jamais)
    [int]$ArenaMin = 20,
    [switch]$Loop
)
. "$PSScriptRoot\lib\Config.ps1"
. "$PSScriptRoot\lib\Modes.ps1"
$cfg = Get-DownHereConfig
$logDir = $cfg.Paths.Logs
$stateFile = Join-Path $logDir 'stack_state.txt'
$log = Join-Path $logDir 'auto_cycle.log'
function Log([string]$m) { Add-Content -Path $log -Value "[$(Get-Date -Format 'MM-dd HH:mm:ss')] $m"; Write-Host $m }

# Pause-aware : dort en petits increments, sort tot si on appuie sur "Arreter".
function Wait-Phase([int]$minutes) {
    $deadline = (Get-Date).AddMinutes($minutes)
    while ((Get-Date) -lt $deadline) {
        try { if ((Get-Content $stateFile -Raw -ErrorAction Stop) -match 'PAUSED') { return $false } } catch {}
        Start-Sleep -Seconds 20
    }
    return $true
}

function Set-Phase([string]$mode) {
    try { Set-DownHereMode -Mode $mode -Config $cfg | Out-Null } catch {}
    Add-Content -Path $cfg.Paths.DevLog -Value "- [cycle] -> $mode ($(Get-Date -Format 'HH:mm'))"
    Log "PHASE -> $mode"
}

Log "=== BOUCLE COMPLETE: PLAY ${PlayMin}min <-> DEV ${DevMin}min$(if($ArenaEvery){" (ARENA tous les $ArenaEvery tours)"}) ==="
$round = 0
do {
    $round++
    # PLAY : jouer + remonter les trouvailles au dev (play_agent lance play_report).
    Set-Phase 'PLAY'
    if (-not (Wait-Phase $PlayMin)) { Log 'PAUSED pendant PLAY -> arret du cycle'; break }
    # Filet : agrege une derniere fois les trouvailles vers la ROADMAP avant de coder.
    try { Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $cfg.Paths.Scripts 'play_report.ps1'), '-Emit', '-ToRoadmap' -WindowStyle Hidden -Wait } catch {}

    # DEV : corriger/ameliorer le jeu (ROADMAP enrichie par les remontees).
    Set-Phase 'DEV'
    if (-not (Wait-Phase $DevMin)) { Log 'PAUSED pendant DEV -> arret du cycle'; break }

    # ARENA (optionnel, periodique) : garder le meilleur cerveau.
    if ($ArenaEvery -gt 0 -and ($round % $ArenaEvery) -eq 0) {
        Set-Phase 'ARENA'
        if (-not (Wait-Phase $ArenaMin)) { Log 'PAUSED pendant ARENA -> arret du cycle'; break }
    }
} while ($Loop)
Log 'cycle termine.'
