# Boots the whole autonomous dev stack after a PC restart (idempotent -
# safe to run when things are already up). Registered as a logon task.

# Source de verite unique (paths/url/modele) - voir scripts/lib/Config.ps1.
. "$PSScriptRoot\lib\Config.ps1"
$cfg = Get-DownHereConfig
$scripts = $cfg.Paths.Scripts
$logDir = $cfg.Paths.Logs

# 1. LLM server: llama-server with ROCm inside WSL (18x faster prefill than
# the Windows Vulkan path - benchmarked 1040 vs 57 tok/s pp2048). PAS de
# fallback LM Studio (il squatte le port + la VRAM).
# Health probe must distinguish llama-server (WSL, /health -> "ok") from
# LM Studio squatting the same port (answers 200 with an error JSON).
function Test-WslLlm {
    try {
        $r = Invoke-WebRequest "$($cfg.Llm.BaseUrl)$($cfg.Llm.HealthPath)" -UseBasicParsing -TimeoutSec 5
        return ($r.StatusCode -eq 200 -and $r.Content -match 'ok' -and $r.Content -notmatch 'error')
    } catch { return $false }
}
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

# 3. Dev-loop watchdog (exactly one instance)
$loopRunning = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -match 'dev_loop' }
if (-not $loopRunning) {
    Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $scripts 'dev_loop_watchdog.ps1') -WindowStyle Hidden
}

# 4. Dashboard - probe the actual HTTP endpoint, not just the process
# (a zombie process can exist without listening).
$dashAlive = $false
try { $dashAlive = (Invoke-WebRequest "http://localhost:$($cfg.Dashboard.Port)" -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 } catch {}
if (-not $dashAlive) {
    Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
        Where-Object { $_.CommandLine -match 'dashboard_server' } |
        ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {} }
    Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $scripts 'dashboard_server.ps1') -WindowStyle Hidden
}

# 5. Game watchdog (keeps the game itself running and on the latest build)
$gameWd = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -match 'game_watchdog' }
if (-not $gameWd) {
    Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $scripts 'game_watchdog.ps1') -WindowStyle Hidden
}

# 6b. Model arena (selection naturelle continue): cherche en permanence un
# meilleur cerveau dans l'ocean HF, remplace le champion quand un challenger
# gagne. Exactement un instance.
$arena = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -match 'model_arena' }
if (-not $arena) {
    Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $scripts 'model_arena.ps1'), '-Forever' -WindowStyle Hidden
}

# 6c. Agent joueur: le dev JOUE le stade microbe (lit l'etat, decide, pilote la
# cellule). Idle hors partie. Exactement une instance.
$player = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -match 'play_agent' }
if (-not $player) {
    Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $scripts 'play_agent.ps1') -WindowStyle Hidden
}

# 6. Publish the public progress site if it changed
pwsh -NoProfile -File (Join-Path $scripts 'publish_site.ps1') 2>$null

Add-Content -Path $cfg.Paths.DevLog -Value "- [startup] Stack relaunched after boot ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))."
