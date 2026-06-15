# DOWN HERE - DEMARRER toute la pile (raccourci bureau).
# Lance dashboard + orchestrateur + LLM (via startup_all, idempotent) puis ouvre
# le tableau de bord dans le navigateur. Non bloquant : le LLM monte en arriere-plan.
. "$PSScriptRoot\lib\Config.ps1"
$cfg = Get-DownHereConfig
Set-Content -Path (Join-Path $cfg.Paths.Logs 'stack_state.txt') -Value 'RUNNING'
try { Enable-ScheduledTask -TaskName RimworkAIDev -ErrorAction SilentlyContinue | Out-Null } catch {}

# startup_all peut attendre jusqu'a ~160s la montee du LLM -> on le lance CACHE en
# arriere-plan pour que le raccourci rende la main tout de suite.
Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $cfg.Paths.Scripts 'startup_all.ps1') -WindowStyle Hidden

# Attends que le dashboard reponde (quelques secondes) puis ouvre-le.
$url = "http://localhost:$($cfg.Dashboard.Port)"
for ($i = 0; $i -lt 20; $i++) {
    try { if ((Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { break } } catch {}
    Start-Sleep -Milliseconds 700
}
Start-Process $url
