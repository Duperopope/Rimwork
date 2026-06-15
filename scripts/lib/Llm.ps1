# DOWN HERE - Lancement robuste du serveur LLM local (llama-server, ROCm/WSL).
#
# POURQUOI un script WSL dedie (/root/start-llm.sh) plutot qu'une commande inline :
#  1) Le raccourci -m est CASSE dans le build actuel de llama.cpp : il ne remplit
#     pas params.model.path -> le serveur croit qu'aucun modele n'est fourni et
#     part en "router mode" (server.cpp: is_router_server = model.path.empty()),
#     bind 127.0.0.1:8080, charge 0 modele, ne sert JAMAIS sur 1234. Il faut
#     --model (forme LONGUE). Verifie le 15/06 sur le serveur live.
#  2) Passer une longue commande a espaces via `Start-Process wsl -ArgumentList`
#     mange le quoting (PowerShell -> wsl -> bash -lc) : la commande arrive
#     tronquee. Un script avec des arguments SIMPLES (sans espace) elimine ce
#     piege : le seul argument variable est le NOM de fichier du modele.

# Ecrit /root/start-llm.sh dans WSL (idempotent). Contenu version-controle ici.
function Write-LlmLauncher {
    $sh = @'
#!/bin/bash
# DOWN HERE - lance llama-server (ROCm). Genere par lib/Llm.ps1 - ne pas editer ici.
# --model en forme LONGUE: le raccourci -m est casse dans ce build (-> router mode).
MODEL="${1:-Qwen2.5-Coder-14B-Instruct-Q4_K_S.gguf}"
LOG=/tmp/llama-server.log
BIN=/root/llama.cpp/build/bin/llama-server
pkill -f llama-server 2>/dev/null
sleep 1
# Log de demarrage TOUJOURS ecrit (diagnostic) + verifications avant exec.
{
  echo "[start-llm] $(date '+%F %T') model=$MODEL"
  [ -x "$BIN" ]               || { echo "[start-llm] ERREUR: binaire absent: $BIN"; exit 1; }
  [ -f "/root/models/$MODEL" ] || { echo "[start-llm] ERREUR: modele absent: /root/models/$MODEL"; ls -la /root/models/; exit 1; }
} > "$LOG" 2>&1
# AUTO-FIT: pas de -ngl force; llama.cpp place autant de couches que la VRAM libre
# le permet (le JEU partage les 16 Go), le reste sur CPU.
exec "$BIN" --model "/root/models/$MODEL" --ctx-size 8192 --host 0.0.0.0 --port 1234 >> "$LOG" 2>&1
'@
    # CR-strip cote WSL avec tr -d '\r' : INDISPENSABLE. Un '#!/bin/bash\r' (CRLF)
    # casse l'interpreteur et colle un \r a chaque valeur (MODEL="...gguf\r" ->
    # chemin invalide). PowerShell REAJOUTE des CRLF en pipant vers le stdin d'une
    # commande native, donc un -replace cote PS ne suffit pas : seul tr garantit du LF.
    $sh | wsl -d Ubuntu -u root -- bash -c "tr -d '\r' > /root/start-llm.sh && chmod +x /root/start-llm.sh" | Out-Null
}

# Lance le serveur (processus wsl.exe PERSISTANT, cache). Les enfants en
# arriere-plan meurent quand la session wsl se ferme -> on garde wsl.exe vivant.
function Start-LlamaServer {
    param([Parameter(Mandatory)][string]$Model)
    Write-LlmLauncher
    Start-Process wsl -ArgumentList "-d", "Ubuntu", "-u", "root", "--", "bash", "/root/start-llm.sh", $Model -WindowStyle Hidden
}

# Console LLM : journal des tests envoyes aux modeles et de leurs sorties, lu en
# direct par le dashboard (onglet Console). Rolling pour ne pas grossir sans fin.
function Write-LlmConsole {
    param([string]$Src = '', [string]$Model = '', [string]$Kind = '', [string]$Text = '')
    try {
        $f = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'logs') 'llm_console.jsonl'
        $t = ($Text -replace "`r", '' -replace "`n", ' ')
        if ($t.Length -gt 600) { $t = $t.Substring(0, 600) + '…' }
        $entry = @{ ts = (Get-Date -Format 'HH:mm:ss'); src = $Src; model = $Model; kind = $Kind; text = $t } | ConvertTo-Json -Compress
        Add-Content -Path $f -Value $entry
        $lines = @(Get-Content $f -ErrorAction SilentlyContinue)
        if ($lines.Count -gt 600) { Set-Content $f -Value ($lines | Select-Object -Last 400) }
    } catch {}
}

# Telecharge un GGUF depuis HuggingFace s'il manque (re-DL d'un modele supprime).
# Retourne le nom de fichier local, ou $null. Partage par l'arene et la selection
# manuelle. Verifie la taille pour ne pas servir un telechargement tronque.
function Get-ModelFile {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$File)
    $have = wsl -d Ubuntu -u root -- bash -c "test -s /root/models/$File && echo OK"
    if ($have -match 'OK') { return $File }
    if (-not $Repo) { return $null }
    try { $tree = Invoke-RestMethod "https://huggingface.co/api/models/$Repo/tree/main" -TimeoutSec 30 } catch { return $null }
    $entry = $tree | Where-Object { $_.path -ieq $File } | Select-Object -First 1
    if (-not $entry) {
        $pat = ($File -replace '.*(Q\d_K_[MS]).*', '$1')
        $entry = $tree | Where-Object { $_.path -match "$pat.*\.gguf$" -and $_.path -notmatch "0000\d-of" } | Select-Object -First 1
    }
    if (-not $entry) { return $null }
    $name = [System.IO.Path]::GetFileName($entry.path)
    $want = [long]($entry.lfs.size ?? $entry.size)
    wsl -d Ubuntu -u root -- bash -c "cd /root/models && timeout 1200 wget -q -c --tries=2 --timeout=30 'https://huggingface.co/$Repo/resolve/main/$($entry.path)' -O '$name'" | Out-Null
    $size = [long](wsl -d Ubuntu -u root -- bash -c "stat -c%s /root/models/$name 2>/dev/null || echo 0")
    if ($size -eq $want -and $want -gt 3e9) { return $name }
    return $null
}
