<#
DOWN HERE - boucle de dev autonome (edition THRIVE / stade cellulaire actif).

Cible: reference/thrive (le jeu actif). Le superviseur ecrit ROADMAP.md ;
ce script execute UNE tache etroite a la fois via le LLM local, valide, et
ne garde que si ca passe. Scope assume (voir docs/DOWN_HERE_DESIGN.md):
- donnees JSON (organites, composes, biomes, membranes...) -> validees par parse JSON
- code C# nomme par la tache -> valide par `dotnet build Thrive.csproj`
- traductions .po -> gardees si la tache l'autorise
PAS de reecriture d'archi: un petit modele ne game-designe pas Thrive.

Garde-fous conserves de l'ancienne boucle: anti-stub, prediction d'echec,
verification de preuve, detection de no-op, lecons, revert sur echec.
#>

param(
    [string]$LlmUrl = "",
    [string]$Model = "downhere-coder",
    [string]$ProjectDir = "",
    [int]$MaxIterations = 200,
    [int]$DelaySeconds = 5
)

# Socle (paths/url, matcher de patch, world model + policy) - voir scripts/lib/.
. "$PSScriptRoot\lib\Config.ps1"
. "$PSScriptRoot\lib\Patch.ps1"
. "$PSScriptRoot\lib\Policy.ps1"
$cfg = Get-DownHereConfig
$Root = $cfg.Root
if (-not $LlmUrl) { $LlmUrl = $cfg.Llm.BaseUrl + $cfg.Llm.ChatPath }
if (-not $ProjectDir) { $ProjectDir = $cfg.Paths.ActiveGame }

$systemPrompt = [string](Get-Content "$Root\LM_STUDIO_SYSTEM_PROMPT.md" -Raw) + "`n`n/no_think"
$logDir = "$Root\scripts\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

# ---------------------------------------------------------------------------
# Build = dotnet build du projet Thrive. Les DLL natives sont deja compilees
# (le jeu se lance), on ne valide donc QUE la couche C#.
function Invoke-Build {
    Push-Location $ProjectDir
    $out = dotnet build Thrive.csproj -c Debug --nologo 2>&1 | Out-String
    $ok = $out -match "\b0 Erreur\(s\)|\b0 Error\(s\)"
    Pop-Location
    return @{ Ok = $ok; Output = $out }
}

# Validation des fichiers de donnees: un JSON malforme ne casse pas le build
# (charge au runtime) mais plante le jeu. On verifie au moins qu'il parse.
function Test-JsonValid {
    param([string]$Text)
    try { $null = $Text | ConvertFrom-Json; return $true } catch { return $false }
}

function Invoke-Llm {
    param([string]$UserMessage)
    $body = @{
        model       = $Model
        messages    = @(
            @{ role = "system"; content = $systemPrompt },
            @{ role = "user"; content = $UserMessage }
        )
        max_tokens  = 1200
        temperature = 0.4
    } | ConvertTo-Json -Depth 6
    try {
        $r = Invoke-RestMethod -Uri $LlmUrl -Method Post -ContentType "application/json" -Body $body -TimeoutSec 900
        return $r.choices[0].message.content
    } catch {
        Write-Host "Appel LLM echoue: $_" -ForegroundColor DarkRed
        return $null
    }
}

