<#
DOWN HERE - Dashboard (API + SPA moderne).

Architecture pro : le serveur expose UNE API JSON (Get-DashboardData) et sert une
SPA mono-fichier (Get-DashboardHtml) qui la consomme et se rafraichit seule
(fetch /api.json toutes les 4s) - pas de rechargement de page, pas de build, pas
de dependance reseau (fonctionne hors-ligne). La meme SPA sert au site public
(donnees injectees inline par publish_site).

Design : theme "abysses bioluminescents" (le jeu = cellules dans la soupe
primordiale) - fond anime de cellules a la derive, verre depoli, halos cyan/vert.
Statut honnete (LLM on/off + conscience du mode ARENA), activite REELLE.
#>

. "$PSScriptRoot\State.ps1"   # Get-DownHereState (+ Config, Modes)

# Activite datee, REELLE : commits des deux depots, fusionnes par horodatage,
# DEBARRASSES du bruit auto ("site: progress update (auto)").
function Get-DashboardActivity {
    param($Config = (Get-DownHereConfig), [int]$Max = 30)
    $rows = @()
    # git emet de l'UTF-8; sans forcer l'encodage, PowerShell decode la sortie en
    # CP850 (accents casses: "co├╗t" au lieu de "cout", "R®duire" au lieu de
    # "Reduire"). On force UTF-8 le temps de lire le log, puis on restaure.
    $prevEnc = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        foreach ($repo in @($Config.Root, (Join-Path $Config.Root 'reference\thrive'))) {
            $log = git -C $repo log -80 --format="%at|%ad|%s" --date=format:"%d/%m %H:%M" 2>$null
            foreach ($l in $log) {
                $p = $l -split '\|', 3
                if ($p.Count -lt 3) { continue }
                if ($p[2] -match 'site: progress update|progress update \(auto\)') { continue }
                $rows += [pscustomobject]@{ at = [long]$p[0]; date = $p[1]; msg = $p[2] }
            }
        }
    } finally { [Console]::OutputEncoding = $prevEnc }
    $out = @()
    foreach ($c in ($rows | Sort-Object at -Descending | Select-Object -First $Max)) {
        $isAi = $c.msg -match '^\[ai-loop'
        $type = if ($c.msg -match '^(feat|fix|refactor|docs|chore|test|perf)') { $Matches[1] } elseif ($isAi) { 'ai' } else { 'commit' }
        $out += @{ date = $c.date; who = $(if ($isAi) { 'IA locale' } else { 'superviseur' }); type = $type
            text = ($c.msg -replace '^\[ai-loop iter \d+\]\s*', '' -replace '^(feat|fix|refactor|docs|chore|test|perf)(\([^)]*\))?:\s*', '') }
    }
    return $out
}

# Taches en file (roadmap), groupees par categorie.
function Get-DashboardTracker {
    param($Config = (Get-DownHereConfig))
    $rm = Get-Content $Config.Paths.Roadmap -ErrorAction SilentlyContinue
    $items = @()
    foreach ($line in $rm) {
        if ($line -match '^\s*-\s*\[ \]\s*(.+)$') {
            $t = $Matches[1]
            $cat = if ($t -match '\.json') { 'Donnees' } elseif ($t -match '\.po') { 'Traductions' } elseif ($t -match '\.cs') { 'Code' } else { 'Autre' }
            $items += @{ cat = $cat; text = $t }
        }
    }
    return $items
}

function Get-DashboardData {
    param($Config = (Get-DownHereConfig))
    $st = Get-DownHereState -Config $Config
    $rm = Get-Content $Config.Paths.Roadmap -ErrorAction SilentlyContinue
    $dl = Get-Content $Config.Paths.DevLog -ErrorAction SilentlyContinue
    $done = @($rm | Select-String '^\s*-\s*\[x\]').Count
    $todo = @($rm | Select-String '^\s*-\s*\[ \]').Count
    $tot = [Math]::Max(1, $done + $todo)
    $lessons = @()
    try { $lessons = @(Get-Content (Join-Path $Config.Paths.Logs 'lessons.md') | Where-Object { $_.Trim() } | Select-Object -Last 6 | ForEach-Object { $_ -replace '^- ', '' }) } catch {}
    $fb = @()
    try {
        $e = Get-Content (Join-Path $Config.Paths.Logs 'feedback.jsonl') | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} } | Where-Object { $_ }
        $e = @($e); [array]::Reverse($e)
        foreach ($f in ($e | Select-Object -First 20)) { $fb += @{ date = $f.date; type = $f.type; status = $f.status; text = $f.text } }
    } catch {}
    # Fraicheur du dev : age du dernier health.json (pour un statut honnete).
    $devAgeMin = $null
    try { $devAgeMin = [int]((Get-Date) - [datetime]::ParseExact($st.health.timestamp, "yyyy-MM-dd HH:mm:ss", $null)).TotalMinutes } catch {}

    # Statut LIVE de l'arene (ecrit par model_arena.ps1 a chaque etape).
    $arena = $null
    try { $arena = (Get-Content (Join-Path $Config.Paths.Logs 'arena_status.json') -Raw -ErrorAction Stop | ConvertFrom-Json) } catch {}

    # Selection MANUELLE: modele epingle + dernier message de la selection.
    $llmPin = $null; try { $llmPin = (Get-Content (Join-Path $Config.Paths.Logs 'llm_pinned.txt') -Raw -ErrorAction Stop).Trim() } catch {}
    $llmUseMsg = $null; try { $llmUseMsg = (Get-Content (Join-Path $Config.Paths.Logs 'llm_use_status.txt') -Raw -ErrorAction Stop).Trim() } catch {}

    # Console LLM : derniers tests + sorties des modeles (onglet Console).
    $console = @()
    try {
        foreach ($l in (Get-Content (Join-Path $Config.Paths.Logs 'llm_console.jsonl') -ErrorAction Stop | Select-Object -Last 200)) {
            try { $console += ($l | ConvertFrom-Json) } catch {}
        }
    } catch {}
    # Progression LIVE (barre dynamique) : telechargement (% octets) ou benchmark.
    $arenaProgress = $null
    try { $arenaProgress = (Get-Content (Join-Path $Config.Paths.Logs 'arena_progress.json') -Raw -ErrorAction Stop | ConvertFrom-Json) } catch {}

    # Evenements arene (cote modeles) : telecharge / benche / champion / echec.
    $arenaEvents = @()
    try {
        foreach ($l in (Get-Content (Join-Path $Config.Paths.Logs 'arena_events.jsonl') -ErrorAction Stop | Select-Object -Last 30)) {
            try { $arenaEvents += ($l | ConvertFrom-Json) } catch {}
        }
    } catch {}

    # Serie temporelle (graphes temps reel) : derniers snapshots d'etat.
    $history = @()
    try {
        $snaps = Get-Content (Join-Path $Config.Paths.Logs 'state_history.jsonl') -ErrorAction Stop | Select-Object -Last 48
        foreach ($s in $snaps) {
            try { $j = $s | ConvertFrom-Json } catch { continue }
            $history += @{ t = ($j.timestamp -replace '^\d{4}-\d\d-\d\d ', ''); kept = [int]$j.devlog.kept; reverted = [int]$j.devlog.reverted; pct = [double]$j.roadmap.pct; llm = [bool]$j.llmAlive }
        }
    } catch {}

    return @{
        generatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        state       = $st
        devAgeMin   = $devAgeMin
        progress    = @{ pct = [math]::Round($done * 100 / $tot); done = $done; todo = $todo
            kept = @($dl | Select-String 'KEPT:|DONE ').Count; reverted = @($dl | Select-String 'REVERTED').Count
            predicted = @($dl | Select-String 'ECHEC-PREDIT|PREDICTED|WM-SKIP').Count
        }
        activity    = (Get-DashboardActivity -Config $Config)
        tracker     = (Get-DashboardTracker -Config $Config)
        lessons     = $lessons
        feedback    = $fb
        arena       = $arena
        history     = $history
        llm         = @{ pinned = $llmPin; useMsg = $llmUseMsg }
        console     = $console
        arenaEvents = $arenaEvents
        arenaProgress = $arenaProgress
    }
}

