#!/usr/bin/env powershell
# Script: llm_call.ps1
# Quick way to call local LM Studio API from PowerShell

param(
    [string]$SystemPrompt = "You are a helpful C# coding assistant.",
    [string]$UserMessage = $(throw "UserMessage required"),
    [int]$MaxTokens = 4096,
    [string]$ApiBase = "http://localhost:1234/v1",
    [string]$Model = "local-model"
)

Write-Host "Calling LM Studio..."
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
    Write-Host "Make sure:"
    Write-Host "  1. LM Studio is running"
    Write-Host "  2. A model is loaded"
    Write-Host "  3. 'Start Server' was clicked"
    Write-Host "  4. http://localhost:1234 is accessible"
    exit 1
}
