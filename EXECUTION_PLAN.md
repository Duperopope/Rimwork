# Execution Plan — Phase 0 & Phase 1 Roadmap

## Phase 0: Cartographie Passive (2-3 weeks)

**Goal**: Assembler le corpus, lire, documenter sans coder.

### Week 0.1: Repository Acquisition

- [ ] Clone `Chillu1/RimWorldDecompiled` → `reference/rimworld-decompiled/`
- [ ] Clone `firefly-dev/FyWorld` → `reference/fyworld/`
- [ ] Clone Performance-Fish (find exact link) → `reference/performance-fish/`
- [ ] Clone Multiplayer mod → `reference/multiplayer/`
- [ ] Clone LibColony → `reference/libcolony/`

```bash
# Bash commands to clone
mkdir -p reference
cd reference

git clone https://github.com/Chillu1/RimWorldDecompiled.git rimworld-decompiled
git clone https://github.com/firefly-dev/FyWorld.git fyworld
# ... others
cd ..
```

### Week 0.2: Documentation — Core Systems

Read decompiled code. For each system, write a one-page **System Description**:

- [ ] **Job.cs** → `/docs/systems/jobs.md`
  - What is a job?
  - What states?
  - How does reservation work?
  - Failures?
  
- [ ] **Pawn.cs** → `/docs/systems/pawn.md`
  - Pawn lifecycle.
  - Needs, health, inventory.
  - Job queue.
  
- [ ] **Map.cs** → `/docs/systems/map.md`
  - 2D grid.
  - Collision.
  - Regions / pathfinding regions.
  
- [ ] **Need.cs** → `/docs/systems/needs.md`
  - Need types.
  - Falloff rates.
  - Satiation.
  
- [ ] **Reservation.cs** → `/docs/systems/reservation.md`
  - Registry.
  - Conflicts.
  - Cleanup.
  
- [ ] **GameLoop.cs** → `/docs/systems/tick_loop.md`
  - Frame rate.
  - Update order.
  - Physics / pathfinding update cadence.

- [ ] **SaveLoad** → `/docs/systems/save_load.md`
  - What gets saved?
  - Format?
  - Reference resolution?

### Week 0.3: Comparison — Vanilla vs. Libre

- [ ] Read FyWorld architecture → `/docs/reference/fyworld_architecture.md`
- [ ] Compare with vanilla → `/docs/analysis/vanilla_vs_fyworld.md`
- [ ] Performance-Fish bottlenecks → `/docs/reference/perf_fish_insights.md`
- [ ] Identify Phase 1 MVP → `/docs/phase_1_mvp.md`

**Phase 1 MVP checklist** (example):
- [ ] Tick loop (deterministic, 60 ticks/sec)
- [ ] 2D map (50×50 cells)
- [ ] 10 pawns
- [ ] Hunger need (increases, can eat to reduce)
- [ ] Fatigue need (increases, can sleep to reduce)
- [ ] Simple job: eat when hungry, sleep when tired
- [ ] Stockpile (holds food)
- [ ] Bed (one per pawn)
- [ ] Pathfinding (A*)
- [ ] Reservation (no double-book)
- [ ] Save/load (deterministic)

### Week 0.4: Planning

- [ ] Create Phase 1 architecture diagram → `/docs/phase_1_architecture.md`
- [ ] Draft C# project structure → `/docs/project_structure.md`
- [ ] Create test plan → `/docs/test_plan.md`
- [ ] Finalize LLM briefing → Use `LLM_SYSTEM_PROMPT.md`

**Exit criteria for Phase 0**:
- [ ] All reference repos cloned.
- [ ] 7+ system descriptions written.
- [ ] Phase 1 MVP clearly defined.
- [ ] C# project structure ready to brief LLM.
- [ ] Test strategy documented.

---

## Phase 1: Mini-Rim Headless (3-4 weeks)

**Goal**: Minimal working simulation where 10 pawns survive 7 days.

