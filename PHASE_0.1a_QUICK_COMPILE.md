# Phase 0.1a — Quick Compile & Test Loop

## Goal

Skip passive research. **Compile the decompiled RimWorld, verify it runs, then iterate fast with local LLM.**

This is a **velocity phase**: get code running, see what breaks, fix iteratively.

---

## Prerequisites

- Visual Studio 2022 (Community is free)
- .NET Framework 4.7.2+ or .NET 6+
- LM Studio running (see `LM_STUDIO_SETUP.md`)
- `reference/rimworld-decompiled/` cloned

---

## Step 1: Clone & Explore Decompiled Code

```powershell
cd reference/rimworld-decompiled/

# List what's there
ls

# Check if there's a .csproj or .sln
ls *.csproj
ls *.sln
```

**Expected**: One or more `.csproj` files, possibly a `.sln`.

If not, you may need to create a minimal wrapper project.

---

## Step 2: Create a Minimal C# Project to Test Decompiled Code

If `rimworld-decompiled/` doesn't have a `.sln`, create one:

```powershell
# In g:\Rimwork\src\
cd src/

# Create new C# console project
dotnet new console -n RimWorldLab -f net472

cd RimWorldLab

# Edit .csproj to reference decompiled code
# (see below)
```

Edit `RimWorldLab.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net472</TargetFramework>
    <LangVersion>latest</LangVersion>
  </PropertyGroup>

  <!-- Reference decompiled RimWorld -->
  <ItemGroup>
    <Reference Include="..\..\reference\rimworld-decompiled\**\*.dll" />
  </ItemGroup>

</Project>
```

---

## Step 3: Try to Compile

```powershell
cd g:\Rimwork\src\RimWorldLab

dotnet build
```

**Likely errors**:
- Missing dependencies (UnityEngine, other DLLs)
- Incompatible .NET version

**If errors**: Add missing DLLs from RimWorld install folder:

```powershell
# Copy RimWorld DLLs
copy "C:\Program Files\Steam\steamapps\common\RimWorld\RimWorldLinux_Data\Managed\*.dll" `
     "g:\Rimwork\reference\rimworld-decompiled\lib\"
```

Then retry `dotnet build`.

---

## Step 4: Create Minimal Tick Loop Test

Create `Program.cs`:

```csharp
using System;
using System.Diagnostics;

// Minimal tick loop (no dependencies on full RimWorld yet)
class TickLoop
{
    const int TICKS_PER_SECOND = 60;
    const int TARGET_TICK_MS = 1000 / TICKS_PER_SECOND; // ~16.67 ms

    static void Main()
    {
        Console.WriteLine("RimWorld Lab - Minimal Tick Loop");
        Console.WriteLine($"Target: {TICKS_PER_SECOND} ticks/sec");
        Console.WriteLine("");

        int totalTicks = 0;
        var sw = Stopwatch.StartNew();
        var targetRuntime = 7000; // 7 seconds

        while (sw.ElapsedMilliseconds < targetRuntime)
        {
            // Tick
            OnTick(totalTicks);
            totalTicks++;

            // Sleep to maintain tick rate
            int sleepTime = TARGET_TICK_MS - (int)(sw.ElapsedMilliseconds % TARGET_TICK_MS);
            if (sleepTime > 0)
                System.Threading.Thread.Sleep(sleepTime);

            // Log every 100 ticks
            if (totalTicks % 100 == 0)
                Console.WriteLine($"Tick {totalTicks} @ {sw.ElapsedMilliseconds}ms");
        }

        sw.Stop();
        Console.WriteLine("");
        Console.WriteLine($"Completed {totalTicks} ticks in {sw.ElapsedMilliseconds}ms");
        Console.WriteLine($"Average: {(double)totalTicks / (sw.ElapsedMilliseconds / 1000.0):F1} ticks/sec");
    }

