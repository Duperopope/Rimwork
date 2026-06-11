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

    # The model sometimes "completes" a task with an empty stub that
    # compiles and passes tests (observed: a TryClaimBest placeholder
    # returning null). Reject placeholder patches outright.
    if ($Replace -match '(?i)placeholder|will be (expanded|implemented)|// TODO: implement|throw new NotImplementedException') {
        return "REJECTED anti-stub: patch contains a placeholder/stub instead of a real implementation. Write the actual logic."
    }
    # Structural stub: a newly added method whose whole body is empty or a
    # bare 'return null;'/'return;' (the TryClaimBest incident). Methods
    # like that compile, pass tests, and do nothing.
    foreach ($m in [regex]::Matches($Replace, '(?ms)(public|private|protected)\s+[\w<>\[\]?, ]+\s+(\w+)\s*\([^)]*\)\s*\{(.*?)\}')) {
        $body = $m.Groups[3].Value.Trim() -replace '//.*', ''
        if ($body -match '^\s*(return\s+(null|false|0f?|"")\s*;)?\s*$') {
            return "REJECTED anti-stub: method '$($m.Groups[2].Value)' has an empty/trivial body (returns nothing useful). Implement the real behavior."
        }
    }

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

function Test-ItemEvidence {
    # ANTI-FALSE-SUCCESS: a roadmap item may only be checked off if the code
    # it quotes actually exists in the target file. Two confirmed incidents
    # of "marked done, code absent" (TryClaimBest stub, phantom Pawn.Mood)
    # motivated this. Returns $true when evidence is sufficient OR the item
    # quotes no code (nothing checkable). Whitespace-normalized comparison.
    param([string]$ItemText, [string]$TargetContent)
    $quoted = [regex]::Matches($ItemText, '(?m)^\s*`(.+)`\s*$') |
        ForEach-Object { Get-NormalizedLine $_.Groups[1].Value } |
        Where-Object { $_.Length -gt 10 -and $_ -notmatch '^//' }
    if (-not $quoted -or @($quoted).Count -eq 0) { return $true }
    $normContent = ($TargetContent -split "`n" | ForEach-Object { Get-NormalizedLine $_ })
    $found = 0
    foreach ($q in $quoted) { if ($normContent -contains $q) { $found++ } }
    $ratio = $found / @($quoted).Count
    if ($ratio -ge 0.6) { return $true }
    Write-Host "EVIDENCE CHECK FAILED: only $found/$(@($quoted).Count) quoted code lines present in target file." -ForegroundColor Red
    return $false
}

function Get-NormalizedLine {
    param([string]$Line)
    return ($Line.Trim() -replace '\s+', ' ')
}
# TEST 1: stub method must be rejected
$r1 = Test-PatchPrediction -Replace "public TaskOrder TryClaimBest(Pawn pawn)`n{`n    // Placeholder implementation`n    return null;`n}" -TargetContent "class X {}" -ApiMap "TaskOrder"
# TEST 2: real implementation must pass
$r2 = Test-PatchPrediction -Replace "public int Add(int a, int b)`n{`n    int sum = a + b;`n    if (sum > 100) sum = 100;`n    return sum;`n}" -TargetContent "class X {}" -ApiMap ""
# TEST 3: item evidence - quoted code absent from file must fail
$r3 = Test-ItemEvidence -ItemText "- [ ] Step T - insert:`n      ``    public float Mood { get; set; } = 70f;``" -TargetContent "public class Pawn { public int X; }"
# TEST 4: item evidence - quoted code present must pass
$r4 = Test-ItemEvidence -ItemText "- [ ] Step T - insert:`n      ``    public float Mood { get; set; } = 70f;``" -TargetContent "public class Pawn { `n    public float Mood { get; set; } = 70f;`n }"
"T1 stub rejected:    " + ($null -ne $r1) + "  reason: $r1"
"T2 real accepted:    " + ($null -eq $r2)
"T3 absent -> false:  " + ($r3 -eq $false)
"T4 present -> true:  " + ($r4 -eq $true)
