<#
DOWN HERE - Selection MANUELLE d'un modele LLM depuis l'interface (dashboard).

L'utilisateur choisit un modele dans l'onglet Arene. Ce script:
  1. retrouve son repo+fichier dans le leaderboard persistant,
  2. le RE-TELECHARGE s'il a ete supprime (selection naturelle),
  3. l'EPINGLE (logs/llm_pinned.txt) -> l'arene ne le remplacera plus,
  4. le sert en prod (port 1234).
Lance en arriere-plan par le dashboard (/llm/use). Pour revenir au choix
automatique (meilleur de tous les temps), voir /llm/auto (supprime le pin).

  pwsh -File use-model.ps1 -Key <cle du modele>
#>
param([Parameter(Mandatory)][string]$Key)
. "$PSScriptRoot\lib\Config.ps1"
. "$PSScriptRoot\lib\Llm.ps1"
$cfg = Get-DownHereConfig
$leaderFile = Join-Path $cfg.Paths.Logs 'arena_leaderboard.json'
$pinFile = Join-Path $cfg.Paths.Logs 'llm_pinned.txt'
$statusFile = Join-Path $cfg.Paths.Logs 'llm_use_status.txt'   # feedback pour l'UI
function Note($m) { Set-Content $statusFile $m; Write-Host $m }

$lb = $null
if (Test-Path $leaderFile) { try { $lb = Get-Content $leaderFile -Raw | ConvertFrom-Json } catch {} }
$m = if ($lb) { $lb.models | Where-Object { $_.key -eq $Key } | Select-Object -First 1 } else { $null }
if (-not $m) { Note "Modele inconnu dans le classement: $Key"; exit 1 }

Note "Selection manuelle: $($m.key)"
$file = $m.file
$have = wsl -d Ubuntu -u root -- bash -c "test -s /root/models/$file && echo OK"
if ($have -notmatch 'OK') {
    Note "Re-telechargement de $($m.key) (supprime) - peut prendre quelques minutes..."
    $file = Get-ModelFile -Repo $m.repo -File $m.file
    if (-not $file) { Note "Echec du (re)telechargement de $($m.key)"; exit 1 }
}
Set-Content $cfg.Llm.ChampionFile $file -Encoding ascii
Set-Content $pinFile $file
Note "Chargement de $($m.key) en prod (~1-2 min)..."
Start-LlamaServer -Model $file
Note "OK: $($m.key) est le modele actif (epingle - l'arene ne le remplacera pas)."
