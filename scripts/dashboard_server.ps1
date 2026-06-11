# Rimwork AI-Dev Dashboard - serves a live, human-friendly view of what the
# autonomous developer is doing at http://localhost:8765 (auto-refresh 5s).
# Pure tooling: reads DEV_LOG.md / ROADMAP.md / lessons / loop log, writes nothing.

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:8765/")
try {
    $listener.Start()
} catch {
    # Port already owned by another healthy instance - nothing to do.
    exit 0
}
Write-Host "Dashboard: http://localhost:8765"

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
    if ($ctx.Request.Url.AbsolutePath -eq "/resume") {
        Start-Stack
        $ctx.Response.Redirect("/")
        $ctx.Response.Close()
        continue
    }
    try {
        $roadmap = Get-Content "g:\Rimwork\ROADMAP.md" -ErrorAction SilentlyContinue
        $done = ($roadmap | Select-String '^\s*-\s*\[x\]').Count
        $todo = ($roadmap | Select-String '^\s*-\s*\[ \]').Count
        $total = $done + $todo
        $pct = if ($total -gt 0) { [math]::Round($done * 100 / $total) } else { 0 }

        $devlog = Get-Content "g:\Rimwork\DEV_LOG.md" -ErrorAction SilentlyContinue
        $kept = ($devlog | Select-String 'KEPT|DONE').Count
        $reverted = ($devlog | Select-String 'REVERTED').Count
        $predicted = ($devlog | Select-String 'PREDICTED-FAIL').Count

        # Structured health published by the dev loop each iteration
        $health = "<span class='muted'>en attente de la premiere iteration...</span>"
        $hj = $null
        if (Test-Path "g:\Rimwork\scripts\logs\health.json") {
            try { $hj = Get-Content "g:\Rimwork\scripts\logs\health.json" -Raw | ConvertFrom-Json } catch {}
        }
        $stackState = "RUNNING"
        if (Test-Path "g:\Rimwork\scripts\logs\stack_state.txt") { $stackState = (Get-Content "g:\Rimwork\scripts\logs\stack_state.txt" -Raw).Trim() }
        $revertsLast20 = ($devlog | Select-Object -Last 20 | Select-String 'REVERTED').Count
        $lastCommit = (git -C g:\Rimwork log -1 --format="%h %s (%cr)" 2>$null)
        if ($hj) {
            $rooms = if ($hj.simSummary -match 'VERDICT: (\d+) functional rooms') { $Matches[1] } else { "?" }
            $simTick = if ($hj.simSummary -match '(\[tick[^\r\n]+)') { Esc($Matches[1]) } else { "" }
            $buildCol = if ($hj.build -eq 'OK') { '#3fb950' } else { '#f85149' }
            $simCol = if ($hj.simOk) { '#3fb950' } else { '#f85149' }
            $health = "<b style='color:$buildCol'>BUILD $($hj.build)</b> &nbsp; " +
                "<b style='color:$simCol'>SIM $(if ($hj.simOk) { 'OK' } else { 'CRASH' })</b> &nbsp; " +
                "<b>$rooms pieces fonctionnelles</b><br>" +
                "<span class='health'>$simTick</span><br>" +
                "iteration $($hj.iter) en $($hj.iterSeconds)s ($($hj.timestamp))<br>" +
                "annulations (20 dernieres iterations): <b>$revertsLast20</b><br>" +
                "dernier commit: <span class='health'>$(Esc($lastCommit))</span>"
        }

        # Friendly translation of the last 25 dev log events
        $events = $devlog | Select-Object -Last 25
        [array]::Reverse($events)
        $rows = foreach ($e in $events) {
            $cls = "info"; $label = "Info"
            if ($e -match 'KEPT')           { $cls = "ok";    $label = "Code accepte" }
            elseif ($e -match 'DONE')       { $cls = "done";  $label = "Tache terminee" }
            elseif ($e -match 'REVERTED')   { $cls = "bad";   $label = "Annule (casse le jeu)" }
            elseif ($e -match 'PREDICTED-FAIL') { $cls = "warn"; $label = "Refuse avant build (prediction)" }
            elseif ($e -match 'SELF-REWRITE')   { $cls = "smart"; $label = "S'est reecrit la tache" }
            elseif ($e -match 'CRITIC TASK')    { $cls = "smart"; $label = "Critique: nouvelle idee" }
            elseif ($e -match 'EMERGENT')   { $cls = "smart"; $label = "Idee emergente" }
            elseif ($e -match 'BLOCKED')    { $cls = "bad";   $label = "Bloque (besoin d'aide)" }
            elseif ($e -match 'SKIPPED')    { $cls = "warn";  $label = "Patch non applicable" }
            elseif ($e -match 'PERF')       { $cls = "warn";  $label = "Performance machine" }
            $txt = Esc(($e -replace '^- \[iter \d+\]\s*', '' -replace '^- \[startup\]\s*', ''))
            "<div class='ev $cls'><span class='tag'>$label</span><span class='txt'>$txt</span></div>"
        }

        $lessons = (Get-Content "g:\Rimwork\scripts\logs\lessons.md" -ErrorAction SilentlyContinue |
            Select-Object -Last 8 | ForEach-Object { "<li>$(Esc($_ -replace '^- ',''))</li>" }) -join ""
        if (-not $lessons) { $lessons = "<li class='muted'>Aucune lecon enregistree pour l'instant</li>" }

        $next = ($roadmap | Select-String '^\s*-\s*\[ \]' | Select-Object -First 4 | ForEach-Object {
            "<li>$(Esc(($_.Line.Trim() -replace '^- \[ \] ','')))</li>" }) -join ""

        $html = @"
<!DOCTYPE html><html lang='fr'><head><meta charset='utf-8'>
<meta http-equiv='refresh' content='5'>
<title>Rimwork - Dev IA en direct</title>
<style>
:root { color-scheme: dark; }
* { box-sizing: border-box; margin: 0; }
body { background:#0d1117; color:#e6edf3; font:15px/1.5 'Segoe UI',system-ui,sans-serif; padding:24px; }
h1 { font-size:22px; margin-bottom:4px; } h2 { font-size:15px; color:#8b949e; font-weight:600; margin-bottom:10px; text-transform:uppercase; letter-spacing:.5px; }
.sub { color:#8b949e; margin-bottom:24px; }
.grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(280px,1fr)); gap:16px; margin-bottom:16px; }
.card { background:#161b22; border:1px solid #30363d; border-radius:12px; padding:18px; }
.big { font-size:34px; font-weight:700; }
.bar { height:10px; background:#21262d; border-radius:5px; overflow:hidden; margin-top:10px; }
.bar i { display:block; height:100%; background:linear-gradient(90deg,#2ea043,#3fb950); width:$pct%; }
.kpis { display:flex; gap:18px; margin-top:8px; }
.kpis div b { font-size:20px; display:block; }
.ok b { color:#3fb950; } .bad b { color:#f85149; } .warn b { color:#d29922; }
.ev { display:flex; gap:10px; padding:8px 10px; border-radius:8px; margin-bottom:6px; background:#0d1117; border:1px solid #21262d; align-items:baseline; }
.ev .tag { flex:none; font-size:11px; font-weight:700; padding:2px 8px; border-radius:20px; }
.ev.ok .tag { background:#1a3520; color:#3fb950; } .ev.done .tag { background:#1a2c4a; color:#58a6ff; }
.ev.bad .tag { background:#3d1518; color:#f85149; } .ev.warn .tag { background:#3a2d10; color:#d29922; }
.ev.smart .tag { background:#2d1b46; color:#bc8cff; } .ev.info .tag { background:#21262d; color:#8b949e; }
.ev .txt { color:#c9d1d9; font-size:13px; }
ul { padding-left:20px; } li { margin-bottom:6px; font-size:13.5px; color:#c9d1d9; }
.muted { color:#8b949e; } .health { font-family:Consolas,monospace; font-size:12.5px; color:#7ee787; }
</style></head><body>
<h1>&#129302; Down Here ! &mdash; le developpeur IA en direct</h1>
<div style='margin:8px 0 14px 0'>
  <a href='/pause' style='background:#7d2c2c;color:#fff;padding:9px 18px;border-radius:8px;text-decoration:none;font-weight:700'>&#9208; PAUSE MACHINE (libere GPU/CPU pour toi)</a>
  &nbsp;
  <a href='/resume' style='background:#1f6f35;color:#fff;padding:9px 18px;border-radius:8px;text-decoration:none;font-weight:700'>&#9654; REPRENDRE l'usine IA</a>
  &nbsp; <span class='muted'>etat: $stackState</span>
</div>
<p class='sub'>Tout ce qui est ici est fait par le modele local, sans intervention humaine. Actualisation auto toutes les 5s.</p>
<div class='grid'>
  <div class='card'><h2>Avancement du jeu</h2><span class='big'>$pct%</span> <span class='muted'>($done / $total taches)</span><div class='bar'><i></i></div></div>
  <div class='card'><h2>Bilan du codeur</h2><div class='kpis'>
    <div class='ok'><b>$kept</b>acceptes</div>
    <div class='bad'><b>$reverted</b>annules</div>
    <div class='warn'><b>$predicted</b>predits-evites</div>
  </div></div>
  <div class='card'><h2>Sante du jeu (simulation)</h2><div class='health'>$health</div></div>
</div>
<div class='grid'>
  <div class='card'><h2>&#128300; Ce qu'il a appris (lecons)</h2><ul>$lessons</ul></div>
  <div class='card'><h2>&#128203; Prochaines taches</h2><ul>$next</ul></div>
</div>
<div class='card'><h2>&#9889; Activite en direct (plus recent en haut)</h2>$($rows -join "`n")</div>
</body></html>
"@
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
        $ctx.Response.ContentType = "text/html; charset=utf-8"
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } catch {
        try { $ctx.Response.StatusCode = 500 } catch {}
    } finally {
        try { $ctx.Response.Close() } catch {}
    }
}
