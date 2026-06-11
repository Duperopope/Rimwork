# Boots the whole autonomous dev stack after a PC restart (idempotent -
# safe to run when things are already up). Registered as a logon task.

# 1. LM Studio local server
lms server start 2>$null

# 2. The coding model (skip if something is already loaded)
$loaded = (lms ps 2>$null | Out-String)
if ($loaded -notmatch "qwen2.5-coder-14b-instruct") {
    # --parallel 1: a single slot keeps the whole KV cache in VRAM
    # (4 slots x 16k context overflowed into RAM = 10x slower generation).
    lms load "qwen2.5-coder-14b-instruct" --gpu max --context-length 16384 --parallel 1 -y 2>$null
}

# 3. Dev-loop watchdog (exactly one instance)
$loopRunning = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -match 'dev_loop' }
if (-not $loopRunning) {
    Start-Process pwsh -ArgumentList '-NoProfile','-File','g:\Rimwork\scripts\dev_loop_watchdog.ps1' -WindowStyle Hidden
}

# 4. Dashboard (http://localhost:8765) - probe the actual HTTP endpoint,
# not just the process (a zombie process can exist without listening).
$dashAlive = $false
try { $dashAlive = (Invoke-WebRequest http://localhost:8765 -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 } catch {}
if (-not $dashAlive) {
    Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
        Where-Object { $_.CommandLine -match 'dashboard_server' } |
        ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {} }
    Start-Process pwsh -ArgumentList '-NoProfile','-File','g:\Rimwork\scripts\dashboard_server.ps1' -WindowStyle Hidden
}

# 5. Game watchdog (keeps the game itself running and on the latest build)
$gameWd = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -match 'game_watchdog' }
if (-not $gameWd) {
    Start-Process pwsh -ArgumentList '-NoProfile','-File','g:\Rimwork\scripts\game_watchdog.ps1' -WindowStyle Hidden
}

Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [startup] Stack relaunched after boot ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))."
