<#
Autonomous local dev loop: build -> test -> ask LM Studio -> apply patch -> verify -> repeat.
Reverts the change if build fails after applying.
#>

param(
    [string]$LmStudioUrl = "http://127.0.0.1:1234/v1/chat/completions",
    [string]$Model = "qwen2.5-coder-14b-instruct",
    [string]$ProjectDir = "g:\Rimwork\src\RimWorldGodot",
    [string]$LabDir = "g:\Rimwork\src\RimWorldLab",
    [int]$MaxIterations = 200,
    [int]$DelaySeconds = 5
)

$systemPrompt = [string](Get-Content "g:\Rimwork\LM_STUDIO_SYSTEM_PROMPT.md" -Raw) + "`n`n/no_think"
$logDir = "g:\Rimwork\scripts\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Invoke-Build {
    # Build via the Godot project, since it references RimWorldLab.Core -
    # this validates BOTH Main.cs (Godot) and Core changes in one pass.
    Push-Location $ProjectDir
    $out = dotnet build -c ExportRelease 2>&1 | Out-String
    $ok = $out -match "\b0 Erreur\(s\)|\b0 Error\(s\)"
    Pop-Location
    return @{ Ok = $ok; Output = $out }
}

function Invoke-Run {
    # The console lab project still hosts the deterministic-loop tests.
    # No --no-build: Invoke-Build only builds the Godot project, not this one.
    Push-Location $LabDir
    $out = dotnet run -c Release 2>&1 | Out-String
    Pop-Location
    return $out
}

function Get-ApiMap {
    # Deterministic "world map" of the codebase: every public type, method,
    # property and enum member the model is ALLOWED to call. Injected into
    # each prompt so the model stops inventing APIs that don't exist.
    $files = @(
        "g:\Rimwork\src\RimWorldLab.Core\GameWorld.cs",
        "g:\Rimwork\src\RimWorldLab.Core\Jobs.cs",
        "g:\Rimwork\src\RimWorldLab.Core\Needs.cs",
        "g:\Rimwork\src\RimWorldLab.Core\RoomDetection.cs",
        "g:\Rimwork\src\RimWorldLab.Core\FurnitureCatalog.cs"
    )
    $map = New-Object System.Text.StringBuilder
    foreach ($f in $files) {
        if (-not (Test-Path $f)) { continue }
        [void]$map.AppendLine("## $(Split-Path $f -Leaf)")
        $content = Get-Content $f -Raw
        # public class/enum/record declarations
        foreach ($m in [regex]::Matches($content, '(?m)^\s*public\s+(?:class|enum|record|interface|struct)\s+\w+[^\r\n{]*')) {
            [void]$map.AppendLine($m.Value.Trim())
        }
        # enum members (bodies of enums, compact)
        foreach ($m in [regex]::Matches($content, '(?ms)public\s+enum\s+(\w+)\s*\{(.*?)\}')) {
            $members = ($m.Groups[2].Value -split ',' | ForEach-Object { ($_ -replace '//.*','').Trim() } | Where-Object { $_ -match '^\w+$' }) -join ', '
            [void]$map.AppendLine("  enum $($m.Groups[1].Value): $members")
        }
        # public methods & properties
        foreach ($m in [regex]::Matches($content, '(?m)^\s*public\s+(?:static\s+|const\s+|readonly\s+)*[\w<>\[\]?,() ]+?\s+\w+\s*(?:\([^\r\n]*\)|\{ get|=>|=)')) {
            $sig = ($m.Value.Trim() -replace '\s*\{ get.*$','' -replace '\s*=>.*$','' -replace '\s*=.*$','')
            [void]$map.AppendLine("  $sig")
        }
    }
    $result = $map.ToString()
    # Keep the map prompt-sized: with the 16k context there is room for
    # ~2k tokens of API map, cap defensively anyway.
    if ($result.Length -gt 4500) { $result = $result.Substring(0, 4500) + "`n(...truncated)" }
    return $result
}

