<#
DOWN HERE - Dashboard (API + SPA moderne).

Architecture pro : le serveur expose UNE API JSON (Get-DashboardData) et sert une
SPA mono-fichier (Get-DashboardHtml) qui la consomme et se rafraichit seule
(fetch /api.json toutes les 4s) - pas de rechargement de page, pas de build, pas
de dependance reseau (fonctionne hors-ligne). La meme SPA sert au site public
(donnees injectees inline par publish_site).

Corrige les vrais defauts : statut honnete (LLM on/off, fraicheur), activite
REELLE (commits filtres du spam "site: progress update"), bouton START clair.
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
:root{--bg:#0a0e16;--panel:#111824;--panel2:#0d1420;--line:#1e2a3a;--ink:#e6edf3;--mut:#8b98a9;--acc:#3fb950;--blue:#4493f8;--red:#f85149;--amb:#d29922}
*{box-sizing:border-box;margin:0}body{background:var(--bg);color:var(--ink);font:14px/1.55 "Segoe UI",system-ui,sans-serif}
a{color:var(--blue);text-decoration:none}
.top{position:sticky;top:0;z-index:5;background:rgba(13,20,32,.92);backdrop-filter:blur(8px);border-bottom:1px solid var(--line);padding:14px 22px}
.top .wrap{max-width:1280px;margin:0 auto;display:flex;align-items:center;gap:16px;flex-wrap:wrap}
.brand{font-size:20px;font-weight:800;letter-spacing:.5px}.brand b{color:var(--acc)}
.pills{display:flex;gap:8px;margin-left:auto;flex-wrap:wrap}
.pill{display:flex;align-items:center;gap:6px;background:var(--panel);border:1px solid var(--line);border-radius:999px;padding:5px 12px;font-size:12px;font-weight:600;color:var(--mut)}
.dot{width:8px;height:8px;border-radius:50%;background:var(--mut)}.dot.on{background:var(--acc);box-shadow:0 0 8px var(--acc)}.dot.off{background:var(--red)}.dot.warn{background:var(--amb)}
main{max-width:1280px;margin:0 auto;padding:20px 22px 60px}
.ctrl{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin-bottom:20px}
.btn{border:none;border-radius:10px;padding:11px 20px;font-weight:700;font-size:14px;cursor:pointer;color:#fff;transition:.15s}
.btn:hover{filter:brightness(1.1)}.btn.start{background:var(--acc)}.btn.stop{background:#b3322b}.btn.ghost{background:var(--panel);color:var(--ink);border:1px solid var(--line)}
.seg{display:flex;background:var(--panel2);border:1px solid var(--line);border-radius:10px;overflow:hidden}
.seg button{background:none;border:none;color:var(--mut);padding:10px 14px;font-weight:700;font-size:12.5px;cursor:pointer}
.seg button.on{background:var(--acc);color:#fff}.seg button:hover:not(.on){color:var(--ink)}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:14px;margin-bottom:20px}
.kpi{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:16px 18px}
.kpi .v{font-size:28px;font-weight:800;line-height:1}.kpi .l{color:var(--mut);font-size:12px;margin-top:6px}
.kpi .bar{height:6px;background:#1c2533;border-radius:3px;margin-top:10px;overflow:hidden}.kpi .bar i{display:block;height:100%;background:linear-gradient(90deg,#2ea043,#3fb950)}
.g{color:var(--acc)}.r{color:var(--red)}.y{color:var(--amb)}.b{color:var(--blue)}
.tabs{display:flex;gap:4px;border-bottom:1px solid var(--line);margin-bottom:18px;flex-wrap:wrap}
.tabs button{background:none;border:none;color:var(--mut);padding:11px 16px;font-weight:700;font-size:13.5px;cursor:pointer;border-bottom:2px solid transparent}
.tabs button.on{color:var(--ink);border-bottom-color:var(--acc)}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(330px,1fr));gap:16px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:18px}
.card h3{font-size:12px;text-transform:uppercase;letter-spacing:1px;color:var(--mut);margin-bottom:12px;display:flex;align-items:center;gap:8px}
.row{display:flex;gap:10px;padding:9px 0;border-bottom:1px solid var(--line);align-items:flex-start}.row:last-child{border:0}
.time{flex:none;color:var(--mut);font-size:12px;min-width:74px;font-variant-numeric:tabular-nums}
.badge{flex:none;font-size:10px;font-weight:800;padding:2px 8px;border-radius:999px;background:#1c2533;color:var(--mut);text-transform:uppercase}
.badge.feat{background:#143a23;color:var(--acc)}.badge.fix{background:#3a2417;color:#e0883a}.badge.ai{background:#0f2f4a;color:var(--blue)}.badge.refactor,.badge.docs,.badge.test,.badge.chore{background:#22283a;color:#9db1c9}
.txt{font-size:13.5px}.mut{color:var(--mut)}
.task{background:var(--panel2);border:1px solid var(--line);border-radius:10px;padding:10px 12px;margin-bottom:8px;font-size:13px}
.cat{display:inline-block;font-size:10px;font-weight:800;color:var(--blue);background:#0f2f4a;border-radius:6px;padding:1px 7px;margin-right:8px}
.spark{font-size:12px;color:var(--acc);word-spacing:2px;margin-top:6px}
.empty{color:var(--mut);padding:18px;text-align:center}
.warnbox{background:#2a1f10;border:1px solid #5a4420;color:#e8c37a;border-radius:10px;padding:10px 14px;font-size:13px;margin-bottom:16px}
input,select,textarea{background:var(--panel2);color:var(--ink);border:1px solid var(--line);border-radius:9px;padding:9px;font:inherit}
</style></head><body>
<div class="top"><div class="wrap">
  <div class="brand">DOWN HERE <b>!</b></div>
  <div class="pills" id="pills"></div>
</div></div>
<main>
  <div id="banner"></div>
  <div class="ctrl" id="ctrl"></div>
  <div class="kpis" id="kpis"></div>
  <div class="tabs" id="tabs"></div>
  <div id="view"></div>
</main>
<script>
__BOOT__
const $=(h)=>{const t=document.createElement('template');t.innerHTML=h.trim();return t.content.firstChild;};
const esc=(s)=>(s==null?'':String(s)).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
let DATA=window.__DATA__||null, TAB=sessionStorage.getItem('tab')||'overview', BUSY=false;
const TABS=[['overview','Vue d\'ensemble'],['activity','Activité'],['tasks','Tâches'],['feedback','Feedback']];

async function api(path,opts){ try{return await fetch(path,opts);}catch(e){return null;} }
async function load(){ if(!window.__DATA__){ const r=await api('/api.json'); if(r){try{DATA=await r.json();}catch(e){}} } render(); }
async function act(path){ if(BUSY)return; BUSY=true; await api(path,{method:'POST'}); setTimeout(()=>{BUSY=false;load();},1200); }
function setMode(m){ act('/mode?set='+m); }

function pill(label,cls){ return `<span class="pill"><span class="dot ${cls}"></span>${label}</span>`; }
function renderPills(){
  const s=DATA?DATA.state:null; const llm=s&&s.llmAlive; const age=DATA?DATA.devAgeMin:null;
  let fresh='warn',freshL='dev: inconnu';
  if(age!=null){ if(age<5){fresh='on';freshL='dev actif'} else if(age<120){fresh='warn';freshL='dev: '+age+' min'} else {fresh='off';freshL='dev inactif ('+Math.round(age/60)+'h)'} }
  document.getElementById('pills').innerHTML=
    pill(llm?'LLM en ligne':'LLM hors ligne', llm?'on':'off')+
    pill('Mode: '+(s?s.mode:'?'), s&&s.mode!=='IDLE'?'on':'')+
    pill(s&&s.stackState==='PAUSED'?'En pause':'En marche', s&&s.stackState==='PAUSED'?'off':'on')+
    pill(freshL,fresh);
}
function renderBanner(){
  const s=DATA?DATA.state:null; let h='';
  if(s&&!s.llmAlive){ h+='<div class="warnbox">⚠ Le LLM local est <b>hors ligne</b> — clique <b>DÉMARRER</b> (lance llama-server + la pile). Sans lui, le dev IA ne progresse pas.</div>'; }
  document.getElementById('banner').innerHTML=h;
}
function renderCtrl(){
  const s=DATA?DATA.state:null; const paused=s&&s.stackState==='PAUSED';
  const modes=['DEV','PLAY','ARENA','EVOLVE','IDLE'];
  const seg=modes.map(m=>`<button class="${s&&s.mode===m?'on':''}" onclick="setMode('${m}')">${m}</button>`).join('');
  document.getElementById('ctrl').innerHTML=
    (paused?`<button class="btn start" onclick="act('/resume')">▶ DÉMARRER</button>`
           :`<button class="btn stop" onclick="if(confirm('Arrêter toute la pile ?'))act('/pause')">■ ARRÊTER</button>`)+
    `<div class="seg">${seg}</div>`+
    `<a class="btn ghost" href="/chat">💬 Parler à l'IA</a>`;
}
function renderKpis(){
  const p=DATA?DATA.progress:{}, b=DATA&&DATA.state?DATA.state.brain:null;
  const k=[['v',(p.pct||0)+'%','avancement','<div class="bar"><i style="width:'+(p.pct||0)+'%"></i></div>'],
    ['g',p.kept||0,'patchs acceptés',''],['r',p.reverted||0,'annulés',''],
    ['y',p.predicted||0,'refusés avant build',''],
    ['b',b?b.utility:'—','cerveau (utilité)','']];
  document.getElementById('kpis').innerHTML=k.map(x=>`<div class="kpi"><div class="v ${x[0]}">${x[1]}</div><div class="l">${x[2]}</div>${x[3]}</div>`).join('');
}
function renderTabs(){
  document.getElementById('tabs').innerHTML=TABS.map(t=>`<button class="${TAB===t[0]?'on':''}" onclick="go('${t[0]}')">${t[1]}</button>`).join('');
}
function go(t){ TAB=t; sessionStorage.setItem('tab',t); renderTabs(); renderView(); }

function card(title,body){ return `<div class="card"><h3>${title}</h3>${body}</div>`; }
function viewOverview(){
  const s=DATA?DATA.state:{}, b=s.brain, ct=s.currentTask;
  let task='<span class="mut">aucune tâche en cours</span>';
  if(ct&&ct.item){ task=esc(ct.item.length>140?ct.item.slice(0,140)+'…':ct.item); }
  const game=s.game&&s.game.running?`<b class="g">lancé</b> (pid ${s.game.pid})`:'<span class="mut">non lancé</span>';
  const health=card('🩺 Santé en direct',
    `<div class="txt"><b>Tâche:</b> ${task}</div>
     <div class="txt" style="margin-top:8px"><b>Jeu:</b> ${game}</div>
     <div class="txt" style="margin-top:8px"><b>Agents:</b> ${s.agents?Object.keys(s.agents).filter(a=>s.agents[a]).join(', ')||'<span class=mut>aucun</span>':'—'}</div>`);
  let brain='<span class="mut">pas encore de cerveau conçu</span>';
  if(b){ brain=`<div class="txt">Champion <b>${esc(b.model)}</b> · ${b.features} features · utilité <b class="g">${b.utility}</b></div>
    <div class="mut" style="margin-top:6px">gain +${b.gain} sur ${b.gens} générations</div>`; }
  const brainC=card('🧠 Cerveau auto-conçu (successeur)',brain);
  const lessons=(DATA.lessons&&DATA.lessons.length)?DATA.lessons.map(l=>`<div class="row"><div class="txt">${esc(l)}</div></div>`).join(''):'<div class="empty">—</div>';
  const lessonsC=card('🎓 Leçons récentes de l\'IA',lessons);
  document.getElementById('view').innerHTML=`<div class="grid">${health}${brainC}${lessonsC}</div>`;
}
function viewActivity(){
  const a=DATA?DATA.activity:[];
  if(!a||!a.length){ document.getElementById('view').innerHTML=card('⚡ Activité',`<div class="empty">aucune activité</div>`); return; }
  const rows=a.map(e=>`<div class="row"><span class="time">${esc(e.date)}</span><span class="badge ${esc(e.type)}">${esc(e.who==='IA locale'?'IA':e.type)}</span><span class="txt">${esc(e.text)}</span></div>`).join('');
  document.getElementById('view').innerHTML=card('⚡ Activité réelle (commits, hors bruit auto)',rows);
}
function viewTasks(){
  const t=DATA?DATA.tracker:[];
  if(!t||!t.length){ document.getElementById('view').innerHTML=card('🗂️ Tâches en file',`<div class="empty">aucune tâche en file</div>`); return; }
  const rows=t.map(x=>`<div class="task"><span class="cat">${esc(x.cat)}</span>${esc(x.text)}</div>`).join('');
  document.getElementById('view').innerHTML=card('🗂️ Tâches en file (roadmap)',rows);
}
function viewFeedback(){
  const f=DATA?DATA.feedback:[];
  const form=`<form onsubmit="sendFb(event)" style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px">
    <select id="fbtype"><option value="feature">✨ Feature</option><option value="bug">🐛 Bug</option></select>
    <input id="fbtext" placeholder="Décris ta demande ou un bug…" style="flex:1;min-width:240px">
    <button class="btn start" type="submit">Envoyer</button></form>`;
  const rows=(f&&f.length)?f.map(x=>`<div class="row"><span class="time">${esc(x.date)}</span><span class="badge">${esc(x.type)} · ${esc(x.status)}</span><span class="txt">${esc(x.text)}</span></div>`).join(''):'<div class="empty">aucune demande</div>';
  document.getElementById('view').innerHTML=card('💬 Feedback',form+rows);
}
function sendFb(e){ e.preventDefault(); const t=document.getElementById('fbtext').value.trim(); if(!t)return;
  const ty=document.getElementById('fbtype').value;
  api('/feedback?type='+ty+'&text='+encodeURIComponent(t),{method:'GET'}).then(()=>{document.getElementById('fbtext').value='';setTimeout(load,400);}); }
function renderView(){ ({overview:viewOverview,activity:viewActivity,tasks:viewTasks,feedback:viewFeedback}[TAB]||viewOverview)(); }
function render(){ if(!DATA){return;} renderPills();renderBanner();renderCtrl();renderKpis();renderTabs();renderView(); }
load(); if(!window.__DATA__){ setInterval(load,4000); }
</script></body></html>
'@
    return $html.Replace('__BOOT__', $boot)
}
