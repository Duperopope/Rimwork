# Rimwork AI-Dev Dashboard - serves a live, human-friendly view of what the
# autonomous developer is doing (auto-refresh 5s).
# Pure tooling: reads DEV_LOG.md / ROADMAP.md / lessons / loop log, writes state.

# Source de verite unique (paths/port) - voir scripts/lib/Config.ps1.
. "$PSScriptRoot\lib\Config.ps1"
. "$PSScriptRoot\lib\Modes.ps1"
. "$PSScriptRoot\lib\State.ps1"
. "$PSScriptRoot\lib\Chat.ps1"
. "$PSScriptRoot\lib\Dashboard.ps1"
. "$PSScriptRoot\lib\Llm.ps1"
$cfg = Get-DownHereConfig
$port = $cfg.Dashboard.Port
$logDir = $cfg.Paths.Logs
$stateFile = Join-Path $logDir 'stack_state.txt'

$listener = [System.Net.HttpListener]::new()
# http://+ = reachable from the LAN (phone on the same wifi). Needs a
# one-time urlacl + firewall rule; falls back to localhost-only without them.
$listener.Prefixes.Add("http://+:$port/")
try {
    $listener.Start()
} catch {
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://localhost:$port/")
    try {
        $listener.Start()
    } catch {
        # Port already owned by another healthy instance - nothing to do.
        exit 0
    }
}
Write-Host "Dashboard: http://localhost:$port"
. (Join-Path $cfg.Paths.Scripts 'site_gen.ps1')
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
    Set-Content -Path $stateFile -Value "PAUSED"
}

function Start-Stack {
    Enable-ScheduledTask -TaskName RimworkAIDev -ErrorAction SilentlyContinue | Out-Null
    Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $cfg.Paths.Scripts 'startup_all.ps1') -WindowStyle Hidden
    Set-Content -Path $stateFile -Value "RUNNING"
}

