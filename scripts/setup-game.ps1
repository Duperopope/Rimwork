<#
DOWN HERE - SETUP DU JEU ACTIF (Phase 4 : reproductibilite).

Le jeu actif (fork Thrive rebrande) vit dans reference/thrive. Il a son PROPRE
depot git (branche down-here) et n'est PAS versionne dans ce depot (3.9 Go).
Donc un clone frais de Rimwork n'a pas le jeu. Ce script le rend reproductible :

  - si reference/thrive est absent  -> le CLONE depuis le fork (branche down-here)
  - s'il est present                -> affiche son etat (branche, dernier commit)

  pwsh -File setup-game.ps1            # clone si absent, sinon statut
  pwsh -File setup-game.ps1 -Pull      # + git pull si deja present
#>

param([switch]$Pull)

. "$PSScriptRoot\lib\Config.ps1"
$cfg = Get-DownHereConfig
$dir = $cfg.Paths.ActiveGame
$url = $cfg.Game.RepoUrl
$branch = $cfg.Game.Branch

if (Test-Path (Join-Path $dir '.git')) {
    $cur = (git -C $dir branch --show-current 2>$null)
    $last = (git -C $dir log -1 --format="%h %s" 2>$null)
    Write-Host "Jeu deja present : $dir" -ForegroundColor Green
    Write-Host "  branche       : $cur"
    Write-Host "  dernier commit: $last"
    if ($Pull) {
        Write-Host "  git pull..." -ForegroundColor Cyan
        git -C $dir pull --ff-only 2>&1 | ForEach-Object { "    $_" }
    }
    return
}

Write-Host "Jeu absent - clone du fork ($branch) dans $dir ..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path (Split-Path $dir) | Out-Null
git clone --branch $branch --single-branch $url $dir
if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $dir '.git'))) {
    Write-Host "OK - jeu clone. Lance-le avec : godot --path `"$dir`"" -ForegroundColor Green
} else {
    Write-Host "ECHEC du clone. Verifie l'acces a $url (branche $branch)." -ForegroundColor Red
    exit 1
}