function Add-Lesson {
    # Persistent experience store: distill each failure into a one-line
    # lesson the model will see in every future prompt (continual learning
    # without gradient training - Reflexion-style).
    param([string]$Context)
    $lessonPrompt = @"
You just failed a coding task. Failure details:
$Context

Distill ONE short reusable lesson (max 25 words) that would prevent this
exact mistake next time, e.g. "GameWorld.cs has no ResourceKind.Stone -
Stone is an int property on GameWorldManager." Reply with only the lesson.
"@
    $lesson = Invoke-LmStudio -UserMessage $lessonPrompt
    if ($lesson) {
        $line = ($lesson -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()
        if ($line.Length -gt 5 -and $line.Length -lt 300) {
            Add-Content -Path "g:\Rimwork\scripts\logs\lessons.md" -Value "- $line"
        }
    }
}

function Get-Lessons {
    $lp = "g:\Rimwork\scripts\logs\lessons.md"
    if (Test-Path $lp) {
        return (Get-Content $lp | Select-Object -Last 10) -join "`n"
    }
    return ""
}

function Test-PatchPrediction {
    # Predictive world model of the dev process (JEPA spirit, engineering
    # form): before paying a 30s build+test cycle, predict whether the patch
    # will fail by checking every identifier the REPLACE introduces against
    # (a) the real API map, (b) identifiers already present in the target
    # file, and (c) a learned blocklist of identifiers that caused past
    # compile failures. Returns $null if the patch looks viable, otherwise
    # a human-readable reason for the predicted failure.
    param([string]$Replace, [string]$TargetContent, [string]$ApiMap)

    $knownBad = @{}
    $kbFile = "g:\Rimwork\scripts\logs\bad_identifiers.txt"
    if (Test-Path $kbFile) { Get-Content $kbFile | ForEach-Object { $knownBad[$_] = $true } }

    # Identifiers used as members/calls in the replace text: Foo.Bar / .Baz(
    $ids = [regex]::Matches($Replace, '\.([A-Z]\w{3,})\s*\(') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    foreach ($id in $ids) {
        if ($knownBad.ContainsKey($id)) {
            return "Identifier '$id' caused a compile failure before (learned blocklist)."
        }
        if ($TargetContent -notmatch [regex]::Escape($id) -and $ApiMap -notmatch [regex]::Escape($id) -and $id -notmatch '^(Draw|Get|Set|Add|New|To|Math|Abs|Max|Min|Count|Where|Select|Any|First)') {
            return "Identifier '$id' does not exist in the target file or the game API - it would not compile."
        }
    }
    return $null
}

function Add-BadIdentifiers {
    # Learn from a real compile failure: extract the identifiers the compiler
    # rejected (CS0117/CS1061/CS0103) and add them to the blocklist so the
    # predictor refuses them instantly next time.
    param([string]$BuildErrors)
    foreach ($m in [regex]::Matches($BuildErrors, "'(\w{4,})'")) {
        Add-Content -Path "g:\Rimwork\scripts\logs\bad_identifiers.txt" -Value $m.Groups[1].Value
    }
}

function Find-DuplicateBlocks {
    # Deterministic janitor: detect the loop's known failure mode of pasting
    # the same multi-line block several times (e.g. 4x "if Bed" overlays).
    # Returns a short report of 2-line sequences repeated 3+ times in a file.
    param([string]$Path)
    $lines = Get-Content $Path | ForEach-Object { $_.Trim() }
    $seen = @{}
    for ($k = 0; $k -lt $lines.Count - 1; $k++) {
        if ($lines[$k].Length -lt 15) { continue }
        $pair = $lines[$k] + " / " + $lines[$k + 1]
        if (-not $seen.ContainsKey($pair)) { $seen[$pair] = 0 }
        $seen[$pair]++
    }
    $dups = $seen.GetEnumerator() | Where-Object { $_.Value -ge 3 } | Select-Object -First 5
    if ($dups) {
        return ($dups | ForEach-Object { "$($_.Value)x: $($_.Key)" }) -join "`n"
    }
    return ""
}

function Invoke-CriticPass {
    # The "ruthless gamer" pass: actually play the build (headless sim),
    # judge it, and write the next improvement tasks - the model managing
    # its own project instead of waiting for a human roadmap.
    param([int]$Iter)
    Write-Host "CRITIC PASS: playing the build and judging it..." -ForegroundColor Magenta
    $diag = Invoke-DiagSim
    $dupReport = ""
    foreach ($f in @("g:\Rimwork\src\RimWorldGodot\Main.cs", "g:\Rimwork\src\RimWorldLab.Core\GameWorld.cs")) {
        $d = Find-DuplicateBlocks -Path $f
        if ($d) { $dupReport += "Duplicated code in $(Split-Path $f -Leaf):`n$d`n" }
    }
    $doneTitles = (Get-Content "g:\Rimwork\ROADMAP.md" | Select-String '^\s*-\s*\[x\] Step' | Select-Object -Last 12 | ForEach-Object { ($_.Line.Trim() -split ' - ')[0] }) -join ", "
    $criticPrompt = @"
You are a ruthless, passionate game critic AND the game's lead developer.
You just played the current build of your colony-sim (deterministic, RimWorld-like, planetary ambitions).

PLAYTEST RESULT (5000-tick headless run):
$($diag.Summary)

$(if ($dupReport) { "CODE HYGIENE ISSUES:`n$dupReport" })
RECENTLY SHIPPED: $doneTitles

As a critical gamer, what is the SINGLE biggest weakness a player would feel
in this build right now? Then, as the developer, write ONE small, concretely
implementable roadmap item to fix it (a few lines of code in GameWorld.cs,
Needs.cs, Jobs.cs or Main.cs).
Reply with EXACTLY one line, nothing else:
- [ ] Step C.$Iter - <concrete one-sentence change, name the target file>
"@
    $critique = Invoke-LmStudio -UserMessage $criticPrompt
    $critLine = ($critique -split "`n" | Where-Object { $_.Trim() -match '^- \[ \] Step C\.' } | Select-Object -First 1)
    if ($critLine) {
        # Drop near-duplicate proposals (same description, different number).
        $desc = ($critLine -split ' - ', 2)[-1].Trim()
        if ($desc -and ((Get-Content "g:\Rimwork\ROADMAP.md" -Raw) -match [regex]::Escape($desc))) {
            Write-Host "Critic proposed a duplicate task - ignored." -ForegroundColor DarkYellow
            return
        }
    }
    if ($critLine) {
        Add-Content -Path "g:\Rimwork\ROADMAP.md" -Value $critLine.Trim()
        Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [iter $Iter] CRITIC TASK: $($critLine.Trim())"
        Write-Host "Critic task appended: $($critLine.Trim())" -ForegroundColor Magenta
    }
}

function Invoke-DiagSim {
    # "Play" the actual game headless for 5000 ticks (same world setup as the
    # Godot build) and report colony health - this is how the loop SEES the
    # game it is making, instead of only knowing whether the code compiles.
    Push-Location $LabDir
    $out = dotnet run -c Release -- --diag 5000 2>&1 | Out-String
    Pop-Location
    $lastTick = (($out -split "`n") | Select-String '^\[tick' | Select-Object -Last 1) -join ""
    $verdict = (($out -split "`n") | Select-String '^VERDICT' | Select-Object -First 1) -join ""
    $crashed = $out -match 'Unhandled exception'
    return @{
        Ok      = -not $crashed
        Summary = if ($crashed) { "GAME CRASHED during simulation!" } else { "$lastTick`n$verdict" }
    }
}

function Invoke-LmStudio {
    param([string]$UserMessage)
    $body = @{
        model    = $Model
        messages = @(
            @{ role = "system"; content = $systemPrompt },
            @{ role = "user"; content = $UserMessage }
        )
        # Patches are small; 3000 tokens at degraded-GPU speed = 15 min per
        # iteration. 1200 is enough for any reasonable SEARCH/REPLACE set.
        max_tokens = 1200
        temperature = 0.4
    } | ConvertTo-Json -Depth 6

    try {
        $response = Invoke-RestMethod -Uri $LmStudioUrl -Method Post -ContentType "application/json" -Body $body -TimeoutSec 900
        return $response.choices[0].message.content
    } catch {
        Write-Host "LM call exception: $_" -ForegroundColor DarkRed
        if ($_.Exception.Response) {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            Write-Host "LM error body: $($reader.ReadToEnd())" -ForegroundColor DarkRed
        }
        return $null
    }
}

# Parses one or more SEARCH/REPLACE blocks from the model output.
# Format:
#   FILE: <path>
#   <<<<<<< SEARCH
#   <old lines>
#   =======
#   <new lines>
#   >>>>>>> REPLACE
function Parse-SearchReplaceBlocks {
    param([string]$Text)
    $results = @()
    $pattern = '(?ms)FILE:\s*(?<path>\S+)\s*<{5,}\s*SEARCH\s*\r?\n(?<search>.*?)\r?\n={5,}\s*\r?\n(?<replace>.*?)\r?\n>{5,}\s*REPLACE'
    foreach ($m in [regex]::Matches($Text, $pattern)) {
        $results += [pscustomobject]@{
            Path    = $m.Groups['path'].Value.Trim()
            Search  = $m.Groups['search'].Value -replace "`r", ""
            Replace = $m.Groups['replace'].Value -replace "`r", ""
        }
    }
    return $results
}

# Small models reproduce the SEARCH text with different indentation/whitespace
# than the real file, so a literal Contains() match almost always fails.
# Indentation is cosmetic in C# (doesn't affect compilation), so match
# line-by-line after collapsing whitespace, then splice in the REPLACE text
# verbatim at the matched location.
function Get-NormalizedLine {
    param([string]$Line)
    return ($Line.Trim() -replace '\s+', ' ')
}

function Try-ApplyEdit {
    param([string]$Content, [string]$Search, [string]$Replace)

    $contentLines = $Content -split "`n"
    $searchLines = @($Search -split "`n")
    while ($searchLines.Count -gt 0 -and (Get-NormalizedLine $searchLines[0]) -eq '') { $searchLines = @($searchLines[1..($searchLines.Count - 1)]) }
    while ($searchLines.Count -gt 0 -and (Get-NormalizedLine $searchLines[-1]) -eq '') { $searchLines = @($searchLines[0..($searchLines.Count - 2)]) }
    if ($searchLines.Count -eq 0) { return $null }

    $normSearch = @($searchLines | ForEach-Object { Get-NormalizedLine $_ })

    for ($start = 0; $start -le $contentLines.Count - $searchLines.Count; $start++) {
        $isMatch = $true
        for ($k = 0; $k -lt $searchLines.Count; $k++) {
            if ((Get-NormalizedLine $contentLines[$start + $k]) -ne $normSearch[$k]) { $isMatch = $false; break }
        }
        if ($isMatch) {
            $end = $start + $searchLines.Count - 1
            $before = if ($start -gt 0) { (@($contentLines[0..($start - 1)]) -join "`n") + "`n" } else { "" }
            $after = if ($end -lt $contentLines.Count - 1) { "`n" + (@($contentLines[($end + 1)..($contentLines.Count - 1)]) -join "`n") } else { "" }
            return $before + $Replace.Trim("`n") + $after
        }
    }
    return $null
}

# LM Studio is loaded with a small context window (8192 tokens). Large files
# (Main.cs is ~1250 lines / ~16k tokens) blow that limit and every call fails
# with "n_keep >= n_ctx". For big files, only show the parts of the file that
# are relevant to the current roadmap item (plus the top of the file for
# using/namespace/class context). The full $Content is still used for the
# actual SEARCH/REPLACE application, so this only shrinks what's *shown*.
# The local model has a strong, hard-to-suppress tendency to "fix" any
# enum it sees in an excerpt by hallucinating a missing closing brace,
# even when the enum is already complete and the build is fine. Collapse
# every complete enum body to a single placeholder line so the model
# never sees enum braces to "fix" in the first place.
function Hide-CompleteEnums {
    param([string]$Content)
    return [regex]::Replace($Content, '(?ms)^(\s*(?:public |internal |private )?enum\s+\w+)\s*\{.*?\n\s*\}', '$1 { /* complete, do not modify */ }')
}

function Get-RelevantExcerpt {
    param([string]$Content, [string]$RoadmapItem, [int]$ContextLines = 15, [int]$MaxLines = 140)
    $Content = Hide-CompleteEnums -Content $Content
    $lines = $Content -split "`n"
    if ($lines.Count -le $MaxLines) { return $Content }

    $keywords = @(([regex]::Matches($RoadmapItem, '[A-Za-z_][A-Za-z0-9_]{4,}') | ForEach-Object { $_.Value }) | Select-Object -Unique)
    $keywords += @('SubViewport', '_Draw', 'partial class', 'asset_manifest')

    $matched = New-Object System.Collections.Generic.HashSet[int]
    for ($idx = 0; $idx -lt $lines.Count; $idx++) {
        foreach ($kw in $keywords) {
            if ($lines[$idx] -match [regex]::Escape($kw)) {
                for ($j = [Math]::Max(0, $idx - $ContextLines); $j -le [Math]::Min($lines.Count - 1, $idx + $ContextLines); $j++) {
                    [void]$matched.Add($j)
                }
                break
            }
        }
    }

    # Always include the top of the file (usings/namespace/class declaration)
    for ($j = 0; $j -lt [Math]::Min(40, $lines.Count); $j++) { [void]$matched.Add($j) }

    $sorted = $matched | Sort-Object
    if ($sorted.Count -gt $MaxLines) { $sorted = $sorted | Select-Object -First $MaxLines }

    $sb = New-Object System.Text.StringBuilder
    $prev = -2
    foreach ($n in $sorted) {
        if ($n -ne $prev + 1) { [void]$sb.AppendLine("// ... (lines omitted) ...") }
        [void]$sb.AppendLine($lines[$n])
        $prev = $n
    }
    return $sb.ToString()
}

# Self-cleaning: per-iteration model output logs and the stdout/stderr
# transcripts grow without bound otherwise. Keep the most recent ones only.
function Invoke-Cleanup {
    $iterLogs = Get-ChildItem "$logDir\iter_*.txt" -ErrorAction SilentlyContinue |
        Sort-Object { [int]([regex]::Match($_.BaseName, '\d+').Value) } -Descending
    if ($iterLogs.Count -gt 30) {
        $iterLogs | Select-Object -Skip 30 | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    foreach ($f in @("g:\Rimwork\scripts\loop_stdout.log", "g:\Rimwork\scripts\loop_stderr.log")) {
        if ((Test-Path $f) -and (Get-Item $f).Length -gt 5MB) {
            $tail = Get-Content $f -Tail 1000
            Set-Content -Path $f -Value $tail
        }
    }
}

Write-Host "=== Rimwork autonomous dev loop ===" -ForegroundColor Cyan

# Self-managed resources: benchmark the LLM at startup so a slow runtime or
# a saturated GPU is detected immediately instead of silently crippling
# every iteration (a stale Vulkan runtime once cost 10x throughput).
try {
    $benchStart = Get-Date
    $benchBody = @{ model = $Model; messages = @(@{ role = "user"; content = "Count from 1 to 60 separated by spaces, nothing else." }); max_tokens = 120; temperature = 0 } | ConvertTo-Json -Depth 5
    $benchResp = Invoke-RestMethod -Uri "http://localhost:1234/v1/chat/completions" -Method Post -ContentType "application/json" -Body $benchBody -TimeoutSec 120
    $benchSecs = ((Get-Date) - $benchStart).TotalSeconds
    $tokS = [math]::Round($benchResp.usage.completion_tokens / [math]::Max($benchSecs, 0.1), 1)
    Write-Host "LLM benchmark: $($benchResp.usage.completion_tokens) tokens in $([math]::Round($benchSecs,1))s (~$tokS tok/s)" -ForegroundColor Cyan
    if ($benchSecs -gt 0 -and $tokS -lt 8) {
        $gpuHogs = (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'godot|game|obs|chrome|firefox' } | Select-Object -First 3 -ExpandProperty Name) -join ", "
        $hint = if ($gpuHogs) { "GPU likely shared with: $gpuHogs (normal if the game is open - the loop just runs slower)." } else { "No obvious GPU consumer - check the llama.cpp runtime (lms runtime ls; vulkan@2.21 expected)." }
        Write-Host "WARNING: throughput $tokS tok/s. $hint" -ForegroundColor Red
        Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [startup] PERF: LLM at $tokS tok/s. $hint"
    }
} catch {
    Write-Host "LLM benchmark failed - is the model loaded in LM Studio?" -ForegroundColor Red
}

# Items the local model fails on repeatedly (build keeps failing or no
# patch ever matches) get parked here so the loop moves on to other
# roadmap items instead of spinning forever on the same one. Persisted
# across restarts.
$blockedFile = "$logDir\blocked_items.txt"
$blockedItems = if (Test-Path $blockedFile) { @(Get-Content $blockedFile) } else { @() }
$prevItem = $null
$failStreak = 0
$StuckThreshold = 4
# The local model can get fixated on hallucinated "fix a missing brace"
# patches for a specific item and repeat the EXACT same bogus patch
# forever (those don't count toward $failStreak since no build/test ran).
# Track consecutive bogus-brace rejections separately and block fast.
$braceStreak = 0
$BraceStuckThreshold = 3

# A roadmap item is never marked [x] by the model itself - the loop only
# ever moves on via blocking (failure). That means an item that the model
# CAN make small successful (KEPT) edits to forever (e.g. endlessly
# tweaking a color value) never finishes and blocks real progress. After
# several consecutive KEPT changes on the SAME item, consider it done
# enough and check it off in ROADMAP.md so the loop advances.
$keptStreak = 0
$KeptDoneThreshold = 2

# The model sometimes keeps proposing the EXACT SAME patch over and over
# for the same item (it already applied successfully once, but since the
# anchor line still exists it matches again, duplicating the inserted code
# block 5x before keptStreak fires). Detect a byte-identical repeat patch
# for the same item and mark the item done immediately instead of
# re-applying it.
$lastEditFingerprint = $null
$lastEditItem = $null

# Failure feedback: remember WHY the last attempt on an item failed (build
# errors from its own patch, or a SEARCH that didn't match) and show that
# to the model on its next attempt at the SAME item, so it can correct
# itself instead of repeating the mistake blind.
$lastFailNote = $null
$lastFailItem = $null

# How many times each stuck item has been self-rewritten by the model
# (max 2 rewrites before it gets hard-blocked).
$rewriteCounts = @{}

for ($i = 1; $i -le $MaxIterations; $i++) {
    Write-Host "`n--- Iteration $i ---" -ForegroundColor Yellow

    # Every 15 iterations the model steps back, plays its own build and
    # writes the next improvement task as a "ruthless gamer" - continuous
    # self-directed project management.
    if ($i -gt 0 -and $i % 15 -eq 0) {
        Invoke-CriticPass -Iter $i
    }

    $roadmapLines = Get-Content "g:\Rimwork\ROADMAP.md"
    $firstMatch = $roadmapLines | Select-String -Pattern '^\s*-\s*\[ \]' |
        Where-Object { $blockedItems -notcontains $_.Line.Trim() } |
        Select-Object -First 1

    if (-not $firstMatch) {
        # Nothing actionable left: instead of idling, ask the model to PROPOSE
        # its own next small task (emergent dev) and append it to the roadmap.
        # The normal build/test/revert guardrails then judge the result like
        # any other item.
        # Roadmap exhausted: first let the critic play the build and write
        # an improvement task; the emergent proposal below is the fallback.
        Invoke-CriticPass -Iter $i
        $recheckMatch = Get-Content "g:\Rimwork\ROADMAP.md" | Select-String -Pattern '^\s*-\s*\[ \]' |
            Where-Object { $blockedItems -notcontains $_.Line.Trim() } | Select-Object -First 1
        if ($recheckMatch) { continue }
        Write-Host "All items blocked/done - asking model to propose an emergent task." -ForegroundColor Cyan
        $recentLog = (Get-Content "g:\Rimwork\DEV_LOG.md" -ErrorAction SilentlyContinue | Select-Object -Last 15) -join "`n"
        $proposePrompt = @"
You are the sole developer of a deterministic colony-sim game (C#, Godot).
Recent dev log:
$recentLog

Propose ONE new, very small, concretely-implementable roadmap item that makes
the game more fun, emergent or alive. It must be a single small code change to
one of: src/RimWorldLab.Core/GameWorld.cs, src/RimWorldLab.Core/Needs.cs,
src/RimWorldLab.Core/Jobs.cs, src/RimWorldGodot/Main.cs.
Reply with EXACTLY one line in this format and nothing else:
- [ ] Step E.$i - <one-sentence concrete change, mention the target file>
"@
        $proposal = Invoke-LmStudio -UserMessage $proposePrompt
        $propLine = ($proposal -split "`n" | Where-Object { $_.Trim() -match '^- \[ \] Step E\.' } | Select-Object -First 1)
        if ($propLine) {
            $propDesc = ($propLine -split ' - ', 2)[-1].Trim()
            if ($propDesc -and ((Get-Content "g:\Rimwork\ROADMAP.md" -Raw) -match [regex]::Escape($propDesc))) {
                Write-Host "Emergent proposal is a duplicate - ignored." -ForegroundColor DarkYellow
                $propLine = $null
            }
        }
        if ($propLine) {
            Add-Content -Path "g:\Rimwork\ROADMAP.md" -Value $propLine.Trim()
            Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [iter $i] EMERGENT TASK PROPOSED: $($propLine.Trim())"
            Write-Host "Emergent task appended: $($propLine.Trim())" -ForegroundColor Cyan
        } else {
            Write-Host "Model proposal unusable - sleeping." -ForegroundColor DarkYellow
            Start-Sleep -Seconds ([Math]::Max($DelaySeconds * 10, 300))
        }
        continue
    }

    Invoke-Cleanup

    $build = Invoke-Build
    Write-Host $(if ($build.Ok) { "BUILD OK" } else { "BUILD FAILED" })

    $testOutput = ""
    if ($build.Ok) {
        $testOutput = Invoke-Run
        $testSummary = ($testOutput -split "`n" | Select-String "passed|failed|tests ran") -join "`n"
        # Show the model the actual health of the game it is making - colony
        # metrics from a 5000-tick headless playthrough, not just compile state.
        $diag = Invoke-DiagSim
        $testSummary += "`nGAME HEALTH (5000-tick simulation): " + $diag.Summary
    } else {
        $testSummary = "(skipped, build failed)"
    }

    # A single Select-String match only captures the bullet's FIRST line,
    # but most roadmap items wrap across several indented continuation
    # lines that contain the actual concrete instructions. Pull those in
    # too, so the model sees the full item instead of a truncated fragment.
    $itemKey = $firstMatch.Line.Trim()
    $itemLines = New-Object System.Collections.Generic.List[string]
    $itemLines.Add($firstMatch.Line)
    for ($j = $firstMatch.LineNumber; $j -lt $roadmapLines.Count; $j++) {
        $contLine = $roadmapLines[$j]
        if ($contLine -match '^\s*-\s*\[' -or $contLine -match '^\s*#' -or $contLine.Trim() -eq '') { break }
        $itemLines.Add($contLine)
    }
    $firstUnchecked = $itemLines -join "`n"

    if ($itemKey -eq $prevItem) {
        $failStreak++
    } else {
        $failStreak = 0
        $braceStreak = 0
        $keptStreak = 0
        $prevItem = $itemKey
    }

    if ($failStreak -ge $StuckThreshold) {
        # DONE-DETECTION: if this item already produced successful (KEPT)
        # edits in any past run and now only yields unmatched/no-op patches,
        # the work most likely already exists in the file (the model keeps
        # "re-doing" it) - mark it done instead of burning more attempts.
        # U.3.1 burned ~30 iterations exactly this way.
        $keptHistoryFile = "g:\Rimwork\scripts\logs\kept_history.txt"
        if ((Test-Path $keptHistoryFile) -and ((Get-Content $keptHistoryFile) -contains $itemKey)) {
            Write-Host "Item had KEPT edits in past runs and no longer matches - marking done." -ForegroundColor Green
            $roadmapNow = Get-Content "g:\Rimwork\ROADMAP.md"
            for ($r = 0; $r -lt $roadmapNow.Count; $r++) {
                if ($roadmapNow[$r].Trim() -eq $itemKey) {
                    $roadmapNow[$r] = $roadmapNow[$r] -replace '\[ \]', '[x]'
                    break
                }
            }
            Set-Content -Path "g:\Rimwork\ROADMAP.md" -Value $roadmapNow
            Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [iter $i] DONE (had past KEPT edits, change already in file): $itemKey"
            $prevItem = $null
            $failStreak = 0
            Start-Sleep -Seconds $DelaySeconds
            continue
        }
        # SELF-REPAIR: before giving up on an item, let the model act as its
        # own lead dev - it gets the failure evidence (its bad SEARCH blocks,
        # its compiler errors) and rewrites the item into something smaller
        # and more precise. Only after a rewritten item ALSO fails is the
        # item truly blocked.
        if (-not $rewriteCounts.ContainsKey($itemKey)) { $rewriteCounts[$itemKey] = 0 }
        if ($rewriteCounts[$itemKey] -lt 2) {
            $rewriteCounts[$itemKey]++
            Write-Host "Item stuck - asking model to diagnose and rewrite it (rewrite $($rewriteCounts[$itemKey])/2)." -ForegroundColor Cyan
            $evidence = ""
            foreach ($lf in @("failed_searches.log", "failed_builds.log")) {
                $lp = "g:\Rimwork\scripts\logs\$lf"
                if (Test-Path $lp) {
                    $chunks = (Get-Content $lp -Raw) -split '(?m)^=== '
                    $evidence += (($chunks | Select-Object -Last 2) -join "`n=== ") + "`n"
                }
            }
            if ($evidence.Length -gt 3000) { $evidence = $evidence.Substring($evidence.Length - 3000) }
            $rewritePrompt = @"
You are the lead developer triaging a task your junior coder failed 4 times.
Recent failure evidence (the junior's bad patches and the compiler errors):
$evidence

THE FAILED TASK:
$firstUnchecked

Rewrite this task so the next attempt succeeds. Requirements:
- ONE much smaller step (a few lines of code at most)
- name the exact target file
- describe the change concretely; if part of the original task already
  works, keep only the missing part
- do NOT invent APIs - only reference code you saw in the evidence
Reply with ONLY the rewritten item text, a single line starting exactly with:
- [ ] Step
"@
            $rewritten = Invoke-LmStudio -UserMessage $rewritePrompt
            $newItemLine = ($rewritten -split "`n" | Where-Object { $_.Trim() -match '^- \[ \] Step' } | Select-Object -First 1)
            if ($newItemLine) {
                # Replace the old multi-line item in ROADMAP.md with the new one-liner.
                $rl = Get-Content "g:\Rimwork\ROADMAP.md"
                $outLines = New-Object System.Collections.Generic.List[string]
                $skipping = $false
                foreach ($line in $rl) {
                    if (-not $skipping -and $line.Trim() -eq $itemKey) {
                        $outLines.Add($newItemLine.Trim())
                        $skipping = $true
                        continue
                    }
                    if ($skipping) {
                        if ($line -match '^\s*-\s*\[' -or $line -match '^\s*#' -or $line.Trim() -eq '') { $skipping = $false }
                        else { continue }
                    }
                    $outLines.Add($line)
                }
                Set-Content -Path "g:\Rimwork\ROADMAP.md" -Value $outLines
                Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [iter $i] SELF-REWRITE: item rewritten by model after $StuckThreshold failures: $($newItemLine.Trim())"
                $prevItem = $null
                $failStreak = 0
                Start-Sleep -Seconds $DelaySeconds
                continue
            }
            Write-Host "Rewrite unusable - blocking item." -ForegroundColor DarkYellow
        }
        Write-Host "Item stuck after $StuckThreshold attempts - blocking it for now." -ForegroundColor DarkYellow
        Add-Content -Path $blockedFile -Value $itemKey
        Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [iter $i] BLOCKED (stuck after $StuckThreshold attempts, needs manual fix): $itemKey"
        $blockedItems += $itemKey
        $prevItem = $null
        $failStreak = 0
        Start-Sleep -Seconds $DelaySeconds
        continue
    }

    # Route each roadmap item to the single file most likely to need the
    # change, by keyword. The patch is always applied to THIS one file,
    # regardless of what path the model echoes back - this avoids garbage
    # files being written to the wrong project. Most gameplay/world/economy
    # logic (GameMap, Pawn, SetupAutoColonyPlan, resources, weather,
    # animals, rooms, ...) lives in GameWorld.cs, NOT Jobs.cs (which is
    # just the TaskKind/TaskBoard/pathing plumbing) - routing everything
    # non-UI to Jobs.cs caused the model to fixate on its enums.
    if ($firstUnchecked -match 'Step U\.|Main\.cs|SubViewport|DrawColonyTab|DrawSidePanel|DrawBuildTab|AudioStreamPlayer|hexagon|DrawColoredPolygon') {
        $targetRelPath = "src/RimWorldGodot/Main.cs"
        $targetAbsPath = "g:\Rimwork\src\RimWorldGodot\Main.cs"
    } elseif ($firstUnchecked -match 'Mood|PawnNeedState|Needs\.cs|Recreation|Hunger|Fatigue') {
        $targetRelPath = "src/RimWorldLab.Core/Needs.cs"
        $targetAbsPath = "g:\Rimwork\src\RimWorldLab.Core\Needs.cs"
    } elseif ($firstUnchecked -match 'TaskKind|TaskBoard|TaskOrder|PawnTaskDriver|Pathfinder|Jobs\.cs') {
        $targetRelPath = "src/RimWorldLab.Core/Jobs.cs"
        $targetAbsPath = "g:\Rimwork\src\RimWorldLab.Core\Jobs.cs"
    } else {
        # Default: GameMap/Pawn/world simulation/economy (GridShape, rooms,
        # weather, animals, food, hauling, raiders, organic growth, ...).
        $targetRelPath = "src/RimWorldLab.Core/GameWorld.cs"
        $targetAbsPath = "g:\Rimwork\src\RimWorldLab.Core\GameWorld.cs"
    }
    $targetContent = (Get-Content $targetAbsPath -Raw) -replace "`r", ""
    $displayContent = Get-RelevantExcerpt -Content $targetContent -RoadmapItem $firstUnchecked
    $apiMap = Get-ApiMap
    # When patching the Godot layer, also hand the model the Godot C# API
    # reference (correct Draw* signatures, .X/.Y casing rules, ...) so it
    # acts like a Godot expert instead of guessing from training data.
    if ($targetRelPath -match 'Main\.cs') {
        $apiMap += "`n" + (Get-Content "g:\Rimwork\scripts\godot_api_reference.md" -Raw)
    }
    $lessonsText = Get-Lessons

    $prompt = @"
BUILD: $(if ($build.Ok) {"OK"} else {"FAILED"})
$(if (-not $build.Ok) { "BUILD ERRORS:`n" + ($build.Output -split "`n" | Select-String "error" | Select-Object -First 10 | Out-String) })
TEST SUMMARY: $testSummary
$(if ($lastFailNote -and $lastFailItem -eq $itemKey) { "`nIMPORTANT - YOUR PREVIOUS ATTEMPT ON THIS ITEM FAILED:`n$lastFailNote`nDo NOT repeat the same approach.`n" })
$(if ($lessonsText) { "LESSONS FROM YOUR PAST MISTAKES (respect them):`n$lessonsText`n" })
AVAILABLE GAME API (these are the ONLY public types/methods/enums that exist
in the Core - NEVER call anything not listed here or shown in the file below):
$apiMap

FIRST UNCHECKED ROADMAP ITEM (work ONLY on this):
$firstUnchecked

CURRENT CONTENT of $targetRelPath (edit THIS file if your change fits here -
do not invent a different namespace/class layout, match what is below exactly.
Some unrelated parts of the file may be omitted below for brevity, marked with
"// ... (lines omitted) ..." - your SEARCH text must still match the real file,
so only target lines actually shown here):
``````csharp
$displayContent
``````

Propose ONE small next change toward the first unchecked roadmap item above.
If BUILD FAILED, fix that first. Output your change as one or more small
SEARCH/REPLACE blocks against the content shown above (see system prompt
for the exact format). Do NOT output the full file.
"@

    $suggestion = Invoke-LmStudio -UserMessage $prompt
    if (-not $suggestion) {
        Write-Host "LM Studio call failed, retrying after delay." -ForegroundColor Red
        Start-Sleep -Seconds $DelaySeconds
        continue
    }

    $suggestion | Out-File -FilePath "$logDir\iter_$i.txt" -Encoding utf8
    $edits = Parse-SearchReplaceBlocks -Text $suggestion

    if ($edits.Count -eq 0) {
        Write-Host "No SEARCH/REPLACE blocks parsed, skipping." -ForegroundColor DarkYellow
        Start-Sleep -Seconds $DelaySeconds
        continue
    }

    $changeDesc = ($suggestion -split "`n" | Select-String "^CHANGE:" | Select-Object -First 1) -replace '^CHANGE:\s*',''

    # The model repeatedly hallucinates "add a missing closing brace"
    # changes (caused by the excerpted file looking unbalanced), which
    # either no-op or break the build. The real file already builds fine
    # before this patch, so any "fix a brace" change is bogus - reject it
    # outright instead of burning a build/test cycle on it.
    if ($build.Ok -and $changeDesc -match 'brace') {
        Write-Host "Rejecting hallucinated brace-fix patch." -ForegroundColor DarkYellow
        Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [iter $i] SKIPPED (bogus brace-fix, build was already OK): $changeDesc ($targetRelPath)"
        # Don't let this count against the item's normal stuck-threshold -
        # it's an instant, free retry (no build/test was run). But if the
        # model fixates on this exact bogus pattern repeatedly, give up on
        # the item fast instead of looping forever.
        $failStreak = [Math]::Max(0, $failStreak - 1)
        $braceStreak++
        if ($braceStreak -ge $BraceStuckThreshold) {
            Write-Host "Stuck on repeated brace-fix hallucinations - blocking item." -ForegroundColor DarkYellow
            Add-Content -Path $blockedFile -Value $itemKey
            Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [iter $i] BLOCKED (stuck on brace-fix hallucination, needs manual fix): $itemKey"
            $blockedItems += $itemKey
            $prevItem = $null
            $failStreak = 0
            $braceStreak = 0
        }
        Start-Sleep -Seconds $DelaySeconds
        continue
    }
    $braceStreak = 0

    $newContent = $targetContent
    $appliedCount = 0
    # Predictive gate: refuse patches the world model predicts will fail,
    # without paying a build cycle - and tell the model WHY immediately.
    $prediction = $null
    foreach ($edit in $edits) {
        $prediction = Test-PatchPrediction -Replace $edit.Replace -TargetContent $targetContent -ApiMap $apiMap
        if ($prediction) { break }
    }
    if ($prediction) {
        Write-Host "PREDICTED FAILURE (no build wasted): $prediction" -ForegroundColor DarkYellow
        Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [iter $i] PREDICTED-FAIL (skipped before build): $changeDesc - $prediction"
        $lastFailNote = "Your patch was REJECTED before building: $prediction Use ONLY identifiers from the API map or the file content shown."
        $lastFailItem = $itemKey
        Start-Sleep -Seconds $DelaySeconds
        continue
    }

    foreach ($edit in $edits) {
        $applied = Try-ApplyEdit -Content $newContent -Search $edit.Search -Replace $edit.Replace
        if ($null -ne $applied) {
            $newContent = $applied
            $appliedCount++
        } else {
            Write-Host "SEARCH text not found in $targetRelPath, skipping that block." -ForegroundColor DarkYellow
            # Log the failing SEARCH text so mismatches can be diagnosed
            # (the model often invents context lines that aren't in the file).
            Add-Content -Path "g:\Rimwork\scripts\logs\failed_searches.log" -Value "=== [iter $i] $targetRelPath ===`n$($edit.Search)`n"
        }
    }

    if ($appliedCount -eq 0) {
        Write-Host "No SEARCH block matched current file content, skipping." -ForegroundColor DarkYellow
        Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [iter $i] SKIPPED (no SEARCH match): $changeDesc ($targetRelPath)"
        $lastFailNote = "Your SEARCH block did NOT match the file (you sent:`n$(($edits | Select-Object -First 1).Search)`n). SEARCH lines must be CONTIGUOUS lines copied EXACTLY from the file content shown - do not skip or merge lines."
        $lastFailItem = $itemKey
        Start-Sleep -Seconds $DelaySeconds
        continue
    }

    if ($newContent -eq $targetContent) {
        # The SEARCH matched but the REPLACE text is equivalent to what's
        # already there (a no-op edit). Build/tests would trivially still
        # pass, which would falsely count as progress on the roadmap item
        # forever. Treat it like a non-match so the item's fail streak
        # advances and the loop eventually moves on to a real change.
        Write-Host "Patch is a no-op (file unchanged), skipping." -ForegroundColor DarkYellow
        Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [iter $i] SKIPPED (no-op patch): $changeDesc ($targetRelPath)"
        Start-Sleep -Seconds $DelaySeconds
        continue
    }

    $editFingerprint = (($edits | ForEach-Object { $_.Search + "|||" + $_.Replace }) -join "###")
    if ($itemKey -eq $lastEditItem -and $editFingerprint -eq $lastEditFingerprint) {
        # Same item, byte-identical patch as last time it was applied - the
        # model thinks it's done and is repeating itself. Don't duplicate
        # the code block again; mark the item done and move on.
        Write-Host "Model repeated the same already-applied patch - marking item done." -ForegroundColor Green
        $roadmapNow = Get-Content "g:\Rimwork\ROADMAP.md"
        for ($r = 0; $r -lt $roadmapNow.Count; $r++) {
            if ($roadmapNow[$r].Trim() -eq $itemKey) {
                $roadmapNow[$r] = $roadmapNow[$r] -replace '\[ \]', '[x]'
                break
            }
        }
        Set-Content -Path "g:\Rimwork\ROADMAP.md" -Value $roadmapNow
        Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [iter $i] DONE (repeated identical patch): $itemKey"
        $keptStreak = 0
        $failStreak = 0
        $lastEditFingerprint = $null
        $lastEditItem = $null
        $prevItem = $null
        Start-Sleep -Seconds $DelaySeconds
        continue
    }

    Set-Content -Path $targetAbsPath -Value $newContent -NoNewline
    Write-Host "Wrote $targetAbsPath ($appliedCount/$($edits.Count) edits applied)"

    $newBuild = Invoke-Build
    if ($newBuild.Ok) {
        # Compiling is not enough - run the regression test suite
        # (GameWorldTests.RunAllTests) so a patch that builds but breaks
        # existing behavior (a previously DONE roadmap item) is reverted too.
        $newTestOutput = Invoke-Run
        $failedCount = 0
        $testLine = ($newTestOutput -split "`n" | Select-String 'tests ran' | Select-Object -Last 1)
        if ($testLine -and $testLine.Line -match '(\d+)\s+failed') { $failedCount = [int]$Matches[1] }
        $hasFailMarker = $newTestOutput -match '\[FAIL\]'

        # A patch that compiles and passes unit tests can still crash the
        # running game (e.g. index-out-of-range during a tick). Play 5000
        # ticks headless and treat a crash as a test failure.
        $newDiag = Invoke-DiagSim
        if (-not $newDiag.Ok) { $hasFailMarker = $true }

        if ($failedCount -eq 0 -and -not $hasFailMarker) {
            Write-Host "BUILD OK + tests pass after patch - keeping changes." -ForegroundColor Green
            Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [iter $i] KEPT: $changeDesc ($targetRelPath)"
            $failStreak = 0
            $keptStreak++
            $lastEditFingerprint = $editFingerprint
            $lastEditItem = $itemKey
            $lastFailNote = $null
            $lastFailItem = $null
            # Persistent record of which items ever produced a successful
            # edit - used by done-detection across loop restarts.
            Add-Content -Path "g:\Rimwork\scripts\logs\kept_history.txt" -Value $itemKey

            # TRAINING DATASET: every verified-successful (prompt -> patch)
            # pair is a future fine-tuning example. Collected from day one so
            # that when we LoRA-train a small model on THIS project, the
            # dataset already exists. JSONL, chat format.
            $trainingExample = @{
                messages = @(
                    @{ role = "user"; content = $prompt },
                    @{ role = "assistant"; content = $suggestion }
                )
                meta = @{ item = $itemKey; file = $targetRelPath; iter = $i }
            } | ConvertTo-Json -Depth 6 -Compress
            Add-Content -Path "g:\Rimwork\scripts\logs\training_data.jsonl" -Value $trainingExample

            if ($keptStreak -ge $KeptDoneThreshold) {
                Write-Host "$keptStreak consecutive KEPT changes on this item - marking it done." -ForegroundColor Green
                $roadmapNow = Get-Content "g:\Rimwork\ROADMAP.md"
                for ($r = 0; $r -lt $roadmapNow.Count; $r++) {
                    if ($roadmapNow[$r].Trim() -eq $itemKey) {
                        $roadmapNow[$r] = $roadmapNow[$r] -replace '\[ \]', '[x]'
                        break
                    }
                }
                Set-Content -Path "g:\Rimwork\ROADMAP.md" -Value $roadmapNow
                Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [iter $i] DONE (after $keptStreak consecutive KEPT changes): $itemKey"
                $keptStreak = 0
                $failStreak = 0
                $prevItem = $null
            }
        } else {
            Write-Host "BUILD OK but tests FAILED after patch - reverting." -ForegroundColor Red
            Set-Content -Path $targetAbsPath -Value $targetContent -NoNewline
            Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [iter $i] REVERTED (tests failed): $changeDesc ($targetRelPath)"
            $lastFailNote = "Your previous patch compiled but made the game's unit tests FAIL (it was reverted). Make a smaller, more conservative change that preserves existing behavior."
            $lastFailItem = $itemKey
        }
    } else {
        Write-Host "BUILD FAILED after patch - reverting." -ForegroundColor Red
        # Capture the patch + first build errors before reverting so failed
        # attempts can be diagnosed (the revert otherwise erases all evidence).
        $buildErrors = ($newBuild.Output -split "`n" | Select-String "error|erreur" | Select-Object -First 5) -join "`n"
        $patchDump = ($edits | ForEach-Object { "<<< SEARCH`n$($_.Search)`n===`n$($_.Replace)`n>>> REPLACE" }) -join "`n"
        Add-Content -Path "g:\Rimwork\scripts\logs\failed_builds.log" -Value "=== [iter $i] $changeDesc ($targetRelPath) ===`n$patchDump`n--- errors ---`n$buildErrors`n"
        Set-Content -Path $targetAbsPath -Value $targetContent -NoNewline
        Add-Content -Path "g:\Rimwork\DEV_LOG.md" -Value "- [iter $i] REVERTED (build failed): $changeDesc ($targetRelPath)"
        $lastFailNote = "Your previous patch applied but BROKE THE BUILD (it was reverted). Compiler errors:`n$buildErrors`nYou invented methods/enum members that do not exist. Use ONLY types, methods and enum values that appear in the file content shown. If the roadmap item gives an exact REPLACE block, copy it VERBATIM."
        $lastFailItem = $itemKey
        Add-BadIdentifiers -BuildErrors $buildErrors
        Add-Lesson -Context "Task: $changeDesc`nYour patch:`n$patchDump`nCompiler errors:`n$buildErrors"
    }

    Start-Sleep -Seconds $DelaySeconds
}