### Week 1.1: Foundation & Tick Loop

**Task**: Deterministic tick loop, Map, Thing registry.

**LLM Brief**:
> "Build a C# project with:
> - A deterministic tick loop (no time.deltaTime, pure integer ticks).
> - A 50×50 2D map with cell collision.
> - A Thing registry (every entity has a unique ID).
> - Tests that verify tick order and map state."

**Expected output**:
- `Game.cs` (tick loop)
- `Map.cs` (grid + collision)
- `Thing.cs` (base entity)
- `ThingRegistry.cs`
- `Tests/FoundationTests.cs`

**Validation**:
- [ ] Compiles, no errors.
- [ ] Tests pass (FoundationTests).
- [ ] Tick loop runs 100,000 ticks in <1 sec (benchmark).

### Week 1.2: Pawn, Needs, Inventory

**Task**: Pawn with hunger, fatigue, job queue, inventory.

**LLM Brief**:
> "Add:
> - Pawn.cs (spawns on map, has inventory, job queue, hunger/fatigue).
> - Need.cs (hunger and fatigue; increases ~1/tick, max at 1.0).
> - Inventory.cs (can hold items, has weight limit).
> - Tests: pawn hunger increases, pawn has empty job queue initially."

**Expected output**:
- `Pawn/Pawn.cs`
- `Pawn/Need.cs`
- `Pawn/Inventory.cs`
- `Tests/PawnTests.cs`

**Validation**:
- [ ] Compile.
- [ ] PawnTests pass.
- [ ] Hunger is observable and increases.

### Week 1.3: World Objects & Pathfinding

**Task**: Food, Beds, Stockpile, A* pathfinding.

**LLM Brief**:
> "Implement:
> - Food.cs (Thing, has amount/quantity).
> - Bed.cs (Thing, can be claimed by 1 pawn).
> - Stockpile.cs (grid-based container, accepts Things).
> - Pathfinding.cs (A* with collision/obstacles).
> - Tests: pathfinding finds shortest path, no infinite loops."

**Expected output**:
- `World/Food.cs`
- `World/Bed.cs`
- `World/Stockpile.cs`
- `Pawn/Pathfinding.cs`
- `Tests/PathfindingTests.cs`

**Validation**:
- [ ] Compile.
- [ ] PathfindingTests pass.
- [ ] Pawn can move from A to B avoiding obstacles.

### Week 1.4: Reservation & Jobs

**Task**: Reservation system, Job system, Workgivers.

**LLM Brief**:
> "Implement:
> - Reservation.cs (registry that prevents double-booking resources).
> - Job.cs (defines: target thing, work type, duration).
> - Workgiver (interface: produces candidate jobs for a pawn).
> - EatWorkgiver (if hungry and food available, create eat job).
> - SleepWorkgiver (if tired and bed available, create sleep job).
> - Pawn.FindJob() (picks highest-priority job).
> - Tests: no duplicate reservations, pawn picks highest-priority job."

**Expected output**:
- `World/Reservation.cs`
- `Pawn/Job.cs`
- `Workgivers/Workgiver.cs`
- `Workgivers/EatWorkgiver.cs`
- `Workgivers/SleepWorkgiver.cs`
- `Tests/ReservationTests.cs`
- `Tests/JobTests.cs`

**Validation**:
- [ ] Compile.
- [ ] ReservationTests pass (no duplicates).
- [ ] JobTests pass (pawn picks right job).

### Week 1.5: Main Loop & Agents Running

**Task**: Put it all together; 10 pawns running autonomously.

**LLM Brief**:
> "Create:
> - GameSetup.cs (spawn 10 pawns, 10 beds, stockpile with food).
> - Main loop (Game.Tick() calls pawn.Update() for each pawn).
> - Pawn.Update() runs: FindJob → pathfind → execute job.
> - Eat job: reduce hunger by 0.1/tick until hunger < 0.1.
> - Sleep job: reduce fatigue by 0.05/tick until fatigue < 0.1.
> - Tests: 10 pawns survive 21,000 ticks (7 days). Log state every 100 ticks."

