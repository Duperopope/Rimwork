# DOWN HERE - ARRETER toute la pile (raccourci bureau).
# Coupe TOUT : dashboard, orchestrateur, agents (dev/jeu/arene/evolve), le jeu et
# le serveur LLM (WSL). Pour relancer : raccourci "Demarrer".
. "$PSScriptRoot\lib\Config.ps1"
$cfg = Get-DownHereConfig
Set-Content -Path (Join-Path $cfg.Paths.Logs 'stack_state.txt') -Value 'PAUSED'
try { Disable-ScheduledTask -TaskName RimworkAIDev -ErrorAction SilentlyContinue | Out-Null } catch {}

# Tue les processus pwsh de la pile (en s'excluant soi-meme). Le nom de fichier de
# ce script ne contient AUCUN des motifs ci-dessous -> pas d'auto-kill.
$pat = 'dashboard_server|orchestrator|dev_loop|game_watchdog|model_arena|play_agent|playtest|self_evolve|recurse|startup_all|publish_site'
Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match $pat } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {} }

# Tue le jeu (Godot/Thrive/Rimwork) s'il tourne.
Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(godot|Thrive|Rimwork)' } |
    ForEach-Object { try { Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch {} }

# Decharge le serveur LLM dans WSL (libere la VRAM).
try { wsl -d Ubuntu -u root -- bash -c "pkill -f llama-server" 2>$null } catch {}

# Confirmation visuelle (le reste est silencieux car lance cache).
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    [System.Windows.Forms.MessageBox]::Show('DOWN HERE : tout est arrete (dashboard, agents, jeu, LLM).', 'DOWN HERE', 'OK', 'Information') | Out-Null
} catch {}
