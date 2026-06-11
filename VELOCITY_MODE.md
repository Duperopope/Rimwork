# Velocity Mode — New Execution Plan

**Old plan**: 2 weeks research → slow code.  
**New plan**: Code running today → fast iteration with local LLM.

---

## Timeline

| Timeframe | Activity | Deliverable |
|-----------|----------|-------------|
| **Today** | Clone, compile, tick loop | Bare loop running at 60 ticks/sec |
| **Day 2-3** | LM Studio + Map/Thing | Entities on grid |
| **Day 4-5** | Pawns + basic jobs | 10 pawns eating/sleeping |
| **Day 6-7** | Reservation + pathfinding | No double-books, navigation works |
| **Day 8-10** | Save/load + tests | Deterministic replay |
| **Week 2** | Polish + Phase 2 roadmap | Ready for scale-up |

---

## How This Works

1. **You code** (or LLM codes with your direction)
2. **You compile** (PowerShell: `dotnet build`)
3. **You run** (PowerShell: `dotnet run`)
4. **You see it work** (or fail visibly)
5. **You ask LLM to fix/expand** (use `llm_call.ps1`)
6. **Repeat step 1**

---

## Key Difference from Phase 0

### Old Phase 0 (Passive)
- Read decompiled code ❌
- Write system descriptions ❌
- Plan on paper ❌
- Wait 2 weeks ❌

### New Phase 0 (Active)
- Clone repo ✅
- Create tick loop ✅
- Test immediately ✅
- Ask LLM to expand ✅
- See it running ✅

---

## Tools You Have Now

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/setup_project.ps1` | One-click project creation |
| `scripts/test_lm_api.ps1` | Verify LM Studio is working |
| `scripts/llm_call.ps1` | Query LM Studio for code |

### Documentation

| Doc | Purpose |
|-----|---------|
| `START_HERE.md` | Quick 3-step startup |
| `LM_STUDIO_SETUP.md` | Detailed LM Studio config |
| `PHASE_0.1a_QUICK_COMPILE.md` | Detailed compile walkthrough |
| `LLM_SYSTEM_PROMPT.md` | Full system prompt for LLM |

---

## Quick Start (Right Now)

```powershell
# 1. Start LM Studio (GUI app)
# -> Load model (e.g., "mistral-7b")
# -> Click "Start Server"

# 2. Verify it works
cd g:\Rimwork
& .\scripts\test_lm_api.ps1

# 3. Create & test project
& .\scripts\setup_project.ps1

# 4. If successful, tick loop is running!
```

**Total time: ~15 minutes.**

---

## Then: Iterate with LLM

Ask LM Studio to help expand:

```powershell
$prompt = @"
I have a working deterministic C# tick loop.

I need to add:
1. A 50x50 2D map (cells with passability)
2. A Thing registry (unique entity IDs)
3. A simple Pawn class

Code this in C#. Include tests. Show the class structure.
"@

& .\scripts\llm_call.ps1 -UserMessage $prompt -MaxTokens 3000
```

LLM returns code. You paste it into your project. Compile. Run. Repeat.

---

## Advantages

| Old | New |
|-----|-----|
| Waiting 2 weeks | Running code today |
| Theory first | Code first |
| Slow refinement | Fast iteration |
| Single source (decompiled RimWorld) | Multiple sources + LLM guidance |
| Theoretical validation | Real runtime validation |

---

## Phase 0.1a (Velocity) Steps

1. ✅ Clone repos (if not done)
2. ✅ Create C# project
3. ✅ Run tick loop test
4. ✅ Verify 60 ticks/sec stable
5. → Ask LLM for Map class
6. → Compile + test
7. → Ask LLM for Pawn class
8. → Compile + test
9. → Ask LLM for Job system
10. → Compile + test
... (iterate until Phase 1 MVP complete)

---

## Key Metrics

Track as you go:

- **Tick rate**: Should stay ~60 ticks/sec
- **Memory**: Should stay <500 MB (for now)
- **Compile time**: Should be <10 sec
- **Test pass rate**: Should be 100%

---

## LLM Prompts (Copy & Paste)

### Prompt 1: Map Class
```
I have a deterministic tick loop in C#. 
Now add a 50x50 2D map with:
- Cell passability (walkable, blocked)
- Edge collision (can't walk off map)
Show me Map.cs with unit tests.
```

### Prompt 2: Thing Registry
```
Add an entity system:
- Thing class (base entity: position, ID)
- ThingRegistry (maps ID → Thing)
- Tests for no duplicate IDs
Show code.
```

### Prompt 3: Pawn Class
```
Add Pawn (extends Thing):
- Hunger need (0.0-1.0, increases ~1/100 ticks)
- Fatigue need (0.0-1.0, increases ~1/150 ticks)
- job queue (1 active job)
- inventory
Show code + tests.
```

### Prompt 4: Pathfinding
```
Add A* pathfinding to Pawn:
- Pawn.MoveTo(target) returns path
- Respects map collision
- Cached paths
Show Pathfinding.cs + tests.
```

### Prompt 5: Jobs
```
Add job system:
- Job class (target, type, duration)
- Workgiver interface (produces candidate jobs)
- EatWorkgiver (hunger > 0.5 → find food)
- SleepWorkgiver (fatigue > 0.5 → find bed)
Show code + tests.
```

Keep going until Phase 1 MVP is complete.

---

## Decision Point

**After tick loop is running (in ~30 min):**

Do you want to:
- **A) Keep it simple** — LLM helps incrementally, you review each step
- **B) Go faster** — Paste LLM output directly, less review
- **C) Go collaborative** — You and LLM design together

Pick your pace. No wrong answer.

---

## Success Criteria (After Phase 0.1a)

- ✅ Tick loop runs at 60 ticks/sec
- ✅ Compiles without errors
- ✅ Tests pass
- ✅ LM Studio integrated
- ✅ Ready for Phase 1.1 (Map + Thing)

---

## Next: You're in Control

The setup is done. **You decide**:

1. Read `START_HERE.md` (5 min)
2. Run `setup_project.ps1` (15 min)
3. Run `test_lm_api.ps1` (2 min)
4. Ask LLM a question (5 min)
5. Copy code into your project
6. Compile
7. Test
8. Repeat

**No waiting. No theory. Code runs today.**

---

**Ready?**

```powershell
cd g:\Rimwork
& .\scripts\setup_project.ps1
```

Go. 🚀
