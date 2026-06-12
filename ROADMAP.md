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

## PRIORITE ABSOLUE: FINITION & POLISH (un jeu fini, pas une demo)
Chaque item doit etre RESSENTI en jouant. Le playtest automatique (toutes les
12 iterations) verifie tes changements en jouant vraiment.

- [ ] Step F.1a - In src/RimWorldLab.Core/GameWorld.cs, in the GameWorldManager Tick() method, right after `TickGoals();` style calls, add: if (TotalTicks == 200) LogEvent("Guide: recoltez 10 bois (clic sur un arbre).");
- [ ] Step F.2a - In src/RimWorldLab.Core/GameWorld.cs (class GameWorldManager), add: private int GetHourFromTicks() { return (TotalTicks / 400) % 24; }
- [ ] Step F.3a - In src/RimWorldLab.Core/GameWorld.cs, inside the existing `if (TotalTicks % 40 == 0)` block in the Tick() method, add: `foreach (var pw in _pawns.Where(q => q.HP > 0 && q.Fatigue > 80)) pw.Fatigue = Math.Max(0f, pw.Fatigue - 2f);`
- [ ] Step F.4b - Audio procedural: dans src/RimWorldGodot/Game3D.cs, ajouter la méthode GenerateShortBipSound() sans appel pour générer un bip court via AudioStreamGenerator.
- [ ] Step F.5a - In src/RimWorldLab.Core/GameWorld.cs, find the method where Hunger increases each tick for living pawns and add a check to see if the pawn's task is not null. Ensure the method signature matches the existing code.
- [ ] Step F.6a - In src/RimWorldLab.Core/GameWorld.cs, add a new method to check if the colony is outillee: `public bool IsColonyOutillee() { return _functionalRoomCount >= 3 && Tools >= 10; }`.

## PRIORITE: la vie sur les cartes (Down Here! chantier faune)
- [ ] Step D.1 - In src/RimWorldLab.Core/GameWorld.cs, immediately after the line `Macro.Tick(TotalTicks);`, insert the following line:
- [x] Step D.2 - Hunting: a pawn standing next to a SmallAnimal harvests it
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
- [x] Step D.3 - Animals must wander. In src/RimWorldLab.Core/GameWorld.cs,
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
- [x] Step D.4 - Low colony morale slows work. In
      src/RimWorldLab.Core/Jobs.cs, inside TryClaimBest, find the exact line:
      `            double score = task.Priority * 10.0;`
      and REPLACE it with:
      `            double score = task.Priority * 10.0;`
      `            score += (pawn.Mood - 50.0) / 25.0;`
- [x] Step Z.1 - Trade caravan: Add private fields for Tools and Food in GameWorld.cs.
- [x] Step Z.3.1 - Add a private field `int TotalTicks` to `GameWorld.cs`.

## NOTE: stade ORIGINES = fork de Thrive (reference/thrive, branche down-here)
NE TOUCHE PAS au fork. MicroStage.cs ne sert plus que de fond de menu.
Les items S.x ci-dessous sont GELES (ne pas travailler dessus).

- [x] Step S.1a - (gele, fork Thrive) In src/RimWorldGodot/MicroStage.cs, find the exact line: `_traitPool.Add(("Compacité", "-15% taille (discret), +10% vitesse", o => { o.Size *= 0.85f; o.Speed *= 1.1f; }));` Immediately AFTER that line, insert this new line: `_traitPool.Add(("Toxines", "Les prédateurs perdent de l'énergie en te mordant", o => o.Spikes += 2));`
- [x] Step S.2 - (gele, fork Thrive) In MicroStage.cs, modify the _Process method to check if the population is less than 30.
- [x] Step S.3.1 - (gele, fork Thrive) Add a method to check if the population is less than 30 in `src/RimWorldLab.Core/GameWorld.cs`. The method should return a boolean indicating the population status.

