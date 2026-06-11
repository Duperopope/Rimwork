# DOWN HERE ! — Roadmap du développeur IA local

Le projet a évolué : ce n'est plus un prototype de jam mais DOWN HERE !,
un jeu de gestion de colonie / 4X / exploration spatiale (voir
docs/DOWN_HERE_DESIGN.md). Tu es le développeur du GAMEPLAY COEUR.

## Règles permanentes
- UN SEUL petit changement par itération, ancré sur des lignes EXACTES.
- Fichiers autorisés: src/RimWorldLab.Core/GameWorld.cs, WorldModel.cs,
  Needs.cs, Jobs.cs, src/RimWorldGodot/Game3D.cs.
- INTERDITS (rejet automatique): UiShell.cs, Boot3D.tscn, RenderCatalog.cs,
  Main.cs 2D legacy, tout placeholder/stub/dummy.
- Chaque feature doit avoir un effet MESURABLE dans la simulation.

## PRIORITE: la vie sur les cartes (Down Here! chantier faune)
- [ ] Step D.1 - In src/RimWorldLab.Core/GameWorld.cs, immediately after the line `Macro.Tick(TotalTicks);`, insert the following line:
- [ ] Step D.2 - Hunting: a pawn standing next to a SmallAnimal harvests it
      for food. In src/RimWorldLab.Core/GameWorld.cs, find the exact line:
      `        if (TotalTicks % 1500 == 0)`
      Immediately BEFORE that line, insert these new lines:
      `        if (TotalTicks % 200 == 0)`
      `        {`
      `            foreach (var hunter in _pawns.Where(p => p.HP > 0 && p.Name != "SmallAnimal"))`
      `            {`
      `                var prey = _pawns.FirstOrDefault(a => a.Name == "SmallAnimal" && a.HP > 0 && Math.Abs(a.X - hunter.X) <= 1 && Math.Abs(a.Y - hunter.Y) <= 1);`
      `                if (prey != null)`
      `                {`
      `                    prey.HP = 0f;`
      `                    Food += 3;`
      `                    hunter.Remember(TotalTicks, "hunted small game", +1f);`
      `                    break;`
      `                }`
      `            }`
      `        }`
- [ ] Step D.3 - Animals must wander. In src/RimWorldLab.Core/GameWorld.cs,
      find the exact line:
      `        if (TotalTicks % 50 == 0)`
      Immediately AFTER that line and its `            AssignPersonalFurniture();` line, insert:
      `        if (TotalTicks % 40 == 0)`
      `            foreach (var an in _pawns.Where(p => p.Name == "SmallAnimal" && p.HP > 0))`
      `            {`
      `                int nx = an.X + _rng.Next(-1, 2), ny = an.Y + _rng.Next(-1, 2);`
      `                if (_map.IsPassable(nx, ny)) { an.X = nx; an.Y = ny; }`
      `            }`

## PRIORITE: humeur qui compte (Bannerlord layer)
- [ ] Step D.4 - Low colony morale slows work. In
      src/RimWorldLab.Core/Jobs.cs, inside TryClaimBest, find the exact line:
      `            double score = task.Priority * 10.0;`
      and REPLACE it with:
      `            double score = task.Priority * 10.0;`
      `            score += (pawn.Mood - 50.0) / 25.0;`
- [ ] Step Z.1 - Trade caravan: every 4000 ticks, if Tools >= 2 and
      Macro.TradeDemand > 0.5f, remove 2 Tools, add 8 Food and LogEvent
      "Caravan trade: 2 tools sold for 8 food." in GameWorld.cs Tick.
- [ ] Step Z.3 - When a Build task completes (the PlaceFurniture branch in
      GameWorld.cs Tick), call pawn.Remember(TotalTicks, "built a structure", +1.5f).

