# Shared site generator for DOWN HERE! - used by BOTH the live dashboard
# (localhost:8765) and the public GitHub Pages (docs/index.html).
# Data sources are REAL: git history (dated deliverables), ROADMAP.md
# (in-dev tasks), DEV_LOG.md (activity), health.json (live health).
# No fake future estimates - this dev doesn't need them.

function Get-DownHereSiteHtml {
    param([bool]$Live = $false, [string]$StackState = "RUNNING")

    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
    function E([string]$s) { [System.Web.HttpUtility]::HtmlEncode($s) }

    $roadmap = Get-Content "g:\Rimwork\ROADMAP.md" -ErrorAction SilentlyContinue
    $devlog = Get-Content "g:\Rimwork\DEV_LOG.md" -ErrorAction SilentlyContinue
    $done = ($roadmap | Select-String '^\s*-\s*\[x\]').Count
    $todo = ($roadmap | Select-String '^\s*-\s*\[ \]').Count
    $total = [Math]::Max(1, $done + $todo)
    $pct = [math]::Round($done * 100 / $total)
    $kept = ($devlog | Select-String 'KEPT|DONE').Count
    $reverted = ($devlog | Select-String 'REVERTED').Count
    $predicted = ($devlog | Select-String 'PREDICTED-FAIL').Count

    # ---------- RELEASE VIEW: real dated deliverables from git ----------
    $commits = git -C g:\Rimwork log --reverse --format="%h|%ad|%s" --date=format:"%d/%m/%Y %H:%M" 2>$null
    $r01 = New-Object System.Collections.Generic.List[string]
    $r02 = New-Object System.Collections.Generic.List[string]
    $r03 = New-Object System.Collections.Generic.List[string]
    $phase = 1
    foreach ($c in $commits) {
        $parts = $c -split '\|', 3
        if ($parts.Count -lt 3) { continue }
        $h = $parts[0]; $d = $parts[1]; $msg = $parts[2]
        $isAi = $msg -match '^\[ai-loop'
        $title = $msg -replace '^\[ai-loop iter \d+\]\s*', ''
        if ($title.Length -gt 95) { $title = $title.Substring(0, 95) + "..." }
        $badge = if ($isAi) { "<span class='who ai'>IA locale</span>" } else { "<span class='who claude'>superviseur</span>" }
        $entry = "<div class='deliv'><div class='deliv-date'>&#128197; $d &middot; <code>$h</code> $badge</div><div class='deliv-title'>$(E($title))</div></div>"
        if ($phase -eq 1) { $r01.Add($entry) }
        elseif ($phase -eq 2) { $r02.Add($entry) }
        else { $r03.Add($entry) }
        if ($msg -match 'GAMEJAM SUPERPASS') { $phase = 2 }
        if ($msg -match 'DOWN HERE! - visit flow|DOWN HERE ! - visit flow') { $phase = 3 }
    }
    function RelCol($title, $tag, $cls, $items, $collapsedNote) {
        # Group deliveries by day -> <details> per day for a clean overview.
        $byDay = [ordered]@{}
        foreach ($it in $items) {
            $day = if ($it -match '&#128197; (\d\d/\d\d/\d\d\d\d)') { $Matches[1] } else { "divers" }
            if (-not $byDay.Contains($day)) { $byDay[$day] = New-Object System.Collections.Generic.List[string] }
            $byDay[$day].Add($it)
        }
        $list = ""
        $dayKeys = @($byDay.Keys)
        for ($di = 0; $di -lt $dayKeys.Count; $di++) {
            $day = $dayKeys[$di]
            $list += "<details class='day'><summary>&#128197; $day <span class='pill'>$($byDay[$day].Count) patchs</span></summary>" + ($byDay[$day] -join "`n") + "</details>"
        }
        $count = $items.Count
        "<div class='rel-col'><div class='rel-head $cls'>$title<br><span class='rel-tag'>$tag &middot; $count livraisons</span></div><div class='rel-body'>$list</div></div>"
    }
    $relHtml = "<div class='rel-grid'>" +
        (RelCol "0.1 — FONDATIONS (JAM)" "LIVR&Eacute; 11/06/2026" "done" $r01 "") +
        (RelCol "0.2 — DOWN HERE" "LIVR&Eacute; 11-12/06/2026" "done" $r02 "") +
        (RelCol "0.3 — MONDE VIVANT" "EN D&Eacute;VELOPPEMENT" "tent" $r03 "") +
        "<div class='rel-col'><div class='rel-head future'>0.4+ — HORIZON<br><span class='rel-tag'>SANS DATE (dev autonome)</span></div><div class='rel-body'>" +
        (@("Départ Spore: stade bactérie jouable", "Stade organisme (créature)", "Cartes x10 + eau logique (rivières/lacs)",
           "Vue 4X des unités réelles", "Gravité/atmosphère par planète", "Multi-systèmes stellaires", "Endgame spatial KSP") |
            ForEach-Object { "<div class='deliv'><div class='deliv-title'>$(E($_))</div></div>" }) -join "" +
        "</div></div></div>"

    # ---------- PROGRESS TRACKER: teams x in-dev items (expandable) ----------
    $pendingBlocks = @()
    $cur = $null
    foreach ($line in $roadmap) {
        if ($line -match '^\s*-\s*\[ \] (Step .*)$') {
            if ($cur) { $pendingBlocks += ,$cur }
            $cur = @($Matches[1])
        } elseif ($cur -and $line -match '^\s{4,}(\S.*)$' -and $line -notmatch '^\s*-\s*\[') {
            $cur += $line.Trim()
        } elseif ($cur -and ($line -match '^\s*-\s*\[' -or $line -match '^#')) {
            $pendingBlocks += ,$cur; $cur = $null
        }
    }
    if ($cur) { $pendingBlocks += ,$cur }

    $teams = [ordered]@{
        "CŒUR DE SIMULATION" = @()
        "PLANÈTES & ÉCHELLES" = @()
        "PRÉSENTATION 3D" = @()
        "IDÉES DU CRITIQUE IA" = @()
    }
    foreach ($b in $pendingBlocks) {
        $head = $b[0]
        $body = if ($b.Count -gt 1) { ($b[1..([Math]::Min($b.Count - 1, 6))] -join " ") } else { "" }
        if ($body.Length -gt 320) { $body = $body.Substring(0, 320) + "..." }
        $card = "<details class='trk-item'><summary><span class='trk-dot'></span>$(E($head))</summary>" +
                "<div class='trk-desc'>$(E($body))<br><span class='muted'>Statut: en file pour le développeur IA local &middot; pas d'estimation (dev autonome 24/7)</span></div></details>"
        if ($head -match '^Step C\.') { $teams["IDÉES DU CRITIQUE IA"] += $card }
        elseif ($head -match 'Game3D|planet|orbit|Planet') { $teams["PRÉSENTATION 3D"] += $card }
        elseif ($head -match 'WorldModel|Micro|Region|tile|M\.\d') { $teams["PLANÈTES & ÉCHELLES"] += $card }
        else { $teams["CŒUR DE SIMULATION"] += $card }
    }
    $trkHtml = ""
    foreach ($tm in $teams.Keys) {
        $items = $teams[$tm]
        $inner = if ($items.Count -eq 0) { "<div class='muted' style='padding:6px'>aucune tâche en file</div>" } else { $items -join "" }
        $trkHtml += "<div class='trk-team'><div class='trk-name'>$tm <span class='pill'>$($items.Count)</span></div>$inner</div>"
    }

    # ---------- ACTIVITY: dated via commits interleaved with devlog tail ----------
    $actRows = ""
    $recent = git -C g:\Rimwork log -25 --format="%ad|%s" --date=format:"%d/%m %H:%M" 2>$null
    foreach ($c in $recent) {
        $p2 = $c -split '\|', 2
        $isAi = $p2[1] -match '^\[ai-loop'
        $cls = if ($isAi) { "ok" } else { "done" }
        $who = if ($isAi) { "IA locale" } else { "superviseur" }
        $t2 = $p2[1] -replace '^\[ai-loop iter \d+\]\s*', ''
        if ($t2.Length -gt 110) { $t2 = $t2.Substring(0, 110) + "..." }
        $actRows += "<div class='ev $cls'><span class='tag'>$($p2[0])</span><span class='tag2'>$who</span><span class='txt'>$(E($t2))</span></div>"
    }

    # ---------- Live health (dashboard only) ----------
    $liveBlock = ""
    if ($Live) {
        $hj = $null
        try { $hj = Get-Content "g:\Rimwork\scripts\logs\health.json" -Raw -ErrorAction Stop | ConvertFrom-Json } catch {}
        $h = if ($hj) {
            $rooms = if ($hj.simSummary -match 'VERDICT: (\d+)') { $Matches[1] } else { "?" }
            "BUILD <b style='color:#3fb950'>$($hj.build)</b> &middot; SIM <b style='color:#3fb950'>$(if ($hj.simOk) {'OK'} else {'CRASH'})</b> &middot; $rooms pièces &middot; itération $($hj.iter) en $($hj.iterSeconds)s ($($hj.timestamp))"
        } else { "en attente d'itération..." }
        $lessons = ""
        try { $lessons = (Get-Content "g:\Rimwork\scripts\logs\lessons.md" | Select-Object -Last 5 | ForEach-Object { "<li>$(E($_ -replace '^- ',''))</li>" }) -join "" } catch {}

        # Task timer: which roadmap item the AI works on and for how long.
        $taskLine = "<span class='muted'>aucune t&acirc;che en cours</span>"
        try {
            $ci = Get-Content "g:\Rimwork\scripts\logs\current_item.json" -Raw -ErrorAction Stop | ConvertFrom-Json
            $mins = [int]((Get-Date) - [datetime]::ParseExact($ci.since, "yyyy-MM-dd HH:mm:ss", $null)).TotalMinutes
            $itTxt = $ci.item; if ($itTxt.Length -gt 130) { $itTxt = $itTxt.Substring(0, 130) + "..." }
            $warn = if ($mins -ge 30) { " <b style='color:#f85149'>&#9888; bloqu&eacute; depuis $mins min</b>" } elseif ($mins -ge 10) { " <b style='color:#d29922'>$mins min</b>" } else { " <span class='muted'>depuis $mins min</span>" }
            $taskLine = "$(E($itTxt))$warn"
        } catch {}

        # Game state from the agent bridge: never silently stuck at the menu.
        $gameLine = "<span class='muted'>&eacute;tat du jeu inconnu (bridge muet)</span>"
        try {
            $ast = Get-Item "g:\Rimwork\scripts\logs/agent_state.json" -ErrorAction Stop
            $ageS = [int]((Get-Date) - $ast.LastWriteTime).TotalSeconds
            $as = Get-Content $ast.FullName -Raw | ConvertFrom-Json
            if ($ageS -gt 30) { $gameLine = "<b style='color:#f85149'>jeu arr&ecirc;t&eacute; ou gel&eacute; (dernier &eacute;tat il y a ${ageS}s)</b>" }
            elseif ($as.menuOpen) { $gameLine = "<b style='color:#d29922'>AU MENU PRINCIPAL</b> &middot; l'agent peut le sortir (newgame)" }
            else { $gameLine = "EN JEU &middot; jour $($as.day), $($as.hour)h &middot; vue $($as.view) &middot; $(@($as.pawns).Count) pawns &middot; $($as.rooms) pi&egrave;ces$(if ($as.paused) { " &middot; <b style='color:#d29922'>PAUSE</b>" })" }
        } catch {}
        $pt = ""
        try {
            $ptr = Get-Content "g:\Rimwork\scripts\logs\playtest_report.json" -Raw -ErrorAction Stop | ConvertFrom-Json
            $pt = " &middot; dernier playtest IA: $($ptr.issued.Count) actions, $($ptr.anomalies.Count) anomalies ($($ptr.timestamp))"
        } catch {}
        $liveBlock = @"
<div class='card'><h2>&#127918; Sant&eacute; en direct</h2><div>$h</div>
<div style='margin-top:8px'><b>T&Acirc;CHE EN COURS:</b> $taskLine</div>
<div style='margin-top:4px'><b>JEU:</b> $gameLine$pt</div>
<div style='margin-top:8px'><button class='btnp' onclick="if(confirm('Mettre toute la machine en pause ?')){fetch('/pause',{method:'POST'}).then(()=>location.reload())}">&#9208; PAUSE MACHINE</button> <button class='btnr' onclick="fetch('/resume',{method:'POST'}).then(()=>location.reload())">&#9654; REPRENDRE</button> <span class='muted'>&eacute;tat: $StackState</span></div></div>
<div class='card'><h2>&#129504; Le&ccedil;ons r&eacute;centes de l'IA</h2><ul>$lessons</ul></div>
"@
    }

    # ---------- FEEDBACK: stored locally, mirrored as GitHub issues ----------
    $fbFile = "g:/Rimwork/scripts/logs/feedback.jsonl"
    $fbRows = ""
    if (Test-Path $fbFile) {
        $entries = Get-Content $fbFile | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} } | Where-Object { $_ }
        $entries = @($entries); [array]::Reverse($entries)
        foreach ($f in $entries | Select-Object -First 30) {
            $stCls = switch ($f.status) { "valide" { "ok" } "traite" { "done" } "rejete" { "bad" } default { "warn" } }
            $typeIco = if ($f.type -eq "bug") { "&#128027;" } else { "&#10024;" }
            $fbRows += "<div class='ev $stCls'><span class='tag'>$($f.date)</span><span class='tag2'>$typeIco $($f.type) &middot; $($f.status)</span><span class='txt'>$(E($f.text))</span></div>"
        }
    }
    if (-not $fbRows) { $fbRows = "<div class='muted'>Aucune demande pour l'instant.</div>" }
    $feedbackBody = if ($Live) {
        @"
<form method='GET' action='/feedback' style='display:flex;gap:8px;flex-wrap:wrap;margin-bottom:12px'>
<select name='type' style='background:#0d1420;color:#e6edf3;border:1px solid #1f2a3a;border-radius:8px;padding:8px'>
<option value='feature'>&#10024; Feature</option><option value='bug'>&#128027; Bug</option></select>
<input name='text' placeholder='Décris ta demande ou le bug...' style='flex:1;min-width:280px;background:#0d1420;color:#e6edf3;border:1px solid #1f2a3a;border-radius:8px;padding:8px'>
<button style='background:#1f6f35;color:#fff;border:none;border-radius:8px;padding:8px 18px;font-weight:700;cursor:pointer'>Envoyer</button>
</form>
<p class='muted'>Statuts: propos&eacute; &rarr; valid&eacute; (sera trait&eacute; par le dev IA) &rarr; trait&eacute;. Les demandes valid&eacute;es deviennent des t&acirc;ches du roadmap.</p>
$fbRows
"@
    } else {
        @"
<p>Proposez des features ou signalez des bugs directement sur GitHub &mdash; les demandes valid&eacute;es deviennent des t&acirc;ches du d&eacute;veloppeur IA:</p>
<p><a class='btnr' href='https://github.com/Duperopope/Rimwork/issues/new?labels=feature&title=%5BFeature%5D%20'>&#10024; Proposer une feature</a>
&nbsp;<a class='btnp' href='https://github.com/Duperopope/Rimwork/issues/new?labels=bug&title=%5BBug%5D%20'>&#128027; Signaler un bug</a></p>
$fbRows
"@
    }

    $refresh = if ($Live) { "<meta http-equiv='refresh' content='10'>" } else { "" }
    $genAt = Get-Date -Format "dd/MM/yyyy HH:mm"
    $publicNote = if ($Live) { "" } else { "<p class='sub'>Site g&eacute;n&eacute;r&eacute; automatiquement depuis les donn&eacute;es r&eacute;elles du d&eacute;p&ocirc;t &mdash; <a href='https://github.com/Duperopope/Rimwork'>code source</a>.</p>" }

    return @"
