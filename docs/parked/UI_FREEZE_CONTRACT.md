# UI FREEZE CONTRACT — effective after the 2026-06-11 superpass

The frontier-LLM pass that produced Boot3D.tscn / Game3D.cs / UiShell.cs /
RenderCatalog.cs was the ONLY authorized high-level UI/presentation
intervention. The dev loop enforces this mechanically: any patch targeting
UiShell.cs, Boot3D.tscn or RenderCatalog.cs is rejected with
"REJECTED ui-freeze".

## Frozen (no LLM may redesign)
- Main menu structure (Nouvelle partie / Continuer / Options / Dev / Crédits / Quitter + version + premise)
- In-game HUD layout: top resource bar, clock+speed, left column (objective /
  macro-world / events), right pawn inspector, center alert banner, bottom hints
- Options menu structure and its persistence file (user://options.cfg)
- Dev/Diagnostics tab: the 9 numbered sections and their order
- Typography/colors: dark panel (#14191f @92%), accent green (#5cc26e), panel radius 8
- Camera model: fixed-angle orthogonal isometric, wheel zoom, edge/WASD pan, middle-drag
- Container/anchor responsive strategy (no absolute pixel layouts)
- KayKit visual identity (see docs/ASSET_CATALOG.md)
- 3D presentation itself: the game may never return to 2D

## Allowed (extension points for the local LLM)
- New data into existing UI slots (the labels read live sim state - extend the sim)
- New resources: add a property to GameWorldManager and it appears in the
  resource bar string (UiShell reads it through the existing format line — add
  via roadmap item editing GameWorld.cs only)
- New pawn stats: same principle, extend Pawn and the inspector rows pick up
- New dev metrics inside the existing 9 sections (data comes from sim/logs)
- New entity kinds: ONE row in RenderCatalog dictionaries... via roadmap items
  that Claude (not the local model) applies, since RenderCatalog.cs is frozen
  to the local model. Practical rule: local model adds the sim entity,
  a human/frontier pass adds the catalog row.
- New macro events / sites / tech entries (pure data in WorldModel/GameWorld)

## Forbidden forever
- Layout redesign, UI system replacement, returning to 2D, removing the
  3D camera, removing the dev proof panel, hiding blockers, removing safety
  gates or build/test/sim proof, marking fake systems complete.
