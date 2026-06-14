#!/usr/bin/env powershell
# Script: test_lm_api.ps1
# Verify the LOCAL LLM server (llama-server WSL, port 1234) is running and the
# API works. NB: PAS LM Studio - voir docs/DOWN_HERE_DESIGN.md.

# Source de verite unique (URL) - voir scripts/lib/Config.ps1.
. "$PSScriptRoot\lib\Config.ps1"
$cfg = Get-DownHereConfig
$ApiBase = "$($cfg.Llm.BaseUrl)/v1"

Write-Host "Testing local LLM connection..." -ForegroundColor Cyan
Write-Host ""

# Test 1: Check if API is reachable
Write-Host "[1/3] Testing API endpoint..."
try {
    $models = Invoke-RestMethod -Uri "$ApiBase/models" -Method Get -TimeoutSec 5
    Write-Host "  ✓ Connected to $ApiBase" -ForegroundColor Green
    Write-Host "  ✓ Models available: $($models.data[0].id)" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Failed to connect" -ForegroundColor Red
    Write-Host "    Make sure llama-server (WSL) is running: $($cfg.Llm.BaseUrl)" -ForegroundColor Yellow
    Write-Host "    -> powershell -File scripts/startup_all.ps1" -ForegroundColor Yellow
    exit 1
}

Write-Host ""

# Test 2: Test chat endpoint
Write-Host "[2/3] Testing chat endpoint..."
try {
    $body = @{
        "model" = "local-model"
        "messages" = @(
            @{ "role" = "system"; "content" = "You are a helpful assistant." },
            @{ "role" = "user"; "content" = "Say 'the local LLM is working!' in 5 words or less." }
        )
        "max_tokens" = 50
        "temperature" = 0.7
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
        -Uri "$ApiBase/chat/completions" `
        -Method Post `
        -Body $body `
        -ContentType "application/json" `
        -TimeoutSec 30

    $reply = $response.choices[0].message.content
    Write-Host "  ✓ Chat works" -ForegroundColor Green
    Write-Host "    Response: '$reply'" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Chat failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Test 3: Quick performance test
Write-Host "[3/3] Performance check..."
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $body = @{
        "model" = "local-model"
        "messages" = @(
            @{ "role" = "user"; "content" = "Write a simple C# function." }
        )
        "max_tokens" = 200
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
        -Uri "$ApiBase/chat/completions" `
        -Method Post `
        -Body $body `
        -ContentType "application/json" `
        -TimeoutSec 60

    $sw.Stop()
    $tokens = $response.usage.completion_tokens
    $timeMs = $sw.ElapsedMilliseconds
    $tokensPerSec = [math]::Round($tokens / ($timeMs / 1000.0), 1)

    Write-Host "  ✓ Generated $tokens tokens in ${timeMs}ms" -ForegroundColor Green
    Write-Host "    Speed: $tokensPerSec tokens/sec" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Performance test failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "✓ Local LLM is ready!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host ""
Write-Host "Next: Use 'llm_call.ps1' to query the model"
Write-Host "Example:"
Write-Host "  & .\scripts\llm_call.ps1 -UserMessage 'Write a hello world in C#'"