## ARCHIVE (accompli - ne pas retoucher)
- [x] Step W.1 - Mining is already implemented (Mine furniture,
- [x] Step W.1b - VERIFIED DEADLOCK (headless 30k-tick sim): Stone stays 0
- [x] Step W.1c - VERIFIED BUG (headless sim): when a pawn finishes a
- [x] Step G.0 - When every pawn is dead the game sits frozen forever; it
- [x] Step G.1 - The win condition is frozen at "3 functional rooms" forever;
- [x] Step G.2b - In src/RimWorldGodot/Main.cs, SEARCH for the line `			_world.RefreshRooms();` and REPLACE it with these 4 lines:
- [x] Step G.3 - Show the CURRENT goal instead of the frozen one. In
- [x] Step G.4a - In src/RimWorldGodot/Main.cs, replace `if (num9 >= 3)` with `if (_world.GoalIndex > 0)`.
- [x] Step P.0a - Bridges are built without purpose (nearest water tile,
- [x] Step P.0b - Set the flag where the need is discovered. In
- [x] Step P.0c - Only bridge when there is a reason. In
- [x] Step P.1 - Pawns must pick the BEST task for them, not the first one.
- [x] Step P.2 - In src/RimWorldLab.Core/GameWorld.cs, add the method `TryClaimBest(Pawn pawn)` if it doesn't exist.
- [x] Step P.3 - Pawns need an inner life: a Mood. In
- [x] Step P.3b - The Pawn class lives in src/RimWorldLab.Core/GameWorld.cs
- [x] Step P.4b - Mood dynamics. In src/RimWorldLab.Core/GameWorld.cs,
- [x] Step A - "Rooms" tab removed; its content is now a "ROOMS" section at
- [x] Step B - Map hover tooltip implemented: hovering any tile shows a
- [x] Step C - Dev tab now reads DEV_LOG.md and shows "X kept / Y reverted"
- [x] Step D - Dev tab now shows a sparkline of roadmap done-count sampled
- [x] Step K - Already covered: in the raider combat tick (Main.cs), any
- [x] Step L - Raider variety: 1/3 spawns are "Brute" (HP 60, dmg 10, half
- [x] Step M - Dead pawns (HP<=0) are now removed from
- [x] Step N - Digging a player-built wall (non-border) or removing
- [x] Step U.1 - User-provided KayKit CC0 packs (furniture, nature,
- [x] Step U.2 - REVERTED/NOT ACTUALLY DONE (re-checked: Main.cs has no
- [x] Step U.3.1 - DONE (verified in code): Rock resources now draw DrawCircle + 3 darker grey DrawColoredPolygon facets in Main.cs._Draw (lines ~824-847).
- [x] Step U.3.2 - In src/RimWorldGodot/Main.cs, find this exact line:
- [x] Step U.3.3 - In src/RimWorldGodot/Main.cs, find this exact block:
- [x] Step U.3.4 - In src/RimWorldGodot/Main.cs, find this exact line:
- [x] Step U.3.5 - In src/RimWorldGodot/Main.cs, find this exact line:
- [x] Step U.3.6 - In src/RimWorldGodot/Main.cs, find this exact line:
- [x] Step U.3.7 - In src/RimWorldGodot/Main.cs, find this exact line:
- [x] Step U.3.8 - In src/RimWorldGodot/Main.cs, find this exact line:
- [x] Step U.4.1 - In src/RimWorldGodot/Main.cs, find this exact line:
- [x] Step U.4.2 - In src/RimWorldGodot/Main.cs, find this exact line:
- [x] Step U.5 - Polish pass once U.3.x/U.4.x are done: review the new
- [x] Step V.1 - Added `HexCoord` (axial Q,R) in `HexGrid.cs`: Neighbors(),
- [x] Step V.2 - Add a `GridShape` property to GameMap with a default value of "Square".
- [x] Step V.3 - Main.cs._Draw: when GridShape==Hex, draw each tile as a
- [x] Step V.4 - Planet/region map: add a new class `RegionMap` with a private field `List<(int X, int Y, string Biome)> _regions` in `src/RimWorldLab.Core/RegionMap.cs`.
- [x] Step O - Atmosphere: subtle grid lines drawn over all tiles, plus a
- [x] Step Q1 - Add a method to check if a pawn is at the edge of the current region's hex map in GameWorld.cs.
- [x] Step R - Weather: every few in-game days, toggle a "Rain" state that
- [x] Step S - Ambient sound hooks: add an `AudioStreamPlayer` node that
- [x] Step T (partial) - Furniture now draws a soft drop-shadow (offset
- [x] Step E - Day/night cycle implemented: GameWorldManager.TotalTicks ->
- [x] Step F - Random events: every ~60-120s a Raider spawns at a random
- [x] Step G - Basic combat: Pawn.HP (default 100), raiders and pawns
- [x] Step H - Resource cost: chopping a Tree gives +1 Wood (start with 5),
- [x] Step I - Win condition: header shows "Goal: 3 functional rooms (X/3)";
- [x] Step J - Already covered by existing PawnTaskDriver.Step: when
- [x] Step K - Renewable trees: chopping a Tree drops 0-2 seeds onto nearby
- [x] Step L - Real consequences for needs and the resource loop: a maxed
- [x] Step M - Fixed the auto-build queue getting permanently stuck: a
- [x] Step N2 - Pawns/Skills/Stone overhaul: pawns now have a `Sex` (M/F,
- [x] Step N3 - Mines: a new "Mine" Production furniture (build cost 20
- [x] Step N4 - Autonomous dev loop fixed: scripts/dev_loop.ps1 was
- [x] Step N5 - Personal furniture & terrain economy: Bed and Chair are
- [x] Step N6 - Bridges & water-aware expansion: the river was a 2-tile
- [x] Step W.0 - Meals & cooking: Stove (already buildable) consumes raw
- [x] Step W.2 - Water tiles: add Cell.TileType "Water" patches to
- [x] Step W.5 - Tie it together: Wood/Stone/Water/Food become the four
- [x] Step E.7 - Add a method to randomly generate small animal populations in GameWorld.cs
- [x] Step E.39 - Implement a simple weather system that affects resource availability in src/RimWorldLab.Core/GameWorld.cs
- [x] Step C.45 - Add a basic room detection system to identify functional rooms in GameWorld.cs by defining a method to check if a given tile is part of a room.
- [x] Step C.60 - Add properties X and Y to the Cell class. (src/RimWorldLab.Core/GameWorld.cs)
- [x] Step C.75.1 - Ensure the Cell class in GameWorld.cs has properties X and Y defined only once.
- [x] Step C.45.1 - Ensure the Cell class has properties X and Y defined only once in GameWorld.cs
- [x] Step C.105 - Implement a basic room detection system to count functional rooms and trigger win condition in GameWorld.cs
- [x] Step C.15 - Implement a system to generate functional rooms automatically to meet the win condition.
- [x] Step Z.2 - Wildlife pressure: in src/RimWorldLab.Core/WorldModel.cs,
- [x] Step C.75 - Implement a system to automatically generate functional rooms to meet the win condition, ensuring player progress is not hindered by resource scarcity. (GameWorld.cs)
- [x] Step C.120 - Implement a system to automatically generate functional rooms based on furniture placement in GameWorld.cs
- [x] Step C.15 - Implement a system to generate resources over time to encourage sustainable resource management.
- [x] Step C.45 - Implement a system to track and display the number of functional rooms in the colony, allowing players to see their progress towards the win condition.
- [x] Step C.120 - Add a private field _regions to the GameMap class. (src/RimWorldLab.Core/GameWorld.cs)
- [x] Step C.180 - Implement a basic resource management system to ensure players have to gather and manage resources to build rooms.
- [x] Step C.90 - Implement a resource consumption system that requires players to manage food, water, and energy for their pawns, forcing them to prioritize building functional rooms to meet basic needs.
- [x] Step C.105 - Implement a resource consumption system that forces players to manage their colony's food and materials to prevent starvation and resource depletion.
- [x] Step C.135.1 - Implement a method to check if a room is functional in GameWorld.cs.
- [x] Step C.150 - Implement a resource consumption system for pawns to ensure they use resources like wood and stone to build furniture and walls, preventing infinite building without resource management. (GameWorld.cs)
- [x] Step C.165 - Implement a resource consumption system for pawns to simulate hunger and thirst, forcing players to manage food and water production. (GameWorld.cs)
- [x] Step C.15 - Implement a resource consumption system to ensure players manage their colony's needs effectively.
- [x] Step C.30 - Improve resource management by adding a recycling system for unused materials in GameWorld.cs
- [x] Step C.105 - Implement a mechanic that requires players to manage resources more efficiently to unlock new building types.
- [x] Step C.150 - Implement a system to automatically assign pawns to build tasks based on their skills and the current needs of the colony.
- [x] Step C.15.1.1 - Add a private dictionary `_recycledResources` to `GameWorld.cs` to track recycled resources.
- [x] Step C.30.1 - Add a private dictionary `_recycledResources` to `GameWorld.cs` by inserting it inside the `GameWorld` class.
- [x] Step C.64.1 - Implement the method `GetTotalResourceConsumption` in `GameWorld.cs` to iterate over `_pawnResourceConsumption.Values` and sum the consumption for the specified `ResourceKind`.
- [x] Step C.90a - Implement a method to simulate resource regeneration for a single resource type, such as trees regrowing, in the `GameWorld` class.
- [x] Step E.99a - Implement the `IsZoneFunctional` method in src/RimWorldLab.Core/GameWorld.cs.
- [x] Step C.120 - Implement a system to detect and count functional rooms in the game world.
- [x] Step C.135 - Implement a system to track and display functional room counts to the player.
- [x] Step C.150 - Implement a system to automatically assign pawns to tasks based on their needs and skills in GameWorld.cs.
- [x] Step C.161 - Implement a mechanism to generate resources over time to encourage sustainable resource management.
- [x] Step C.164 - Implement a method to check if a zone is functional. (src/RimWorldLab.Core/GameWorld.cs)
