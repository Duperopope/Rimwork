<#
DOWN HERE - Demarre / repare le serveur LLM local (llama-server, ROCm/WSL).

POURQUOI CE SCRIPT : si le dashboard affiche "LLM hors ligne", c'est presque
toujours parce que le serveur est parti en "router mode" (bind 8080, charge 0
modele, ne sert jamais sur 1234). CAUSE REELLE (verifiee le 15/06 sur le serveur
live) : dans le build actuel de llama.cpp, le raccourci -m ne remplit PAS
params.model.path -> le serveur croit qu'aucun modele n'est fourni et part en
router (server.cpp: is_router_server = params.model.path.empty()). Le fix est
d'utiliser --model (forme longue). PAS de recompilation necessaire : le binaire
et le GPU sont bons.

Ce script tue tout serveur bancal, relance avec les BONS flags (--model), et
VERIFIE que /health repond et que le modele est bien servi sur 1234.

  pwsh -File scripts/setup-llm.ps1
#>

. "$PSScriptRoot\lib\Config.ps1"
. "$PSScriptRoot\lib\Llm.ps1"
$cfg   = Get-DownHereConfig
$champ = Get-DownHereChampion -Config $cfg
$base  = $cfg.Llm.BaseUrl

function Wsl([string]$c) { wsl -d Ubuntu -u root -- bash -lc $c 2>&1 | Out-String }

Write-Host "=== DOWN HERE - demarrage du serveur LLM ===" -ForegroundColor Cyan
Write-Host "Modele champion : $champ"

Write-Host "1) Arret d'un serveur bancal eventuel..."
Wsl "pkill -f llama-server 2>/dev/null; sleep 1; echo ok" | Out-Null

Write-Host "2) Lancement avec --model (forme longue, evite le router mode)..."
# Lancement robuste partage avec startup_all (script WSL anti-quoting).
Start-LlamaServer -Model $champ

Write-Host "3) Attente du chargement en VRAM (jusqu'a ~2 min)..." -ForegroundColor Yellow
$ok = $false
foreach ($w in 1..12) {
    Start-Sleep -Seconds 10
    try {
        $h = Invoke-WebRequest "$base$($cfg.Llm.HealthPath)" -UseBasicParsing -TimeoutSec 4
        if ($h.StatusCode -eq 200 -and $h.Content -match 'ok' -and $h.Content -notmatch 'error') { $ok = $true; break }
    } catch {}
    Write-Host ("   ... {0}s" -f ($w * 10))
}

Write-Host "4) Verification du modele servi..." -ForegroundColor Cyan
$models = ''
try { $models = (Invoke-WebRequest "$base$($cfg.Llm.ModelsPath)" -UseBasicParsing -TimeoutSec 4).Content } catch {}

if ($ok -and $models -match 'gguf|qwen|coder|yi|model') {
    Write-Host "`n[OK] LLM en ligne sur le port 1234, modele charge." -ForegroundColor Green
    Write-Host "     Le dashboard affichera 'LLM en ligne'. Rien d'autre a faire."
} elseif ($ok) {
    Write-Host "`n[OK] /health repond mais /v1/models est vide - le modele finit de charger." -ForegroundColor Yellow
    Write-Host "     Attends 30 s puis rafraichis le dashboard."
} else {
    Write-Host "`n[!] Le LLM ne repond toujours pas. Derniers logs :" -ForegroundColor Red
    Write-Host (Wsl "tail -15 /tmp/llama-server.log")
    Write-Host "Si tu vois 'router server is listening' : un flag -m a survecu quelque part." -ForegroundColor Red
    Write-Host "Sinon, copie-moi ces logs et je corrige." -ForegroundColor Red
}
