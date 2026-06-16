# DOWN HERE - LANCER LA BOUCLE COMPLETE AUTONOME (raccourci bureau).
# Demarre toute la pile (dashboard + orchestrateur + LLM) PUIS le meta-cycle qui
# alterne PLAY (jouer + remonter bugs/friction) et DEV (corriger/ameliorer), sans
# humain. Ouvre le tableau de bord pour suivre.
. "$PSScriptRoot\lib\Config.ps1"
$cfg = Get-DownHereConfig
Set-Content -Path (Join-Path $cfg.Paths.Logs 'stack_state.txt') -Value 'RUNNING'

# 1. La pile (idempotent, en arriere-plan).
Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $cfg.Paths.Scripts 'startup_all.ps1') -WindowStyle Hidden

# 1b. PRE-ENTRAINEMENT du world model : la cellule NAIT en comprenant le risque (ne
# fonce pas dans les vagues de H2S) au lieu d'apprendre en mourant. Anti spirale de
# la mort. Synchrone (~1 min) pour que game_wm.pkl existe AVANT que le jeu se lance.
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if ($py) {
    if (-not (Test-Path (Join-Path $cfg.Paths.Logs 'pretrain_transitions.jsonl'))) {
        & $py (Join-Path $cfg.Paths.Scripts 'wm\pretrain_world.py') --configs 40 --episodes 6 2>$null
    }
    & $py (Join-Path $cfg.Paths.Scripts 'wm\play_brain.py') --train 2>$null
}

# 2. Le meta-cycle PLAY <-> DEV (une seule instance : on tue un cycle precedent).
Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'auto_cycle' } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {} }
Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $cfg.Paths.Scripts 'auto_cycle.ps1'), '-Loop' -WindowStyle Hidden

# 3. Ouvre le dashboard pour suivre le cycle en direct.
$url = "http://localhost:$($cfg.Dashboard.Port)"
for ($i = 0; $i -lt 20; $i++) {
    try { if ((Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { break } } catch {}
    Start-Sleep -Milliseconds 700
}
Start-Process $url