function Add-Lesson {
    param([string]$Context)
    $p = @"
You just failed a coding task on the Thrive (DOWN HERE) codebase. Details:
$Context

Distill ONE short reusable lesson (max 25 words) preventing this exact
mistake next time. Reply with only the lesson.
"@
    $lesson = Invoke-Llm -UserMessage $p
    if ($lesson) {
        $line = ($lesson -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()
        if ($line.Length -gt 5 -and $line.Length -lt 300) {
            Add-Content -Path "$logDir\lessons.md" -Value "- $line"
        }
    }
}

function Get-Lessons {
    $lp = "$logDir\lessons.md"
    if (Test-Path $lp) { return (Get-Content $lp | Select-Object -Last 10) -join "`n" }
    return ""
}

function Invoke-Improve {
    # Le dev REGARDE le jeu (ses donnees reelles) et propose UNE amelioration
    # concrete, qu'il s'ajoute a lui-meme dans ROADMAP.md. Portee realiste d'un
    # LLM local: raisonner sur le CONTENU (equilibrage, organites, biomes...) et
    # proposer une petite addition verifiable - UNE a la fois. Le vrai "jouer au
    # jeu 3D" (vision + controle) reste l'horizon world-model (agent bridge).
    param([int]$Iter)
    $dataFiles = @(
        "simulation_parameters/microbe_stage/compounds.json",
        "simulation_parameters/microbe_stage/organelles.json",
        "simulation_parameters/microbe_stage/biomes.json",
        "simulation_parameters/microbe_stage/membranes.json"
    )
    $rel = $dataFiles[(Get-Random -Maximum $dataFiles.Count)]
    $abs = Join-Path $ProjectDir ($rel -replace '/', '\')
    if (-not (Test-Path $abs)) { return }
    $content = (Get-Content $abs -TotalCount 120) -join "`n"
    $existing = (Get-Content "$Root\ROADMAP.md" -Raw)

    # APPROCHE JOUEUR: si une partie microbe tourne, le jeu a ecrit l'etat REEL
    # du joueur (vie, composes, position) dans user://agent_state.json. Le dev
    # s'en sert pour proposer une amelioration ANCREE dans le vecu, pas devinee.
    $playBlock = ""
    $asPath = "$env:APPDATA\DownHereOrigins\agent_state.json"
    try {
        if ((Test-Path $asPath) -and (((Get-Date) - (Get-Item $asPath).LastWriteTime).TotalMinutes -lt 5)) {
            $state = (Get-Content $asPath -Raw)
            $playBlock = @"

ETAT REEL OBSERVE EN JOUANT (capture pendant une vraie partie):
$state
Pense a ce qu'un JOUEUR passionne RESSENTIRAIT avec cet etat (affame ? trop
facile ? composes introuvables ? ennuyeux ?) et vise une amelioration qui
repond a CE vecu concret.
"@
        }
    } catch {}

    $prompt = @"
Tu es game designer ET dev de Down Here Origins (stade cellulaire, base Thrive).
Tu examines un fichier de DONNEES reel du jeu. Propose UNE seule petite
amelioration CONCRETE et equilibree de CE fichier (une valeur, un champ, une
entree) qui rend le jeu plus riche ou mieux equilibre. Reste minuscule et sur
(donnee uniquement, JSON qui reste valide).
$playBlock
FICHIER $rel (extrait):
``````json
$content
``````

Reponds par EXACTEMENT une ligne, rien d'autre, au format:
- [ ] <action concrete d'une phrase>, dans $rel.
"@
    $resp = Invoke-Llm -UserMessage $prompt
    $line = ($resp -split "`n" | Where-Object { $_.Trim() -match '^- \[ \]' } | Select-Object -First 1)
    if (-not $line) { return }
    $desc = ($line -split ',', 2)[0]
    if ($existing -match [regex]::Escape($desc.Trim())) { Write-Host "Proposition deja en file - ignoree." -ForegroundColor DarkYellow; return }
    Add-Content -Path "$Root\ROADMAP.md" -Value $line.Trim()
    Add-Content -Path "$Root\DEV_LOG.md" -Value "- [iter $Iter] AMELIORATION PROPOSEE PAR LE DEV: $($line.Trim())"
    Write-Host "Le dev propose: $($line.Trim())" -ForegroundColor Magenta
}

# Anti-stub + prediction d'echec (sans payer un build). Verifie que les
# identifiants .Method() introduits par le REPLACE existent dans le fichier
# cible (on n'a pas de carte d'API globale pour 200k lignes de Thrive, donc
# on s'appuie sur le contenu du fichier montre + une liste noire apprise).
function Test-PatchPrediction {
    param([string]$Replace, [string]$TargetContent, [bool]$IsCSharp)

    if ($Replace -match '(?i)placeholder|will be (expanded|implemented)|// TODO: implement|throw new NotImplementedException') {
        return "REJETE anti-stub: le patch contient un placeholder au lieu d'une vraie implementation."
    }
    if (-not $IsCSharp) { return $null }

    foreach ($m in [regex]::Matches($Replace, '(?ms)(public|private|protected)\s+[\w<>\[\]?, ]+\s+(\w+)\s*\([^)]*\)\s*\{(.*?)\}')) {
        $bodyTxt = $m.Groups[3].Value.Trim() -replace '//.*', ''
        if ($bodyTxt -match '^\s*(return\s+(null|false|0f?|"")\s*;)?\s*$') {
            return "REJETE anti-stub: la methode '$($m.Groups[2].Value)' a un corps vide/trivial."
        }
    }

    $knownBad = @{}
    $kbFile = "$logDir\bad_identifiers.txt"
    if (Test-Path $kbFile) { Get-Content $kbFile | ForEach-Object { $knownBad[$_] = $true } }
    $ids = [regex]::Matches($Replace, '\.([A-Z]\w{3,})\s*\(') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    foreach ($id in $ids) {
        if ($knownBad.ContainsKey($id)) { return "Identifiant '$id' a deja casse le build (liste noire apprise)." }
        if ($TargetContent -notmatch [regex]::Escape($id) -and $id -notmatch '^(Draw|Get|Set|Add|New|To|Math|Abs|Max|Min|Count|Where|Select|Any|First|Contains|Remove|Clear)') {
            return "Identifiant '$id' absent du fichier cible - ne compilera pas."
        }
    }
    return $null
}

function Add-BadIdentifiers {
    param([string]$BuildErrors)
    foreach ($m in [regex]::Matches($BuildErrors, "'(\w{4,})'")) {
        Add-Content -Path "$logDir\bad_identifiers.txt" -Value $m.Groups[1].Value
    }
}

# Get-NormalizedLine / Parse-SearchReplaceBlocks / Try-ApplyEdit -> deplaces
# dans scripts/lib/Patch.ps1 (testables + passe tolerante). Voir Phase 5.

# Une tache n'est cochee que si le code qu'elle CITE existe vraiment dans le
# fichier cible (anti faux-succes). Vrai si aucun code cite (rien a verifier).
function Test-ItemEvidence {
    param([string]$ItemText, [string]$TargetContent)
    $quoted = [regex]::Matches($ItemText, '(?m)^\s*`(.+)`\s*$') |
        ForEach-Object { Get-NormalizedLine $_.Groups[1].Value } |
        Where-Object { $_.Length -gt 10 -and $_ -notmatch '^//' }
    if (-not $quoted -or @($quoted).Count -eq 0) { return $true }
    $normContent = ($TargetContent -split "`n" | ForEach-Object { Get-NormalizedLine $_ })
    $found = 0
    foreach ($q in $quoted) { if ($normContent -contains $q) { $found++ } }
    if (($found / @($quoted).Count) -ge 0.6) { return $true }
    Write-Host "PREUVE INSUFFISANTE: $found/$(@($quoted).Count) lignes citees presentes." -ForegroundColor Red
    return $false
}

# (Parse-SearchReplaceBlocks + Try-ApplyEdit : voir scripts/lib/Patch.ps1)

function Hide-CompleteEnums {
    param([string]$Content)
    return [regex]::Replace($Content, '(?ms)^(\s*(?:public |internal |private )?enum\s+\w+)\s*\{.*?\n\s*\}', '$1 { /* complete, do not modify */ }')
}

# Thrive a de gros fichiers: on ne montre au modele que les zones pertinentes
# (mots-cles de la tache) + le haut du fichier, pour tenir dans le contexte.
function Get-RelevantExcerpt {
    param([string]$Content, [string]$RoadmapItem, [int]$ContextLines = 16, [int]$MaxLines = 160)
    $Content = Hide-CompleteEnums -Content $Content
    $lines = $Content -split "`n"
    if ($lines.Count -le $MaxLines) { return $Content }
    $keywords = @(([regex]::Matches($RoadmapItem, '[A-Za-z_][A-Za-z0-9_]{4,}') | ForEach-Object { $_.Value }) | Select-Object -Unique)
    $matched = New-Object System.Collections.Generic.HashSet[int]
    for ($idx = 0; $idx -lt $lines.Count; $idx++) {
        foreach ($kw in $keywords) {
            if ($lines[$idx] -match [regex]::Escape($kw)) {
                for ($j = [Math]::Max(0, $idx - $ContextLines); $j -le [Math]::Min($lines.Count - 1, $idx + $ContextLines); $j++) { [void]$matched.Add($j) }
                break
            }
        }
    }
    for ($j = 0; $j -lt [Math]::Min(40, $lines.Count); $j++) { [void]$matched.Add($j) }
    $sorted = $matched | Sort-Object
    if ($sorted.Count -gt $MaxLines) { $sorted = $sorted | Select-Object -First $MaxLines }
    $sb = New-Object System.Text.StringBuilder
    $prev = -2
    foreach ($n in $sorted) {
        if ($n -ne $prev + 1) { [void]$sb.AppendLine("// ... (lignes omises) ...") }
        [void]$sb.AppendLine($lines[$n]); $prev = $n
    }
    return $sb.ToString()
}

function Invoke-Cleanup {
    $iterLogs = Get-ChildItem "$logDir\iter_*.txt" -ErrorAction SilentlyContinue |
        Sort-Object { [int]([regex]::Match($_.BaseName, '\d+').Value) } -Descending
    if ($iterLogs.Count -gt 30) { $iterLogs | Select-Object -Skip 30 | Remove-Item -Force -ErrorAction SilentlyContinue }
}

# Resout le chemin cible nomme par la tache, sous reference/thrive uniquement.
function Resolve-Target {
    param([string]$ItemText)
    $m = [regex]::Match($ItemText, '([\w./-]+\.(cs|json|po|tres|tscn))')
    if (-not $m.Success) { return $null }
    $rel = $m.Groups[1].Value
    $abs = Join-Path $ProjectDir ($rel -replace '/', '\')
    if (-not (Test-Path $abs)) { return $null }
    return [pscustomobject]@{ Rel = $rel; Abs = $abs; Ext = $m.Groups[2].Value.ToLower() }
}

Write-Host "=== DOWN HERE - boucle de dev (Thrive) ===" -ForegroundColor Cyan

# Benchmark LLM au demarrage (detecte un GPU sature / runtime lent).
try {
    $benchStart = Get-Date
    $benchBody = @{ model = $Model; messages = @(@{ role = "user"; content = "Count from 1 to 60 separated by spaces, nothing else." }); max_tokens = 120; temperature = 0 } | ConvertTo-Json -Depth 5
    $benchResp = Invoke-RestMethod -Uri $LlmUrl -Method Post -ContentType "application/json" -Body $benchBody -TimeoutSec 120
    $benchSecs = ((Get-Date) - $benchStart).TotalSeconds
    $tokS = [math]::Round($benchResp.usage.completion_tokens / [math]::Max($benchSecs, 0.1), 1)
    Write-Host "Benchmark LLM: $($benchResp.usage.completion_tokens) tokens en $([math]::Round($benchSecs,1))s (~$tokS tok/s)" -ForegroundColor Cyan
} catch {
    Write-Host "Benchmark LLM echoue - le serveur llama (port 1234) est-il lance ?" -ForegroundColor Red
}

$blockedFile = "$logDir\blocked_items.txt"
$blockedItems = if (Test-Path $blockedFile) { @(Get-Content $blockedFile) } else { @() }
$prevItem = $null
$failStreak = 0
$StuckThreshold = 4
$keptStreak = 0
$KeptDoneThreshold = 2
$lastFailNote = $null
$lastFailItem = $null

for ($i = 1; $i -le $MaxIterations; $i++) {
    Write-Host "`n--- Iteration $i ---" -ForegroundColor Yellow
    $iterStart = Get-Date

    $roadmapLines = Get-Content "$Root\ROADMAP.md"
    $firstMatch = $roadmapLines | Select-String -Pattern '^\s*-\s*\[ \]' |
        Where-Object { $blockedItems -notcontains $_.Line.Trim() } | Select-Object -First 1

    if (-not $firstMatch) {
        # Plus de tache en file: au lieu d'idler, le dev REGARDE le jeu et
        # propose UNE amelioration concrete (auto-direction). Le superviseur
        # peut aussi ajouter des taches a tout moment.
        Write-Host "ROADMAP vide - le dev examine le jeu et propose une amelioration." -ForegroundColor Cyan
        Invoke-Improve -Iter $i
        @{ iter = $i; timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); build = "IDLE"; simOk = $true; simSummary = "le dev examine le jeu et propose des ameliorations"; iterSeconds = 0 } |
            ConvertTo-Json -Compress | Set-Content -Path "$logDir\health.json" -Encoding utf8
        $recheck = Get-Content "$Root\ROADMAP.md" | Select-String -Pattern '^\s*-\s*\[ \]' |
            Where-Object { $blockedItems -notcontains $_.Line.Trim() } | Select-Object -First 1
        if ($recheck) { continue }
        Start-Sleep -Seconds ([Math]::Max($DelaySeconds * 6, 60))
        continue
    }

    Invoke-Cleanup

    # Item multi-lignes complet.
    $itemKey = $firstMatch.Line.Trim()
    $itemLines = New-Object System.Collections.Generic.List[string]
    $itemLines.Add($firstMatch.Line)
    for ($j = $firstMatch.LineNumber; $j -lt $roadmapLines.Count; $j++) {
        $contLine = $roadmapLines[$j]
        if ($contLine -match '^\s*-\s*\[' -or $contLine -match '^\s*#' -or $contLine.Trim() -eq '') { break }
        $itemLines.Add($contLine)
    }
    $firstUnchecked = $itemLines -join "`n"

    # Cible nommee par la tache (doit exister sous reference/thrive).
    $target = Resolve-Target -ItemText $firstUnchecked
    if (-not $target) {
        Write-Host "Tache sans fichier cible valide sous reference/thrive - bloquee." -ForegroundColor DarkYellow
        Add-Content -Path $blockedFile -Value $itemKey
        Add-Content -Path "$Root\DEV_LOG.md" -Value "- [iter $i] BLOQUEE (aucun fichier cible valide nomme dans la tache): $itemKey"
        $blockedItems += $itemKey
        Start-Sleep -Seconds $DelaySeconds
        continue
    }
    $isCSharp = ($target.Ext -eq 'cs')

    # Timer dashboard.
    $ciPath = "$logDir\current_item.json"
    $prevCi = $null
    try { $prevCi = Get-Content $ciPath -Raw -ErrorAction Stop | ConvertFrom-Json } catch {}
    $since = if ($prevCi -and $prevCi.item -eq $itemKey) { $prevCi.since } else { (Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
    @{ item = $itemKey; since = $since; iter = $i } | ConvertTo-Json -Compress | Set-Content $ciPath -Encoding utf8

    if ($itemKey -eq $prevItem) { $failStreak++ } else { $failStreak = 0; $keptStreak = 0; $prevItem = $itemKey }

    if ($failStreak -ge $StuckThreshold) {
        Write-Host "Item bloque apres $StuckThreshold tentatives." -ForegroundColor DarkYellow
        Add-Content -Path $blockedFile -Value $itemKey
        Add-Content -Path "$Root\DEV_LOG.md" -Value "- [iter $i] BLOQUEE (coincee apres $StuckThreshold essais, besoin d'un humain): $itemKey"
        $blockedItems += $itemKey
        $prevItem = $null; $failStreak = 0
        Start-Sleep -Seconds $DelaySeconds
        continue
    }

    # Build de reference (uniquement pertinent pour le C#).
    $build = if ($isCSharp) { Invoke-Build } else { @{ Ok = $true; Output = "(cible non-C#, build ignore)" } }
    Write-Host $(if ($build.Ok) { "BUILD OK" } else { "BUILD FAILED" })

    $targetContent = (Get-Content $target.Abs -Raw) -replace "`r", ""
    $displayContent = if ($isCSharp) { Get-RelevantExcerpt -Content $targetContent -RoadmapItem $firstUnchecked } else { $targetContent }
    if ($displayContent.Length -gt 12000) { $displayContent = $displayContent.Substring(0, 12000) + "`n// ... (tronque) ..." }
    $lessonsText = Get-Lessons
    $lang = if ($isCSharp) { "csharp" } elseif ($target.Ext -eq 'json') { "json" } else { $target.Ext }

    $prompt = @"
PROJET: DOWN HERE (base Thrive, Godot 4.6 mono, C#). Tu travailles sur le
stade cellulaire ACTIF, dans reference/thrive.
BUILD: $(if ($build.Ok) {"OK"} else {"FAILED"})
$(if (-not $build.Ok) { "BUILD ERRORS:`n" + ($build.Output -split "`n" | Select-String "error|erreur" | Select-Object -First 10 | Out-String) })
$(if ($lastFailNote -and $lastFailItem -eq $itemKey) { "`nTON ESSAI PRECEDENT SUR CETTE TACHE A ECHOUE:`n$lastFailNote`nNe repete pas la meme approche.`n" })
$(if ($lessonsText) { "LECONS DE TES ERREURS PASSEES (respecte-les):`n$lessonsText`n" })

PREMIERE TACHE NON COCHEE (travaille UNIQUEMENT sur celle-ci):
$firstUnchecked

CONTENU ACTUEL de $($target.Rel) (edite CE fichier; certaines parties non
liees peuvent etre remplacees par "// ... (lignes omises) ..." - ton SEARCH
doit matcher EXACTEMENT des lignes reellement montrees):
``````$lang
$displayContent
``````

Propose UN petit changement vers la tache ci-dessus, en un ou plusieurs
blocs SEARCH/REPLACE (format du prompt systeme). N'affiche PAS le fichier
entier. Pour du JSON, garde un JSON VALIDE.
"@

    $suggestion = Invoke-Llm -UserMessage $prompt
    if (-not $suggestion) { Write-Host "Appel LLM echoue." -ForegroundColor Red; Start-Sleep -Seconds $DelaySeconds; continue }
    $suggestion | Out-File -FilePath "$logDir\iter_$i.txt" -Encoding utf8
    $edits = Parse-SearchReplaceBlocks -Text $suggestion
    if ($edits.Count -eq 0) { Write-Host "Aucun bloc SEARCH/REPLACE." -ForegroundColor DarkYellow; Start-Sleep -Seconds $DelaySeconds; continue }
    $changeDesc = (($suggestion -split "`n" | Select-String "^CHANGE:" | Select-Object -First 1) -replace '^CHANGE:\s*', '')

    # Prediction d'echec (sans payer un build).
    $prediction = $null
    foreach ($edit in $edits) { $prediction = Test-PatchPrediction -Replace $edit.Replace -TargetContent $targetContent -IsCSharp $isCSharp; if ($prediction) { break } }
    if ($prediction) {
        Write-Host "ECHEC PREDIT (build economise): $prediction" -ForegroundColor DarkYellow
        Add-Content -Path "$Root\DEV_LOG.md" -Value "- [iter $i] ECHEC-PREDIT: $changeDesc - $prediction"
        $lastFailNote = "Patch REJETE avant build: $prediction"; $lastFailItem = $itemKey
        Start-Sleep -Seconds $DelaySeconds; continue
    }

    $newContent = $targetContent
    $appliedCount = 0
    foreach ($edit in $edits) {
        $applied = Try-ApplyEdit -Content $newContent -Search $edit.Search -Replace $edit.Replace
        if ($null -ne $applied) { $newContent = $applied; $appliedCount++ }
        else { Add-Content -Path "$logDir\failed_searches.log" -Value "=== [iter $i] $($target.Rel) ===`n$($edit.Search)`n" }
    }
    if ($appliedCount -eq 0) {
        Write-Host "Aucun bloc SEARCH ne matche le fichier." -ForegroundColor DarkYellow
        Add-Content -Path "$Root\DEV_LOG.md" -Value "- [iter $i] SAUTE (SEARCH sans match): $changeDesc ($($target.Rel))"
        $lastFailNote = "Ton bloc SEARCH ne matchait PAS le fichier. Copie des lignes CONTIGUES exactement comme montrees."; $lastFailItem = $itemKey
        Start-Sleep -Seconds $DelaySeconds; continue
    }
    if ($newContent -eq $targetContent) {
        Write-Host "Patch no-op (fichier inchange)." -ForegroundColor DarkYellow
        Start-Sleep -Seconds $DelaySeconds; continue
    }

    # Validation pre-ecriture pour les donnees: JSON doit rester valide.
    if ($target.Ext -eq 'json' -and -not (Test-JsonValid -Text $newContent)) {
        Write-Host "Patch rejete: le JSON resultant est invalide." -ForegroundColor Red
        Add-Content -Path "$Root\DEV_LOG.md" -Value "- [iter $i] REJETE (JSON invalide): $changeDesc ($($target.Rel))"
        $lastFailNote = "Ton patch rendait le JSON invalide (il n'a pas ete ecrit). Garde une syntaxe JSON correcte (virgules, accolades)."; $lastFailItem = $itemKey
        Start-Sleep -Seconds $DelaySeconds; continue
    }

    # --- WORLD MODEL gate (RSI) : economise un build sur un patch surement
    # casse. Seuil choisi par la POLICY bandit (auto-reglee). Tolerant : si
    # modele/python absent -> aucun effet. ---
    $wmArm = $null; $wmPolicy = $null
    try {
        if (Test-WorldModelReady) {
            $wmPolicy = Get-Policy
            $sel = Select-PolicyArm -Policy $wmPolicy
            $wmArm = $sel.Index
            if ($sel.Threshold -gt 0) {
                $minP = 1.0
                foreach ($edit in $edits) {
                    $pp = Get-PatchSuccessProbability -Search $edit.Search -Replace $edit.Replace -Ext $target.Ext
                    if ($null -ne $pp -and $pp -lt $minP) { $minP = $pp }
                }
                if ($minP -lt $sel.Threshold) {
                    Write-Host "WM-SKIP (P=$([math]::Round($minP,3)) < $($sel.Threshold))" -ForegroundColor DarkYellow
                    Add-Content -Path "$Root\DEV_LOG.md" -Value "- [iter $i] WM-SKIP (P=$([math]::Round($minP,3)) < seuil $($sel.Threshold)): $changeDesc ($($target.Rel))"
                    $wmPolicy = Update-PolicyReward -Index $wmArm -Reward 0.5 -Policy $wmPolicy
                    $lastFailNote = "Le world model juge ce patch tres risque (P=$([math]::Round($minP,3))). Change d'approche."; $lastFailItem = $itemKey
                    Start-Sleep -Seconds $DelaySeconds; continue
                }
            }
        }
    } catch {}

    Set-Content -Path $target.Abs -Value $newContent -NoNewline
    Write-Host "Ecrit $($target.Rel) ($appliedCount/$($edits.Count) edits)"

    # Validation post-ecriture: C# -> build doit passer.
    $ok = $true
    $buildErrors = ""
    if ($isCSharp) {
        $newBuild = Invoke-Build
        $ok = $newBuild.Ok
        if (-not $ok) { $buildErrors = ($newBuild.Output -split "`n" | Select-String "error|erreur" | Select-Object -First 6) -join "`n" }
    }

    if ($ok) {
        Write-Host "GARDE (validation OK)." -ForegroundColor Green
        Add-Content -Path "$Root\DEV_LOG.md" -Value "- [iter $i] KEPT: $changeDesc ($($target.Rel))"
        @{ iter = $i; timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); build = "OK"; simOk = $true; simSummary = "patch garde: $($target.Rel)"; iterSeconds = [math]::Round(((Get-Date) - $iterStart).TotalSeconds) } |
            ConvertTo-Json -Compress | Set-Content -Path "$logDir\health.json" -Encoding utf8
        $failStreak = 0; $keptStreak++; $lastFailNote = $null; $lastFailItem = $null

        # World model : experience POSITIVE + recompense max au bras de policy.
        try {
            foreach ($edit in $edits) { Add-PatchExperience -Search $edit.Search -Replace $edit.Replace -Ext $target.Ext -Label 1 }
            if ($null -ne $wmArm) { $wmPolicy = Update-PolicyReward -Index $wmArm -Reward 1.0 -Policy $wmPolicy }
        } catch {}

        # Dataset d'entrainement (prompt -> patch verifie) pour un futur fine-tuning.
        @{ messages = @(@{ role = "user"; content = $prompt }, @{ role = "assistant"; content = $suggestion }); meta = @{ item = $itemKey; file = $target.Rel; iter = $i } } |
            ConvertTo-Json -Depth 6 -Compress | Add-Content -Path "$logDir\training_data.jsonl"

        # Versionne dans le depot Thrive (reference/thrive a son propre git).
        git -C $ProjectDir add -A 2>$null | Out-Null
        git -C $ProjectDir commit -q -m "[ai-loop iter $i] $changeDesc ($($target.Rel))" 2>$null | Out-Null
        git -C $ProjectDir push -q 2>$null | Out-Null

        if ($keptStreak -ge $KeptDoneThreshold -and (Test-ItemEvidence -ItemText $firstUnchecked -TargetContent $newContent)) {
            Write-Host "$keptStreak changements KEPT consecutifs - tache cochee." -ForegroundColor Green
            $roadmapNow = Get-Content "$Root\ROADMAP.md"
            for ($r = 0; $r -lt $roadmapNow.Count; $r++) {
                if ($roadmapNow[$r].Trim() -eq $itemKey) { $roadmapNow[$r] = $roadmapNow[$r] -replace '\[ \]', '[x]'; break }
            }
            Set-Content -Path "$Root\ROADMAP.md" -Value $roadmapNow
            Add-Content -Path "$Root\DEV_LOG.md" -Value "- [iter $i] DONE (apres $keptStreak KEPT): $itemKey"
            $keptStreak = 0; $failStreak = 0; $prevItem = $null
        }
    } else {
        Write-Host "BUILD CASSE apres patch - revert." -ForegroundColor Red
        Add-Content -Path "$logDir\failed_builds.log" -Value "=== [iter $i] $changeDesc ($($target.Rel)) ===`n$buildErrors`n"
        Set-Content -Path $target.Abs -Value $targetContent -NoNewline
        Add-Content -Path "$Root\DEV_LOG.md" -Value "- [iter $i] REVERTED (build casse): $changeDesc ($($target.Rel))"
        $lastFailNote = "Ton patch a CASSE le build (reverti). Erreurs:`n$buildErrors`nN'utilise QUE des types/methodes presents dans le contenu montre."; $lastFailItem = $itemKey
        Add-BadIdentifiers -BuildErrors $buildErrors
        Add-Lesson -Context "Tache: $changeDesc`nErreurs:`n$buildErrors"

        # World model : experience NEGATIVE + recompense nulle au bras de policy.
        try {
            foreach ($edit in $edits) { Add-PatchExperience -Search $edit.Search -Replace $edit.Replace -Ext $target.Ext -Label 0 }
            if ($null -ne $wmArm) { $wmPolicy = Update-PolicyReward -Index $wmArm -Reward 0.0 -Policy $wmPolicy }
        } catch {}
    }

    Start-Sleep -Seconds $DelaySeconds
}
