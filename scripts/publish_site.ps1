# Publishes the public DOWN HERE! progress site to GitHub Pages (docs/).
# Called by the self-heal scheduled task - only commits when content changed.

# Source de verite unique (paths) - voir scripts/lib/Config.ps1.
. "$PSScriptRoot\lib\Config.ps1"
$cfg = Get-DownHereConfig
. (Join-Path $cfg.Paths.Scripts 'site_gen.ps1')

$html = Get-DownHereSiteHtml -Live $false
$target = Join-Path $cfg.Paths.Docs 'index.html'

# DEV_LOG rotation: keep the working log small (the loop appends forever);
# overflow goes to docs/archive/ so the repo root stays readable.
try {
    $dl = $cfg.Paths.DevLog
    $lines = Get-Content $dl
    if ($lines.Count -gt 1500) {
        $archDir = Join-Path $cfg.Paths.Docs 'archive'
        New-Item -ItemType Directory -Force -Path $archDir | Out-Null
        $arch = Join-Path $archDir "DEV_LOG_$(Get-Date -Format yyyy-MM).md"
        $lines[0..($lines.Count - 301)] | Add-Content $arch
        , @($lines[0]) + @("") + $lines[($lines.Count - 300)..($lines.Count - 1)] | Set-Content $dl -Encoding utf8
    }
} catch {}
$old = if (Test-Path $target) { Get-Content $target -Raw } else { "" }
# Ignore the timestamp line when comparing so we don't commit every tick.
$norm = { param($x) ($x -replace 'Mise &agrave; jour: [^<]+', '' -replace 'g&eacute;n&eacute;r&eacute; [^<]+', '') }
if ((& $norm $html) -eq (& $norm $old)) { exit 0 }

Set-Content -Path $target -Value $html -Encoding utf8
git -C $cfg.Root add docs/index.html 2>$null | Out-Null
git -C $cfg.Root commit -q -m "site: progress update (auto)" 2>$null | Out-Null
git -C $cfg.Root push -q origin master 2>$null | Out-Null
Write-Host "site published"
