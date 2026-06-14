<#
DOWN HERE - BOUCLE META RECURSIVE (auto-amelioration).

C'est la recursion : le systeme apprend de ses propres resultats pour mieux agir.
A chaque cycle :
  1. INGERE l'experience (patchs gardes + casses + vecu en direct du dev_loop)
  2. RE-ENTRAINE le world model (predicteur de succes d'un patch)
  3. JOURNALISE les metriques (AUC, n) + l'etat de la policy bandit

Le world model ainsi ameliore sert au dev_loop a trier ses patchs (gate), ce
qui change les resultats, donc l'experience, donc le prochain re-entrainement...
La policy bandit, elle, regle seule le seuil de gate par recompense mesuree.

  pwsh -File scripts/recurse.ps1              # un cycle
  pwsh -File scripts/recurse.ps1 -Loop        # en continu (defaut 30 min)
#>

param([switch]$Loop, [int]$IntervalMin = 30)

. "$PSScriptRoot\lib\Config.ps1"
$cfg = Get-DownHereConfig
$wm = Join-Path $cfg.Paths.Scripts 'wm'
$hist = Join-Path $cfg.Paths.Logs 'wm_history.jsonl'

function Invoke-RecurseCycle {
    Write-Host "[recurse] ingestion de l'experience..." -ForegroundColor Cyan
    & python (Join-Path $wm 'bootstrap.py')
    Write-Host "[recurse] conception d'un successeur (champion-challenger garde)..." -ForegroundColor Cyan
    & python (Join-Path $wm 'successor.py') '--gens' '8'
    Write-Host "[recurse] deploiement du champion (world model)..." -ForegroundColor Cyan
    & python (Join-Path $wm 'train.py')

    # Journalise un point d'historique (metriques + policy) pour voir progresser.
    try {
        $meta = Get-Content (Join-Path $cfg.Paths.Logs 'wm_model.json') -Raw | ConvertFrom-Json
        $polF = Join-Path $cfg.Paths.Logs 'policy.json'
        $pol = if (Test-Path $polF) { Get-Content $polF -Raw | ConvertFrom-Json } else { $null }
        @{
            ts        = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            model     = $meta.model
            cv_auc    = $meta.cv_auc
            n         = $meta.n
            n_pos     = $meta.n_pos
            n_neg     = $meta.n_neg
            threshold = $meta.default_threshold
            policy_means = if ($pol) { $pol.mean } else { $null }
        } | ConvertTo-Json -Compress | Add-Content -Path $hist -Encoding utf8
        Write-Host "[recurse] AUC=$($meta.cv_auc) n=$($meta.n) seuil=$($meta.default_threshold)" -ForegroundColor Green
    } catch { Write-Host "[recurse] metriques indisponibles (peu de donnees ?)" -ForegroundColor DarkYellow }
}

if ($Loop) {
    while ($true) { Invoke-RecurseCycle; Start-Sleep -Seconds ($IntervalMin * 60) }
} else {
    Invoke-RecurseCycle
}
