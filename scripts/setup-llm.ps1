<#
DOWN HERE - Repare / construit le serveur LLM local (llama-server, ROCm/WSL).

POURQUOI : certains builds recents de llama.cpp forcent un "router mode"
experimental (serveur vide sur 127.0.0.1:8080, ignore -m/--port) -> le LLM ne
sert jamais sur le port 1234 et le dashboard reste "LLM hors ligne". Ce script
ramene llama.cpp a une version d'AVANT le router et recompile `llama-server`
avec les memes flags ROCm (HIP, gfx1101) deja configures, puis VERIFIE.

A lancer UNE fois (reparation du binaire). Ensuite le bouton DEMARRER suffit.

  pwsh -File scripts/setup-llm.ps1
#>

. "$PSScriptRoot\lib\Config.ps1"
$cfg = Get-DownHereConfig
$repo = '/root/llama.cpp'

function Wsl([string]$c) { wsl -d Ubuntu -u root -- bash -lc $c 2>&1 | Out-String }

Write-Host "=== DOWN HERE - reparation du serveur LLM ===" -ForegroundColor Cyan
Write-Host "1) Recuperation de l'historique git (unshallow si besoin)..."
Wsl "cd $repo && (git rev-parse --is-shallow-repository | grep -q true && git fetch --unshallow 2>&1 | tail -1 || echo 'historique deja complet')" | Write-Host

Write-Host "2) Retour a la version d'avant le 'router mode'..."
$co = Wsl @"
cd $repo && pkill -f llama-server 2>/dev/null
RC=`$(git log --oneline --reverse 2>/dev/null | grep -iE 'router' | head -1 | awk '{print `$1}')
if [ -n "`$RC" ]; then git checkout `${RC}^ 2>&1 | tail -1; else git checkout b9000 2>&1 | tail -1; fi
git log --oneline -1
"@
Write-Host $co

Write-Host "3) Compilation de llama-server (ROCm, peut prendre 10-20 min)..." -ForegroundColor Yellow
$build = Wsl "cd $repo && cmake --build build --target llama-server -j`$(nproc) 2>&1 | tail -4"
Write-Host $build

Write-Host "4) Verification (le binaire ne doit PLUS partir en router)..." -ForegroundColor Cyan
$champ = Get-DownHereChampion -Config $cfg
$verify = Wsl @"
cd $repo && pkill -f llama-server 2>/dev/null; rm -f /tmp/llv.log
timeout 30 ./build/bin/llama-server -m /root/models/$champ -c 2048 --port 1234 --host 127.0.0.1 > /tmp/llv.log 2>&1 &
sleep 22
if grep -qi 'router server' /tmp/llv.log; then echo 'ECHEC: encore en router mode'; else echo 'OK: pas de router'; fi
(curl -s -m 3 http://127.0.0.1:1234/health && echo ' <- /health repond') || echo '/health pas encore (modele peut-etre encore en chargement)'
pkill -f llama-server 2>/dev/null
tail -4 /tmp/llv.log
"@
Write-Host $verify
if ($verify -match 'OK: pas de router') {
    Write-Host "`n[OK] Binaire repare. Le bouton DEMARRER du dashboard montera le LLM." -ForegroundColor Green
} else {
    Write-Host "`n[!] Toujours en router - il faut reculer davantage (tag plus ancien). Dis-le moi." -ForegroundColor Red
}
