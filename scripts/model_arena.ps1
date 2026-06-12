# DOWN HERE! - MODEL ARENA: downloads recent local code LLMs, benchmarks
# them on OUR REAL TASK (write a SEARCH/REPLACE patch against this repo's
# actual code that applies cleanly and still builds), crowns a champion in
# scripts/llm_champion.txt (read by startup_all.ps1), and deletes losers to
# reclaim disk. Raw tok/s is only a tiebreaker - relevance beats speed.
#
# Usage:
#   pwsh -File model_arena.ps1                  # bench every candidate
#   pwsh -File model_arena.ps1 -Only devstral   # bench one candidate
param(
    [string]$Only = "",
    [int]$KeepTop = 2
)

$ErrorActionPreference = "Continue"
$llm = "http://localhost:1234"
$arenaLog = "g:\Rimwork\scripts\logs\model_arena.json"
$championFile = "g:\Rimwork\scripts\llm_champion.txt"

# ---- Candidates (GGUF fitting a 16GB RX 7800 XT; MoE may spill to CPU) ----
$candidates = @(
    @{ key = "qwen25-14b";  file = "Qwen2.5-Coder-14B-Instruct-Q4_K_S.gguf"; repo = $null }  # baseline, already installed
    @{ key = "devstral";    file = "Devstral-Small-2505-Q4_K_M.gguf";        repo = "mistralai/Devstral-Small-2505_gguf" }
    @{ key = "qwen3-coder-30b"; file = "Qwen3-Coder-30B-A3B-Instruct-Q3_K_M.gguf"; repo = "unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF" }
)
# ---- CRAWLER: discover recent code-capable GGUF models (the same catalog
# LM Studio pulls from - the HF hub), keep only files fitting 16GB VRAM,
# max 2 new downloads per run (bandwidth sanity).
function Get-CrawledCandidates {
    $found = @()
    foreach ($q in "coder gguf", "code instruct gguf") {
        try {
            $hits = Invoke-RestMethod "https://huggingface.co/api/models?search=$([uri]::EscapeDataString($q))&sort=downloads&direction=-1&limit=12" -TimeoutSec 60
        } catch { continue }
        foreach ($m in $hits) {
            if ($m.id -match "embed|rerank|vision|VL|abliterat") { continue }
            try { $tree = Invoke-RestMethod "https://huggingface.co/api/models/$($m.id)/tree/main" -TimeoutSec 60 } catch { continue }
            $gg = $tree | Where-Object { $_.path -match "Q4_K_M\.gguf$|Q3_K_M\.gguf$" -and $_.path -notmatch "of-000" } |
                  Where-Object { ($_.lfs.size ?? $_.size) -gt 4e9 -and ($_.lfs.size ?? $_.size) -lt 15.5e9 } |
                  Sort-Object { $_.lfs.size ?? $_.size } -Descending | Select-Object -First 1
            if ($gg) {
                $found += @{ key = ($m.id -replace '.*/', '') ; file = [System.IO.Path]::GetFileName($gg.path); repo = $m.id }
            }
        }
    }
    return $found
}
$known = @($candidates | ForEach-Object { $_.file })
$newOnes = @(Get-CrawledCandidates | Where-Object { $known -notcontains $_.file } | Select-Object -First 2)
if ($newOnes.Count -gt 0) {
    Write-Host "crawler found $($newOnes.Count) new candidate(s): $($newOnes.key -join ', ')" -ForegroundColor Cyan
    $candidates = @($candidates) + $newOnes
}
if ($Only) { $candidates = @($candidates | Where-Object { $_.key -match $Only }) }

