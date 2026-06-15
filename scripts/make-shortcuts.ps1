# DOWN HERE - cree les RACCOURCIS BUREAU (Demarrer / Arreter / Voir l'IA jouer /
# Tableau de bord). Idempotent : relancer ecrase les .lnk existants.
#   pwsh -NoProfile -File scripts\make-shortcuts.ps1
. "$PSScriptRoot\lib\Config.ps1"
$cfg = Get-DownHereConfig
$scripts = $cfg.Paths.Scripts
$desktop = [Environment]::GetFolderPath('Desktop')
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = (Get-Command powershell).Source }
$ws = New-Object -ComObject WScript.Shell

function New-PsShortcut($name, $script, $icon, $iconIdx) {
    $lnk = Join-Path $desktop "$name.lnk"
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = $pwsh
    $s.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $scripts $script)`""
    $s.WorkingDirectory = $scripts
    $s.IconLocation = "$icon,$iconIdx"
    $s.Description = "DOWN HERE - $name"
    $s.Save()
    Write-Host "  cree: $lnk"
}

# Icones systeme (shell32.dll) lisibles et toujours presentes.
New-PsShortcut 'DOWN HERE - BOUCLE COMPLETE' 'loop-all.ps1'  "$env:SystemRoot\System32\shell32.dll" 144  # etoiles/auto
New-PsShortcut 'DOWN HERE - Demarrer'        'start-all.ps1' "$env:SystemRoot\System32\shell32.dll" 137  # fleches/marche
New-PsShortcut "DOWN HERE - Voir l'IA jouer" 'play-now.ps1'  "$env:SystemRoot\System32\shell32.dll" 137
New-PsShortcut 'DOWN HERE - Arreter'         'stop-all.ps1'  "$env:SystemRoot\System32\shell32.dll" 27   # croix/stop

# Tableau de bord = raccourci Internet (.url) vers le dashboard, ouvre le navigateur.
$urlFile = Join-Path $desktop 'DOWN HERE - Tableau de bord.url'
Set-Content -Path $urlFile -Encoding ascii -Value @(
    '[InternetShortcut]'
    "URL=http://localhost:$($cfg.Dashboard.Port)"
    "IconFile=$env:SystemRoot\System32\shell32.dll"
    'IconIndex=18'
)
Write-Host "  cree: $urlFile"
Write-Host "`nRaccourcis bureau crees. (Demarrer / Voir l'IA jouer / Arreter / Tableau de bord)"
