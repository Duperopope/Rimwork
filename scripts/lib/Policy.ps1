<#
DOWN HERE - POLICY (bandit auto-reglant) : le cote RECURSIF.

Le world model donne P(succes). Reste a choisir le SEUIL de gate (en dessous
duquel on saute le patch sans payer un build). Plutot que de le fixer a la main,
un bandit epsilon-greedy l'APPREND par recompense mesuree :

  recompense par patch traite :
    1.0  -> patch GARDE (build/parse OK)         (le mieux)
    0.5  -> patch SAUTE par le world model       (build economise; peut-etre un rate)
    0.0  -> patch CASSE (build paye pour rien)   (le pire)

Le bandit prefere donc le seuil qui maximise la recompense moyenne = compromis
entre "economiser des builds" et "ne pas jeter les bons patchs". C'est le
systeme qui regle sa propre politique a partir de ses resultats. Persiste dans
logs/policy.json.
#>

. "$PSScriptRoot\Config.ps1"
. "$PSScriptRoot\WorldModel.ps1"

function Get-PolicyArms {
    param($Config = (Get-DownHereConfig))
    # Les bras = seuils candidats. 0 = pas de gate (baseline). Les autres sont
    # derives du seuil adaptatif du modele (logs/wm_model.json).
    $t = 0.05
    $m = Get-WorldModelMeta -Config $Config
    if ($m -and $m.default_threshold) { $t = [double]$m.default_threshold }
    return @(0.0, [math]::Round($t, 4), [math]::Round($t * 2, 4), [math]::Round($t * 4, 4))
}

function Get-Policy {
    param($Config = (Get-DownHereConfig))
    $f = Join-Path $Config.Paths.Logs 'policy.json'
    $arms = Get-PolicyArms -Config $Config
    try {
        $p = Get-Content $f -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($p.arms.Count -eq $arms.Count) { return $p }
    } catch {}
    # init
    return [pscustomobject]@{
        eps   = 0.2
        arms  = $arms
        n     = @(0) * $arms.Count
        mean  = @(0.0) * $arms.Count
    }
}

function Save-Policy {
    param($Policy, $Config = (Get-DownHereConfig))
    $f = Join-Path $Config.Paths.Logs 'policy.json'
    $Policy | ConvertTo-Json -Depth 5 -Compress | Set-Content -Path $f -Encoding utf8
}

# Choisit un bras (epsilon-greedy). Retourne l'index + le seuil.
function Select-PolicyArm {
    param($Policy, $Config = (Get-DownHereConfig))
    $k = $Policy.arms.Count
    # exploration des bras jamais essayes d'abord
    for ($i = 0; $i -lt $k; $i++) { if ($Policy.n[$i] -eq 0) { return @{ Index = $i; Threshold = [double]$Policy.arms[$i] } } }
    if ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt $Policy.eps) {
        $i = Get-Random -Minimum 0 -Maximum $k
    } else {
        $best = 0; for ($j = 1; $j -lt $k; $j++) { if ($Policy.mean[$j] -gt $Policy.mean[$best]) { $best = $j } }
        $i = $best
    }
    return @{ Index = $i; Threshold = [double]$Policy.arms[$i] }
}

# Met a jour la recompense moyenne du bras (moyenne incrementale) + persiste.
function Update-PolicyReward {
    param([int]$Index, [double]$Reward, $Policy, $Config = (Get-DownHereConfig))
    $n = [int]$Policy.n[$Index] + 1
    $mean = [double]$Policy.mean[$Index] + ($Reward - [double]$Policy.mean[$Index]) / $n
    $Policy.n[$Index] = $n
    $Policy.mean[$Index] = [math]::Round($mean, 4)
    Save-Policy -Policy $Policy -Config $Config
    return $Policy
}
