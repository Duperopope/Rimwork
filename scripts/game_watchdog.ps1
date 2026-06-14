<#
Keeps the game running and up to date with the dev loop's KEPT changes,
with no manual restart needed:
  - Watches DEV_LOG.md for new "KEPT" lines.
  - On a new KEPT change (or if the game process isn't running / crashed),
    (re)launches the project via `godot --path <project>`, which runs
    Main.tscn directly against the latest compiled C# (rebuilt by the
    Godot editor's own incremental build on launch).
  - `--headless --export-release` is NOT used: it takes ~10min, can crash
    ("no debug info in PE/COFF executable"), and produced a stale/broken
    Rimwork.exe that showed a ".NET assemblies not found" dialog forever.
#>

param(
    # DOWN HERE: le vrai jeu = Thrive reworke (reference/thrive), plus l'ancien
    # colony-sim RimWorld. On lance ce projet-la.
    [string]$ProjectDir = "g:\Rimwork\reference\thrive",
    [int]$PollSeconds = 10,
    # The dev loop can produce a new KEPT change every ~10s, which used to
    # restart the game (and lose all in-game progress/days) just as often.
    # Debounce: wait for a quiet period with no new KEPT changes before
    # restarting, so the game stays up and visibly progresses. A max
    # interval still forces a restart periodically so changes aren't
    # delayed forever during a long streak of KEPT changes.
    [int]$SettleSeconds = 120,
    [int]$MaxIntervalSeconds = 600
)

$logDir = "g:\Rimwork\scripts\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$pidFile = "g:\Rimwork\scripts\game.pid"
$watchLog = "$logDir\game_watchdog.log"

# SELF-GUARD: only one game watchdog may run. Duplicate instances each kill
# the other's game as "stale", restarting it every few seconds forever.
$me = $PID
$twins = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -match 'game_watchdog' -and $_.ProcessId -ne $me }
if ($twins) {
    Write-Host "Another game watchdog is already running (pid $($twins[0].ProcessId)) - exiting."
    exit 0
}

function Write-Log {
    param([string]$Msg)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $watchLog -Value "[$stamp] $Msg"
    Write-Host "[$stamp] $Msg"
}

# `godot --path` runs the project's "Debug" build, but dev_loop.ps1 only
# ever rebuilds "ExportRelease" (the Debug build was last compiled hours
# ago and is missing every feature added since - that's the regression).
# Copy the up-to-date ExportRelease assemblies over the Debug ones so the
# game launch always reflects the latest KEPT code.
function Sync-DebugAssemblies {
    # Thrive: `godot --path` recompile le projet en Debug a chaque lancement
    # (build incremental de l'editeur Godot), donc on n'a pas a copier des
    # assemblages ExportRelease comme pour l'ancien RimWorld. On copie quand
    # meme Thrive.dll si une build ExportRelease plus recente existe.
    $src = "$ProjectDir\.godot\mono\temp\bin\ExportRelease"
    $dst = "$ProjectDir\.godot\mono\temp\bin\Debug"
    foreach ($name in @('Thrive.dll', 'Thrive.pdb')) {
        $from = Join-Path $src $name
        if ((Test-Path $from) -and (Test-Path $dst)) {
            Copy-Item -Path $from -Destination (Join-Path $dst $name) -Force -ErrorAction SilentlyContinue
        }
    }
}

# Self-cleaning: stop any leftover godot/Rimwork processes from previous
# crashed/duplicated runs so they don't pile up or fight over the build output.
function Clear-StaleGameProcesses {
    param([int]$KeepPid = -1)
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { ($_.Name -match '^(godot|Thrive|Rimwork)') -and $_.ProcessId -ne $KeepPid } |
        ForEach-Object {
            Write-Log "Cleaning up stale process $($_.Name) (pid $($_.ProcessId))"
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}

function Start-Game {
    Sync-DebugAssemblies
    Clear-StaleGameProcesses
    # --max-fps 20: this is a 20-ticks/sec tile game; uncapped rendering was
    # eating most of the GPU and starving the local LLM (3 tok/s vs 40).
    # User decision 12/06/2026: the game must boot to the MENU, never
    # straight into the colony. Gameplay verification uses the headless
    # diag sim instead of autostart screenshots.
    $env:RIMWORK_AUTOSTART = "0"
    # Minimized: the watchdog needs the game alive for its self-screenshots,
    # but it has no business popping windows onto the user's screen.
    $p = Start-Process -FilePath "godot" -ArgumentList @("--path", $ProjectDir, "--max-fps", "20") -PassThru -WindowStyle Minimized
    $p.Id | Out-File -FilePath $pidFile -Encoding ascii -NoNewline
    Write-Log "Launched game pid $($p.Id)"
    return $p
}

function Get-LastKeptCount {
    if (-not (Test-Path "g:\Rimwork\DEV_LOG.md")) { return 0 }
    return @(Get-Content "g:\Rimwork\DEV_LOG.md" | Select-String "KEPT:").Count
}

$lastKeptCount = Get-LastKeptCount
$proc = Start-Game
$lastRestartTime = Get-Date
$pendingSince = $null

while ($true) {
    Start-Sleep -Seconds $PollSeconds

    $exited = $proc.HasExited
    $newKeptCount = Get-LastKeptCount
    $now = Get-Date

    if ($newKeptCount -gt $lastKeptCount) {
        if ($null -eq $pendingSince) {
            Write-Log "$($newKeptCount - $lastKeptCount) new KEPT change(s) detected - waiting for quiet period before restart"
        }
        $lastKeptCount = $newKeptCount
        $pendingSince = $now
    }

    $settleElapsed = $pendingSince -and (($now - $pendingSince).TotalSeconds -ge $SettleSeconds)
    $maxElapsed = $pendingSince -and (($now - $lastRestartTime).TotalSeconds -ge $MaxIntervalSeconds)
    $shouldRestart = $exited -or $settleElapsed -or $maxElapsed

    if ($shouldRestart) {
        if ($exited) {
            Write-Log "Game process exited unexpectedly - restarting"
        } elseif ($settleElapsed) {
            Write-Log "KEPT changes settled - restarting game to pick them up"
        } else {
            Write-Log "Max interval reached with pending KEPT changes - restarting game to pick them up"
        }

        if (-not $exited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }

        $pendingSince = $null
        $lastRestartTime = $now
        $proc = Start-Game
    }
}