    static void OnTick(int tick)
    {
        // Placeholder for actual game logic
        // Later: call Game.Tick(), update pawns, etc.
    }
}
```

---

## Step 5: Build & Run

```powershell
dotnet build

# Run
dotnet run

# Expected output:
# RimWorld Lab - Minimal Tick Loop
# Target: 60 ticks/sec
# 
# Tick 100 @ 1666ms
# Tick 200 @ 3333ms
# Tick 300 @ 5000ms
# ...
```

If this works, your tick loop is deterministic and stable. ✅

---

## Step 6: Integrate Decompiled Game Logic (Optional Now)

Once the bare loop works, you can gradually pull in RimWorld classes:

```csharp
// Example: try to instantiate a decompiled class
try
{
    // Assuming Verse.Game exists in decompiled
    // var game = new Verse.Game();
    Console.WriteLine("Loaded Verse.Game successfully");
}
catch (Exception ex)
{
    Console.WriteLine($"Failed to load RimWorld class: {ex.Message}");
}
```

---

## Step 7: Performance Baseline

Add to Program.cs:

```csharp
Console.WriteLine("");
Console.WriteLine("Performance Baseline:");
Console.WriteLine($"  Ticks/sec: {(double)totalTicks / (sw.ElapsedMilliseconds / 1000.0):F1}");
Console.WriteLine($"  Total memory: {GC.GetTotalMemory(false) / 1024 / 1024} MB");
Console.WriteLine($"  Avg tick time: {(double)sw.ElapsedMilliseconds / totalTicks:F2} ms");
```

**Baseline target** (bare tick loop):
- 60 ticks/sec ✅
- <50 MB memory ✅
- <16.67 ms per tick ✅

---

## Step 8: Next — Brief LLM to Expand

Once the bare loop is working, ask LM Studio to help:

```powershell
$prompt = @"
I have a working C# deterministic tick loop (60 ticks/sec).

Now I need to add:
1. A 50x50 2D map with cell passability
2. A Thing registry (unique IDs for entities)
3. A Pawn class with position and needs

Show me the C# class structure and a test for a pawn moving on the map.
"@

& .\scripts\llm_call.ps1 `
  -SystemPrompt (Get-Content .\LLM_SYSTEM_PROMPT.md -Raw) `
  -UserMessage $prompt `
  -MaxTokens 2000
```

---

## Checklist: Phase 0.1a

- [ ] Clone `reference/rimworld-decompiled/`
- [ ] Create `src/RimWorldLab/` C# project
- [ ] Create minimal `Program.cs` with tick loop
- [ ] Run `dotnet build` successfully
- [ ] Run and see tick loop output
- [ ] Verify 60 ticks/sec baseline
- [ ] LM Studio running and tested (from `LM_STUDIO_SETUP.md`)
- [ ] Ready to expand with LLM guidance

---

## Troubleshooting

### "dotnet: command not found"
Install .NET SDK: https://dotnet.microsoft.com/download

### "Missing UnityEngine.dll"
Copy from RimWorld install folder to `lib/` subdirectory and retry build.

### "Tick loop runs but too slow"
Reduce `TARGET_TICK_MS` or check for blocking operations in `OnTick()`.

### "Can't load decompiled RimWorld classes"
That's OK for now. Focus on the bare tick loop first. Integrate RimWorld code gradually.

---

## Speed Strategy

✅ Phase 0.1a (now): Bare loop runs, baseline known.
✅ Phase 1.1 (next): Add Map + Thing + Pawn with LLM help.
✅ Phase 1.2+: Iterate fast — code → LLM → test → repeat.

**No more passive reading. Code runs. LLM watches. You steer.**

---

## Next Step

1. Complete Phase 0.1a checklist above.
2. Go to `LM_STUDIO_INTEGRATION.md` and verify LM Studio ready.
3. Ask LLM (via `llm_call.ps1`) to implement Phase 1.1 (Map + Thing + Pawn).
4. Compile, run, iterate.

**Speed > perfection.**
