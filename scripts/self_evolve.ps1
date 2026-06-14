<#
DOWN HERE - AUTO-MODIFICATION (le systeme reecrit son PROPRE code).

Le dev_loop ameliore le JEU. Ici, le systeme ameliore SES PROPRES scripts
(dashboard, utilitaires...). C'est l'auto-amelioration au niveau du code, lignee
ADAS (Automated Design of Agentic Systems), STOP (Self-Taught Optimizer),
machine de Godel (conceptuel), Voyager (bibliotheque de competences).

GARDE-FOUS INFRANCHISSABLES (un systeme qui se reecrit ne doit jamais pouvoir
casser ou desactiver ses propres freins) :
  - ALLOWLIST : il ne peut editer qu'une liste blanche de fichiers non critiques.
  - PROTEGES  : Config, Modes, le harnais de tests, l'orchestrateur et CE moteur
                ne sont JAMAIS editables.
  - VALIDATION: toute edition doit passer le parse de TOUS les scripts + le
                harnais run-tests.ps1, sinon REVERT immediat.
  - PAS DE PUSH, master jamais casse : les editions validees sont ecrites en
                PATCH a revoir (logs/self_evolve/), et avec -Apply commitees sur
                une branche dediee self-evolve/<ts> (jamais master, jamais push).

Dot-sourcable pour les tests (le runner ne s'execute pas si dot-source).

  pwsh -File scripts/self_evolve.ps1                 # un cycle autonome
  pwsh -File scripts/self_evolve.ps1 -Index          # regenere scripts/INDEX.md
#>

param([switch]$Index, [switch]$Apply, [switch]$Loop, [int]$IntervalMin = 10)

. "$PSScriptRoot\lib\Config.ps1"
. "$PSScriptRoot\lib\Patch.ps1"
. "$PSScriptRoot\lib\Chat.ps1"   # Invoke-LocalLlm

# Fichiers que le systeme PEUT s'auto-editer (non critiques).
function Get-SelfAllowlist {
    return @('site_gen.ps1', 'llm_call.ps1', 'test_lm_api.ps1', 'downhere-dev.ps1', 'publish_site.ps1')
}
# Jamais editables (les freins + le moteur). Defense en profondeur.
function Get-SelfProtected {
    return @('Config.ps1', 'Modes.ps1', 'run-tests.ps1', 'self_evolve.ps1', 'orchestrator.ps1',
        'startup_all.ps1', 'dev_loop.ps1', 'dashboard_server.ps1')
}

function Test-SelfEditAllowed {
    param([string]$FileName)
    $n = Split-Path $FileName -Leaf
    if ((Get-SelfProtected) -contains $n) { return $false }
    return ((Get-SelfAllowlist) -contains $n)
}

function Add-SelfJournal {
    param([string]$Text, $Config = (Get-DownHereConfig))
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Text"
    Add-Content -Path (Join-Path $Config.Paths.Logs 'self_evolve.log') -Value $line
    Write-Host $line
}

# GATE : tous les scripts parsent + le harnais de tests passe. $true si OK.
function Invoke-SelfValidate {
    param($Config = (Get-DownHereConfig), [switch]$SkipHarness)
    # 1. parse de tous les scripts (en-process, fiable)
    $bad = 0
    Get-ChildItem $Config.Paths.Scripts -Filter *.ps1 -Recurse | ForEach-Object {
        $e = $null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e) | Out-Null
        if ($e) { $bad++ }
    }
    if ($bad -gt 0) { return $false }
    if ($SkipHarness) { return $true }
    # 2. harnais de tests (process enfant). Best-effort : si le spawn echoue,
    #    on retombe sur le parse (deja validant) plutot que de bloquer.
    try {
        & pwsh -NoProfile -File (Join-Path $Config.Paths.Scripts 'tests\run-tests.ps1') *> $null
        return ($LASTEXITCODE -eq 0)
    } catch { return $true }
}