while ($true) {
    try { $ctx = $listener.GetContext() } catch { Start-Sleep -Seconds 1; continue }
    if ($ctx.Request.Url.AbsolutePath -eq "/mode") {
        if ($ctx.Request.HttpMethod -ne "POST") { $ctx.Response.StatusCode = 405; $ctx.Response.Close(); continue }
        $set = $ctx.Request.QueryString["set"]
        if ($set -and ($cfg.Modes -contains $set.ToUpper())) {
            try {
                Set-DownHereMode -Mode $set -Config $cfg | Out-Null
                Add-Content -Path $cfg.Paths.DevLog -Value "- [mode] -> $($set.ToUpper()) (dashboard $(Get-Date -Format 'HH:mm'))"
            } catch {}
        }
        $ctx.Response.Redirect("/")
        $ctx.Response.Close()
        continue
    }
    if ($ctx.Request.Url.AbsolutePath -eq "/pause") {
        # POST only: browsers (especially mobile) PREFETCH plain GET links,
        # which used to pause the whole stack just by opening the page.
        if ($ctx.Request.HttpMethod -ne "POST") { $ctx.Response.StatusCode = 405; $ctx.Response.Close(); continue }
        Add-Content (Join-Path $logDir 'watchdog.log') -Value "[$(Get-Date -Format HH:mm:ss)] /pause by $($ctx.Request.RemoteEndPoint)"
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
            Add-Content -Path (Join-Path $logDir 'feedback.jsonl') -Value $entry
        }
        $ctx.Response.Redirect("/")
        $ctx.Response.Close()
        continue
    }
    if ($ctx.Request.Url.AbsolutePath -eq "/resume") {
        if ($ctx.Request.HttpMethod -ne "POST") { $ctx.Response.StatusCode = 405; $ctx.Response.Close(); continue }
        Start-Stack
        $ctx.Response.Redirect("/")
        $ctx.Response.Close()
        continue
    }
    if ($ctx.Request.Url.AbsolutePath -eq "/llm/use") {
        # SELECTION MANUELLE: epingle + (re)telecharge + sert un modele choisi dans
        # l'interface. Le travail (long: DL + chargement) part en arriere-plan.
        if ($ctx.Request.HttpMethod -ne "POST") { $ctx.Response.StatusCode = 405; $ctx.Response.Close(); continue }
        $key = $ctx.Request.QueryString["key"]
        if ($key) {
            Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $cfg.Paths.Scripts 'use-model.ps1'), '-Key', $key -WindowStyle Hidden
        }
        $ctx.Response.Redirect("/"); $ctx.Response.Close(); continue
    }
    if ($ctx.Request.Url.AbsolutePath -eq "/llm/auto") {
        # Retour au choix AUTOMATIQUE (meilleur de tous les temps): retire le pin.
        if ($ctx.Request.HttpMethod -ne "POST") { $ctx.Response.StatusCode = 405; $ctx.Response.Close(); continue }
        try { Remove-Item (Join-Path $logDir 'llm_pinned.txt') -Force -ErrorAction SilentlyContinue } catch {}
        try {
            $lb = Get-Content (Join-Path $logDir 'arena_leaderboard.json') -Raw | ConvertFrom-Json
            $best = $lb.models | Sort-Object total -Descending | Select-Object -First 1
            if ($best) { Set-Content $cfg.Llm.ChampionFile $best.file -Encoding ascii; Start-LlamaServer -Model $best.file }
        } catch {}
        Set-Content (Join-Path $logDir 'llm_use_status.txt') -Value "Mode AUTO: l'arene choisit le meilleur modele." -ErrorAction SilentlyContinue
        $ctx.Response.Redirect("/"); $ctx.Response.Close(); continue
    }
    if ($ctx.Request.Url.AbsolutePath -eq "/console/clear") {
        # Vider la console LLM (journal des tests/sorties) depuis l'interface.
        if ($ctx.Request.HttpMethod -ne "POST") { $ctx.Response.StatusCode = 405; $ctx.Response.Close(); continue }
        try { Remove-Item (Join-Path $logDir 'llm_console.jsonl') -Force -ErrorAction SilentlyContinue } catch {}
        $ctx.Response.Redirect("/"); $ctx.Response.Close(); continue
    }
    if ($ctx.Request.Url.AbsolutePath -eq "/state.json") {
        # Etat consolide, machine-readable (Phase 3) - voir lib/State.ps1.
        try {
            $json = Get-DownHereState -Config $cfg | ConvertTo-Json -Depth 6
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $ctx.Response.ContentType = "application/json; charset=utf-8"
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } catch { try { $ctx.Response.StatusCode = 500 } catch {} }
        try { $ctx.Response.Close() } catch {}
        continue
    }
    if ($ctx.Request.Url.AbsolutePath -eq "/api.json") {
        # API unique de la SPA (etat + activite + taches + feedback + cerveau).
        try {
            $json = Get-DashboardData -Config $cfg | ConvertTo-Json -Depth 8
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $ctx.Response.ContentType = "application/json; charset=utf-8"
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } catch { try { $ctx.Response.StatusCode = 500 } catch {} }
        try { $ctx.Response.Close() } catch {}
        continue
    }
    if ($ctx.Request.Url.AbsolutePath -eq "/chat") {
        # Onglet conversation (page autonome).
        $bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-ChatPageHtml))
        $ctx.Response.ContentType = "text/html; charset=utf-8"
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        try { $ctx.Response.Close() } catch {}
        continue
    }
    if ($ctx.Request.Url.AbsolutePath -eq "/chat/send") {
        if ($ctx.Request.HttpMethod -ne "POST") { $ctx.Response.StatusCode = 405; $ctx.Response.Close(); continue }
        $reply = "(erreur)"
        try {
            $reader = New-Object System.IO.StreamReader($ctx.Request.InputStream, $ctx.Request.ContentEncoding)
            $raw = $reader.ReadToEnd(); $reader.Close()
            $msg = ($raw | ConvertFrom-Json).message
            if ($msg) { $reply = Invoke-ChatTurn -Message ([string]$msg) -Config $cfg }
        } catch { $reply = "erreur: $_" }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes((@{ reply = $reply } | ConvertTo-Json -Compress))
        $ctx.Response.ContentType = "application/json; charset=utf-8"
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        try { $ctx.Response.Close() } catch {}
        continue
    }
    try {
        $html = Get-DashboardHtml
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
        $ctx.Response.ContentType = "text/html; charset=utf-8"
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } catch {
        try { $ctx.Response.StatusCode = 500 } catch {}
    } finally {
        try { $ctx.Response.Close() } catch {}
    }
}
