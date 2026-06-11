# Checklist — Phase 0 Execution

Use this to track your progression through Phase 0 Cartography.

---

## Week 0.1: Repository Acquisition

**Goal**: Clone all reference materials.

### Cloning Tasks

- [ ] Create `/reference/` directory
- [ ] Clone RimWorldDecompiled
  ```bash
  git clone https://github.com/Chillu1/RimWorldDecompiled.git reference/rimworld-decompiled/
  ```
  
- [ ] Clone FyWorld
  ```bash
  git clone https://github.com/firefly-dev/FyWorld.git reference/fyworld/
  ```
  
- [ ] Clone Performance-Fish (find current link)
  - Search GitHub: "rimworld performance-fish"
  - Clone to `reference/performance-fish/`
  
- [ ] Clone Multiplayer mod
  - Search GitHub: "rimworld multiplayer"
  - Clone to `reference/multiplayer/`
  
- [ ] Clone RimWorld-Together (if different)
  - Clone to `reference/rimworld-together/`
  
- [ ] Clone LibColony
  - GitHub: "LibColony" (C++/JS task scheduling)
  - Clone to `reference/libcolony/`

### Verification

- [ ] `reference/` contains 5+ subdirectories
- [ ] Each subdirectory has `.git` folder
- [ ] No errors during cloning

**Estimated time**: 30-60 minutes.

**Exit**: All repos cloned and accessible.

---

## Week 0.2: System Documentation (Read & Write)

**Goal**: Understand vanilla systems by reading decompiled code. Write one-page summaries.

### System: Job & Workgiver

**Read**:
- [ ] `RimWorldDecompiled/Core/Jobs/Job.cs`
- [ ] `RimWorldDecompiled/Core/Jobs/JobDriver.cs`
- [ ] `RimWorldDecompiled/Core/AI/JobGiver.cs` (or similar workgiver pattern)

**Write**: `/docs/systems/JOBS.md`
- What is a Job? (target, driver, state machine)
- What are Workgivers? (autonomous job discovery)
- How do pawns find jobs?
- What happens on job failure?
- Reservation conflicts?
- Unknown/deferred behaviors

**Time**: 2-3 hours per system.

---

### System: Pawn & Needs

**Read**:
- [ ] `RimWorldDecompiled/Core/Pawn/Pawn.cs`
- [ ] `RimWorldDecompiled/Core/Pawn/Pawn_Needs.cs`
- [ ] `RimWorldDecompiled/Core/Pawn/Need_Base.cs`

**Write**: `/docs/systems/PAWN.md`
- Pawn lifecycle (spawn → tick → destroy)
- Needs system (hunger, fatigue, rest, etc.)
- How needs increase/decrease
- Thresholds / critical levels
- Inventory
- Health / conditions

---

### System: Map & Pathfinding

**Read**:
- [ ] `RimWorldDecompiled/Core/Map/Map.cs`
- [ ] `RimWorldDecompiled/Core/Pathfinding/PathFinder.cs`
- [ ] `RimWorldDecompiled/Core/Pathfinding/RegionAndRoomQuery.cs`

**Write**: `/docs/systems/MAP.md`
- 2D grid structure
- Cells / passability
- Regions (optimization for pathfinding)
- A* implementation
- Cached paths

---

### System: Reservation

**Read**:
- [ ] `RimWorldDecompiled/Core/Reserving/ReservationManager.cs`
- [ ] Search for "Reserve(" in Pawn code

**Write**: `/docs/systems/RESERVATION.md`
- What is a reservation?
- Registry (who reserves what)
- Conflict prevention (no double-book)
- Cleanup / expiry
- Reference to Thing being reserved

---

### System: SaveLoad

**Read**:
- [ ] `RimWorldDecompiled/Core/SaveLoad/SaveLoad.cs`
- [ ] `RimWorldDecompiled/Core/SaveLoad/SaveLoadUtility.cs`
- [ ] Find serialization mechanisms (Scribe, XML, etc.)

