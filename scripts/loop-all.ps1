# DOWN HERE - LANCER LA BOUCLE COMPLETE AUTONOME (raccourci bureau).
# Demarre toute la pile (dashboard + orchestrateur + LLM) PUIS le meta-cycle qui
# alterne PLAY (jouer + remonter bugs/friction) et DEV (corriger/ameliorer), sans
# humain. Ouvre le tableau de bord pour suivre.
. "$PSScriptRoot\lib\Config.ps1"
$cfg = Get-DownHereConfig
Set-Content -Path (Join-Path $cfg.Paths.Logs 'stack_state.txt') -Value 'RUNNING'

# 1. La pile (idempotent, en arriere-plan).
Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $cfg.Paths.Scripts 'startup_all.ps1') -WindowStyle Hidden

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
