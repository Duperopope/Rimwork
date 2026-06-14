#!/usr/bin/env powershell
# Script: llm_call.ps1
# Quick way to call the LOCAL LLM API (llama-server WSL, port 1234) from PowerShell.
# NB: PAS LM Studio - voir docs/DOWN_HERE_DESIGN.md.

param(
    [string]$SystemPrompt = "You are a helpful C# coding assistant.",
    [string]$UserMessage = $(throw "UserMessage required"),
    [int]$MaxTokens = 4096,
    [string]$ApiBase = "",
    [string]$Model = "local-model"
)

# Source de verite unique (URL) - voir scripts/lib/Config.ps1.
. "$PSScriptRoot\lib\Config.ps1"
$cfg = Get-DownHereConfig
if (-not $ApiBase) { $ApiBase = "$($cfg.Llm.BaseUrl)/v1" }

Write-Host "Calling local LLM..."
Write-Host "  Endpoint: $ApiBase"
Write-Host "  Model: $Model"
Write-Host ""

try {
    # Build request
    $body = @{
        "model" = $Model
        "messages" = @(
            @{ "role" = "system"; "content" = $SystemPrompt },
            @{ "role" = "user"; "content" = $UserMessage }
        )
        "temperature" = 0.7
        "max_tokens" = $MaxTokens
        "top_p" = 0.95
    } | ConvertTo-Json -Depth 10

    # Call API
    $response = Invoke-RestMethod `
        -Uri "$ApiBase/chat/completions" `
        -Method Post `
        -Body $body `
        -ContentType "application/json" `
        -TimeoutSec 300

    # Extract and print response
    $content = $response.choices[0].message.content

    Write-Host "Response:"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host $content
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host ""

    # Stats
    $usage = $response.usage
    Write-Host "Tokens used:"
    Write-Host "  Input: $($usage.prompt_tokens)"
    Write-Host "  Output: $($usage.completion_tokens)"
    Write-Host "  Total: $($usage.total_tokens)"

    return $content
}
catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Make sure the local LLM server is up:"
    Write-Host "  1. llama-server (WSL ROCm) is running"
    Write-Host "  2. A model is loaded (scripts/llm_champion.txt)"
    Write-Host "  3. $($cfg.Llm.BaseUrl) is accessible"
    Write-Host "  -> sinon: powershell -File scripts/startup_all.ps1"
    exit 1
}
