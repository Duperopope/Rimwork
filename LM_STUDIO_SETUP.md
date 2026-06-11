# LM Studio Integration — Local LLM Setup

## Why Local LLM?

- **Fast iteration**: No API rate limits.
- **Private**: Code stays on your machine.
- **Cheap**: No API costs.
- **Offline-capable**: Works without internet.

---

## Prerequisites

- **LM Studio installed** (https://lmstudio.ai/)
- **A quantized model loaded** (e.g., `mistral-7b`, `neural-chat-7b`, or `codellama`)
- **OpenAI-compatible API running** (LM Studio provides this by default)

---

## Step 1: Start LM Studio

1. Open LM Studio.
2. Go to **Chat** tab.
3. Load a model (if not already loaded):
   - Recommended: `mistral-7b` or `neural-chat-7b` (good for coding, small)
   - Or: `codellama-34b` (more powerful, larger)
4. Set context window to **4096** or higher.
5. Click **Start Server** (local server on `http://localhost:1234`).

**Check**: Server should be running on `http://localhost:1234/v1/chat/completions`.

---

## Step 2: Verify API Endpoint

Open PowerShell:

```powershell
$response = Invoke-RestMethod `
  -Uri "http://localhost:1234/v1/models" `
  -Method Get

$response | ConvertTo-Json
```

**Expected output**:
```json
{
  "object": "list",
  "data": [
    {
      "id": "local-model",
      "object": "model",
      "owned_by": "lm-studio",
      "permission": []
    }
  ]
}
```

If this works, your local LLM is ready.

---

## Step 3: Configure for Claude Code / Copilot

### Option A: Use with curl/PowerShell Scripts (Simplest)

Create `/scripts/llm_call.ps1`:

```powershell
param(
    [string]$SystemPrompt,
    [string]$UserMessage,
    [int]$MaxTokens = 4096
)

$body = @{
    "model" = "local-model"
    "messages" = @(
        @{ "role" = "system"; "content" = $SystemPrompt },
        @{ "role" = "user"; "content" = $UserMessage }
    )
    "temperature" = 0.7
    "max_tokens" = $MaxTokens
} | ConvertTo-Json

$response = Invoke-RestMethod `
  -Uri "http://localhost:1234/v1/chat/completions" `
  -Method Post `
  -Body $body `
  -ContentType "application/json"

return $response.choices[0].message.content
```

**Usage**:
```powershell
& .\scripts\llm_call.ps1 `
  -SystemPrompt (Get-Content .\LLM_SYSTEM_PROMPT.md) `
  -UserMessage "Build Phase 1 tick loop in C#"
```

---

### Option B: Use Claude Code Directly

Copilot Chat supports OpenAI-compatible endpoints via environment variables:

```powershell
# Set environment variables
$env:OPENAI_API_BASE = "http://localhost:1234/v1"
$env:OPENAI_API_KEY = "not-needed"
$env:OPENAI_API_TYPE = "openai"
```

Then use Copilot Chat normally — it will route to your local LM Studio.

**Note**: This depends on Copilot's configuration. Check `/copilot-instructions.md` or extension settings.

---

### Option C: Use OpenAI CLI (Recommended)

Install OpenAI CLI:

```powershell
pip install openai
```

Create `/scripts/openai_config.json`:

```json
{
  "api_key": "dummy-key",
  "api_base": "http://localhost:1234/v1",
  "model": "local-model"
}
```

**Usage** (from PowerShell):

```powershell
$env:OPENAI_API_KEY = "dummy"
openai --api-base http://localhost:1234/v1 api chat_completions create `
  -m local-model `
  -g system "You are a C# code engineer." `
  -g user "Write a deterministic tick loop."
```

---

## Step 4: Test the Connection

**Quick test** (PowerShell):

```powershell
$body = @{
    "model" = "local-model"
    "messages" = @(
        @{ "role" = "system"; "content" = "You are a helpful assistant." },
        @{ "role" = "user"; "content" = "Write a hello world function in C#." }
    )
    "max_tokens" = 500
} | ConvertTo-Json

$response = Invoke-RestMethod `
  -Uri "http://localhost:1234/v1/chat/completions" `
  -Method Post `
  -Body $body `
  -ContentType "application/json"

Write-Host $response.choices[0].message.content
```

**Expected**: LLM returns a simple C# hello world function.

---

## Step 5: Integration with Project

### Add to Project Root

Create `/lm_studio_config.md`:

```markdown
# LM Studio Local Configuration

## API Endpoint
- **URL**: http://localhost:1234/v1
- **Model**: local-model
- **Max Tokens**: 4096
- **Temperature**: 0.7

## How to Start
1. Open LM Studio
2. Load model (e.g., mistral-7b)
3. Click "Start Server"
4. Server will be ready on http://localhost:1234

## How to Test
Run: powershell .\scripts\test_lm_api.ps1

## Usage
- For manual queries: Use LM Studio Chat UI
- For scripted queries: Use .\scripts\llm_call.ps1
- For Copilot integration: Set env vars in terminal
```

---

## Step 6: PowerShell Helper Scripts

Create `/scripts/test_lm_api.ps1`:

```powershell
Write-Host "Testing LM Studio API..."

try {
    $models = Invoke-RestMethod -Uri "http://localhost:1234/v1/models" -Method Get
    Write-Host "✓ Connected to LM Studio"
    Write-Host "  Available models: $($models.data[0].id)"
} catch {
    Write-Host "✗ Failed to connect to LM Studio"
    Write-Host "  Make sure LM Studio is running on http://localhost:1234"
    exit 1
}

# Test chat
$body = @{
    "model" = "local-model"
    "messages" = @(
        @{ "role" = "system"; "content" = "You are a helpful assistant." },
        @{ "role" = "user"; "content" = "Say 'Hello from LM Studio!' in one line." }
    )
    "max_tokens" = 100
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod `
      -Uri "http://localhost:1234/v1/chat/completions" `
      -Method Post `
      -Body $body `
      -ContentType "application/json"
    
    Write-Host "✓ Chat works"
    Write-Host "  Response: $($response.choices[0].message.content)"
} catch {
    Write-Host "✗ Chat failed: $_"
    exit 1
}

Write-Host ""
Write-Host "LM Studio is ready!"
```

Run it:

```powershell
& .\scripts\test_lm_api.ps1
```

---

## Step 7: Recommended Model Sizes

| Model | Size | Speed | Quality | Coding |
|-------|------|-------|---------|--------|
| mistral-7b | 3.5 GB | Fast | Good | Good |
| neural-chat-7b | 3.5 GB | Fast | Good | Very Good |
| codellama-7b | 3.8 GB | Fast | Good | **Excellent** |
| dolphin-2.2:7b | 3.8 GB | Fast | Good | Very Good |
| mistral-medium | 8 GB | Medium | Better | Better |
| codellama-34b | 20 GB | Slow | Great | **Best** |

**For RimWorld lab**: I recommend **codellama-7b** (good for C# coding, fast enough).

---

## Step 8: Next — Use in Phase 0.1a

Once LM Studio is running and tested, brief it using `LLM_SYSTEM_PROMPT.md`:

```powershell
$systemPrompt = Get-Content .\LLM_SYSTEM_PROMPT.md -Raw
$userMessage = "Read PHASE_1_MVP.md. Plan the C# project structure for a deterministic tick loop. Show the class diagram."

& .\scripts\llm_call.ps1 `
  -SystemPrompt $systemPrompt `
  -UserMessage $userMessage `
  -MaxTokens 2000
```

---

## Troubleshooting

### "Connection refused"
- LM Studio not running. Open it and click "Start Server".

### "Model not found"
- No model loaded. Open LM Studio, download a model, then start server.

### "Slow responses"
- Model too large for your system. Try a smaller model (e.g., 7B instead of 34B).
- Or use less context window (4096 instead of 8192).

### "API works but responses are bad"
- Temperature too high/low. Try 0.7.
- Model not suitable for coding. Switch to codellama or neural-chat.

---

## Summary

✅ LM Studio running on `localhost:1234`  
✅ API tested with PowerShell  
✅ Helper scripts created  
✅ Ready to use with Phase 0.1a  

**Next**: Go to `PHASE_0.1a_QUICK_COMPILE.md`.