**Expected output**:
- `GameSetup.cs`
- `Pawn/Pawn.Update()` updated
- `Tests/SurvivalTest.cs`

**Validation**:
- [ ] SurvivalTest passes (10 agents alive after 7 days).
- [ ] No crashes, no infinite loops.
- [ ] Log shows all pawns eating and sleeping.

### Week 1.6: Save/Load & Determinism

**Task**: Serialize state, load it, verify replay is bit-identical.

**LLM Brief**:
> "Implement:
> - SaveGame.cs (serialize entire game state to JSON).
> - LoadGame.cs (deserialize and restore state).
> - Tests: save after 1000 ticks, load, run another 1000, compare.
> - DeterminismTest: run with seed 12345 twice, get identical tick history."

**Expected output**:
- `SaveLoad/SaveGame.cs`
- `SaveLoad/LoadGame.cs`
- `Tests/SaveLoadTests.cs`
- `Tests/DeterminismTests.cs`

**Validation**:
- [ ] SaveLoadTests pass (bit-for-bit recovery).
- [ ] DeterminismTests pass (same seed → same history).

### Week 1.7: Benchmarking & Documentation

**Task**: Measure performance, write Phase 1 completion report.

**Benchmark target**:
- 10 pawns, 100 days (600,000 ticks): should be <10 sec.
- Memory: should be <100 MB.
- Pathfinding: should be <1 ms per call (cached).

**Output**:
- [ ] `docs/PHASE_1_COMPLETE.md`
- [ ] `docs/BENCHMARK_REPORT.txt`
- [ ] `docs/ARCHITECTURE.md` (updated)
- [ ] `docs/TEST_RESULTS.md`
- [ ] Proposed Phase 2 roadmap → `docs/PHASE_2_ROADMAP.md`

**Exit criteria for Phase 1**:
- [ ] All tests pass.
- [ ] 10 pawns survive 100 days consistently.
- [ ] Deterministic replay verified.
- [ ] Save/load works.
- [ ] Benchmark acceptable.
- [ ] Documentation complete.
- [ ] Ready to brief LLM on Phase 2.

---

## Timeline

| Week | Phase | Goal | Deliverable |
|------|-------|------|-------------|
| 0.1 | 0 | Clone repos | reference/ + list |
| 0.2 | 0 | System docs | docs/systems/*.md |
| 0.3 | 0 | Compare | docs/analysis/* |
| 0.4 | 0 | Plan Phase 1 | docs/phase_1_architecture.md |
| 1.1 | 1 | Tick loop | Game.cs, tests |
| 1.2 | 1 | Pawns | Pawn.cs, tests |
| 1.3 | 1 | World | Food, Beds, Pathfinding |
| 1.4 | 1 | Jobs | Reservation, Job, Workgivers |
| 1.5 | 1 | Main loop | 10 pawns alive, tests |
| 1.6 | 1 | Save/Load | Determinism, tests |
| 1.7 | 1 | Benchmark | Report, Phase 2 proposal |

**Total**: ~7 weeks (Phase 0 + 1).

---

## Success Criteria

- [ ] C# project compiles, zero warnings.
- [ ] All unit tests pass.
- [ ] 10 pawns autonomously survive 7 simulated days.
- [ ] Save/load preserves state exactly.
- [ ] Deterministic replay verified (same seed = same history).
- [ ] Benchmark acceptable (<10 sec for 600k ticks, <100 MB memory).
- [ ] Documentation complete (systems, architecture, test results).
- [ ] Phase 2 roadmap ready.

---

## Next Immediate Action

**→ Start Phase 0, Week 0.1: Clone repos and set up reference directory.**

Then proceed to system documentation reads.
