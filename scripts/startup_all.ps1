# Boots the whole autonomous dev stack after a PC restart (idempotent -
# safe to run when things are already up). Registered as a logon task.

# 1. LLM server: llama-server with ROCm inside WSL (18x faster prefill than
# the Windows Vulkan path - benchmarked 1040 vs 57 tok/s pp2048). Falls back
# to LM Studio only if the WSL server cannot come up.
$llmAlive = $false
try { $llmAlive = (Invoke-WebRequest http://localhost:1234/health -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 } catch {}
if (-not $llmAlive) {
    wsl -d Ubuntu -u root -- bash -c "pgrep -f llama-server >/dev/null || nohup /root/llama.cpp/build/bin/llama-server -m /root/models/Qwen2.5-Coder-14B-Instruct-Q4_K_S.gguf -ngl 99 -c 16384 --host 0.0.0.0 --port 1234 > /var/log/llama-server.log 2>&1 &"
    Start-Sleep -Seconds 30
    try { $llmAlive = (Invoke-WebRequest http://localhost:1234/health -UseBasicParsing -TimeoutSec 10).StatusCode -eq 200 } catch {}
    if (-not $llmAlive) {
        # Fallback: LM Studio (Vulkan, slower but battle-tested)
        lms server start 2>$null
        $loaded = (lms ps 2>$null | Out-String)
        if ($loaded -notmatch "qwen2.5-coder-14b-instruct") {
            lms load "qwen2.5-coder-14b-instruct" --gpu max --context-length 16384 --parallel 1 -y 2>$null
        }
    }
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

# 6. Publish the public progress site if it changed
pwsh -NoProfile -File "g:\Rimwork\scripts\publish_site.ps1" 2>$null

Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [startup] Stack relaunched after boot ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))."