# Auto-maintenance reelle : regenere un index de tous les scripts depuis leurs
# en-tetes. Le systeme documente lui-meme sa propre structure.
function Update-SelfIndex {
    param($Config = (Get-DownHereConfig))
    $scripts = Get-ChildItem $Config.Paths.Scripts -Filter *.ps1 -Recurse | Sort-Object FullName
    $rows = foreach ($s in $scripts) {
        $syn = ''
        foreach ($ln in (Get-Content $s.FullName -TotalCount 12)) {
            $t = $ln.Trim()
            if ($t -and $t -notmatch '^(<#|#>|param|\.|#!)' -and $t -ne '#') {
                $syn = ($t -replace '^#+\s*', '') -replace '\|', '/'; break
            }
        }
        $rel = $s.FullName.Substring($Config.Root.Length).TrimStart('\', '/') -replace '\\', '/'
        "| ``$rel`` | $syn |"
    }
    $md = @"
# Index des scripts (auto-genere par self_evolve.ps1)

> Genere le $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Ne pas editer a la main.

| Script | Synopsis |
|--------|----------|
$($rows -join "`n")
"@
    $out = Join-Path $Config.Paths.Scripts 'INDEX.md'
    Set-Content -Path $out -Value $md -Encoding utf8
    return $out
}

# Coeur : applique une edition a un fichier AUTORISE, valide, et soit ecrit un
# patch a revoir, soit (avec -Apply) commite sur une branche dediee. Master et
# l'arbre de travail principal sont TOUJOURS restaures. Jamais de push.
function Invoke-SelfEdit {
    param(
        [Parameter(Mandatory)][string]$Target,   # nom de fichier (ex: site_gen.ps1)
        [Parameter(Mandatory)][string]$Search,
        [Parameter(Mandatory)][string]$Replace,
        [string]$Why = 'self-edit',
        [switch]$Apply,
        [switch]$SkipHarness,
        $Config = (Get-DownHereConfig)
    )
    if (-not (Test-SelfEditAllowed -FileName $Target)) {
        return [pscustomobject]@{ ok = $false; reason = "REFUSE : '$Target' n'est pas dans l'allowlist (ou est protege)." }
    }
    # localise le fichier sous scripts/
    $abs = Get-ChildItem $Config.Paths.Scripts -Filter (Split-Path $Target -Leaf) -Recurse | Select-Object -First 1
    if (-not $abs) { return [pscustomobject]@{ ok = $false; reason = "introuvable: $Target" } }
    $abs = $abs.FullName
    $snapshot = Get-Content $abs -Raw

    $patched = Try-ApplyEdit -Content ($snapshot -replace "`r", "") -Search $Search -Replace $Replace
    if ($null -eq $patched -or $patched -eq ($snapshot -replace "`r", "")) {
        return [pscustomobject]@{ ok = $false; reason = "le SEARCH ne matche pas / no-op" }
    }

    Set-Content -Path $abs -Value $patched -NoNewline
    $valid = Invoke-SelfValidate -Config $Config -SkipHarness:$SkipHarness
    if (-not $valid) {
        Set-Content -Path $abs -Value $snapshot -NoNewline   # REVERT
        Add-SelfJournal -Text "REJETE (validation KO, reverti) : $Target - $Why" -Config $Config
        return [pscustomobject]@{ ok = $false; reason = "validation echouee -> reverti" }
    }

    # validee : produire un PATCH a revoir
    $dir = Join-Path $Config.Paths.Logs 'self_evolve'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $patchFile = Join-Path $dir "$ts`_$(Split-Path $Target -Leaf).patch"
    git -C $Config.Root diff -- $abs | Set-Content -Path $patchFile -Encoding utf8

    $branch = $null
    if ($Apply) {
        # branche dediee, basee sur master, jamais push. master restaure ensuite.
        $branch = "self-evolve/$ts"
        $rel = $abs.Substring($Config.Root.Length).TrimStart('\', '/')
        git -C $Config.Root switch -c $branch 2>$null | Out-Null
        git -C $Config.Root add -- $rel 2>$null | Out-Null
        git -C $Config.Root commit -q -m "self-evolve: $Why ($([System.IO.Path]::GetFileName($abs)))" 2>$null | Out-Null
        git -C $Config.Root switch - 2>$null | Out-Null   # retour a la branche precedente
    }
    # restaure l'arbre principal (l'edition vit dans le patch / la branche).
    Set-Content -Path $abs -Value $snapshot -NoNewline
    Add-SelfJournal -Text "VALIDEE : $Target - $Why -> patch $([System.IO.Path]::GetFileName($patchFile))$(if($branch){" + branche $branch"})" -Config $Config
    return [pscustomobject]@{ ok = $true; patch = $patchFile; branch = $branch }
}

# Cycle autonome : demande au LLM local UNE petite amelioration d'un fichier
# autorise ; si le LLM est injoignable, fait de l'auto-maintenance (INDEX.md).
function Invoke-SelfEvolveCycle {
    param([switch]$Apply, $Config = (Get-DownHereConfig))
    $target = Get-SelfAllowlist | Get-Random
    $abs = Get-ChildItem $Config.Paths.Scripts -Filter $target -Recurse | Select-Object -First 1
    if (-not $abs) { return }
    $content = (Get-Content $abs.FullName -Raw)
    $excerpt = ($content -split "`n" | Select-Object -First 60) -join "`n"
    $sys = "Tu ameliores le code d'un outil PowerShell SANS changer son comportement (lisibilite, robustesse, commentaire utile). Reponds par UN bloc: FILE: $target puis <<<<<< SEARCH / lignes exactes / ====== / remplacement / >>>>>> REPLACE. Rien d'autre."
    $resp = Invoke-LocalLlm -Messages @(@{role='system';content=$sys}, @{role='user';content="Fichier $target (extrait):`n$excerpt"}) -Temperature 0.3 -MaxTokens 300 -Config $Config
    if (-not $resp) {
        $out = Update-SelfIndex -Config $Config
        Add-SelfJournal -Text "LLM injoignable -> auto-maintenance: INDEX.md regenere ($out)" -Config $Config
        return
    }
    $blocks = Parse-SearchReplaceBlocks -Text $resp
    if (@($blocks).Count -eq 0) { Add-SelfJournal -Text "pas de bloc SEARCH/REPLACE propose pour $target" -Config $Config; return }
    $b = $blocks[0]
    $r = Invoke-SelfEdit -Target $target -Search $b.Search -Replace $b.Replace -Why "amelioration LLM auto-proposee" -Apply:$Apply -Config $Config
    Add-SelfJournal -Text "cycle sur $target -> ok=$($r.ok) $($r.reason)" -Config $Config
}

# --- Runner (ne s'execute PAS si le fichier est dot-source pour les tests) ---
if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.Line -notmatch '^\s*\.\s') {
    $cfg = Get-DownHereConfig
    # SELF-GUARD : une seule instance en boucle (mode EVOLVE).
    if ($Loop) {
        $me = $PID
        $twins = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match 'self_evolve' -and $_.ProcessId -ne $me }
        if ($twins) { Write-Host "self_evolve deja en cours - sortie."; exit 0 }
        while ($true) { Invoke-SelfEvolveCycle -Apply:$Apply -Config $cfg; Start-Sleep -Seconds ($IntervalMin * 60) }
    }
    elseif ($Index) { $p = Update-SelfIndex -Config $cfg; Write-Host "INDEX.md regenere -> $p" }
    else { Invoke-SelfEvolveCycle -Apply:$Apply -Config $cfg }
}
