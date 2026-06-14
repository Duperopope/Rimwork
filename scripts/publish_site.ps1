# Publie le site public DOWN HERE! (docs/index.html) = la MEME SPA, en statique
# (donnees injectees inline). Ne commit QUE si le contenu reel a change -> fini
# le spam "site: progress update (auto)" a chaque tick.

. "$PSScriptRoot\lib\Config.ps1"
. "$PSScriptRoot\lib\Dashboard.ps1"
$cfg = Get-DownHereConfig

# Rotation DEV_LOG (garde le log de travail petit ; surplus -> docs/archive/).
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

$data = Get-DashboardData -Config $cfg

# Signature de contenu REEL (progression + derniere activite significative).
# Les commits "site auto" sont filtres de l'activite -> publier ne se
# re-declenche pas lui-meme. On ne commit que si ca change vraiment.
$lastAct = if ($data.activity -and $data.activity.Count) { $data.activity[0].text } else { "" }
$sig = "$($data.progress.pct)|$($data.progress.done)|$($data.progress.todo)|$($data.progress.kept)|$lastAct"
$sigFile = Join-Path $cfg.Paths.Logs 'site.sig'
$last = if (Test-Path $sigFile) { (Get-Content $sigFile -Raw).Trim() } else { "" }
if ($sig -eq $last) { exit 0 }

$json = $data | ConvertTo-Json -Depth 8 -Compress
$html = Get-DashboardHtml -DataJson $json
$target = Join-Path $cfg.Paths.Docs 'index.html'
Set-Content -Path $target -Value $html -Encoding utf8
Set-Content -Path $sigFile -Value $sig -Encoding ascii

git -C $cfg.Root add docs/index.html 2>$null | Out-Null
git -C $cfg.Root commit -q -m "site: progress update (auto)" 2>$null | Out-Null
git -C $cfg.Root push -q origin master 2>$null | Out-Null
Write-Host "site published (contenu change)"
