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
.node .ic{font-size:16px}
.arrow{color:var(--dim);font-size:18px;flex:none}
.chip{display:inline-flex;align-items:center;gap:6px;background:var(--glass2);border:1px solid var(--line2);border-radius:999px;padding:4px 11px;font-size:12px;font-weight:700;margin:3px 5px 3px 0}
.chip.on{border-color:var(--line);color:var(--cyan)}
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
let DATA=window.__DATA__||null, TAB=sessionStorage.getItem('tab')||'overview', BUSY=false;
const TABS=[['overview','Vue d\'ensemble'],['activity','Activité'],['tasks','Tâches'],['feedback','Feedback']];

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
    if(s.mode==='ARENA'){ h='<div class="warnbox ok">🔬 Mode <b>ARENA</b> : l\'arène teste des modèles et occupe le GPU — le serveur de prod est coupé par intermittence. C\'est normal, pas une panne.</div>'; }
    else { h='<div class="warnbox">⚠ Le LLM local est <b>hors ligne</b> — clique <b>DÉMARRER</b> (lance llama-server + la pile). Sans lui, le dev IA ne progresse pas.</div>'; }
  }
  document.getElementById('banner').innerHTML=h;
}
function renderCtrl(){
  const s=DATA?DATA.state:null; const paused=s&&s.stackState==='PAUSED';
  const modes=[['DEV','code le jeu'],['PLAY','joue'],['ARENA','choisit le cerveau'],['EVOLVE','s\'auto-modifie'],['IDLE','repos']];
  const seg=modes.map(m=>`<button class="${s&&s.mode===m[0]?'on':''}" title="${m[1]}" onclick="setMode('${m[0]}')">${m[0]}</button>`).join('');
  document.getElementById('ctrl').innerHTML=
    (paused?`<button class="btn start" onclick="act('/resume')">▶ DÉMARRER</button>`
           :`<button class="btn stop" onclick="if(confirm('Arrêter toute la pile ?'))act('/pause')">■ ARRÊTER</button>`)+
    `<div class="seg">${seg}</div>`+
    `<a class="btn ghost" href="/chat">💬 Parler à l'IA</a>`;
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
function flowView(s){
  // Pipeline recursif REEL : roadmap -> patch LLM -> build/test -> garde/annule -> world model (qui re-trie).
  const mode=s?s.mode:'';
  const steps=[['🗺️','Roadmap','une tâche', mode==='DEV'],
    ['🧠','LLM local','propose un patch', s&&s.llmAlive],
    ['🛠️','Build + test','valide', mode==='DEV'],
    ['✅','Garde / annule','ne garde que ce qui marche', mode==='DEV'],
    ['🔁','World model','ré-entraîne et re-trie', s&&s.brain]];
  const n=steps.map((x,i)=>`<div class="node${x[3]?' act':''}"><div class="ic">${x[0]}</div><div class="n">${x[1]}</div><div class="d">${x[2]}</div></div>`+
    (i<steps.length-1?'<div class="arrow">→</div>':'')).join('');
  return card('🔁 Boucle d\'auto-amélioration récursive',`<div class="flow">${n}</div>`,true);
}
function viewOverview(){
  const s=DATA?DATA.state:{}, b=s.brain, ct=s.currentTask;
  let task='<span class="mut">aucune tâche en cours</span>';
  if(ct&&ct.item){ task=esc(ct.item.length>150?ct.item.slice(0,150)+'…':ct.item); }
  const game=s.game&&s.game.running?`<span class="hl">lancé</span> (pid ${s.game.pid})`:'<span class="mut">fermé (le jeu ne tourne pas pendant le dev)</span>';
  const agentsList=s.agents?Object.keys(s.agents).filter(a=>s.agents[a]):[];
  const agents=agentsList.length?agentsList.map(a=>`<span class="chip on">⬤ ${esc(a)}</span>`).join(''):'<span class="mut">aucun agent actif</span>';
  const health=card('🩺 Santé en direct',
    `<div class="txt"><b>Tâche :</b> ${task}</div>
     <div class="txt" style="margin-top:10px"><b>Jeu :</b> ${game}</div>
     <div class="txt" style="margin-top:10px"><b>Agents :</b><div style="margin-top:6px">${agents}</div></div>`);
  let brain='<span class="mut">pas encore de cerveau conçu</span>';
  if(b){ brain=`<div class="txt">Champion <span class="hl">${esc(b.model)}</span> · ${b.features} features · utilité <span class="hl">${b.utility}</span></div>
    <div class="mut" style="margin-top:8px">gain +${b.gain} sur ${b.gens} générations (champion-challenger)</div>`; }
  const brainC=card('🧠 Cerveau auto-conçu (successeur)',brain);
  const lessons=(DATA.lessons&&DATA.lessons.length)?DATA.lessons.map(l=>`<div class="row"><div class="txt">${esc(l)}</div></div>`).join(''):'<div class="empty">—</div>';
  const lessonsC=card('🎓 Leçons récentes de l\'IA',lessons);
  document.getElementById('view').innerHTML=flowView(s)+`<div class="grid">${health}${brainC}${lessonsC}</div>`;
}
function viewActivity(){
  const a=DATA?DATA.activity:[];
  if(!a||!a.length){ document.getElementById('view').innerHTML=card('⚡ Activité',`<div class="empty">aucune activité</div>`,true); return; }
  const rows=a.map(e=>`<div class="row"><span class="time">${esc(e.date)}</span><span class="badge ${esc(e.type)}">${esc(e.who==='IA locale'?'IA':e.type)}</span><span class="txt">${esc(e.text)}</span></div>`).join('');
  document.getElementById('view').innerHTML=card('⚡ Activité réelle (commits, hors bruit auto)',rows,true);
}
function viewTasks(){
  const t=DATA?DATA.tracker:[];
  if(!t||!t.length){ document.getElementById('view').innerHTML=card('🗂️ Tâches en file',`<div class="empty">aucune tâche en file</div>`,true); return; }
  const rows=t.map(x=>`<div class="task"><span class="cat">${esc(x.cat)}</span>${esc(x.text)}</div>`).join('');
  document.getElementById('view').innerHTML=card('🗂️ Tâches en file (roadmap)',rows,true);
}
function viewFeedback(){
  const f=DATA?DATA.feedback:[];
  const form=`<form onsubmit="sendFb(event)" style="display:flex;gap:9px;flex-wrap:wrap;margin-bottom:16px">
    <select id="fbtype"><option value="feature">✨ Feature</option><option value="bug">🐛 Bug</option></select>
    <input id="fbtext" placeholder="Décris ta demande ou un bug…" style="flex:1;min-width:240px">
    <button class="btn start" type="submit">Envoyer</button></form>`;
  const rows=(f&&f.length)?f.map(x=>`<div class="row"><span class="time">${esc(x.date)}</span><span class="badge">${esc(x.type)} · ${esc(x.status)}</span><span class="txt">${esc(x.text)}</span></div>`).join(''):'<div class="empty">aucune demande</div>';
  document.getElementById('view').innerHTML=card('💬 Feedback',form+rows,true);
}
function sendFb(e){ e.preventDefault(); const t=document.getElementById('fbtext').value.trim(); if(!t)return;
  const ty=document.getElementById('fbtype').value;
  api('/feedback?type='+ty+'&text='+encodeURIComponent(t),{method:'GET'}).then(()=>{document.getElementById('fbtext').value='';setTimeout(load,400);}); }
function renderView(){ ({overview:viewOverview,activity:viewActivity,tasks:viewTasks,feedback:viewFeedback}[TAB]||viewOverview)(); }
function render(){ if(!DATA){return;} renderPills();renderBanner();renderCtrl();renderKpis();renderTabs();renderView(); }

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
