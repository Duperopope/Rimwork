<#
DOWN HERE - Changer de MODE (Phase 2).

Ecrit le mode voulu ; l'orchestrateur l'applique dans les secondes qui suivent.

  pwsh -File set-mode.ps1 DEV     # le dev IA code (jeu ferme)
  pwsh -File set-mode.ps1 PLAY    # l'agent joue (jeu ouvert)
  pwsh -File set-mode.ps1 ARENA   # selection de modele
  pwsh -File set-mode.ps1 IDLE    # tout au repos (session superviseur)
#>

param(
    [Parameter(Mandatory)][ValidateSet('IDLE', 'DEV', 'PLAY', 'ARENA')]
    [string]$Mode
)

. "$PSScriptRoot\lib\Modes.ps1"
$cfg = Get-DownHereConfig
$applied = Set-DownHereMode -Mode $Mode -Config $cfg
Add-Content -Path $cfg.Paths.DevLog -Value "- [mode] -> $applied ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))"
Write-Host "Mode = $applied. L'orchestrateur va aligner les processus." -ForegroundColor Green
