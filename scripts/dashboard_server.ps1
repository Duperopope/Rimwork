# Rimwork AI-Dev Dashboard - serves a live, human-friendly view of what the
# autonomous developer is doing at http://localhost:8765 (auto-refresh 5s).
# Pure tooling: reads DEV_LOG.md / ROADMAP.md / lessons / loop log, writes nothing.

$listener = [System.Net.HttpListener]::new()
# http://+ = reachable from the LAN (phone on the same wifi). Needs a
# one-time urlacl + firewall rule; falls back to localhost-only without them.
$listener.Prefixes.Add("http://+:8765/")
try {
    $listener.Start()
} catch {
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://localhost:8765/")
    try {
        $listener.Start()
    } catch {
        # Port already owned by another healthy instance - nothing to do.
        exit 0
    }
}
Write-Host "Dashboard: http://localhost:8765"
. "g:\Rimwork\scripts\site_gen.ps1"
Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

function Esc([string]$s) { [System.Web.HttpUtility]::HtmlEncode($s) }
Add-Type -AssemblyName System.Web

function Stop-Stack {
    # Free the machine: stop dev loop, game, game watchdog, and unload the LLM.
    Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
        Where-Object { $_.CommandLine -match 'dev_loop|game_watchdog' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Get-Process | Where-Object { $_.Name -match '^(godot|Rimwork)' } |
        ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
    wsl -d Ubuntu -u root -- bash -c "pkill -f llama-server" 2>$null
    Disable-ScheduledTask -TaskName RimworkAIDev -ErrorAction SilentlyContinue | Out-Null
    Set-Content -Path "g:\Rimwork\scripts\logs\stack_state.txt" -Value "PAUSED"
}

function Start-Stack {
    Enable-ScheduledTask -TaskName RimworkAIDev -ErrorAction SilentlyContinue | Out-Null
    Start-Process pwsh -ArgumentList '-NoProfile','-File','g:\Rimwork\scripts\startup_all.ps1' -WindowStyle Hidden
    Set-Content -Path "g:\Rimwork\scripts\logs\stack_state.txt" -Value "RUNNING"
}

while ($true) {
    try { $ctx = $listener.GetContext() } catch { Start-Sleep -Seconds 1; continue }
    if ($ctx.Request.Url.AbsolutePath -eq "/pause") {
        Stop-Stack
        $ctx.Response.Redirect("/")
        $ctx.Response.Close()
        continue
    }
    if ($ctx.Request.Url.AbsolutePath -eq "/feedback") {
        $q = $ctx.Request.QueryString
        $text = $q["text"]
        if ($text -and $text.Trim().Length -gt 3) {
            $entry = @{
                date = (Get-Date -Format "dd/MM HH:mm")
                type = if ($q["type"] -eq "bug") { "bug" } else { "feature" }
                text = $text.Trim()
                status = "propose"
            } | ConvertTo-Json -Compress
            Add-Content -Path "g:/Rimwork/scripts/logs/feedback.jsonl" -Value $entry
        }
        $ctx.Response.Redirect("/")
        $ctx.Response.Close()
        continue
    }
    if ($ctx.Request.Url.AbsolutePath -eq "/resume") {
        Start-Stack
        $ctx.Response.Redirect("/")
        $ctx.Response.Close()
        continue
    }
    try {
        $stackState = "RUNNING"
        if (Test-Path "g:\Rimwork\scripts\logs\stack_state.txt") { $stackState = (Get-Content "g:\Rimwork\scripts\logs\stack_state.txt" -Raw).Trim() }
        $html = Get-DownHereSiteHtml -Live $true -StackState $stackState
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
        $ctx.Response.ContentType = "text/html; charset=utf-8"
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } catch {
        try { $ctx.Response.StatusCode = 500 } catch {}
    } finally {
        try { $ctx.Response.Close() } catch {}
    }
}