**Write**: `/docs/systems/SAVE_LOAD.md`
- What gets saved?
- Format (XML, JSON, binary?)
- Reference resolution (how are Thing/Pawn IDs restored)
- Determinism (does load + replay give same history?)

---

### System: Tick Loop / Game Loop

**Read**:
- [ ] `RimWorldDecompiled/Core/Game.cs` (main loop)
- [ ] Find TickManager or similar
- [ ] Update order (physics → AI → rendering)

**Write**: `/docs/systems/TICK_LOOP.md`
- Tick rate (60 ticks/sec? Variable?)
- Update order
- Physics / collision updates
- Pathfinding cache updates
- Rendering separation (or not)
- Determinism constraints

---

### Checklist: System Docs

- [ ] `/docs/systems/JOBS.md`
- [ ] `/docs/systems/PAWN.md`
- [ ] `/docs/systems/MAP.md`
- [ ] `/docs/systems/RESERVATION.md`
- [ ] `/docs/systems/SAVE_LOAD.md`
- [ ] `/docs/systems/TICK_LOOP.md`

**Time**: 12-18 hours total (~2-3 hours per system).

**Exit**: 6+ system description files, each 1-2 pages.

---

## Week 0.3: Comparison & Analysis

**Goal**: Compare vanilla with libre architectures. Extract insights.

### FyWorld Architecture

