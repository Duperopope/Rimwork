# DOWN HERE! - automated end-to-end playtest of the Origines stage (Thrive fork).
# "L'IA doit apprendre a y jouer au jeu de bout en bout" (12/06/2026):
# launches the fork's microbe benchmark scene (spawns real cells, real AI,
# real physics - the game playing itself) for a fixed duration, then reports
# alive/dead + duration into scripts/logs/health_origines.json so the loop
# and the dashboard can SEE the microbe stage running, not just compiling.
param(
    [int]$DurationSec = 90,
    [string]$ForkDir = "g:\Rimwork\reference\thrive",
    [string]$GodotExe = "C:\Users\Smedj\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine.Mono_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_mono_win64\Godot_v4.6.3-stable_mono_win64.exe"
)

$log = "g:\Rimwork\scripts\logs\playtest_origines.log"
$out = "g:\Rimwork\scripts\logs\health_origines.json"

$p = Start-Process -FilePath $GodotExe -PassThru -RedirectStandardOutput $log `
    -ArgumentList @("--path", $ForkDir, "res://src/benchmark/microbe/MicrobeBenchmark.tscn")

$deadline = (Get-Date).AddSeconds($DurationSec)
while ((Get-Date) -lt $deadline -and -not $p.HasExited) { Start-Sleep 3 }

$survived = -not $p.HasExited
if ($survived) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }

$tail = if (Test-Path $log) { (Get-Content $log -Tail 30) -join "`n" } else { "" }
$errors = ([regex]::Matches($tail, 'ERROR|Unhandled')).Count

@{
    timestamp   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    stage       = "Origines (fork Thrive - microbe benchmark)"
    survivedSec = $DurationSec
    alive       = $survived
    errorsTail  = $errors
} | ConvertTo-Json | Set-Content $out -Encoding utf8

Write-Host "playtest origines: alive=$survived errorsInTail=$errors"
exit ($(if ($survived -and $errors -lt 5) { 0 } else { 1 }))
