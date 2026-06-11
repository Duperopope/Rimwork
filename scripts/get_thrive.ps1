# Fetches the official Thrive release used as the ORIGINES stage.
$dest = "g:\Rimwork\thirdparty"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
if (Test-Path "$dest\thrive\Thrive.exe") { Write-Host "Thrive already installed."; exit 0 }
gh release download v1.1.0 -R Revolutionary-Games/Thrive -p "Thrive_1.1.0.0_windows_desktop.7z" -D $dest --clobber
& "g:\Rimwork\scripts\7zr.exe" x "$dest\Thrive_1.1.0.0_windows_desktop.7z" -o"$dest\thrive_tmp" -y
$inner = Get-ChildItem "$dest\thrive_tmp" -Directory | Select-Object -First 1
Move-Item $inner.FullName "$dest\thrive" -Force
Write-Host "Thrive installed at $dest\thrive"