<!DOCTYPE html><html lang='fr'><head><meta charset='utf-8'>$refresh
<meta name='viewport' content='width=device-width, initial-scale=1'>
<title>DOWN HERE ! — Roadmap &amp; Progress</title>
<style>
:root { color-scheme: dark; }
* { box-sizing:border-box; margin:0; }
body { background:#0a0e14; color:#e6edf3; font:15px/1.5 'Segoe UI',system-ui,sans-serif; }
header { background:linear-gradient(180deg,#101a2b,#0a0e14); border-bottom:1px solid #1f2a3a; padding:26px 28px 0 28px; }
h1 { font-size:30px; letter-spacing:1px; } h1 b { color:#5cc26e; }
.sub { color:#8b949e; margin:6px 0 14px 0; }
nav { display:flex; gap:4px; }
nav a { padding:10px 18px; color:#9fb0c3; text-decoration:none; font-weight:600; border-radius:8px 8px 0 0; }
nav a.on { background:#141d2b; color:#fff; border:1px solid #1f2a3a; border-bottom:none; }
main { padding:22px 28px; max-width:1500px; margin:0 auto; }
section { display:none; } section.on { display:block; }
.kpis { display:flex; gap:26px; flex-wrap:wrap; margin-bottom:18px; }
.kpi { background:#121a26; border:1px solid #1f2a3a; border-radius:12px; padding:14px 22px; }
.kpi b { font-size:26px; display:block; } .g { color:#3fb950; } .r { color:#f85149; } .y { color:#d29922; }
.bar { height:10px; background:#1c2533; border-radius:5px; overflow:hidden; margin-top:8px; width:240px; }
.bar i { display:block; height:100%; width:$pct%; background:linear-gradient(90deg,#2ea043,#3fb950); }
.card { background:#121a26; border:1px solid #1f2a3a; border-radius:12px; padding:16px 18px; margin-bottom:16px; }
h2 { font-size:14px; color:#9fb0c3; text-transform:uppercase; letter-spacing:1px; margin-bottom:10px; }
.rel-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(290px,1fr)); gap:14px; }
.rel-col { background:#0d1420; border:1px solid #1f2a3a; border-radius:12px; overflow:hidden; display:flex; flex-direction:column; }
.rel-head { padding:12px; font-weight:800; text-align:center; border-bottom:3px solid #2ea043; background:#101a2b; }
.rel-head.tent { border-bottom-color:#d29922; } .rel-head.future { border-bottom-color:#8b949e; }
.rel-tag { font-size:10.5px; color:#8b949e; letter-spacing:1px; font-weight:600; }
.rel-body { padding:8px; overflow-y:auto; max-height:560px; }
.deliv { background:#121a26; border:1px solid #1f2a3a; border-radius:8px; padding:8px 10px; margin-bottom:6px; }
.deliv-date { font-size:11px; color:#8b949e; margin-bottom:3px; }
.deliv-title { font-size:13px; }
.who { font-size:10px; padding:1px 7px; border-radius:10px; font-weight:700; }
.who.ai { background:#143a23; color:#3fb950; } .who.claude { background:#1a2c4a; color:#58a6ff; }
.more { cursor:pointer; color:#58a6ff; font-size:12px; padding:4px; }
details.day > summary { cursor:pointer; padding:6px 8px; font-size:12.5px; font-weight:700; color:#9fb0c3; list-style:none; }
details.day { border-bottom:1px solid #1f2a3a; margin-bottom:4px; }
.trk-team { margin-bottom:14px; }
.trk-name { font-weight:800; color:#5cc26e; margin-bottom:6px; letter-spacing:.5px; }
.pill { background:#1c2533; border-radius:10px; padding:1px 9px; font-size:12px; color:#9fb0c3; }
.trk-item { background:#0d1420; border:1px solid #1f2a3a; border-radius:8px; margin-bottom:5px; }
.trk-item summary { padding:8px 10px; cursor:pointer; font-size:13.5px; display:flex; gap:8px; align-items:center; list-style:none; }
.trk-dot { width:8px; height:8px; border-radius:50%; background:#d29922; flex:none; }
.trk-desc { padding:0 12px 10px 26px; font-size:12.5px; color:#9fb0c3; }
.ev { display:flex; gap:10px; padding:7px 10px; border-radius:8px; margin-bottom:5px; background:#0d1420; border:1px solid #1f2a3a; align-items:baseline; }
.ev .tag { flex:none; font-size:11px; font-weight:700; color:#8b949e; min-width:84px; }
.ev .tag2 { flex:none; font-size:10px; font-weight:700; padding:1px 8px; border-radius:10px; background:#1c2533; color:#9fb0c3; }
.ev.ok .tag2 { background:#143a23; color:#3fb950; } .ev.done .tag2 { background:#1a2c4a; color:#58a6ff; }
.ev .txt { font-size:13px; }
.btnp { background:#7d2c2c; color:#fff; padding:8px 16px; border-radius:8px; text-decoration:none; font-weight:700; }
.btnr { background:#1f6f35; color:#fff; padding:8px 16px; border-radius:8px; text-decoration:none; font-weight:700; }
.muted { color:#8b949e; } ul { padding-left:20px; } li { font-size:13px; margin-bottom:4px; }
footer { text-align:center; color:#566374; padding:18px; font-size:12px; }
</style></head><body>
<header>
<h1>DOWN HERE <b>!</b></h1>
<p class='sub'>Colonie &middot; 4X &middot; exploration spatiale &mdash; d&eacute;velopp&eacute; 24/7 par une IA locale autonome supervis&eacute;e. Mise &agrave; jour: $genAt.</p>
$publicNote
<nav>
<a onclick="show('overview',this)" class='on'>Vue d'ensemble</a>
<a onclick="show('releases',this)">Release View</a>
<a onclick="show('tracker',this)">Progress Tracker</a>
<a onclick="show('activity',this)">Activit&eacute;</a>
<a onclick="show('feedback',this)">&#128172; Feedback</a>
</nav>
<script>
function show(id, el) {
  document.querySelectorAll('section').forEach(s => s.classList.remove('on'));
  document.getElementById(id).classList.add('on');
  document.querySelectorAll('nav a').forEach(a => a.classList.remove('on'));
  el.classList.add('on');
  try { sessionStorage.setItem('tab', id); } catch (e) {}
}
// The live dashboard reloads itself to refresh data: restore the active
// tab and the scroll position so a refresh never throws the user back
// to the overview tab.
window.addEventListener('DOMContentLoaded', () => {
  let tab = 'overview';
  try { tab = sessionStorage.getItem('tab') || 'overview'; } catch (e) {}
  const link = Array.from(document.querySelectorAll('nav a'))
    .find(a => (a.getAttribute('onclick') || '').indexOf("'" + tab + "'") >= 0);
  if (link && document.getElementById(tab)) { show(tab, link); }
  else { document.getElementById('overview').classList.add('on'); }
  try {
    const y = sessionStorage.getItem('scrollY');
    if (y !== null) window.scrollTo(0, parseFloat(y));
  } catch (e) {}
});
window.addEventListener('beforeunload', () => {
  try { sessionStorage.setItem('scrollY', String(window.scrollY)); } catch (e) {}
  // Inner scrollable panes (Release View columns, etc.) reset on every
  // 10s reload too: save each pane's scrollTop keyed by its index.
  try {
    const tops = Array.from(document.querySelectorAll('.rel-body')).map(el => el.scrollTop);
    sessionStorage.setItem('relScroll', JSON.stringify(tops));
  } catch (e) {}
});
window.addEventListener('DOMContentLoaded', () => {
  try {
    const tops = JSON.parse(sessionStorage.getItem('relScroll') || '[]');
    document.querySelectorAll('.rel-body').forEach((el, i) => {
      if (typeof tops[i] === 'number') el.scrollTop = tops[i];
    });
  } catch (e) {}
});
// Collapsible groups: remember which ones the user opened/closed so the
// 10s data refresh never undoes a manual fold.
window.addEventListener('DOMContentLoaded', () => {
  const all = document.querySelectorAll('details');
  let saved = {};
  try { saved = JSON.parse(sessionStorage.getItem('folds') || '{}'); } catch (e) {}
  all.forEach((d, i) => {
    const key = 'd' + i + ':' + (d.querySelector('summary') ? d.querySelector('summary').textContent.trim().slice(0, 40) : '');
    if (key in saved) { d.open = saved[key]; }
    d.addEventListener('toggle', () => {
      saved[key] = d.open;
      try { sessionStorage.setItem('folds', JSON.stringify(saved)); } catch (e) {}
    });
  });
});
</script>
</header>
<main>
<section id='releases'><div class='card'><h2>&#128640; Release View &mdash; livraisons dat&eacute;es (donn&eacute;es git r&eacute;elles)</h2>$relHtml</div></section>
<section id='tracker'><div class='card'><h2>&#128202; Progress Tracker &mdash; en d&eacute;veloppement par &eacute;quipe</h2>$trkHtml</div></section>
<section id='feedback'><div class='card'><h2>&#128172; Feedback &mdash; demandes de features &amp; bugs</h2>
$feedbackBody</div></section>
<section id='activity'><div class='card'><h2>&#9889; Activit&eacute; dat&eacute;e (25 derniers commits)</h2>$actRows</div></section>
<section id='overview'>
<div class='kpis'>
<div class='kpi'><b>$pct%</b>avancement<div class='bar'><i></i></div><span class='muted'>$done / $total t&acirc;ches</span></div>
<div class='kpi'><b class='g'>$kept</b>patches accept&eacute;s</div>
<div class='kpi'><b class='r'>$reverted</b>annul&eacute;s</div>
<div class='kpi'><b class='y'>$predicted</b>refus&eacute;s avant build (pr&eacute;diction)</div>
</div>
$liveBlock
<div class='card'><h2>&#127757; Le projet</h2>
<p>DOWN HERE ! commence au niveau bact&eacute;rie (ouverture fa&ccedil;on Spore), grandit en colonie profonde fa&ccedil;on RimWorld/Dwarf Fortress sur des plan&egrave;tes hexagonales compl&egrave;tes (poly&egrave;dre de Goldberg), et s'&eacute;tend en 4X spatial jusqu'&agrave; un endgame fa&ccedil;on Kerbal. Particularit&eacute; unique: le gameplay est &eacute;crit par un LLM local autonome (boucle build&rarr;test&rarr;simulation&rarr;commit), supervis&eacute; et outill&eacute; par une IA frontier. Chaque livraison ci-dessus est un commit r&eacute;el, dat&eacute;, v&eacute;rifi&eacute; par compilation, tests et simulation jou&eacute;e.</p></div>
</section>
</main>
<footer>DOWN HERE ! &mdash; d&eacute;p&ocirc;t: github.com/Duperopope/Rimwork &middot; g&eacute;n&eacute;r&eacute; $genAt</footer>
</body></html>
"@
}
