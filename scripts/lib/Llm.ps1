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
pkill -f llama-server 2>/dev/null
sleep 1
# AUTO-FIT: pas de -ngl force; llama.cpp place autant de couches que la VRAM libre
# le permet (le JEU partage les 16 Go), le reste sur CPU.
exec /root/llama.cpp/build/bin/llama-server --model "/root/models/${MODEL}" --ctx-size 8192 --host 0.0.0.0 --port 1234 > /tmp/llama-server.log 2>&1
'@
    # CR-strip indispensable: un '#!/bin/bash\r' casse l'interpreteur.
    ($sh -replace "`r", "") | wsl -d Ubuntu -u root -- bash -c "cat > /root/start-llm.sh && chmod +x /root/start-llm.sh" | Out-Null
}

# Lance le serveur (processus wsl.exe PERSISTANT, cache). Les enfants en
# arriere-plan meurent quand la session wsl se ferme -> on garde wsl.exe vivant.
function Start-LlamaServer {
    param([Parameter(Mandatory)][string]$Model)
    Write-LlmLauncher
    Start-Process wsl -ArgumentList "-d", "Ubuntu", "-u", "root", "--", "bash", "/root/start-llm.sh", $Model -WindowStyle Hidden
}
