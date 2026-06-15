# DOWN HERE - VOIR L'IA JOUER (raccourci bureau).
# Passe en mode PLAY (l'orchestrateur lance le JEU + l'agent pilote par le WORLD
# MODEL), s'assure que la pile tourne, et ouvre le tableau de bord pour suivre.
. "$PSScriptRoot\lib\Config.ps1"
. "$PSScriptRoot\lib\Modes.ps1"
$cfg = Get-DownHereConfig
Set-Content -Path (Join-Path $cfg.Paths.Logs 'stack_state.txt') -Value 'RUNNING'

# Mode PLAY -> l'orchestrateur demarre game_watchdog (le jeu) + play_agent (cerveau WM).
try { Set-DownHereMode -Mode 'PLAY' -Config $cfg | Out-Null } catch {}

# S'assure que dashboard + orchestrateur + LLM tournent (idempotent, en arriere-plan).
Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $cfg.Paths.Scripts 'startup_all.ps1') -WindowStyle Hidden

$url = "http://localhost:$($cfg.Dashboard.Port)"
for ($i = 0; $i -lt 20; $i++) {
    try { if ((Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { break } } catch {}
    Start-Sleep -Milliseconds 700
}
Start-Process $url