# ---- Bench tasks: REAL repo code, deterministic scoring ----
# Each: a real file, an instruction, and a check that the produced patch
# applies (SEARCH verbatim) and the project still builds.
$tasks = @(
    @{ file = "src/RimWorldLab.Core/WorldModel.cs"; lines = 240
       ask = "Add a public read-only property `TotalBodies` to the SolarSystem class returning Bodies.Count." }
    @{ file = "src/RimWorldLab.Core/Jobs.cs"; lines = 200
       ask = "In TaskBoard, add a public method `PendingOfKind(TaskKind kind)` returning the count of pending orders of that kind." }
    @{ file = "src/RimWorldLab.Core/Needs.cs"; lines = 160
       ask = "Add a public static method `Clamp01(float v)` to the first public static class you see (or create class NeedsMath) returning Math.Clamp(v, 0f, 1f)." }
    @{ file = "src/RimWorldLab.Core/SaveLoad.cs"; lines = 160
       ask = "Add a public static method `SlotExists(string path)` to SaveLoad returning System.IO.File.Exists(path)." }
)

function Wait-Llm([int]$timeoutSec = 240) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $timeoutSec) {
        try { if ((Invoke-WebRequest "$llm/health" -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200) { return $true } } catch {}
        Start-Sleep 5
    }
    return $false
}

function Start-Model([string]$file) {
    wsl -d Ubuntu -u root -- bash -c "pkill -f llama-server; sleep 2; nohup /root/llama.cpp/build/bin/llama-server -m /root/models/$file -ngl 99 -c 16384 --host 0.0.0.0 --port 1234 > /var/log/llama-server.log 2>&1 &" | Out-Null
    return (Wait-Llm)
}

function Get-HfFile([string]$repo, [string]$file) {
    # Resolve the exact file name via the HF API (quant names drift), then
    # download into WSL /root/models with wget (resumable).
    $tree = Invoke-RestMethod "https://huggingface.co/api/models/$repo/tree/main" -TimeoutSec 60
    $entry = $tree | Where-Object { $_.path -ieq $file } | Select-Object -First 1
    if (-not $entry) {
        $pat = ($file -replace '.*(Q\d_K_[MS]).*', '$1')
        $entry = $tree | Where-Object { $_.path -match "$pat.*\.gguf$" -and $_.path -notmatch "0000\d-of" } | Select-Object -First 1
    }
    if (-not $entry) { return $null }
    $name = [System.IO.Path]::GetFileName($entry.path)
    Write-Host "downloading $repo / $($entry.path) ..."
    wsl -d Ubuntu -u root -- bash -c "cd /root/models && wget -q -c 'https://huggingface.co/$repo/resolve/main/$($entry.path)' -O '$name'"
    $ok = wsl -d Ubuntu -u root -- bash -c "test -s /root/models/$name && [ `$(stat -c%s /root/models/$name) -gt 3000000000 ] && [ `$(head -c4 /root/models/$name) = 'GGUF' ] && echo OK || rm -f /root/models/$name"
    if ($ok -match "OK") { return $name }
    Write-Host "  download invalid (not a multi-GB GGUF) - removed"
    return $null
}

