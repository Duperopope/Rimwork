<#
DOWN HERE - WORLD MODEL (cote PowerShell).

Pont vers le predicteur Python (scripts/wm/predict.py) : donne la probabilite
qu'un patch SEARCH/REPLACE soit GARDE (build/parse OK). Le modele est entraine
par scripts/wm/train.py sur l'experience reelle du systeme.

Tout est tolerant aux pannes : si Python/modele absent -> $null (le dev_loop
retombe alors sur ses heuristiques, jamais de blocage).
#>

. "$PSScriptRoot\Config.ps1"

function Get-WorldModelMeta {
    param($Config = (Get-DownHereConfig))
    $f = Join-Path $Config.Paths.Logs 'wm_model.json'
    try { return (Get-Content $f -Raw -ErrorAction Stop | ConvertFrom-Json) } catch { return $null }
}

function Test-WorldModelReady {
    param($Config = (Get-DownHereConfig))
    $m = Get-WorldModelMeta -Config $Config
    return ($null -ne $m -and $m.ready -eq $true)
}

# P(succes) d'un patch, ou $null si indisponible.
function Get-PatchSuccessProbability {
    param(
        [string]$Search, [string]$Replace, [string]$Ext,
        $Config = (Get-DownHereConfig)
    )
    $py = Join-Path $Config.Paths.Scripts 'wm\predict.py'
    if (-not (Test-Path $py)) { return $null }
    try {
        $payload = @{ search = $Search; replace = $Replace; ext = $Ext } | ConvertTo-Json -Compress
        $out = ($payload | & python $py 2>$null)
        if ($out -and $out.Trim() -match '^[0-9]*\.?[0-9]+$') { return [double]$out.Trim() }
    } catch {}
    return $null
}

# Enregistre un exemple d'experience VECU (raw) que le re-entrainement ingerera.
# label : 1 = garde (succes), 0 = casse/echec.
function Add-PatchExperience {
    param(
        [string]$Search, [string]$Replace, [string]$Ext, [int]$Label,
        $Config = (Get-DownHereConfig)
    )
    $f = Join-Path $Config.Paths.Logs 'experience_raw.jsonl'
    @{ search = $Search; replace = $Replace; ext = $Ext; y = $Label } |
        ConvertTo-Json -Compress | Add-Content -Path $f -Encoding utf8
}
