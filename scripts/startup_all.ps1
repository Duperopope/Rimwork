# Boots the whole autonomous dev stack after a PC restart (idempotent -
# safe to run when things are already up). Registered as a logon task.
#
# ORDRE IMPORTANT (corrige 14/06): le DASHBOARD et l'ORCHESTRATEUR demarrent
# EN PREMIER (plan de controle dispo en ~1s), AVANT la montee du LLM qui peut
# bloquer jusqu'a ~160s. Sinon le dashboard semble "inaccessible" pendant
# l'attente du LLM.

# Source de verite unique (paths/url/modele) - voir scripts/lib/Config.ps1.
. "$PSScriptRoot\lib\Config.ps1"
$cfg = Get-DownHereConfig
$scripts = $cfg.Paths.Scripts
$logDir = $cfg.Paths.Logs

function Test-WslLlm {
    try {
        $r = Invoke-WebRequest "$($cfg.Llm.BaseUrl)$($cfg.Llm.HealthPath)" -UseBasicParsing -TimeoutSec 5
        return ($r.StatusCode -eq 200 -and $r.Content -match 'ok' -and $r.Content -notmatch 'error')
    } catch { return $false }
}

# 1. Dashboard EN PREMIER - probe the actual HTTP endpoint, not just the
# process (a zombie process can exist without listening).
$dashAlive = $false
try { $dashAlive = (Invoke-WebRequest "http://localhost:$($cfg.Dashboard.Port)" -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 } catch {}
if (-not $dashAlive) {
    Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
        Where-Object { $_.CommandLine -match 'dashboard_server' } |
        ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {} }
    Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $scripts 'dashboard_server.ps1') -WindowStyle Hidden
}

# 2. Orchestrateur (machine a modes) - AUTORITE UNIQUE. Il lance les agents
# du MODE courant (DEV/PLAY/ARENA/IDLE) et garantit qu'UN SEUL tourne a la
# fois (fini "tout en meme temps"). Voir orchestrator.ps1 + lib/Modes.ps1.
$orch = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -match 'orchestrator' }
if (-not $orch) {
    Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $scripts 'orchestrator.ps1') -WindowStyle Hidden
}

# 3. LLM server (peut etre lent): llama-server with ROCm inside WSL (18x faster
# prefill than the Windows Vulkan path - benchmarked 1040 vs 57 tok/s pp2048).
# PAS de fallback LM Studio (il squatte le port + la VRAM).
# Health probe must distinguish llama-server (WSL, /health -> "ok") from
# LM Studio squatting the same port (answers 200 with an error JSON).
$llmAlive = Test-WslLlm
if (-not $llmAlive) {
    # If LM Studio is squatting port 1234, the WSL server can never be
    # reached from Windows - evict the squatter before (re)starting WSL.
    try {
        $probe = Invoke-WebRequest "$($cfg.Llm.BaseUrl)$($cfg.Llm.ModelsPath)" -UseBasicParsing -TimeoutSec 5
        if ($probe.Content -match 'error|lmstudio|qwen2.5-coder-14b-instruct') { lms server stop 2>$null }
    } catch {}
}
if (-not $llmAlive) {
    # The served model is whatever the model arena crowned champion
    # (scripts/llm_champion.txt, fallback = Qwen2.5-Coder-14B baseline).
    $champ = Get-DownHereChampion -Config $cfg
    # The server must be hosted by a PERSISTENT hidden wsl.exe process:
    # background (&/nohup/setsid) children die when their wsl session ends.
    $up = wsl -d Ubuntu -u root -- bash -c "pgrep -x llama-server >/dev/null && echo UP"
    if ($up -notmatch "UP") {
        # AUTO-FIT (pas de -ngl 99 force): llama.cpp met autant de couches sur le
        # GPU que la VRAM LIBRE le permet, le reste sur CPU. Indispensable car le
        # JEU partage les 16 Go: forcer -ngl 99 fait planter le chargement quand
        # le jeu est ouvert. Un MoE 3B-actifs reste rapide meme avec un peu de CPU.
        Start-Process wsl -ArgumentList "-d","Ubuntu","-u","root","--","/root/llama.cpp/build/bin/llama-server","-m","/root/models/$champ","-c","8192","--host","0.0.0.0","--port","1234" -WindowStyle Hidden
    }
    # Big models (MoE 14GB) can take ~2 min to load into VRAM.
    foreach ($w in 1..8) { Start-Sleep -Seconds 20; $llmAlive = Test-WslLlm; if ($llmAlive) { break } }
    if (-not $llmAlive) {
        # NO LM Studio fallback: it squats port 1234 + VRAM and silently
        # starves the WSL server (root cause of the 12/06 outage). If WSL
        # cannot come up, log it loudly and let the loop wait.
        Add-Content "$logDir\watchdog.log" -Value "[$(Get-Date -Format HH:mm:ss)] LLM WSL DOWN apres attente - PAS de fallback LM Studio (voir /var/log/llama-server.log)"
    }
}

# 4. Publish the public progress site if it changed
pwsh -NoProfile -File (Join-Path $scripts 'publish_site.ps1') 2>$null

Add-Content -Path $cfg.Paths.DevLog -Value "- [startup] Stack relaunched after boot ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))."
