# RimWorld Lab — Private Reconstruction & Modern Engine R&D

## Summary

This is a **private research laboratory** to understand colony simulation architecture, progressively reconstruct a minimal working version, and then build a modern, multi-scale simulation engine.

**Not a commercial clone.** Not a RimWorld redistribution.

**Inspired by**: [Underscore's GTA San Andreas Reverse Engineering Pipeline](https://www.youtube.com/watch?v=XbKYW4Pg7QA&t=972s) — using Claude Code agents for controlled reconstruction and validation.

---

## Key Documents

- **[PROJECT_CHARTER.md](PROJECT_CHARTER.md)** — Vision, intention, legal framing, rules.
- **[RESOURCES.md](RESOURCES.md)** — Available reference materials (decompiled code, mods, open-source games).
- **[LLM_SYSTEM_PROMPT.md](LLM_SYSTEM_PROMPT.md)** — Use this to brief Claude Code or agent dev.
- **[EXECUTION_PLAN.md](EXECUTION_PLAN.md)** — Phase 0 & 1 detailed roadmap.

---

## Quick Start — Velocity Mode

**Skip research. Code today.**

### 1. Phase 0.1a: Get Code Running (Today)

```powershell
cd g:\Rimwork

# Step 1: Start LM Studio (GUI)
# -> Load model (e.g., "mistral-7b")
# -> Click "Start Server"

# Step 2: Verify LM Studio
& .\scripts\test_lm_api.ps1

# Step 3: Create project + tick loop
& .\scripts\setup_project.ps1
```

**Result**: Tick loop runs at 60 ticks/sec. Done in ~20 minutes.

See [START_HERE.md](START_HERE.md) for details.

### 2. Phase 1: Iterate with LLM (Days 2-10)

Ask LM Studio to expand:

```powershell
$prompt = @"
I have a deterministic C# tick loop at 60 ticks/sec.
Add a 50x50 2D map with cell passability and collision.
Show Map.cs with tests.
"@

& .\scripts\llm_call.ps1 -UserMessage $prompt -MaxTokens 2000
```

Copy the code. Paste into project. Compile. Test. Repeat.

See [VELOCITY_MODE.md](VELOCITY_MODE.md) for sample prompts.

---

## Directory Structure

```
RimWork/
├── START_HERE.md                     ← Read this first (velocity mode)
├── VELOCITY_MODE.md                 ← New fast iteration plan
├── LM_STUDIO_SETUP.md               ← Configure local LLM
├── LLM_SYSTEM_PROMPT.md             ← Full system prompt
├── 00_QUICK_START.md
├── PROJECT_CHARTER.md
├── RESOURCES.md
├── EXECUTION_PLAN.md
│
├── scripts/                          ← PowerShell helpers
│   ├── setup_project.ps1            ← One-click setup
│   ├── test_lm_api.ps1              ← Verify LM Studio
│   └── llm_call.ps1                 ← Query LLM
│
├── docs/                            ← Documentation (as you work)
│   ├── systems/
│   ├── analysis/
│   └── reference/
│
├── reference/                       ← Cloned repos (to populate)
│   ├── rimworld-decompiled/
│   └── ...
│
├── src/                             ← Your C# code
│   └── RimWorldLab/
│       ├── Program.cs
│       └── ...
│
├── tests/                           ← Unit tests
│   └── ...
│
└── Transcriptionvideounderscore.txt ← Underscore video transcript
```

---

## Legal & Ethical

- **This is private research and learning use only.**
- **No RimWorld assets, DLLs, or copyrighted code in outputs.**
- **All code written originally, not copied.**
- **No redistribution of Ludeon's intellectual property.**
- **See [PROJECT_CHARTER.md](PROJECT_CHARTER.md) for full framing.**

---

## How to Use Local LLM (LM Studio)

1. **Start LM Studio** (GUI app, https://lmstudio.ai/)
2. **Load a model** (e.g., "mistral-7b" or "codellama-7b")
3. **Click "Start Server"**
4. **Use `llm_call.ps1`** to query:
   ```powershell
   & .\scripts\llm_call.ps1 -UserMessage "Write a C# class for..."
   ```

See [LM_STUDIO_SETUP.md](LM_STUDIO_SETUP.md) for details.

---

## Success Milestones (Velocity Mode)

### Today
- ✅ Tick loop running at 60 ticks/sec
- ✅ LM Studio verified
- ✅ Project compiles

### Days 2-3
- ✅ Map + Thing classes
- ✅ Entities on grid

### Days 4-5
- ✅ Pawns with hunger/fatigue
- ✅ Basic jobs (eat, sleep)

### Days 6-7
- ✅ Reservation system
- ✅ Pathfinding

### Days 8-10
- ✅ Save/load + tests
- ✅ Deterministic replay
- ✅ Phase 1 MVP complete

---

## Next Action

**→ RIGHT NOW:**

```powershell
cd g:\Rimwork
& .\scripts\setup_project.ps1
```

**Then:**

Read [START_HERE.md](START_HERE.md) or [VELOCITY_MODE.md](VELOCITY_MODE.md).

**Go.** 🚀
