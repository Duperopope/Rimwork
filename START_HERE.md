# START HERE — Velocity Mode

**Skip the theory. Get code running today.**

---

## 3-Step Startup

### 1. Start LM Studio (5 minutes)

```powershell
# Open LM Studio
# -> Load a model (e.g., "mistral-7b" or "codellama-7b")
# -> Click "Start Server"
# -> Wait for "Ready to accept connections"

# Verify it works:
& .\scripts\test_lm_api.ps1
```

**Expected**: ✓ LM Studio is ready!

---

### 2. Clone & Compile (10 minutes)

```powershell
# Clone decompiled RimWorld
cd reference/
git clone https://github.com/Chillu1/RimWorldDecompiled.git rimworld-decompiled

# Or if already cloned:
cd g:\Rimwork\

# Create a test project
mkdir -p src/RimWorldLab
cd src/RimWorldLab

# Create C# console project
dotnet new console -f net472

# Try to build
dotnet build

# If errors, add RimWorld DLLs:
#   copy "C:\Program Files\Steam\steamapps\common\RimWorld\RimWorldLinux_Data\Managed\*.dll" `
#        "g:\Rimwork\reference\rimworld-decompiled\lib\"
```

---

### 3. Test Tick Loop (5 minutes)

Create `Program.cs` in `src/RimWorldLab/`:

```csharp
using System;
using System.Diagnostics;

class Program
{
    static void Main()
    {
        Console.WriteLine("Tick Loop Test");
        var sw = Stopwatch.StartNew();
        int ticks = 0;
        
        while (sw.ElapsedMilliseconds < 1000)
        {
            ticks++;
            // Simulate ~60 ticks/sec
            System.Threading.Thread.Sleep(16);
        }
        
        sw.Stop();
        Console.WriteLine($"Ticks: {ticks}, Time: {sw.ElapsedMilliseconds}ms, Rate: {(double)ticks / (sw.ElapsedMilliseconds/1000.0):F1} ticks/sec");
    }
}
```

```powershell
dotnet run
```

**Expected output**:
```
Tick Loop Test
Ticks: 60, Time: 1001ms, Rate: ~60 ticks/sec
```

✅ Loop works.

---

## Now You Have

✅ LM Studio running locally  
✅ Bare C# tick loop compiling and running  
✅ Helper scripts (`llm_call.ps1`, `test_lm_api.ps1`)

---

## Next: Iterate with LLM

Ask LM Studio to expand:

```powershell
$prompt = @"
I have a working C# deterministic tick loop (60 ticks/sec, deterministic, no dependencies).

Now I need to add:
1. A 50x50 2D map with cell collision
2. A Thing registry (unique IDs)
3. A Pawn class with position

Show me the C# class structure (minimal, headless, no graphics).
Include tests.
"@

& .\scripts\llm_call.ps1 `
  -UserMessage $prompt `
  -MaxTokens 2000
```

Copy the output, add to your project, compile, run.

**Repeat**: Ask LLM → Copy code → Compile → Test → Ask LLM again.

---

## Reading (If Needed)

- [LM_STUDIO_SETUP.md](LM_STUDIO_SETUP.md) — Detailed LM Studio configuration
- [PHASE_0.1a_QUICK_COMPILE.md](PHASE_0.1a_QUICK_COMPILE.md) — Detailed compile steps
- [LLM_SYSTEM_PROMPT.md](LLM_SYSTEM_PROMPT.md) — Full system prompt for LLM (copy into -SystemPrompt)

---

## Key Principle

**Code → Test → LLM → Repeat**

No 2-week research phase. Start coding now.

---

**Ready?**

```powershell
cd g:\Rimwork
& .\scripts\test_lm_api.ps1
```

Go go go. 🚀
