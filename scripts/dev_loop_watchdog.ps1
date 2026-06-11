<#
Keeps dev_loop.ps1 running. If it exits for any reason (crash, LM Studio
restart, MaxIterations reached), it is relaunched automatically after a
short delay - no manual restart needed.
#>

param(
    [int]$RestartDelaySeconds = 10
)

$logDir = "g:\Rimwork\scripts\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

# SELF-GUARD: only one dev-loop watchdog may run (duplicates double every
# LLM call and fight over DEV_LOG.md).
$me = $PID
$twins = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -match 'dev_loop_watchdog' -and $_.ProcessId -ne $me }
if ($twins) {
    Write-Host "Another dev-loop watchdog is already running (pid $($twins[0].ProcessId)) - exiting."
    exit 0
}

while ($true) {
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$stamp] Starting dev_loop.ps1" -ForegroundColor Cyan
    Add-Content -Path "$logDir\watchdog.log" -Value "[$stamp] starting dev_loop.ps1"

    & "g:\Rimwork\scripts\dev_loop.ps1" *>> "g:\Rimwork\scripts\loop_stdout.log"

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$stamp] dev_loop.ps1 exited - restarting in $RestartDelaySeconds s" -ForegroundColor Yellow
    Add-Content -Path "$logDir\watchdog.log" -Value "[$stamp] dev_loop.ps1 exited - restarting in $RestartDelaySeconds s"
    Start-Sleep -Seconds $RestartDelaySeconds
}