function Invoke-Bench([string]$key, [double]$temp = 0.2) {
    $score = 0; $details = @(); $t0 = Get-Date
    foreach ($t in $tasks) {
        $src = (Get-Content "g:\Rimwork\$($t.file)" -TotalCount $t.lines) -join "`n"
        $sys = "You write minimal SEARCH/REPLACE patches. Format STRICTLY:`nFILE: <path>`n<<<<<<< SEARCH`n(exact verbatim lines from the file)`n=======`n(replacement)`n>>>>>>> REPLACE`nNEVER write '...' or '(lines omitted)' inside SEARCH. SEARCH must be copied character-for-character from the provided file."
        $body = @{ model = "arena"; max_tokens = 700; temperature = $temp; messages = @(
            @{ role = "system"; content = $sys },
            @{ role = "user"; content = "FILE $($t.file) (first $($t.lines) lines):`n$src`n`nTASK: $($t.ask)`nProduce ONE patch." }
        ) } | ConvertTo-Json -Depth 6
        $ok = $false
        try {
            $r = Invoke-RestMethod "$llm/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 300
            $out = $r.choices[0].message.content
            if ($out -match '(?s)<<<<<<< SEARCH\r?\n(.*?)\r?\n=======\r?\n(.*?)\r?\n>>>>>>> REPLACE') {
                $search = $Matches[1]; $replace = $Matches[2]
                $full = Get-Content "g:\Rimwork\$($t.file)" -Raw
                $norm = ($full -replace "`r`n", "`n"); $snorm = ($search -replace "`r`n", "`n")
                if ($norm.Contains($snorm) -and $snorm.Trim().Length -gt 10 -and $search -notmatch '\.\.\.|omitted') {
                    # Apply in a throwaway copy and build
                    $bak = "$env:TEMP\arena_bak.cs"
                    Copy-Item "g:\Rimwork\$($t.file)" $bak -Force
                    [System.IO.File]::WriteAllText("g:\Rimwork\$($t.file)", $norm.Replace($snorm, ($replace -replace "`r`n", "`n")))
                    Push-Location g:\Rimwork\src\RimWorldLab.Core
                    $b = dotnet build -c Release 2>&1 | Out-String
                    Pop-Location
                    Copy-Item $bak "g:\Rimwork\$($t.file)" -Force
                    if ($b -match "0 Erreur|0 Error") { $ok = $true }
                }
            }
        } catch {}
        if ($ok) { $score += 10 }
        $details += "$(if ($ok) {'PASS'} else {'FAIL'}) $($t.ask.Substring(0, [Math]::Min(60, $t.ask.Length)))"
        Write-Host "  [$key] $($details[-1])"
    }
    $mins = [math]::Round(((Get-Date) - $t0).TotalMinutes, 1)
    # Speed tiebreaker: max 5 points, only matters between equal scores
    $speedPts = [Math]::Max(0, 5 - [int]$mins)
    return @{ key = $key; score = $score; speedPts = $speedPts; total = $score + $speedPts; minutes = $mins; details = $details }
}

# ---- Run the arena ----
$results = @()
foreach ($c in $candidates) {
    $file = $c.file
    $have = wsl -d Ubuntu -u root -- bash -c "test -s /root/models/$file && echo OK"
    if ($have -notmatch "OK") {
        if (-not $c.repo) { Write-Host "skip $($c.key): no local file, no repo"; continue }
        $file = Get-HfFile $c.repo $c.file
        if (-not $file) { Write-Host "skip $($c.key): download failed"; continue }
    }
    Write-Host "=== ARENA: $($c.key) ($file) ===" -ForegroundColor Cyan
    if (-not (Start-Model $file)) { Write-Host "  model failed to come up"; continue }
    # Tune: same bench at two temperatures, keep the better setting.
    $best = $null
    foreach ($tp in 0.2, 0.6) {
        $res = Invoke-Bench $c.key $tp
        $res.temp = $tp
        if (-not $best -or $res.total -gt $best.total) { $best = $res }
        if ($res.score -eq (10 * $tasks.Count)) { break } # perfect, stop tuning
    }
    $best.file = $file
    $results += [pscustomobject]$best
}

# ---- Crown the champion, purge the losers ----
$ranked = $results | Sort-Object -Property total -Descending
$ranked | ConvertTo-Json -Depth 5 | Set-Content $arenaLog -Encoding utf8
if ($ranked.Count -gt 0) {
    $champ = $ranked[0]
    Set-Content $championFile $champ.file -Encoding ascii
    Write-Host "CHAMPION: $($champ.key) ($($champ.score)/40 patches + $($champ.speedPts) speed) -> $championFile" -ForegroundColor Green
    $keep = @($ranked | Select-Object -First $KeepTop | ForEach-Object { $_.file })
    foreach ($r in $ranked | Select-Object -Skip $KeepTop) {
        Write-Host "deleting loser model: $($r.file)"
        wsl -d Ubuntu -u root -- bash -c "rm -f /root/models/$($r.file)"
    }
    # Relaunch the champion for the dev loop
    Start-Model $champ.file | Out-Null
}
$ranked | Format-Table key, score, speedPts, minutes