**Read**: 
- [ ] FyWorld GitHub README
- [ ] FyWorld source structure (C#, Unity)
- [ ] Core files (tick loop, agents, needs)

**Write**: `/docs/reference/FYWORLD_ARCHITECTURE.md`
- How does FyWorld structure jobs?
- How does FyWorld structure pawns?
- How does it handle pathfinding?
- What differs from vanilla?
- Lessons applicable to Phase 1?

**Time**: 2-3 hours.

---

### Performance-Fish Insights

**Read**:
- [ ] Performance-Fish GitHub README
- [ ] Key patch files (what does it optimize?)

**Write**: `/docs/reference/PERF_FISH_INSIGHTS.md`
- What are the main bottlenecks in vanilla RimWorld?
- What does Performance-Fish patch?
- Implications for Phase 1 design?
- Should Phase 1 avoid these pitfalls from the start?

**Time**: 1-2 hours.

---

### Vanilla vs. Libre Comparison

**Write**: `/docs/analysis/VANILLA_VS_FYWORLD.md`
- Job system: vanilla approach vs. FyWorld approach
- Pawn architecture: vanilla vs. FyWorld
- Pathfinding: vanilla vs. FyWorld
- What is the minimal feature set for Phase 1?
- Which systems can be simplified?

**Time**: 2-3 hours.

---

### Checklist: Analysis

- [ ] `/docs/reference/FYWORLD_ARCHITECTURE.md`
- [ ] `/docs/reference/PERF_FISH_INSIGHTS.md`
- [ ] `/docs/analysis/VANILLA_VS_FYWORLD.md`

**Time**: 5-8 hours total.

**Exit**: 3+ analysis/reference files guiding Phase 1 scope.

---

## Week 0.4: Planning & Finalizing Phase 1

**Goal**: Crystallize Phase 1 design before coding.

### Phase 1 Architecture

**Write**: `/docs/PHASE_1_ARCHITECTURE.md`

Include:
- C# project structure (folders)
- Class diagram (Game, Map, Pawn, Job, etc.)
- Tick loop flow
- Update order
- Pathfinding integration
- Save/load flow
- No graphics, no rendering (headless only)

**Time**: 2-3 hours.

---

### Phase 1 MVP Checklist

**Write**: `/docs/PHASE_1_MVP.md`

Specify exactly:
- [ ] 50×50 2D grid (cells, collision)
- [ ] 10 pawns spawn
- [ ] Hunger need (0.0-1.0, +~1/100 ticks)
- [ ] Fatigue need (0.0-1.0, +~1/150 ticks)
- [ ] Food item (in stockpile or on ground)
- [ ] Bed (on map)
- [ ] Eat job (pawn finds food, moves, eats, reduces hunger)
- [ ] Sleep job (pawn finds bed, moves, sleeps, reduces fatigue)
- [ ] Pathfinding works (A*, collision-aware)
- [ ] Reservation system (no double-book food or beds)
- [ ] Main loop: 10 pawns tick autonomously
- [ ] Save/load: state serializes to JSON, loads back, deterministic
- [ ] Tests: SurvivalTest (7 days), ReservationTest, SaveLoadTest, DeterminismTest
- [ ] Benchmark: 600k ticks < 10 sec

**Time**: 1-2 hours.

---

### Test Plan

**Write**: `/docs/TEST_PLAN.md`

List tests:
- FoundationTests (tick loop, map, registry)
- PawnTests (need increase, inventory)
- PathfindingTests (path finding, no infinite loops)
- ReservationTests (no duplicates)
- JobTests (job priority)
- SurvivalTest (7 days, all alive)
- SaveLoadTests (bit-for-bit recovery)
- DeterminismTests (same seed = same history)

**Time**: 1 hour.

---

### Project Structure

**Write**: `/docs/PROJECT_STRUCTURE.md`

Show folder layout:
```
src/
  Core/
    Game.cs
    Map.cs
    Thing.cs
    TickSystem.cs
  Pawn/
    Pawn.cs
    Need.cs
    Job.cs
    Pathfinding.cs
  World/
    Food.cs
    Bed.cs
    Stockpile.cs
    Reservation.cs
  SaveLoad/
    SaveGame.cs
    LoadGame.cs

tests/
  FoundationTests.cs
  PawnTests.cs
  ...
```

**Time**: 30 min.

---

### LLM Briefing Prep

**Read**: [LLM_SYSTEM_PROMPT.md](LLM_SYSTEM_PROMPT.md)

- [ ] Confirm Phase 1 scope aligns with prompt.
- [ ] Prepare context packet for LLM:
  - [ ] Link to LLM_SYSTEM_PROMPT.md
  - [ ] Reference PHASE_1_ARCHITECTURE.md
  - [ ] Reference PHASE_1_MVP.md
  - [ ] Reference TEST_PLAN.md
  - [ ] Reference system docs from `/docs/systems/`

---

### Checklist: Phase 1 Planning

- [ ] `/docs/PHASE_1_ARCHITECTURE.md`
- [ ] `/docs/PHASE_1_MVP.md`
- [ ] `/docs/TEST_PLAN.md`
- [ ] `/docs/PROJECT_STRUCTURE.md`
- [ ] LLM briefing packet ready

**Time**: 4-6 hours total.

**Exit**: Phase 1 fully specified. Ready to hand to LLM/developer.

---

## Phase 0 Summary

| Week | Tasks | Time | Exit Criteria |
|------|-------|------|--------------|
| 0.1 | Clone 5+ repos | 1 hr | All repos in `/reference/` |
| 0.2 | Write 6 system docs | 12-18 hrs | 6 docs in `/docs/systems/` |
| 0.3 | Write 3 analysis docs | 5-8 hrs | Insights extracted |
| 0.4 | Plan Phase 1 spec | 4-6 hrs | Fully specified, LLM-ready |
| **Total** | | **22-33 hrs** | **Ready for Phase 1** |

**Estimated Phase 0 duration**: 1-2 weeks of focused work.

---

## Notes

- If you get stuck on a system doc, mark it as "TODO: investigate further" and move on.
- FyWorld or other open-source games may have README/wiki docs that speed up reading.
- Performance-Fish GitHub repo will have a CHANGELOG or issues describing what it patches.
- Once Phase 0 is done, you're ready to brief the LLM and start Phase 1 coding.

**Good luck! Check off as you go.** 🎯