## PRIORITE: la couche primordiale (depart Spore - LOD Micro)
- [x] Step M.1 - In src/RimWorldLab.Core/GameWorld.cs, find the exact line: `Macro.Tick(TotalTicks);` Immediately AFTER that line, insert these new lines: `if (TotalTicks % 1600 == 0) { float biomass = Macro.Regions[2, 2].MicrobialBiomass; if (biomass > 0.75f) LogEvent($"Microbial bloom enriches the soil (biomass {biomass:P0})."); }`
- [x] Step M.2.1 - Add private field `cookBonus` in `src/RimWorldLab.Core/GameWorld.cs`.

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
- [x] Step C.60 - Add a private field `functionalRoomsCount` to the `GameWorld` class.
- [x] Step C.75 - Implement a basic room detection system by adding a private field to track the number of functional rooms in `GameWorld.cs`.
- [x] Step C.105 - Implement a system to generate resources over time, such as trees regrowing or rocks replenishing, to ensure players have a steady supply of materials.
- [x] Step C.120 - (obsolete, classe poubelle purgee) Add the private field `_resources` to the `GameWorld` class.
- [x] Step C.135 - (obsolete, classe poubelle purgee) Add a private field to track the number of rooms being built in GameWorld.cs. Define the field in the GameWorld class.
- [x] Step C.150 - (obsolete, classe poubelle purgee) Add a private field to track resources in GameWorld.cs.
- [x] Step C.165 - (obsolete, classe poubelle purgee) Change the type of `_resourceRegenerationRates` values from `int` to `double` in `src/RimWorldLab.Core/GameWorld.cs`.
- [x] Step C.180 - (obsolete, classe poubelle purgee) Extract the repeated pawn registration logic into a separate method in Main.cs. Ensure the method is correctly defined and called in both _Ready and _Process methods.
- [ ] Step C.195 - Implement a system to track and display the progress towards building functional rooms, providing players with clear feedback on their progress.
- [ ] Step C.15.1 - Add a method to check if the population is less than 30 in `src/RimWorldLab.Core/GameWorld.cs`. Ensure the method is correctly placed and uses the existing `Pawns` field.
- [ ] Step C.30a - Add a method to check if the population is less than 30 in `GameWorld.cs`. Ensure the method correctly references the `Pawns` collection.
- [ ] Step C.45.1 - Add a private field `List<Pawn> Pawns` to `GameWorld.cs`.
- [ ] Step C.60 - Add a private field to track the number of rooms built and update it when a new room is added. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.75a - Add a private field to store the zones list in GameWorld.cs.
- [ ] Step C.15a - Add private fields `Zones` and `_microbialBiomass` to GameWorld.cs. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.30 - Add private fields for Wood and Stone in GameWorld.cs. Initialize them to 0 in the constructor.
- [ ] Step C.45 - Implement a system to generate multiple types of resources (e.g., wood, stone) instead of just one, increasing resource management complexity. (GameWorld.cs)
- [ ] Step C.60 - Implement a system to track and display progress toward building additional rooms, providing clear feedback on what's needed to reach win conditions. (GameWorld.cs)
- [ ] Step C.75 - Implement a resource consumption system for pawns to ensure they deplete food and water over time, requiring players to manage resources sustainably. (GameWorld.cs)
- [ ] Step C.90 - Add a private field to track the colony population size in GameWorld.cs and initialize it.
- [ ] Step C.105a - Add private fields for tracking wood and stone resources in GameWorld.cs. Define `private int Wood;` and `private int Stone;`.
- [x] Step C.120 - (obsolete, classe poubelle purgee) Initialize _resourceUsage dictionary in the constructor of GameWorld.cs.
- [x] Step C.135 - (obsolete, classe poubelle purgee) Add a private field to track total resource consumption for each kind in GameWorld.cs. Initialize it in the constructor.
- [ ] Step C.150a - Initialize _resourceUsage dictionary in GameWorld constructor (GameWorld.cs).
- [ ] Step C.165.1 - Add the opening brace for the new method `TrackResourceConsumption` in GameWorld.cs. Ensure it is correctly placed within the class and does not cause syntax errors.
- [ ] Step C.179a - Add opening brace for TrackResourceConsumption method (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.180a - Declare private dictionary for tracking recycled resources (GameWorld.cs)
- [ ] Step C.195a - Ensure the private dictionary for tracking recycled resources is declared correctly in the GameWorld class. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.15a - Declare a private dictionary for tracking recycled resources in the GameWorld class. (src/RimWorldLab.Core/GameWorld.cs) - Ensure the dictionary is properly initialized and referenced.
- [ ] Step C.30 - Declare a private dictionary for tracking recycled resources in the GameWorld class. (src/RimWorldLab.Core/GameWorld.cs) - Ensure the field is not declared multiple times and is correctly named.
- [ ] Step C.45a - Add a private field to track progress towards building additional rooms in GameWorld.cs. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.60a - Ensure _recycledResources is declared and initialized in the GameWorld constructor (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.75a - Initialize `_recycledResources` dictionary in `GameWorld` constructor.
- [ ] Step C.90a - Initialize `_recycledResources` dictionary in `GameWorld` constructor. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.105a - Ensure `_recycledResources` is declared as an instance variable in `GameWorld`. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.120a - Ensure `_recycledResources` is declared only once in `GameWorld.cs`.
- [x] Step C.135 - (obsolete, classe poubelle purgee) Ensure `_recycledResources` is declared only once in `GameWorld.cs`.
- [x] Step C.165 - (obsolete, classe poubelle purgee) Add `Wood` and `Stone` values to the `ResourceKind` enum in `GameWorld.cs`.
- [x] Step C.180 - (obsolete, classe poubelle purgee) Implement a system to track and display colony progress towards building functional rooms.
- [ ] Step C.186 - Add 'Wood' and 'Stone' to ResourceKind enum in GameWorld.cs. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.195 - Add private fields for Wood and Stone resources in GameWorld class (GameWorld.cs)
- [ ] Step C.15a - Add Wood and Stone properties to GameWorld class. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.30b - Implement `GetTotalResourceConsumption` method to calculate total resource consumption for a given resource kind in `GameWorld.cs`. This method should iterate over `_recycledResources` and sum up the values for the specified `ResourceKind`.
- [ ] Step C.45a - Add private dictionary _resourceConsumptionRates to GameWorld.cs
- [ ] Step C.60a - Add a private dictionary `_resourceConsumptionRates` to track resource consumption rates in GameWorld.cs.
- [ ] Step C.75 - Add the `_resourceConsumptionRates` dictionary and initialization to the `GameWorld` constructor in src/RimWorldLab.Core/GameWorld.cs.
- [ ] Step C.90a - Add `ResourceKind` enum values for Wood and Stone in src/RimWorldLab.Core/Enums.cs.
- [ ] Step C.105a - Add `ResourceKind` enum values for 'Wood' and 'Stone' (src/RimWorldLab.Core/Enums.cs)
- [ ] Step C.120a - Add `Wood` and `Stone` to the `ResourceKind` enum in `src/RimWorldLab.Core/Enums.cs`.
- [ ] Step C.135a - Add definitions for 'Wood' and 'Stone' to `ResourceKind` enum in src/RimWorldLab.Core/Enums.cs.
- [ ] Step C.150a - Add `Wood` and `Stone` to the `ResourceKind` enum in (src/RimWorldLab.Core/Enums.cs).
- [x] Step C.165 - (obsolete, classe poubelle purgee) Add `Wood` and `Stone` to the `ResourceKind` enum in GameWorld.cs
- [ ] Step C.180a - Add `Wood` and `Stone` to the `ResourceKind` enumeration in (src/RimWorldLab.Core/Enums.cs). Ensure the values are unique and consistent with existing entries.
- [ ] Step C.195.1 - Add `Wood` and `Stone` to the `ResourceKind` enum (src/RimWorldLab.Core/Enums.cs)
- [ ] Step C.15.1 - Add `Wood` and `Stone` values to the `ResourceKind` enum in `GameWorld.cs`.
- [ ] Step C.30a - Define `ResourceKind` enum with `Wood` and `Stone` values (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.45a - Add the `UpdateResourceRegenerationRate` method to `GameWorldManager.cs`. This method should accept a `ResourceKind` and an `int` as parameters and update the corresponding regeneration rate in a dictionary or similar data structure.
- [ ] Step C.60a - Add `_resourceRegenerationRates` dictionary to `GameWorldManager` class in `src/RimWorldLab.Core/GameWorld.cs`.
- [ ] Step C.75.1 - Add a private static dictionary `_resourceRegenerationRates` to `GameWorldManager` class. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.90 - Implement `DisplayFunctionalRooms` method to iterate through rooms and print their status. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.105b - Implement CountFunctionalRooms method to return an integer count of functional rooms. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.120a - Add `TrackResourceConsumption` method to `GameWorld.cs`.
- [ ] Step C.135a - Add a private field `List<Pawn>` named `_pawns` to `GameWorld.cs`. Initialize it in the constructor. Ensure the method references this new field for pawn iteration.
- [ ] Step C.150a - Add a private field `List<Pawn>` named `_pawns` to `GameWorld.cs`.
- [x] Step C.165 - (obsolete, classe poubelle purgee) Add a public property `List<Pawn> Pawns` to expose the `_pawns` field in `GameWorld.cs`.
- [x] Step C.180 - (obsolete, classe poubelle purgee) Implement a system to track and limit resource consumption for building materials, encouraging players to manage their resources efficiently. (GameWorld.cs)
- [ ] Step C.195 - Implement a resource management system to track and limit the use of resources like wood and stone, forcing players to prioritize their usage. (GameWorld.cs)
- [ ] Step C.1a - Add a public property `Pawns` to expose the `_pawns` list in `GameWorld.cs`. Ensure the property returns the `_pawns` field.
- [ ] Step C.15a - Add a public property to access the `_pawns` list in `GameWorld.cs`.
- [ ] Step C.30a - Add a private field `resourceConsumptionRates` of type `Dictionary<string, float>` to store resource consumption rates in GameWorld.cs (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.15.1 - Add a property to the Pawn class that returns true if the pawn's current task kind is TaskKind.Work. Implement this in src/RimWorldLab.Core/Pawn.cs.
- [ ] Step C.15 - Implement a resource consumption system for pawns to ensure they deplete resources and need to manage them efficiently. (Needs.cs)
- [ ] Step C.30 - Implement a resource management system to track and limit resource consumption by pawns, ensuring they must prioritize tasks based on available resources. (GameWorld.cs)
- [ ] Step C.45 - Implement resource consumption for building materials to encourage sustainable use and strategic planning in GameWorld.cs
- [ ] Step C.60 - Implement a system to generate random resources and obstacles to encourage exploration and resource management. (GameWorld.cs)
- [ ] Step C.75a - Add private fields `_pawns` and `_resourceConsumptionTracker` to `GameWorld.cs`.
- [ ] Step C.90a - Implement the `GetTotalResourceConsumption` method to calculate the total resource consumption for a given resource kind in GameWorld.cs.
- [ ] Step C.105a - Add private fields `_saplings` and `_resources` to `GameWorld.cs`. Initialize them as empty lists or arrays.
- [x] Step C.120 - (obsolete, classe poubelle purgee) Add private fields `_saplings` and `_resources` to `GameWorld.cs`.
- [x] Step C.135 - (obsolete, classe poubelle purgee) Add private fields `_saplings` and `_resources` to `GameWorld.cs`.
- [ ] Step C.150a - Add a private field `_saplings` of type `List<Sapling>` to `GameWorld.cs`.
- [ ] Step C.165a - Add a private field `_resourceConsumptionRates` of type `Dictionary<Pawn, Dictionary<ResourceKind, int>>` to `GameWorld.cs`. Initialize it in the constructor.
- [x] Step C.180 - (obsolete, classe poubelle purgee) Add `Pawns` collection to `GameWorld.cs` if it doesn't exist.
- [ ] Step T180a - Ensure Pawns collection is initialized before use in GameWorld constructor (src/RimWorldLab.Core/GameWorld.cs) by adding a private field for Pawns and initializing it in the constructor.
- [ ] Step C.195a - Add a field to track the number of rooms required to win in GameWorld.cs. Initialize it to 0 in the constructor.
- [ ] Step C.15a - Add a private field `_roomsBuilt` to track the number of rooms built in `GameWorld.cs`.
- [ ] Step C.30a - Ensure `_recycledResources` is initialized before use in `GameWorld` constructor. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.45a - Ensure `_recycledResources` is initialized before use in `GameWorld` constructor (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.60 - Ensure `_recycledResources` is initialized before use by adding `_recycledResources = new();` in the `GameWorld` constructor. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.75a - Ensure `_recycledResources` is initialized before use by adding `_recycledResources = new();` in the `GameWorld` constructor. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.90a - Add a private dictionary to track pawn resource consumption in GameWorld.cs. Initialize it as an empty dictionary.
- [ ] Step C.105a - Implement the `CountFunctionalRooms` method to count functional rooms in the game world (src/RimWorldLab.Core/GameWorld.cs).
- [ ] Step C.120a - Add a property `IsRaining` to the `GameWorld` class (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.135a - Initialize the new private dictionary `_pawnResourceConsumption` in GameWorld.cs. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.150a - Add a private dictionary to track resource consumption by pawns in GameWorld.cs. Initialize it in the constructor.
- [x] Step C.165 - (obsolete, classe poubelle purgee) Ensure LocalMap is accessible within GameWorld.cs and implement the CalculateRoomCompletionProgress method to correctly count functional furniture within a zone's bounds.
- [x] Step C.180 - (obsolete, classe poubelle purgee) Add a method to handle water consumption for pawns by checking if the pawn's thirst is greater than zero before consuming water. (src/RimWorldLab.Core/Needs.cs)
- [ ] Step C.195 - Implement a system to generate multiple types of rooms automatically, ensuring players have a diverse set of structures to build towards their win condition. (GameWorld.cs)
- [ ] Step T12a - Add Workshop and Storage to ZoneKind enumeration (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.15a - Add new ZoneKind values for Workshop and Storage in src/RimWorldLab.Core/ZoneKind.cs. Define `Workshop` and `Storage` as valid enum members of the `ZoneKind` enumeration.
- [ ] Step C.30a - Add a private field `List<Pawn> Pawns` to GameWorld.cs and initialize it in the constructor. (GameWorld.cs)
- [ ] Step C.45 - Change the type of `_resourceRegenerationRates` values to `double`. (GameWorld.cs)
- [ ] Step C.60a - Change the type of `_resourceRegenerationRates` values to `double`. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.75.1 - Add a method to check if a furniture placement is isolated by defining `LocalMap` within `IsPlacementIsolated`. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.90a - Add a private field `LocalMap` to the `GameWorld` class and initialize it in the constructor.
- [ ] Step T96a - Define `LocalMap` property in `GameWorld.cs` to access the map data.
- [ ] Step C.105a - Ensure LocalMap is defined and accessible before checking placement isolation. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.120a - Add `LocalMap` as a member variable to `GameWorld.cs`.
- [x] Step C.150 - (obsolete, classe poubelle purgee) Add a private field `LocalMap` to the `GameWorld` class. (src/RimWorldLab.Core/GameWorld.cs)
- [x] Step C.165 - (obsolete, classe poubelle purgee) Ensure `LocalMap` is initialized in the constructor of `GameWorld.cs`.
- [ ] Step C.180.1 - Add a private field `LocalMap` of type `GameMap` to `GameWorld.cs`. Ensure `LocalMap` is initialized in the constructor of `GameWorld.cs`.
- [ ] Step C.195.1 - Add `colonySize` parameter to all calls of `SimulateResourceRegeneration` (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.15 - Implement a system to generate random resource distribution and placement to encourage exploration and strategic planning. (GameWorld.cs)
- [ ] Step C.30 - Implement a system to track and display progress towards building additional rooms, providing players with clear goals and feedback on their colony's development (GameWorld.cs).
- [ ] Step C.45 - Implement a system to track and display progress towards building additional rooms in the game world.
- [ ] Step C.60 - Implement a system to track and display the progress towards building additional rooms.
- [ ] Step C.75 - Implement a resource consumption system for building materials to encourage efficient use and planning. (GameWorld.cs)
- [ ] Step T84 - (playtest) fix: ALL PAWNS IDLE with 1 pending tasks (3 polls) (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.105 - Implement a resource consumption system for pawns to ensure they deplete resources over time and must be managed efficiently. (GameWorld.cs)
- [ ] Step C.120 - Reduce the number of resources generated per tick to encourage sustainable resource management. (GameWorld.cs)
- [ ] Step C.135 - Implement a resource management system to limit the rate of resource consumption and encourage sustainable use. (GameWorld.cs)
