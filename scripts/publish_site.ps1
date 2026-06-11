# Publishes the public DOWN HERE! progress site to GitHub Pages (docs/).
# Called by the self-heal scheduled task - only commits when content changed.
. "g:\Rimwork\scripts\site_gen.ps1"

$html = Get-DownHereSiteHtml -Live $false
$target = "g:\Rimwork\docs\index.html"
$old = if (Test-Path $target) { Get-Content $target -Raw } else { "" }
# Ignore the timestamp line when comparing so we don't commit every tick.
$norm = { param($x) ($x -replace 'Mise &agrave; jour: [^<]+', '' -replace 'g&eacute;n&eacute;r&eacute; [^<]+', '') }
if ((& $norm $html) -eq (& $norm $old)) { exit 0 }

Set-Content -Path $target -Value $html -Encoding utf8
git -C g:\Rimwork add docs/index.html 2>$null | Out-Null
git -C g:\Rimwork commit -q -m "site: progress update (auto)" 2>$null | Out-Null
git -C g:\Rimwork push -q origin master 2>$null | Out-Null
Write-Host "site published"