function Get-DashboardHtml {
    param([string]$DataJson = $null)   # fourni -> page statique (public) ; sinon -> live (fetch)
    $boot = if ($DataJson) { "window.__DATA__=$DataJson;" } else { "" }
    $html = @'
<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>DOWN HERE — Console</title>
<style>
:root{
 --bg0:#03070e;--bg1:#081424;--bg2:#0b1a2e;
 --glass:rgba(13,26,44,.62);--glass2:rgba(9,18,32,.55);
 --line:rgba(70,224,200,.16);--line2:rgba(120,160,200,.10);
 --ink:#eaf4f8;--mut:#8ba2b6;--dim:#5d7286;
 --cyan:#2ee6c8;--green:#49e29f;--blue:#4aa6ff;--red:#ff6b6b;--amb:#ffc861;--violet:#9d8cff;
 --grad:linear-gradient(100deg,#2ee6c8,#49e29f 45%,#4aa6ff);
}
*{box-sizing:border-box;margin:0}
html,body{height:100%}
body{background:var(--bg0);color:var(--ink);font:14px/1.55 "Inter","Segoe UI",system-ui,sans-serif;-webkit-font-smoothing:antialiased;overflow-x:hidden}
#bg{position:fixed;inset:0;z-index:0;pointer-events:none}
.aura{position:fixed;inset:0;z-index:0;pointer-events:none;
 background:
  radial-gradient(900px 600px at 78% -8%,rgba(46,230,200,.10),transparent 60%),
  radial-gradient(800px 700px at 10% 110%,rgba(74,166,255,.10),transparent 60%),
  linear-gradient(180deg,var(--bg1),var(--bg0) 70%)}
a{color:var(--blue);text-decoration:none}
.shell{position:relative;z-index:1}
.top{position:sticky;top:0;z-index:6;backdrop-filter:blur(14px);background:linear-gradient(180deg,rgba(6,14,24,.92),rgba(6,14,24,.55));border-bottom:1px solid var(--line)}
.top .wrap{max-width:1320px;margin:0 auto;display:flex;align-items:center;gap:18px;flex-wrap:wrap;padding:16px 26px}
.brand{display:flex;align-items:center;gap:13px}
.mark{width:34px;height:34px;border-radius:11px;background:var(--grad);position:relative;box-shadow:0 0 22px rgba(46,230,200,.5);flex:none}
.mark::after{content:"";position:absolute;inset:8px;border-radius:6px;background:var(--bg0);opacity:.55}
.mark::before{content:"";position:absolute;left:50%;top:50%;width:8px;height:8px;border-radius:50%;transform:translate(-50%,-50%);background:var(--cyan);box-shadow:0 0 12px var(--cyan);animation:beat 2.6s ease-in-out infinite}
.bt{font-size:21px;font-weight:900;letter-spacing:.6px;line-height:1}
.bt .g{background:var(--grad);-webkit-background-clip:text;background-clip:text;color:transparent}
.tag{font-size:11.5px;color:var(--mut);margin-top:3px;letter-spacing:.2px}
.pills{display:flex;gap:8px;margin-left:auto;flex-wrap:wrap}
.pill{display:flex;align-items:center;gap:7px;background:var(--glass);border:1px solid var(--line2);border-radius:999px;padding:6px 13px;font-size:12px;font-weight:600;color:var(--mut)}
.dot{width:8px;height:8px;border-radius:50%;background:var(--dim);position:relative;flex:none}
.dot.on{background:var(--green);box-shadow:0 0 9px var(--green)}
.dot.on::after{content:"";position:absolute;inset:-4px;border-radius:50%;border:1px solid var(--green);opacity:.6;animation:ring 2s ease-out infinite}
.dot.off{background:var(--red);box-shadow:0 0 9px var(--red)}
.dot.warn{background:var(--amb);box-shadow:0 0 9px var(--amb)}
main{max-width:1320px;margin:0 auto;padding:24px 26px 70px}
.ctrl{display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin-bottom:22px}
.btn{border:none;border-radius:12px;padding:12px 22px;font-weight:800;font-size:14px;cursor:pointer;color:#04121a;transition:.18s;letter-spacing:.3px}
.btn:hover{transform:translateY(-1px);filter:brightness(1.07)}
.btn.start{background:var(--grad);box-shadow:0 6px 26px rgba(46,230,200,.34)}
.btn.stop{background:linear-gradient(100deg,#ff7a6b,#ff5470);color:#fff;box-shadow:0 6px 26px rgba(255,90,90,.3)}
.btn.ghost{background:var(--glass);color:var(--ink);border:1px solid var(--line);box-shadow:none}
.seg{display:flex;gap:4px;background:var(--glass2);border:1px solid var(--line2);border-radius:13px;padding:4px}
.seg button{background:none;border:none;color:var(--mut);padding:9px 15px;font-weight:800;font-size:12px;cursor:pointer;border-radius:9px;letter-spacing:.4px;transition:.15s}
.seg button.on{background:var(--grad);color:#04121a;box-shadow:0 0 16px rgba(46,230,200,.35)}
.seg button:hover:not(.on){color:var(--ink);background:rgba(255,255,255,.04)}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:15px;margin-bottom:22px}
.kpi{position:relative;background:var(--glass);border:1px solid var(--line2);border-radius:17px;padding:18px 20px;overflow:hidden}
.kpi::before{content:"";position:absolute;left:0;top:0;height:100%;width:3px;background:var(--grad);opacity:.85}
.kpi .v{font-size:31px;font-weight:900;line-height:1;font-variant-numeric:tabular-nums}
.kpi .l{color:var(--mut);font-size:11.5px;margin-top:7px;text-transform:uppercase;letter-spacing:.6px}
.kpi .bar{height:6px;background:rgba(255,255,255,.06);border-radius:4px;margin-top:12px;overflow:hidden}
.kpi .bar i{display:block;height:100%;background:var(--grad);box-shadow:0 0 12px rgba(46,230,200,.5);transition:width .6s}
.v.g{background:var(--grad);-webkit-background-clip:text;background-clip:text;color:transparent}
.v.r{color:var(--red)}.v.y{color:var(--amb)}.v.b{color:var(--blue)}.v.p{color:var(--violet)}
.tabs{display:flex;gap:6px;margin-bottom:20px;flex-wrap:wrap}
.tabs button{background:var(--glass2);border:1px solid var(--line2);color:var(--mut);padding:10px 17px;font-weight:800;font-size:13px;cursor:pointer;border-radius:11px;transition:.15s}
.tabs button.on{color:var(--ink);border-color:var(--line);box-shadow:inset 0 0 0 1px rgba(46,230,200,.25),0 0 18px rgba(46,230,200,.12)}
.tabs button:hover:not(.on){color:var(--ink)}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:17px}
.card{position:relative;background:var(--glass);border:1px solid var(--line2);border-radius:18px;padding:20px;backdrop-filter:blur(6px)}
.card.wide{grid-column:1/-1}
.card h3{font-size:11.5px;text-transform:uppercase;letter-spacing:1.2px;color:var(--mut);margin-bottom:15px;display:flex;align-items:center;gap:9px}
.row{display:flex;gap:12px;padding:11px 0;border-bottom:1px solid var(--line2);align-items:flex-start}.row:last-child{border:0}
.time{flex:none;color:var(--dim);font-size:12px;min-width:78px;font-variant-numeric:tabular-nums;padding-top:2px}
.badge{flex:none;font-size:10px;font-weight:900;padding:3px 9px;border-radius:999px;background:rgba(255,255,255,.06);color:var(--mut);text-transform:uppercase;letter-spacing:.5px}
.badge.feat{background:rgba(73,226,159,.16);color:var(--green)}
.badge.fix{background:rgba(255,200,97,.16);color:var(--amb)}
.badge.ai{background:rgba(74,166,255,.18);color:var(--blue)}
.badge.refactor,.badge.docs,.badge.test,.badge.chore,.badge.commit{background:rgba(157,140,255,.16);color:var(--violet)}
.txt{font-size:13.5px}.mut{color:var(--mut)}.hl{color:var(--cyan);font-weight:700}
.task{background:var(--glass2);border:1px solid var(--line2);border-radius:12px;padding:11px 13px;margin-bottom:9px;font-size:13px;transition:.15s}
.task:hover{border-color:var(--line);transform:translateX(2px)}
.cat{display:inline-block;font-size:10px;font-weight:900;color:var(--cyan);background:rgba(46,230,200,.12);border-radius:7px;padding:2px 8px;margin-right:9px;letter-spacing:.4px}
.empty{color:var(--dim);padding:22px;text-align:center}
.warnbox{display:flex;gap:11px;align-items:center;background:linear-gradient(100deg,rgba(255,200,97,.12),rgba(255,200,97,.04));border:1px solid rgba(255,200,97,.3);color:#f4d79a;border-radius:13px;padding:13px 16px;font-size:13.5px;margin-bottom:18px}
.warnbox.ok{background:linear-gradient(100deg,rgba(74,166,255,.12),rgba(46,230,200,.05));border-color:rgba(74,166,255,.3);color:#bfe0ff}
input,select,textarea{background:var(--glass2);color:var(--ink);border:1px solid var(--line2);border-radius:11px;padding:11px;font:inherit}
input:focus,select:focus,textarea:focus{outline:none;border-color:var(--line)}
/* pipeline recursif */
.flow{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.node{flex:1;min-width:120px;background:var(--glass2);border:1px solid var(--line2);border-radius:12px;padding:12px 13px;position:relative;transition:.2s}
.node.act{border-color:var(--line);box-shadow:0 0 20px rgba(46,230,200,.16)}
.node .n{font-size:11px;color:var(--mut);text-transform:uppercase;letter-spacing:.5px}
.node .d{font-size:13px;font-weight:700;margin-top:3px}
.node .nic{color:var(--cyan);margin-bottom:3px}
.arrow{color:var(--dim);font-size:18px;flex:none}
.chip{display:inline-flex;align-items:center;gap:6px;background:var(--glass2);border:1px solid var(--line2);border-radius:999px;padding:4px 11px;font-size:12px;font-weight:700;margin:3px 5px 3px 0}
.chip.on{border-color:var(--line);color:var(--cyan)}
/* icones (Lucide inline) */
.ic{display:inline-block;vertical-align:-3px;flex:none}
h3 .ic{vertical-align:-2px;opacity:.85}
/* scrollbars discrets (fini les grosses barres moches) */
*{scrollbar-width:thin;scrollbar-color:rgba(120,160,200,.2) transparent}
::-webkit-scrollbar{width:8px;height:8px}
::-webkit-scrollbar-thumb{background:rgba(120,160,200,.18);border-radius:8px}
::-webkit-scrollbar-track{background:transparent}
.toolbar{display:flex;gap:8px;margin-bottom:12px;flex-wrap:wrap}
.btn.sm{padding:6px 12px;font-size:12.5px;border-radius:9px}
#toast{position:fixed;bottom:24px;left:50%;transform:translateX(-50%) translateY(20px);background:var(--glass);border:1px solid var(--line);color:var(--ink);padding:10px 18px;border-radius:12px;font-weight:600;opacity:0;pointer-events:none;transition:.25s;z-index:20;backdrop-filter:blur(10px)}
#toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
/* console LLM (terminal) - compacte, sans barre de scroll visible */
.termhead{font-size:12px;color:var(--mut);margin-bottom:10px}
.term{font-family:ui-monospace,"Cascadia Code",Consolas,monospace;font-size:12px;max-height:54vh;overflow:auto;background:rgba(0,0,0,.28);border:1px solid var(--line2);border-radius:12px;padding:10px 14px}
.term{scrollbar-width:none}.term::-webkit-scrollbar{display:none}
.cline{padding:5px 0;border-bottom:1px solid rgba(255,255,255,.04)}.cline:last-child{border:0}
.ct{color:var(--dim)}.cs{color:var(--violet);margin-left:8px;font-weight:700}.ck{margin-left:8px;font-weight:800}
.cx{color:var(--ink);margin-top:3px;white-space:pre-wrap;word-break:break-word;opacity:.9;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
.catbadge{display:inline-flex;align-items:center;gap:5px;background:var(--glass2);border:1px solid var(--line2);border-radius:8px;padding:3px 9px;font-size:11.5px;color:var(--mut)}
.catbadge b{color:var(--ink);font-weight:600}
.htip{position:relative;display:inline-flex;cursor:help;color:var(--mut);align-self:center}
.htip:hover{color:var(--cyan)}
.htip .tipbox{position:absolute;z-index:60;right:0;top:150%;width:312px;background:#0b1722;border:1px solid var(--line);border-radius:13px;padding:13px 15px;box-shadow:0 16px 48px rgba(0,0,0,.6);font-size:12px;line-height:1.5;color:var(--ink);display:none;white-space:normal;text-align:left;font-weight:400}
.htip:hover .tipbox{display:block}
.tipbox h5{font-size:12px;color:var(--cyan);margin:0 0 8px;word-break:break-all}
.tipbox .tr{display:flex;justify-content:space-between;gap:14px;margin:4px 0}
.tipbox .tk{color:var(--mut)}
.tipbox .sub{color:var(--mut);font-size:11px;margin-top:9px;border-top:1px solid var(--line2);padding-top:8px;line-height:1.45}
@keyframes beat{0%,100%{transform:translate(-50%,-50%) scale(1);opacity:1}50%{transform:translate(-50%,-50%) scale(1.5);opacity:.55}}
@keyframes ring{0%{transform:scale(.6);opacity:.7}100%{transform:scale(1.7);opacity:0}}
</style></head><body>
<canvas id="bg"></canvas><div class="aura"></div>
<div class="shell">
<div class="top"><div class="wrap">
  <div class="brand">
    <div class="mark"></div>
    <div><div class="bt"><span class="g">DOWN HERE</span> !</div>
    <div class="tag">Système autonome qui code aux origines du vivant — IA récursive · world model · jeu cellulaire</div></div>
  </div>
  <div class="pills" id="pills"></div>
</div></div>
<main>
  <div id="banner"></div>
  <div class="ctrl" id="ctrl"></div>
  <div class="kpis" id="kpis"></div>
  <div class="tabs" id="tabs"></div>
  <div id="view"></div>
</main>
</div>
<script>
__BOOT__
const $=(h)=>{const t=document.createElement('template');t.innerHTML=h.trim();return t.content.firstChild;};
const esc=(s)=>(s==null?'':String(s)).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
// PowerShell ConvertTo-Json deballe un tableau d'1 element en OBJET -> on reforce
// en tableau partout (sinon .map/.slice plante des qu'une liste a 1 element).
const arr=(x)=>Array.isArray(x)?x:(x==null?[]:[x]);
// Vrai set d'icones open-source (Lucide, licence ISC) vendore inline -> hors-ligne,
// pas d'emoji. ic(name,size) rend un SVG qui herite de la couleur du texte.
const ICONS={
 terminal:'<polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/>',
 zap:'<polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>',
 flask:'<path d="M10 2v7.31"/><path d="M14 9.3V2"/><path d="M8.5 2h7"/><path d="M14 9.3a6.5 6.5 0 1 1-4 0"/><path d="M5.52 16h12.96"/>',
 trophy:'<path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6"/><path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18"/><path d="M4 22h16"/><path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22"/><path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22"/><path d="M18 2H6v7a6 6 0 0 0 12 0V2Z"/>',
 activity:'<polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/>',
 cpu:'<rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/><path d="M9 2v2M15 2v2M9 20v2M15 20v2M2 9h2M2 15h2M20 9h2M20 15h2"/>',
 repeat:'<polyline points="17 1 21 5 17 9"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/><polyline points="7 23 3 19 7 15"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/>',
 map:'<polygon points="1 6 1 22 8 18 16 22 23 18 23 2 16 6 8 2 1 6"/><line x1="8" y1="2" x2="8" y2="18"/><line x1="16" y1="6" x2="16" y2="22"/>',
 wrench:'<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/>',
 check:'<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/>',
 chart:'<line x1="12" y1="20" x2="12" y2="10"/><line x1="18" y1="20" x2="18" y2="4"/><line x1="6" y1="20" x2="6" y2="16"/>',
 list:'<line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/>',
 msg:'<path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/>',
 trend:'<polyline points="23 6 13.5 15.5 8.5 10.5 1 18"/><polyline points="17 6 23 6 23 12"/>',
 pin:'<path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/>',
 play:'<polygon points="5 3 19 12 5 21 5 3"/>',
 stop:'<rect x="5" y="5" width="14" height="14" rx="2"/>',
 rotate:'<polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/>',
 download:'<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/>',
 copy:'<rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
 trash:'<polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>',
 chevron:'<polyline points="9 18 15 12 9 6"/>',
 waves:'<path d="M2 6c.6.5 1.2 1 2.5 1C7 7 7 5 9.5 5c2.6 0 2.4 2 5 2 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1"/><path d="M2 12c.6.5 1.2 1 2.5 1 2.5 0 2.5-2 5-2 2.6 0 2.4 2 5 2 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1"/><path d="M2 18c.6.5 1.2 1 2.5 1 2.5 0 2.5-2 5-2 2.6 0 2.4 2 5 2 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1"/>',
 moon:'<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>',
 swords:'<polyline points="14.5 17.5 3 6 3 3 6 3 17.5 14.5"/><line x1="13" y1="19" x2="19" y2="13"/><line x1="16" y1="16" x2="20" y2="20"/><line x1="19" y1="21" x2="21" y2="19"/>',
 robot:'<rect x="3" y="11" width="18" height="10" rx="2"/><circle cx="12" cy="5" r="2"/><path d="M12 7v4"/><line x1="8" y1="16" x2="8" y2="16"/><line x1="16" y1="16" x2="16" y2="16"/>',
 alert:'<path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>',
 info:'<circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/>',
 archive:'<polyline points="21 8 21 21 3 21 3 8"/><rect x="1" y="3" width="22" height="5"/><line x1="10" y1="12" x2="14" y2="12"/>',
 shield:'<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
 hdd:'<line x1="22" y1="12" x2="2" y2="12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/><line x1="6" y1="16" x2="6.01" y2="16"/><line x1="10" y1="16" x2="10.01" y2="16"/>'
};
function ic(n,sz){sz=sz||16;return '<svg class="ic" width="'+sz+'" height="'+sz+'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+(ICONS[n]||'')+'</svg>';}
let DATA=window.__DATA__||null, TAB=sessionStorage.getItem('tab')||'overview', BUSY=false;
const TABS=[['overview','Vue d\'ensemble'],['activity','Activité'],['arena','Arène'],['console','Console'],['tasks','Tâches'],['feedback','Feedback']];

async function api(path,opts){ try{return await fetch(path,opts);}catch(e){return null;} }
async function load(){ if(!window.__DATA__){ const r=await api('/api.json'); if(r){try{DATA=await r.json();}catch(e){}} } render(); }
async function act(path){ if(BUSY)return; BUSY=true; await api(path,{method:'POST'}); setTimeout(()=>{BUSY=false;load();},1200); }
function setMode(m){ act('/mode?set='+m); }

function pill(label,cls){ return `<span class="pill"><span class="dot ${cls}"></span>${label}</span>`; }
function renderPills(){
  const s=DATA?DATA.state:null; const llm=s&&s.llmAlive; const mode=s?s.mode:'?'; const age=DATA?DATA.devAgeMin:null;
  // LLM : conscient du mode ARENA (l'arene swappe les modeles -> 1234 par intermittence, ce n'est pas une panne).
  let llmL='LLM en ligne',llmC='on';
  if(!llm){ if(mode==='ARENA'){ llmL='LLM : arène (swap)'; llmC='warn'; } else { llmL='LLM hors ligne'; llmC='off'; } }
  let fresh='warn',freshL='dev : inconnu';
  if(age!=null){ if(age<5){fresh='on';freshL='dev actif'} else if(age<120){fresh='warn';freshL='dev : '+age+' min'} else {fresh='off';freshL='dev inactif ('+Math.round(age/60)+'h)'} }
  document.getElementById('pills').innerHTML=
    pill(llmL,llmC)+
    pill('Mode : '+mode, mode!=='IDLE'?'on':'')+
    pill(s&&s.stackState==='PAUSED'?'En pause':'En marche', s&&s.stackState==='PAUSED'?'off':'on')+
    pill(freshL,fresh);
}
function renderBanner(){
  const s=DATA?DATA.state:null; let h='';
  if(s&&!s.llmAlive){
    if(s.mode==='ARENA'){ h='<div class="warnbox ok">'+ic('flask')+' Mode <b>ARENA</b> : l\'arène teste des modèles et occupe le GPU — le serveur de prod est coupé par intermittence. C\'est normal, pas une panne.</div>'; }
    else { h='<div class="warnbox">'+ic('alert')+' Le LLM local est <b>hors ligne</b> — clique <b>DÉMARRER</b> (lance llama-server + la pile). Sans lui, le dev IA ne progresse pas.</div>'; }
  }
  document.getElementById('banner').innerHTML=h;
}
function renderCtrl(){
  const s=DATA?DATA.state:null; const paused=s&&s.stackState==='PAUSED';
  const modes=[['DEV','code le jeu'],['PLAY','joue'],['ARENA','choisit le cerveau'],['EVOLVE','s\'auto-modifie'],['IDLE','repos']];
  const seg=modes.map(m=>`<button class="${s&&s.mode===m[0]?'on':''}" title="${m[1]}" onclick="setMode('${m[0]}')">${m[0]}</button>`).join('');
  document.getElementById('ctrl').innerHTML=
    (paused?`<button class="btn start" onclick="act('/resume')">${ic('play')} DÉMARRER</button>`
           :`<button class="btn stop" onclick="if(confirm('Arrêter toute la pile ?'))act('/pause')">${ic('stop')} ARRÊTER</button>`)+
    `<div class="seg">${seg}</div>`+
    `<a class="btn ghost" href="/chat">${ic('msg')} Parler à l'IA</a>`;
}
function renderKpis(){
  const p=DATA?DATA.progress:{}, b=DATA&&DATA.state?DATA.state.brain:null;
  const k=[['g',(p.pct||0)+'%','avancement jeu','<div class="bar"><i style="width:'+(p.pct||0)+'%"></i></div>'],
    ['g',p.kept||0,'patchs gardés',''],['r',p.reverted||0,'annulés (garde-fou)',''],
    ['y',p.predicted||0,'refusés avant build',''],
    ['p',b?b.utility:'—','cerveau · utilité','']];
  document.getElementById('kpis').innerHTML=k.map(x=>`<div class="kpi"><div class="v ${x[0]}">${x[1]}</div><div class="l">${x[2]}</div>${x[3]}</div>`).join('');
}
function renderTabs(){
  document.getElementById('tabs').innerHTML=TABS.map(t=>`<button class="${TAB===t[0]?'on':''}" onclick="go('${t[0]}')">${t[1]}</button>`).join('');
}
function go(t){ TAB=t; sessionStorage.setItem('tab',t); renderTabs(); renderView(); }

function card(title,body,wide){ return `<div class="card${wide?' wide':''}"><h3>${title}</h3>${body}</div>`; }
// Barre de progression LIVE (telechargement % octets, ou benchmark % epreuves).
function progBar(p){
  if(!p||p.pct==null) return '';
  const isDl=p.kind==='download';
  return '<div class="card" style="margin-bottom:16px"><div style="display:flex;align-items:center;gap:10px;margin-bottom:9px">'+ic(isDl?'download':'flask',16)+'<b>'+(isDl?'Téléchargement':'Benchmark en cours')+' — '+esc(p.key||'')+'</b><span class="hl" style="margin-left:auto;font-variant-numeric:tabular-nums">'+p.pct+'%</span></div><div class="bar" style="height:10px;background:rgba(255,255,255,.06);border-radius:6px;overflow:hidden"><i style="display:block;height:100%;width:'+p.pct+'%;background:var(--grad);box-shadow:0 0 14px rgba(46,230,200,.5);transition:width .5s"></i></div><div class="mut" style="margin-top:7px;font-size:12px">'+esc(p.label||'')+'</div></div>';}
function flowView(s){
  // Pipeline recursif REEL : roadmap -> patch LLM -> build/test -> garde/annule -> world model (qui re-trie).
  const mode=s?s.mode:'';
  const steps=[['map','Roadmap','une tâche', mode==='DEV'],
    ['cpu','LLM local','propose un patch', s&&s.llmAlive],
    ['wrench','Build + test','valide', mode==='DEV'],
    ['check','Garde / annule','ne garde que ce qui marche', mode==='DEV'],
    ['repeat','World model','ré-entraîne et re-trie', s&&s.brain]];
  const n=steps.map((x,i)=>'<div class="node'+(x[3]?' act':'')+'"><div class="nic">'+ic(x[0],20)+'</div><div class="n">'+x[1]+'</div><div class="d">'+x[2]+'</div></div>'+
    (i<steps.length-1?'<div class="arrow">'+ic('chevron',16)+'</div>':'')).join('');
  return card(ic('repeat')+' Boucle d\'auto-amélioration récursive',`<div class="flow">${n}</div>`,true);
}
function viewOverview(){
  const s=DATA?DATA.state:{}, b=s.brain, ct=s.currentTask;
  let task='<span class="mut">aucune tâche en cours</span>';
  if(ct&&ct.item){ task=esc(ct.item.length>150?ct.item.slice(0,150)+'…':ct.item); }
  const game=s.game&&s.game.running?`<span class="hl">lancé</span> (pid ${s.game.pid})`:'<span class="mut">fermé (le jeu ne tourne pas pendant le dev)</span>';
  const agentsList=s.agents?Object.keys(s.agents).filter(a=>s.agents[a]):[];
  const agents=agentsList.length?agentsList.map(a=>`<span class="chip on">⬤ ${esc(a)}</span>`).join(''):'<span class="mut">aucun agent actif</span>';
  const health=card(ic('activity')+' Santé en direct',
    `<div class="txt"><b>Tâche :</b> ${task}</div>
     <div class="txt" style="margin-top:10px"><b>Jeu :</b> ${game}</div>
     <div class="txt" style="margin-top:10px"><b>Agents :</b><div style="margin-top:6px">${agents}</div></div>`);
  let brain='<span class="mut">pas encore de cerveau conçu</span>';
  if(b){ brain=`<div class="txt">Champion <span class="hl">${esc(b.model)}</span> · ${b.features} features · utilité <span class="hl">${b.utility}</span></div>
    <div class="mut" style="margin-top:8px">gain +${b.gain} sur ${b.gens} générations (champion-challenger)</div>`; }
  const brainC=card(ic('cpu')+' Cerveau auto-conçu (successeur)',brain);
  const lessons=arr(DATA.lessons).length?arr(DATA.lessons).map(l=>`<div class="row"><div class="txt">${esc(l)}</div></div>`).join(''):'<div class="empty">—</div>';
  const lessonsC=card(ic('list')+' Leçons récentes de l\'IA',lessons);
  document.getElementById('view').innerHTML=flowView(s)+'<div style="height:18px"></div>'+`<div class="grid">${health}${trendsCard()}${brainC}${lessonsC}</div>`;
}
function viewActivity(){
  // Cote MODELES : evenements arene (telecharge / benche / champion / echec).
  const ev=arr(DATA&&DATA.arenaEvents).slice().reverse();
  const ick={download:'download',bench:'flask',champion:'trophy',fail:'alert',cycle:'repeat'};
  const colk={download:'#4aa6ff',bench:'#49e29f',champion:'var(--cyan)',fail:'#ff6b6b'};
  const evRows=ev.length?ev.map(e=>'<div class="row"><span class="time">'+esc(e.ts)+'</span><span class="badge" style="color:'+(colk[e.kind]||'var(--mut)')+'">'+ic(ick[e.kind]||'zap',13)+'</span><span class="txt">'+esc(e.text)+'</span></div>').join(''):'<div class="empty">aucun événement arène pour l\'instant (passe en mode ARENA)</div>';
  const evCard=card(ic('flask')+' Modèles &amp; arène — téléchargements, benchs, champions, échecs',evRows,true);
  // Cote CODE : commits du jeu et du systeme (hors bruit auto).
  const a=arr(DATA&&DATA.activity);
  const cRows=a.length?a.map(e=>`<div class="row"><span class="time">${esc(e.date)}</span><span class="badge ${esc(e.type)}">${esc(e.who==='IA locale'?'IA':e.type)}</span><span class="txt">${esc(e.text)}</span></div>`).join(''):'<div class="empty">aucun commit</div>';
  const cCard=card(ic('zap')+' Activité code — commits (hors bruit auto)',cRows,true);
  document.getElementById('view').innerHTML=progBar(DATA&&DATA.arenaProgress)+evCard+'<div style="height:16px"></div>'+cCard;
}
function viewTasks(){
  const t=arr(DATA&&DATA.tracker);
  if(!t.length){ document.getElementById('view').innerHTML=card(ic('list')+' Tâches en file',`<div class="empty">aucune tâche en file</div>`,true); return; }
  const rows=t.map(x=>`<div class="task"><span class="cat">${esc(x.cat)}</span>${esc(x.text)}</div>`).join('');
  document.getElementById('view').innerHTML=card(ic('list')+' Tâches en file (roadmap)',rows,true);
}
function viewFeedback(){
  const f=arr(DATA&&DATA.feedback);
  const form=`<form onsubmit="sendFb(event)" style="display:flex;gap:9px;flex-wrap:wrap;margin-bottom:16px">
    <select id="fbtype"><option value="feature">Feature</option><option value="bug">Bug</option></select>
    <input id="fbtext" placeholder="Décris ta demande ou un bug…" style="flex:1;min-width:240px">
    <button class="btn start" type="submit">Envoyer</button></form>`;
  const rows=(f&&f.length)?f.map(x=>`<div class="row"><span class="time">${esc(x.date)}</span><span class="badge">${esc(x.type)} · ${esc(x.status)}</span><span class="txt">${esc(x.text)}</span></div>`).join(''):'<div class="empty">aucune demande</div>';
  document.getElementById('view').innerHTML=card(ic('msg')+' Feedback',form+rows,true);
}
function sendFb(e){ e.preventDefault(); const t=document.getElementById('fbtext').value.trim(); if(!t)return;
  const ty=document.getElementById('fbtype').value;
  api('/feedback?type='+ty+'&text='+encodeURIComponent(t),{method:'GET'}).then(()=>{document.getElementById('fbtext').value='';setTimeout(load,400);}); }
// graphe SVG sans dependance (sparkline)
function spark(vals,color,h){
  h=h||42; const w=260; vals=(vals||[]).filter(v=>v!=null&&!isNaN(v)); if(vals.length<2) return '<div class="mut" style="font-size:12px">pas assez de données</div>';
  const mn=Math.min(...vals),mx=Math.max(...vals),rng=(mx-mn)||1;
  const xy=vals.map((v,i)=>[(i/(vals.length-1)*w),(h-((v-mn)/rng)*(h-8)-4)]);
  const line=xy.map(p=>p[0].toFixed(1)+','+p[1].toFixed(1)).join(' ');
  const area=`0,${h} `+line+` ${w},${h}`;
  const id='g'+Math.random().toString(36).slice(2,7);
  return `<svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" style="width:100%;height:${h}px;display:block">
    <defs><linearGradient id="${id}" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="${color}" stop-opacity=".35"/><stop offset="1" stop-color="${color}" stop-opacity="0"/></linearGradient></defs>
    <polygon points="${area}" fill="url(#${id})"/>
    <polyline points="${line}" fill="none" stroke="${color}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>
    <circle cx="${xy[xy.length-1][0].toFixed(1)}" cy="${xy[xy.length-1][1].toFixed(1)}" r="3" fill="${color}"/></svg>`;
}
function trendsCard(){
  const h=arr(DATA&&DATA.history);
  if(h.length<2) return '';
  const last=h[h.length-1];
  return card(ic('trend')+' Tendances (temps réel)',
    `<div style="display:flex;justify-content:space-between;align-items:baseline"><span class="mut">patchs gardés</span><b class="hl">${last.kept}</b></div>${spark(h.map(x=>x.kept),'#49e29f')}
     <div style="display:flex;justify-content:space-between;align-items:baseline;margin-top:10px"><span class="mut">annulés (garde-fou)</span><b style="color:var(--red)">${last.reverted}</b></div>${spark(h.map(x=>x.reverted),'#ff6b6b')}
     <div style="display:flex;justify-content:space-between;align-items:baseline;margin-top:10px"><span class="mut">avancement jeu</span><b style="color:var(--blue)">${last.pct}%</b></div>${spark(h.map(x=>x.pct),'#4aa6ff')}`);
}
// --- Indicateurs ingenieur deduits du nom de fichier GGUF ---
function quantInfo(f){
  const m=/Q(\d)_K_([MSL])/i.exec(f)||/Q(\d)_(\d)/i.exec(f)||/Q(\d)/i.exec(f);
  if(!m) return null;
  const bits=+m[1];
  const lbl={2:'2-bit · extrême, qualité dégradée',3:'3-bit · très compact, qualité un peu rognée',4:'4-bit · meilleur compromis taille/qualité',5:'5-bit · haute qualité',6:'6-bit · quasi sans perte',8:'8-bit · quasi fp16'}[bits]||(bits+'-bit');
  return {bits:bits,label:lbl};
}
function paramInfo(f){
  const moe=/(\d+(?:\.\d+)?)B[-_]?A(\d+(?:\.\d+)?)B/i.exec(f);   // 30B-A3B = 30B total / 3B actifs (MoE)
  if(moe) return {total:moe[1]+'B',active:moe[2]+'B',moe:true};
  const m=/(\d+(?:\.\d+)?)B/i.exec(f);
  return m?{total:m[1]+'B',active:m[1]+'B',moe:false}:null;
}
// Tooltip riche au survol d'un modele : tout ce qu'un ingenieur regarde et qu'un
// neophyte oublie (qualite, debit tok/s, empreinte VRAM + marge pour le jeu,
// quantization, parametres MoE, contexte, formule du score, barème).
function tipFor(t){
  const name=t.file||t.key;
  const q=quantInfo(name), pr=paramInfo(name);
  const row=(k,v)=>'<div class="tr"><span class="tk">'+k+'</span><span>'+v+'</span></div>';
  if(t.status==='echec'){
    return '<div class="tipbox"><h5>'+esc(name)+'</h5>'+row('État','<span style="color:var(--red)">échec</span>')+row('Raison',esc(t.note||'n\'a pas chargé'))+(q?row('Quantization',q.label):'')+(pr?row('Paramètres',pr.moe?(pr.total+' · ≈'+pr.active+' actifs'):pr.total):'')+'<div class="sub">tenté sur barème v'+esc(t.benchVer||'?')+' · cycle '+(t.lastCycle||'?')+'</div></div>';
  }
  const cats=arr(t.cats);
  const qual=(t.qualityPct!=null)?t.qualityPct:(cats.length?Math.round(cats.reduce((a,c)=>a+(c.pct||0),0)/cats.length):null);
  const gb=t.gb||0, head=gb?Math.round((16-gb)*10)/10:null;
  let h='<div class="tipbox"><h5>'+esc(name)+'</h5>';
  if(qual!=null) h+=row('Qualité (moy. épreuves)','<b>'+qual+'</b> / 100');
  h+=row('Débit',t.tokPerSec?('<b>'+t.tokPerSec+'</b> tok/s'):'<span class="mut">non mesuré</span>');
  if(t.secs) h+=row('Durée du test',t.secs+' s');
  if(gb) h+=row('Empreinte VRAM','<b>'+gb+'</b> Go'+(head!=null?(' · ~'+head+' Go libres pour le jeu'):''));
  if(t.ctx) h+=row('Fenêtre de contexte',(+t.ctx).toLocaleString('fr')+' tokens');
  if(q) h+=row('Quantization',q.label);
  if(pr) h+=row('Paramètres',pr.moe?(pr.total+' total · ≈'+pr.active+' actifs (MoE)'):pr.total);
  h+=row('Score composite',(t.total!=null?'<b>'+t.total+'</b> / 100':'—'));
  h+='<div class="sub">score = qualité − VRAM×0,6 + bonus débit. À qualité proche, le modèle le plus léger et le plus rapide gagne.<br>barème v'+esc(t.benchVer||'?')+' · testé au cycle '+(t.lastCycle||'?')+'</div></div>';
  return h;
}
// --- Gestionnaire des modeles sur le disque (fetch a la demande, pas toutes les 4s) ---
async function loadDisk(force){
  if(window._diskLoading) return;
  if(window._disk!==undefined && !force) return;
  window._diskLoading=true;
  const r=await api('/models.json');
  try{ window._disk=r?await r.json():null; }catch(e){ window._disk=null; }
  window._diskLoading=false;
  if(TAB==='arena') renderView();
}
async function actModel(path){ await api(path,{method:'POST'}); setTimeout(()=>loadDisk(true),500); }
function viewArenaDisk(){
  const d=window._disk;
  if(d===undefined){ loadDisk(); return '<div class="empty">inventaire du disque…</div>'; }
  if(!d){ return '<div class="empty">inventaire indisponible (WSL hors ligne ?)</div>'; }
  const ms=arr(d.models);
  if(!ms.length) return '<div class="empty">aucun modèle sur le disque</div>';
  const head='<div class="mut" style="font-size:11.5px;margin-bottom:11px">'+ms.length+' fichier(s) · <b>'+d.totalGb+' Go</b> occupés · maj '+esc(d.updatedAt)+'</div>';
  const col={champion:'var(--green)',base:'var(--blue)',challenger:'var(--cyan)',orphelin:'var(--mut)'};
  const rows=ms.slice().sort((a,b)=>(b.gb||0)-(a.gb||0)).map(m=>{
    const q=quantInfo(m.file);
    const tags=(m.champion?'<span class="badge" style="background:rgba(73,226,159,.16);color:var(--green)">champion</span>':'')+(m.archived?'<span class="badge" style="background:rgba(255,200,97,.14);color:var(--amb)">archivé</span>':'')+((m.protected&&!m.champion)?'<span class="badge" style="background:rgba(74,166,255,.14);color:var(--blue)">protégé</span>':'')+(m.role==='orphelin'?'<span class="badge" title="présent sur le disque mais absent du classement">orphelin</span>':'');
    const meta='<span class="mut" style="font-size:11.5px">'+m.gb+' Go'+(q?(' · '+q.bits+'-bit'):'')+(m.total!=null?(' · '+m.total+' pts'):'')+'</span>';
    const f="'"+esc(m.file)+"'";
    const arc='<button class="btn ghost sm" onclick="actModel(\'/models/archive?on='+(m.archived?'0':'1')+'&file=\'+encodeURIComponent('+f+'))">'+ic('archive')+(m.archived?' Restaurer':' Archiver')+'</button>';
    const prot=m.champion?'':'<button class="btn ghost sm" title="'+(m.protected?'autoriser la purge auto':'ne jamais purger automatiquement')+'" onclick="actModel(\'/models/protect?on='+(m.protected?'0':'1')+'&file=\'+encodeURIComponent('+f+'))">'+ic('shield')+(m.protected?' Libérer':' Protéger')+'</button>';
    const del=m.champion?'':'<button class="btn ghost sm" title="supprimer du disque" onclick="if(confirm(\'Supprimer définitivement \'+'+f+'+\' du disque ?\'))actModel(\'/models/delete?file=\'+encodeURIComponent('+f+'))">'+ic('trash')+'</button>';
    return '<div class="task"><div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap"><span class="cat" style="color:'+(col[m.role]||'var(--mut)')+';background:transparent;border:1px solid var(--line2)">'+esc(m.role)+'</span><b style="flex:1;min-width:150px;word-break:break-all">'+esc(m.file)+'</b>'+tags+meta+arc+prot+del+'</div></div>';
  }).join('');
  return head+rows;
}
function viewArena(){
  const a=DATA?DATA.arena:null;
  const pin=(DATA&&DATA.llm)?DATA.llm.pinned:null, useMsg=(DATA&&DATA.llm)?DATA.llm.useMsg:null;
  if(!a){ document.getElementById('view').innerHTML=card(ic('flask')+' Arène — sélection naturelle des LLM',`<div class="empty">L'arène n'a pas encore tourné.<br>Passe en mode <b>ARENA</b> (en haut) : elle explore HuggingFace en continu, télécharge et benchmarke les modèles, et garde le plus fort — en direct ici.</div>`,true); return; }
  const phaseL={crawl:'exploration de HuggingFace',download:'téléchargement',bench:'combat en cours',done:'cycle terminé',idle:'repos',rest:'prochain cycle imminent'}[a.phase]||esc(a.phase);
  const curName=a.current?(a.current.file||a.current.key):null;
  const cur=curName?`<div class="txt" style="margin-top:8px">${ic('swords',15)} Teste : <span class="hl">${esc(curName)}</span></div>`:'';
  const bestName=a.best?(a.best.file||a.best.key):null;
  const best=a.best?`${ic('trophy',15)} Plus fort connu : <span class="hl">${esc(bestName)}</span> — <b>${a.best.total} pts</b>`:'<span class="mut">pas encore de gagnant</span>';
  const pinBox=pin?`<div class="warnbox ok" style="margin-top:10px">${ic('pin',15)} Épinglé manuellement : <b>${esc(pin)}</b> — l'arène ne le remplacera pas. <button class="btn ghost sm" style="margin-left:8px" onclick="act('/llm/auto')">${ic('rotate')} Revenir à l'auto</button></div>`:'';
  const msgBox=useMsg?`<div class="mut" style="margin-top:8px">${esc(useMsg)}</div>`:'';
  const head=card(ic('flask')+' Arène — sélection naturelle des LLM (continue)',
    `<div class="txt"><b>Cycle ${a.cycle||1}</b> · ${phaseL} · barème v${esc(a.benchVer||'?')}</div>${cur}
     <div class="txt" style="margin-top:10px">${best}</div>${pinBox}${msgBox}
     <div class="mut" style="margin-top:6px">mise à jour ${esc(a.updatedAt||'')}</div>`,true);
  let board='<div class="empty">aucun combat encore</div>';
  const tested=arr(a.tested).slice().sort((x,y)=>(y.total||0)-(x.total||0));
  window._aOpen=window._aOpen||new Set();   // lignes depliees (persiste a travers le refresh 4s)
  if(tested.length){
    const max=Math.max.apply(null,tested.map(t=>t.total||0).concat([1]));
    const rows=tested.map((t,i)=>{
      const failed=t.status==='echec';
      const stale=!failed&&t.benchVer&&a.benchVer&&t.benchVer!==a.benchVer;
      const w=Math.round((t.total||0)/max*100), name=t.file||t.key, isBest=!failed&&!stale&&a.best&&t.key===a.best.key, isPin=pin&&t.file===pin;
      const open=window._aOpen.has(t.key);
      const right=failed?'<span class="badge" style="background:rgba(255,107,107,.16);color:var(--red)">échec</span>':('<span class="hl" style="font-variant-numeric:tabular-nums">'+t.total+'</span><span class="mut" style="font-size:10px">/100</span>'+(stale?'<span class="badge" style="background:rgba(255,200,97,.16);color:var(--amb)" title="noté sur un ancien barème, re-test auto en cours">ancien barème</span>':''));
      const tip='<span class="htip">'+ic('info',15)+tipFor(t)+'</span>';
      const cats=arr(t.cats).map(c=>{const cc=c.pct>=80?'var(--green)':c.pct>=40?'var(--amb)':'var(--red)';return '<span class="catbadge"><b>'+esc(c.cat)+'</b> <span style="color:'+cc+'">'+c.pct+'%</span></span>';}).join('')||esc(arr(t.details).join(' · '));
      // Replie par defaut : le detail (barre + categories) n'apparait qu'a l'ouverture.
      const detail=!open?'':(failed
        ?'<div class="mut" style="margin-top:6px;font-size:12px">'+esc(t.note||'n\'a pas chargé')+'</div>'
        :'<div class="bar" style="height:7px;background:rgba(255,255,255,.06);border-radius:4px;margin-top:8px;overflow:hidden"><i style="display:block;height:100%;width:'+w+'%;background:var(--grad)"></i></div><div style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap">'+cats+(t.tokPerSec?('<span class="catbadge" title="débit de génération réel">'+t.tokPerSec+' tok/s</span>'):'')+(t.secs?('<span class="catbadge" title="durée totale du test">'+t.secs+'s</span>'):'')+(t.gb?('<span class="catbadge" title="taille du modèle ~ VRAM occupée (sur 16 Go partagés avec le jeu)">'+t.gb+' Go</span>'):'')+'</div>');
      const compact=(!open&&!failed)?'<span class="mut" style="font-size:11.5px">'+(t.gb?(t.gb+' Go'):'')+(t.tokPerSec?(' · '+t.tokPerSec+' tok/s'):'')+'</span>':'';
      const chev='<button class="btn ghost sm" title="'+(open?'Replier':'Déplier')+'" onclick="togArena(\''+esc(t.key)+'\')"><span style="display:inline-flex;transition:transform .2s;transform:rotate('+(open?90:0)+'deg)">'+ic('chevron',15)+'</span></button>';
      return '<div class="task" style="'+(isBest?'border-color:var(--line);box-shadow:0 0 16px rgba(46,230,200,.14)':'')+(failed?';opacity:.62':'')+'"><div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap">'+chev+'<span class="cat">#'+(i+1)+'</span><b style="flex:1;min-width:160px;word-break:break-all;cursor:pointer" onclick="togArena(\''+esc(t.key)+'\')">'+esc(name)+' '+(isBest?ic('trophy',15):'')+(isPin?ic('pin',15):'')+'</b>'+compact+right+tip+'<button class="btn ghost sm" title="Copier le benchmark" onclick="copyBench(\''+esc(t.key)+'\')">'+ic('copy')+'</button><button class="btn ghost sm" title="Renvoyer au bench" onclick="act(\'/arena/rebench?key=\'+encodeURIComponent(\''+esc(t.key)+'\'))">'+ic('repeat')+' Re-bench</button>'+(failed?'':'<button class="btn ghost sm" onclick="act(\'/llm/use?key=\'+encodeURIComponent(\''+esc(t.key)+'\'))">'+ic('play')+' Utiliser</button>')+'</div>'+detail+'</div>';
    }).join('');
    const allOpen=tested.every(t=>window._aOpen.has(t.key));
    const toolbar='<div class="toolbar"><button class="btn ghost sm" onclick="copyBenchAll()">'+ic('copy')+' Copier tout le tableau</button><button class="btn ghost sm" onclick="arenaToggleAll('+(allOpen?'false':'true')+')">'+ic('chevron')+' '+(allOpen?'Tout replier':'Tout déplier')+'</button><span class="mut" style="font-size:11.5px;align-self:center">'+tested.length+' modèles · clique une ligne pour le détail</span></div>';
    board=toolbar+rows;
  }
  document.getElementById('view').innerHTML=progBar(DATA&&DATA.arenaProgress)+head+'<div style="height:14px"></div>'
    +card(ic('chart')+' Classement persistant — survole '+ic('info',13)+' pour les détails ingénieur · « Utiliser » pour activer',board,true)
    +'<div style="height:14px"></div>'
    +card(ic('hdd')+' Modèles sur le disque — supprimer · archiver · protéger de la purge',viewArenaDisk(),true);
}
function togArena(key){ window._aOpen=window._aOpen||new Set(); if(window._aOpen.has(key))window._aOpen.delete(key); else window._aOpen.add(key); renderView(); }
function arenaToggleAll(open){ window._aOpen=window._aOpen||new Set(); const t=arr(DATA&&DATA.arena&&DATA.arena.tested); if(open)t.forEach(x=>window._aOpen.add(x.key)); else window._aOpen.clear(); renderView(); }
function copyBenchAll(){
  const t=arr(DATA&&DATA.arena&&DATA.arena.tested).slice().sort((x,y)=>(y.total||0)-(x.total||0));
  if(!t.length){ toast('aucun benchmark'); return; }
  const cols=[]; t.forEach(m=>arr(m.cats).forEach(c=>{if(cols.indexOf(c.cat)<0)cols.push(c.cat);}));
  const ver=(DATA.arena&&DATA.arena.benchVer)||'?';
  const head=['#','Modele','Score','Vitesse(s)','Go'].concat(cols).join('\t');
  const lines=t.map((m,i)=>{
    if(m.status==='echec') return [i+1,(m.file||m.key),'ECHEC',(m.secs||''),(m.gb||'')].concat(cols.map(()=>'')).join('\t')+'\t'+(m.note||'');
    const byc={}; arr(m.cats).forEach(c=>byc[c.cat]=c.pct+'%');
    return [i+1,(m.file||m.key),m.total,(m.secs||''),(m.gb||'')].concat(cols.map(c=>byc[c]||'')).join('\t');
  });
  const txt='Benchmark Arene — bareme v'+ver+' — '+t.length+' modeles\n'+head+'\n'+lines.join('\n');
  navigator.clipboard.writeText(txt).then(()=>toast('Tableau copié ('+t.length+' modèles)'),()=>toast('copie refusée'));
}
function viewConsole(){
  const all=arr(DATA&&DATA.console);
  const c=all.slice(-60);   // compact: 60 dernieres lignes
  const col={test:'#4aa6ff',pass:'#49e29f',fail:'#ff6b6b',output:'#8ba2b6'};
  const toolbar='<div class="toolbar"><button class="btn ghost sm" onclick="copyConsole()">'+ic('copy')+' Copier</button><button class="btn ghost sm" onclick="if(confirm(\'Vider la console ?\'))act(\'/console/clear\')">'+ic('trash')+' Vider</button></div>';
  let body;
  if(!c.length){ body=toolbar+'<div class="empty">aucune sortie LLM pour l\'instant — lance l\'Arène (ou le DEV) et les tests/réponses des modèles s\'afficheront ici en direct.</div>'; }
  else {
    const rows=c.slice().reverse().map(e=>'<div class="cline"><span class="ct">'+esc(e.ts)+'</span><span class="cs">'+esc(e.src||'')+(e.model?(' · '+esc(e.model)):'')+'</span><span class="ck" style="color:'+(col[e.kind]||'#8ba2b6')+'">'+esc((e.kind||'').toUpperCase())+'</span><div class="cx">'+esc(e.text||'')+'</div></div>').join('');
    body=toolbar+'<div class="termhead">'+c.length+' lignes (sur '+all.length+') · le plus récent en haut · en direct</div><div class="term">'+rows+'</div>';
  }
  document.getElementById('view').innerHTML=card(ic('terminal')+' Console LLM — tests &amp; réponses des modèles',body,true);
}
function copyConsole(){
  const c=arr(DATA&&DATA.console);
  const txt=c.map(e=>e.ts+' ['+(e.src||'')+(e.model?(' '+e.model):'')+'] '+(e.kind||'').toUpperCase()+': '+(e.text||'')).join('\n');
  navigator.clipboard.writeText(txt).then(()=>toast('Console copiée ('+c.length+' lignes)'),()=>toast('copie refusée'));
}
function copyBench(key){
  const m=arr(DATA&&DATA.arena&&DATA.arena.tested).find(x=>x.key===key);
  if(!m){ toast('benchmark introuvable'); return; }
  const cats=arr(m.cats).map(c=>'  '+c.cat+': '+c.pct+'%').join('\n');
  const txt=(m.status==='echec')
    ? 'Benchmark — '+(m.file||m.key)+'\nÉCHEC: '+(m.note||'n\'a pas chargé')
    : 'Benchmark — '+(m.file||m.key)+'\nScore total: '+m.total+' pts (vitesse '+(m.speedPts||0)+' · '+(m.secs||0)+'s)\n'+cats;
  navigator.clipboard.writeText(txt).then(()=>toast('Benchmark copié: '+key),()=>toast('copie refusée'));
}
function toast(msg){ let t=document.getElementById('toast'); if(!t){t=document.createElement('div');t.id='toast';document.body.appendChild(t);} t.textContent=msg; t.className='show'; clearTimeout(window._tt); window._tt=setTimeout(()=>{t.className='';},2200); }
function renderView(){ ({overview:viewOverview,activity:viewActivity,arena:viewArena,console:viewConsole,tasks:viewTasks,feedback:viewFeedback}[TAB]||viewOverview)(); }
function render(){ if(!DATA){return;}
  // Preserve le defilement de la console (et autres zones .term) a travers le
  // re-render auto (4s) -> ne remonte plus en haut quand une entree arrive.
  const term=document.querySelector('#view .term'); const sc=term?term.scrollTop:null;
  renderPills();renderBanner();renderCtrl();renderKpis();renderTabs();renderView();
  if(sc!=null){ const t2=document.querySelector('#view .term'); if(t2)t2.scrollTop=sc; }
}

/* Fond anime : cellules bioluminescentes a la derive (remontent de l'abysse). */
(function(){
  const c=document.getElementById('bg'),x=c.getContext('2d');let W,H,cells=[];
  const COL=['46,230,200','74,166,255','73,226,159'];
  function rs(){W=c.width=innerWidth;H=c.height=innerHeight;}
  function mk(){const col=COL[Math.random()*COL.length|0];return{x:Math.random()*W,y:Math.random()*H,r:Math.random()*2.4+0.8,s:Math.random()*0.35+0.07,col,a:Math.random()*0.5+0.2};}
  function init(){rs();cells=Array.from({length:Math.min(60,Math.round(W*H/26000))},mk);}
  function tick(){x.clearRect(0,0,W,H);for(const p of cells){p.y-=p.s;p.x+=Math.sin(p.y/55)*0.18;if(p.y<-8){p.y=H+8;p.x=Math.random()*W;}
    const g=x.createRadialGradient(p.x,p.y,0,p.x,p.y,p.r*5);g.addColorStop(0,`rgba(${p.col},${p.a})`);g.addColorStop(1,`rgba(${p.col},0)`);
    x.fillStyle=g;x.beginPath();x.arc(p.x,p.y,p.r*5,0,7);x.fill();}requestAnimationFrame(tick);}
  addEventListener('resize',init);init();tick();
})();

load(); if(!window.__DATA__){ setInterval(load,4000); }
</script></body></html>
'@
    return $html.Replace('__BOOT__', $boot)
}
