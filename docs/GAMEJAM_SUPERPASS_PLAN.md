# GAMEJAM SUPERPASS PLAN — 2026-06-11

The single authorized frontier-LLM pass. After it: UI frozen, local LLM adds
depth only through the extension points listed at the end.

## Current state (inspected)
- Sim core (RimWorldLab.Core): 50x50 colony, 8 pawns, needs (hunger/fatigue),
  jobs/taskboard, rooms, economy (Wood/Stone/Water), goals ladder, rebirth,
  mine, weather flags. Pollution: a few placeholder methods left by the local
  LLM (documented in docs/AUTONOMOUS_AUDIT.md) — repaired in this pass.
- Presentation: pure 2D Node2D `_Draw` debug view (eliminatory).
- Assets: 679 GLTF/GLB KayKit models ALREADY extracted+imported under
  assets/models/{characters,dungeon,furniture,nature,resources,restaurant,
  rpgtools} (done in Step U.1) + skeletons/ extracted this pass.
- Loop/dashboard/tests/guards: operational (5/5 tests, anti-stub gates).

## Asset strategy
Use the already-imported flat folders (no re-extraction churn):
- Pawns: characters/Knight|Barbarian|Mage|Ranger|Rogue.glb (Adventurers 2.0)
- Threats: skeletons/Skeleton_Warrior|Minion|Rogue|Mage.glb (Skeletons 1.1)
- Nature: nature/Tree_*\|Rock_*\|Bush_* (Forest Nature Pack)
- Buildings: dungeon/wall*, wall_doorway*, floor_tile* (Dungeon Remastered)
- Furniture: dungeon/bed_*, table_*, barrel_*, restaurant/stove (Furniture/
  Restaurant Bits via dungeon+restaurant folders)
- Production: rpgtools/anvil.gltf (RPG Tools)
Catalog + licences: docs/ASSET_CATALOG.md.

## Architecture (one sentence per layer)
`SolarSystem → WorldBody → WorldRegion[5x5] → LocalMap(50x50) → Room/Tile →
Pawn(body/mind)`, ticked by `MacroSim` at four LOD cadences (Solar 5000t,
Planet 2000t, Region 500t, Local every tick), with macro pressures
(RaidPressure, TradeDemand, ClimatePulse) mutating real local variables.

## Execution order
1. Core spine: WorldModel.cs (Scales 0-2 + LOD + 3 external sites + macro→
   local effects: raid timer, sapling regrowth, event feed).
2. Core depth: Thirst/Stress/Traits/Memories/Relationships on Pawn; REAL
   TryClaimBest on TaskBoard + routed call site; Food/Metal/Tools resources;
   one crafting recipe (anvil: 2 Wood+1 Stone→1 Tool); research thin-slice
   (3 unlocks); colony event log; placeholder repair.
3. 3D presentation: Main3D.tscn + Game3D.cs (isometric Camera3D, light,
   MultiMesh terrain, KayKit entities via RenderCatalog mapping table, zoom/
   pan, selection + inspector hook).
4. UI shell (UiShell.cs, containers/anchors): main menu, HUD (resource bar,
   time/speed, objective, alerts, event feed, inspector, build info, macro/
   LOD indicator), options (ConfigFile persistence), jury Dev tab (9
   sections, French labels).
5. Tests: TryClaimBest behavior, macro→local, LOD updates, thirst decay.
6. Docs + commit + final report.

## Risks / refusals
- Animations: KayKit rigs imported but NOT wired (animation retargeting in
  headless pass = high risk); pawns are posed models that move — documented.
- Visual zoom across scales: data+dev-tab only this pass; camera zoom within
  local scale implemented; cross-scale zoom is an extension point.
- Game save/load: NOT implemented (honest "Aucune sauvegarde" disabled
  button); options persistence IS implemented.
- I will not delete the 2D Main.tscn/Main.cs (rollback safety, dev loop
  builds against it) — the project main scene switches to Boot3D.tscn.
- No mass rewrite of GameWorld.cs: additive edits + targeted repair of the
  3 documented placeholders only.

## Files changing
Core: WorldModel.cs (new), GameWorld.cs (additive), Jobs.cs (TryClaimBest),
Needs.cs (thirst hook). Godot: Boot3D.tscn (new), Game3D.cs (new),
UiShell.cs (new), RenderCatalog.cs (new), project.godot (main scene).
Docs: 3 files. Loop: dev_loop routing additions for new files.
