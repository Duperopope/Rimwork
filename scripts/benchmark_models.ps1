<#
Benchmarks local LM Studio models for the autonomous dev loop.
For each model: loads it, sends a real coding prompt (same format as dev_loop.ps1),
measures tokens/sec and whether the output is a valid, parseable FILE block.
#>

$models = @(
    "google/gemma-4-12b-qat",
    "qwen3.6-35b-a3b-uncensored-hauhaucs-aggressive",
    "gemma-4-e4b-it-obliterated-i1",
    "qwen3-4b",
    "google/gemma-4-e2b"
)

$systemPrompt = Get-Content "g:\Rimwork\LM_STUDIO_SYSTEM_PROMPT.md" -Raw

$prompt = @"
BUILD: OK
TEST SUMMARY: 3 tests ran: 3 passed, 0 failed

Propose ONE small next change to src/RimWorldLab.Core: add a public method
`GetPawnByName(string name)` to GameWorldManager that returns the matching
Pawn or null. Show the FULL updated GameWorld.cs file content is NOT needed -
instead create a new file Extensions.cs containing only this method as an
extension method on GameWorldManager.
"@

$results = @()

foreach ($model in $models) {
    Write-Host "`n=== Testing $model ===" -ForegroundColor Cyan

    lms unload --all 2>&1 | Out-Null
    $loadStart = Get-Date
    lms load $model --gpu max -y 2>&1 | Out-Null
    $loadTime = (Get-Date) - $loadStart
    Write-Host "Load time: $($loadTime.TotalSeconds.ToString('F1'))s"

    $body = @{
        model    = $model
        messages = @(
            @{ role = "system"; content = $systemPrompt },
            @{ role = "user"; content = $prompt }
        )
        max_tokens = 800
        temperature = 0.3
    } | ConvertTo-Json -Depth 6

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-RestMethod -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method Post -ContentType "application/json" -Body $body -TimeoutSec 240
        $sw.Stop()
        $content = $response.choices[0].message.content
        $tokens = $response.usage.completion_tokens
        $tps = if ($sw.Elapsed.TotalSeconds -gt 0) { $tokens / $sw.Elapsed.TotalSeconds } else { 0 }

        $hasFileBlock = $content -match '(?ms)FILE:\s*\S+\s*```(?:csharp|cs)?\s*.*?```'
        $hasChange = $content -match '(?m)^CHANGE:'
        $hasNext = $content -match '(?m)^NEXT:'
        $formatOk = $hasFileBlock -and $hasChange -and $hasNext

        $results += [pscustomobject]@{
            Model      = $model
            LoadSec    = [math]::Round($loadTime.TotalSeconds,1)
            GenSec     = [math]::Round($sw.Elapsed.TotalSeconds,1)
            Tokens     = $tokens
            TokPerSec  = [math]::Round($tps,1)
            FormatOk   = $formatOk
        }

        $logFile = "g:\Rimwork\scripts\logs\bench_$($model -replace '[/\\]','_').txt"
        $content | Out-File $logFile -Encoding utf8
        Write-Host "Tokens: $tokens | $($tps.ToString('F1')) tok/s | Format OK: $formatOk"
    } catch {
        $sw.Stop()
        Write-Host "FAILED: $_" -ForegroundColor Red
        $results += [pscustomobject]@{
            Model = $model; LoadSec = [math]::Round($loadTime.TotalSeconds,1)
            GenSec = "ERR"; Tokens = 0; TokPerSec = 0; FormatOk = $false
        }
    }
}

Write-Host "`n=== RESULTS ===" -ForegroundColor Green
$results | Format-Table -AutoSize
$results | ConvertTo-Json | Out-File "g:\Rimwork\scripts\logs\benchmark_results.json" -Encoding utf8
