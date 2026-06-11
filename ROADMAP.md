# Rimwork - Roadmap

Ordered list of features. The autonomous dev loop should pick the FIRST
unchecked item, implement a small step toward it, then check it off or
leave a note if it needs more steps. ONE SMALL STEP AT A TIME - prefer
edits to existing files (Main.cs, GameWorld.cs, Needs.cs, RoomDetection.cs,
FurnitureCatalog.cs) over new files.

## Guiding mindset
Think like an ultra-critical modern gamer reviewing this build. The player
should be focused on SHAPING THE ENVIRONMENT and reacting to THREATS/EVENTS,
not just watching pawns idle. Every step should produce a VISIBLE change in
the running game (color, text, new tile, new bar, etc).

## URGENT PRIORITY: mining (do this item first)
- [x] Step W.1 - Mining is already implemented (Mine furniture,
      MineWoodCost, MineTicksPerStone, _mineProgress, TryPlanMine() in
      GameWorld.cs Tick) but TryPlanMine() requires Wood >= MineWoodCost
      (20), which the colony's Wood income rarely reaches, so no Mine ever
      gets built in practice. In GameWorld.cs, change the line
      `public const int MineWoodCost = 20;` to
      `public const int MineWoodCost = 10;` so Mines get queued and built
      with the Wood the colony actually accumulates.
- [x] Step W.1b - VERIFIED DEADLOCK (headless 30k-tick sim): Stone stays 0
      forever so walls never get built and no room is ever enclosed. Fix:
      any built Mine must passively produce Stone over time. Do NOT invent
      new methods or enum values - ResourceKind has NO Stone member and
      Furniture has NO ProduceResource method. Stone is simply the existing
      `Stone` int property on GameWorldManager. Make ONE SEARCH/REPLACE
      edit in src/RimWorldLab.Core/GameWorld.cs. SEARCH for exactly this
      one line:
      `        foreach (var mine in _map.Furniture.Where(f => f.Kind == FurnitureKind.Mine))`
      and REPLACE it with exactly these lines (the original line stays,
      with two new lines inserted before it):
      `        if (TotalTicks % 200 == 0 && _map.Furniture.Any(f => f.Kind == FurnitureKind.Mine))`
      `            Stone++;`
      ``
      `        foreach (var mine in _map.Furniture.Where(f => f.Kind == FurnitureKind.Mine))`
- [x] Step W.1c - VERIFIED BUG (headless sim): when a pawn finishes a
      BuildWall task but Wood/Stone ran out while it was walking, the wall
      is silently dropped and never rebuilt - that is why the starter rooms
      never get their walls even after Stone income exists. Fix: put the
      unaffordable wall back on the auto-build plan. In
      src/RimWorldLab.Core/GameWorld.cs make ONE SEARCH/REPLACE edit.
      SEARCH for exactly these 3 contiguous lines (SpendWallCost appears
      only once in the file):
      `                        SpendWallCost();`
      `                        pawn.GainSkill(SkillKind.Construction, 10f);`
      `                    }`
      and REPLACE them with exactly these lines:
      `                        SpendWallCost();`
      `                        pawn.GainSkill(SkillKind.Construction, 10f);`
      `                    }`
      `                    else if (_map.IsPassable(order.TargetX, order.TargetY))`
      `                    {`
      `                        _autoBuildQueue.Add((order.TargetX, order.TargetY, null));`
      `                    }`

## PRIORITY: defeat & rebirth (a dead colony must restart itself)
- [x] Step G.0 - When every pawn is dead the game sits frozen forever; it
      must detect defeat and start a NEW colony automatically (roguelike
      rebirth). In src/RimWorldGodot/Main.cs, find these exact contiguous
      lines:
      `	public override void _Process(double delta)`
      `	{`
      `		_accumulator += delta;`
      and REPLACE them with:
      `	public override void _Process(double delta)`
      `	{`
      `		if (_world.Pawns.Count == 0)`
      `		{`
      `			_world = new GameWorldManager(50, 50);`
      `			string[] rebirth = new string[8] { "Aiden", "Brynn", "Corwin", "Dara", "Elsie", "Finn", "Greta", "Holt" };`
      `			foreach (string name in rebirth)`
      `			{`
      `				int px;`
      `				int py;`
      `				do`
      `				{`
      `					px = _rng.Next(0, _world.Map.Width);`
      `					py = _rng.Next(0, _world.Map.Height);`
      `				}`
      `				while (!_world.Map.IsPassable(px, py));`
      `				_world.RegisterThing(new Pawn(name, px, py));`
      `			}`
      `		}`
      `		_accumulator += delta;`

## PRIORITY: evolving objectives (the game must never feel "finished")
- [x] Step G.1 - The win condition is frozen at "3 functional rooms" forever;
      players need a goal LADDER that keeps evolving. In
      src/RimWorldLab.Core/GameWorld.cs, find this exact line:
      `    public void RefreshRooms() => _rooms = RoomDetector.DetectRooms(_map);`
      Immediately AFTER that line, insert these new lines:
      `    public int GoalIndex { get; private set; } = 0;`
      ``
      `    public string CurrentGoalText => GoalIndex switch`
      `    {`
      `        0 => "Build 3 functional rooms",`
      `        1 => "Grow the colony to 4 pawns",`
      `        2 => "Stockpile 50 Stone",`
      `        3 => "Build 6 functional rooms",`
      `        4 => "Survive to day 100",`
      `        _ => "Colony thriving - endless mode"`
      `    };`
      ``
      `    public void TickGoals()`
      `    {`
      `        bool met = GoalIndex switch`
      `        {`
      `            0 => _rooms.Count(r => r.Function != RoomFunction.Empty) >= 3,`
      `            1 => _pawns.Count(p => p.HP > 0) >= 4,`
      `            2 => Stone >= 50,`
      `            3 => _rooms.Count(r => r.Function != RoomFunction.Empty) >= 6,`
      `            4 => DayNumber >= 100,`
      `            _ => false`
      `        };`
      `        if (met) GoalIndex++;`
      `    }`
- [x] Step G.2b - In src/RimWorldGodot/Main.cs, SEARCH for the line `			_world.RefreshRooms();` and REPLACE it with these 4 lines:
- [x] Step G.3 - Show the CURRENT goal instead of the frozen one. In
      src/RimWorldGodot/Main.cs, SEARCH for exactly this ONE full line:
      `		DrawString(ThemeDB.FallbackFont, new Vector2(8f, 18f), $"Day {_world.DayNumber}, {_world.HourOfDay:00}:00   Wood: {_world.Wood}   Stone: {_world.Stone}   Water: {_world.Water}   Goal: 3 functional rooms ({num9}/3)", HorizontalAlignment.Left, -1f, 16, Colors.White, TextServer.JustificationFlag.Kashida | TextServer.JustificationFlag.WordBound, TextServer.Direction.Auto, TextServer.Orientation.Horizontal, 0f);`
      and REPLACE it with exactly this ONE full line:
      `		DrawString(ThemeDB.FallbackFont, new Vector2(8f, 18f), $"Day {_world.DayNumber}, {_world.HourOfDay:00}:00   Wood: {_world.Wood}   Stone: {_world.Stone}   Water: {_world.Water}   Goal: {_world.CurrentGoalText}", HorizontalAlignment.Left, -1f, 16, Colors.White, TextServer.JustificationFlag.Kashida | TextServer.JustificationFlag.WordBound, TextServer.Direction.Auto, TextServer.Orientation.Horizontal, 0f);`
- [x] Step G.4a - In src/RimWorldGodot/Main.cs, replace `if (num9 >= 3)` with `if (_world.GoalIndex > 0)`.

## PRIORITY: deep simulation v1 (Dwarf-Fortress-style pawn minds)
Pawns must DECIDE with reasons (needs, skills, distance), not just pop a
task queue - and stop doing absurd things like building bridges nobody needs.

- [x] Step P.0a - Bridges are built without purpose (nearest water tile,
      forever). Add the missing "reason" flag. In
      src/RimWorldLab.Core/GameWorld.cs, find this exact line:
      `    private bool _bridgeTaskActive = false;`
      Immediately AFTER that line, insert these new lines:
      ``
      `    /// <summary>True when organic expansion found no dry room slot - the only reason to bridge the river.</summary>`
      `    private bool _needsBridgeToExpand = false;`
- [x] Step P.0b - Set the flag where the need is discovered. In
      src/RimWorldLab.Core/GameWorld.cs, find this exact line:
      `        if (bestSlot < 0) return;`
      and REPLACE it with these lines:
      `        if (bestSlot < 0)`
      `        {`
      `            _needsBridgeToExpand = true;`
      `            return;`
      `        }`
      `        _needsBridgeToExpand = false;`
- [x] Step P.0c - Only bridge when there is a reason. In
      src/RimWorldLab.Core/GameWorld.cs, inside TryAutoBridge, find this
      exact line (the one WITHOUT `false`, not the one in QueueBuildBridge):
      `        if (Wood < BridgeWoodCost) return;`
      and REPLACE it with these lines:
      `        if (!_needsBridgeToExpand) return;`
      `        if (Wood < BridgeWoodCost) return;`
- [x] Step P.1 - Pawns must pick the BEST task for them, not the first one.
      In src/RimWorldLab.Core/Jobs.cs, find these exact contiguous lines
      (the end of TryClaimNext and the closing brace of class TaskBoard):
      `            return task;`
      `        }`
      ``
      `        return null;`
      `    }`
      `}`
      and REPLACE them with:
      `            return task;`
      `        }`
      ``
      `        return null;`
      `    }`
      ``
      `    /// <summary>Claims the best task for THIS pawn: priority first, then skill affinity, then distance.</summary>`
      `    public TaskOrder TryClaimBest(Pawn pawn)`
      `    {`
      `        TaskOrder best = null;`
      `        double bestScore = double.MinValue;`
      `        foreach (var task in _pending)`
      `        {`
      `            if (task.Kind.IsMovementTask() && IsTileReserved(task.TargetX, task.TargetY))`
      `                continue;`
      `            double score = task.Priority * 10.0;`
      `            score -= Math.Abs(task.TargetX - pawn.X) + Math.Abs(task.TargetY - pawn.Y);`
      `            if ((task.Kind == TaskKind.Build || task.Kind == TaskKind.BuildWall || task.Kind == TaskKind.BuildBridge) && pawn.SkillXP.TryGetValue(SkillKind.Construction, out float cxp))`
      `                score += cxp / 100.0;`
      `            if (task.Kind == TaskKind.Harvest && pawn.SkillXP.TryGetValue(SkillKind.Woodcutting, out float wxp))`
      `                score += wxp / 100.0;`
      `            if (score > bestScore) { bestScore = score; best = task; }`
      `        }`
      `        if (best == null) return null;`
      `        _pending.Remove(best);`
      `        if (best.Kind.IsMovementTask())`
      `            ReserveTile(best.TargetX, best.TargetY);`
      `        return best;`
      `    }`
      `}`
- [x] Step P.2 - In src/RimWorldLab.Core/GameWorld.cs, add the method `TryClaimBest(Pawn pawn)` if it doesn't exist.
- [x] Step P.3 - Pawns need an inner life: a Mood. In
      src/RimWorldLab.Core/GameWorld.cs, find this exact line:
      `    public float Hunger { get; set; } = 0f;`
      Immediately AFTER that line, insert these new lines:
      ``
      `    /// <summary>0 (miserable) to 100 (happy). Driven by needs and events.</summary>`
      `    public float Mood { get; set; } = 70f;`
- [ ] Step P.1b - Implement the `TryClaimBest` method in the `TaskBoard` class by adding the following lines after the existing `TryClaimNext` method:
- [ ] Step P.2b - Add the `_pending` list to `TaskBoard` (src/RimWorldLab.Core/Jobs.cs).
- [x] Step P.3b - The Pawn class lives in src/RimWorldLab.Core/GameWorld.cs
      (there is NO Pawn.cs file). SEARCH for exactly this one line:
      `    public float Hunger { get; set; } = 0f;`
      and REPLACE it with exactly these 4 lines:
      `    public float Hunger { get; set; } = 0f;`
      ``
      `    /// <summary>0 (miserable) to 100 (happy). Driven by needs and events.</summary>`
      `    public float Mood { get; set; } = 70f;`
- [x] Step P.4b - Mood dynamics. In src/RimWorldLab.Core/GameWorld.cs,
      SEARCH for exactly this one line:
      `            Needs.Tick(this, driver, pawn, _rng);`
      and REPLACE it with exactly these 2 lines:
      `            Needs.Tick(this, driver, pawn, _rng);`
      `            pawn.Mood = Math.Clamp(pawn.Mood + (pawn.Hunger > 70f ? -0.01f : 0.002f) + (pawn.HP < 50f ? -0.01f : 0f), 0f, 100f);`
- [ ] Step P.5b - In src/RimWorldGodot/Main.cs, append the mood value to the existing DrawString call by appending it to the string. Use the format "Mood: {pawn.Mood}" where "pawn" is the first pawn in the world's pawns list. Ensure the string interpolation is correctly formatted. Only add the mood part, not the whole string.

## CURRENT FOCUS: UI cleanup (small, safe steps)

- [x] Step A - "Rooms" tab removed; its content is now a "ROOMS" section at
      the bottom of the "Colony" tab, only drawn when at least one
      non-Empty room exists. Tab bar is now Colony/Build/Dev (3 tabs).
- [x] Step B - Map hover tooltip implemented: hovering any tile shows a
      black box with pawn+task, furniture name/category, resource, zone,
      room function, and floor/wall - via `DrawMapTooltip`.
- [x] Step C - Dev tab now reads DEV_LOG.md and shows "X kept / Y reverted"
      plus the last 6 entries (green=kept, red=reverted), so the
      autonomous loop's activity is visible to the player.
- [x] Step D - Dev tab now shows a sparkline of roadmap done-count sampled
      once per second (last 120 samples) under the progress bar.

## Next: combat & defense depth

- [x] Step K - Already covered: in the raider combat tick (Main.cs), any
      pawn adjacent to a raider already deals 8 dmg back to it each combat
      tick (mutual damage), regardless of the pawn's current task.
- [x] Step L - Raider variety: 1/3 spawns are "Brute" (HP 60, dmg 10, half
      speed, purple, larger sprite + label) vs normal Raider (HP 30, dmg 5).
- [x] Step M - Dead pawns (HP<=0) are now removed from
      GameWorldManager.Pawns/Registry/drivers each tick (GameWorld.cs
      Tick()), so the Colony tab pawn list shrinks permanently.
- [x] Step N - Digging a player-built wall (non-border) or removing
      Structural furniture with the Dig tool now refunds 1 Wood each.

## DONE (this round): real construction system
- [x] Placing furniture (tool 7) no longer instantly places it - it now
      queues a `Build` task (GameWorldManager.QueueBuild). The nearest idle
      pawn walks to the tile and places it (GameWorldManager.Tick handles
      Build completion, deducting Wood for Structural items). Queued/
      in-progress builds show as a translucent ghost outline on the map.
      Wood is now tracked on GameWorldManager.Wood (was a local Main.cs
      field) so both player tools and the build queue share one pool.

## DONE (this round): autonomous starter-colony plan
- [x] On startup, GameWorldManager.SetupAutoColonyPlan() lays out 3 walled
      5x5 rooms (Bedroom with a Bed, Kitchen with Stove+Workbench, Dining
      Room with Table+Chair), each with a Door gap, and queues their
      furniture as Build tasks (one new build drip-fed every ~3s). Idle
      pawns automatically walk to these sites and construct them - the
      colony now plans and builds its own base, giving purpose to Wood and
      furniture, and should trigger the existing "3 functional rooms" win
      condition once all three are built.

## DONE (this round): pawn-built walls, storage, auto-harvest
- [x] Walls are no longer pre-placed: every perimeter tile (except the
      door gap) is queued as a new `TaskKind.BuildWall`. A pawn walks to a
      tile ADJACENT to the wall tile (since it becomes solid once built)
      and turns it solid for 1 Wood. Ghost ouline (grey) shows pending/
      in-progress wall tiles on the map.
- [x] Each starter room now also queues a Crate (Storage category) -
      pawns build a storage spot per room.
- [x] Auto-harvest: new `TaskKind.Harvest` - whenever Wood < 8 and no
      harvest is pending, the nearest Tree is queued; a pawn walks to it
      and chops it for +1 Wood (GameWorld.Tick). Keeps the autonomous
      build queue funded without player intervention.

## NEXT: visuals via real assets
- [x] Step U.1 - User-provided KayKit CC0 packs (furniture, nature,
      resources, restaurant/kitchen, RPG tools, dungeon, characters,
      skeletons) extracted as .gltf/.glb into
      `src/RimWorldGodot/assets/models/`, with a manifest at
      `src/RimWorldGodot/assets/asset_manifest.json` mapping every
      FurnitureKind, ResourceNode type, pawn, and raider variant to a
      specific model file (plus biome hints for the future region map).
- [x] Step U.2 - REVERTED/NOT ACTUALLY DONE (re-checked: Main.cs has no
      SubViewport/Camera3D/TreeViewport, Main.tscn has no such nodes,
      Tree is still drawn as a flat brown rect + green triangle in
      Main.cs._Draw). The 3D-SubViewport-per-model plan was too big for
      the local model to ever build successfully (every attempt reverted)
      and also requires editing Main.tscn, which the dev loop can't patch.
      DROPPED in favor of the pure-C# 2D icon plan below (U.3.x).
- [x] Step U.3.1 - DONE (verified in code): Rock resources now draw DrawCircle + 3 darker grey DrawColoredPolygon facets in Main.cs._Draw (lines ~824-847).
- [x] Step U.3.2 - In src/RimWorldGodot/Main.cs, find this exact line:
      `				DrawRect(rect2, Colors.White, filled: false, 1f);`
      (it is inside `foreach (Furniture item in map.Furniture)`, right
      before the existing `if (item.Kind == FurnitureKind.Crate)` block).
      Immediately AFTER that line, insert these new lines:
      `				if (item.Kind == FurnitureKind.Bed)`
      `				{`
      `					DrawRect(new Rect2(rect2.Position.X + rect2.Size.X - 4f, rect2.Position.Y, 4f, 4f), new Color(0.9f, 0.9f, 0.95f));`
      `				}`
- [x] Step U.3.3 - In src/RimWorldGodot/Main.cs, find this exact block:
      `				if (item.Kind == FurnitureKind.Crate)`
      `				{`
      `					DrawLine(rect2.Position, rect2.Position + rect2.Size, Colors.White, 1f);`
      `					DrawLine(new Vector2(rect2.Position.X + rect2.Size.X, rect2.Position.Y), new Vector2(rect2.Position.X, rect2.Position.Y + rect2.Size.Y), Colors.White, 1f);`
      `				}`
      Immediately AFTER that block, insert these new lines:
      `				if (item.Kind == FurnitureKind.Stove)`
      `				{`
      `					DrawRect(new Rect2(rect2.Position.X + rect2.Size.X / 2f - 2f, rect2.Position.Y + rect2.Size.Y / 2f - 2f, 4f, 4f), new Color(0.2f, 0.2f, 0.2f));`
      `					DrawLine(new Vector2(rect2.Position.X + rect2.Size.X / 2f, rect2.Position.Y), new Vector2(rect2.Position.X + rect2.Size.X / 2f, rect2.Position.Y - 4f), new Color(0.6f, 0.6f, 0.6f), 1f);`
      `				}`
- [x] Step U.3.4 - In src/RimWorldGodot/Main.cs, find this exact line:
- [x] Step U.3.5 - In src/RimWorldGodot/Main.cs, find this exact line:
      `					DrawRect(new Rect2(rect2.Position.X + rect2.Size.X - 4f, rect2.Position.Y + rect2.Size.Y - 4f, 3f, 3f), new Color(0.7f, 0.7f, 0.7f));`
      (it is inside the new `if (item.Kind == FurnitureKind.Workbench)` block).
      Immediately AFTER the closing `}` of that `if (item.Kind == FurnitureKind.Workbench)`
      block, insert these new lines:
      `				if (item.Kind == FurnitureKind.DiningTable)`
      `				{`
      `					DrawRect(new Rect2(rect2.Position.X + rect2.Size.X / 2f - 2f, rect2.Position.Y + rect2.Size.Y / 2f - 2f, 4f, 4f), new Color(0.85f, 0.85f, 0.7f));`
      `				}`
- [x] Step U.3.6 - In src/RimWorldGodot/Main.cs, find this exact line:
      `					DrawRect(new Rect2(rect2.Position.X + rect2.Size.X / 2f - 2f, rect2.Position.Y + rect2.Size.Y / 2f - 2f, 4f, 4f), new Color(0.85f, 0.85f, 0.7f));`
      (it is inside the new `if (item.Kind == FurnitureKind.DiningTable)` block).
      Immediately AFTER the closing `}` of that `if (item.Kind == FurnitureKind.DiningTable)`
      block, insert these new lines:
      `				if (item.Kind == FurnitureKind.Chair)`
      `				{`
      `					DrawRect(new Rect2(rect2.Position.X, rect2.Position.Y, rect2.Size.X, 2f), new Color(0.4f, 0.3f, 0.2f));`
      `				}`
- [x] Step U.3.7 - In src/RimWorldGodot/Main.cs, find this exact line:
      `					DrawRect(new Rect2(rect2.Position.X, rect2.Position.Y, rect2.Size.X, 2f), new Color(0.4f, 0.3f, 0.2f));`
      (it is inside the new `if (item.Kind == FurnitureKind.Chair)` block).
      Immediately AFTER the closing `}` of that `if (item.Kind == FurnitureKind.Chair)`
      block, insert these new lines:
      `				if (item.Kind == FurnitureKind.Door)`
      `				{`
      `					DrawLine(new Vector2(rect2.Position.X, rect2.Position.Y + rect2.Size.Y / 2f), new Vector2(rect2.Position.X + rect2.Size.X, rect2.Position.Y + rect2.Size.Y / 2f), new Color(0.6f, 0.4f, 0.2f), 2f);`
      `				}`
- [x] Step U.3.8 - In src/RimWorldGodot/Main.cs, find this exact line:
      `				DrawRect(rect2, Colors.White, filled: false, 1f);`
      (it is the last line inside `foreach (Furniture item in map.Furniture)`).
      Immediately AFTER that line, insert these new lines:
      `				if (item.Kind == FurnitureKind.Crate)`
      `				{`
      `					DrawLine(rect2.Position, rect2.Position + rect2.Size, Colors.White, 1f);`
      `					DrawLine(new Vector2(rect2.Position.X + rect2.Size.X, rect2.Position.Y), new Vector2(rect2.Position.X, rect2.Position.Y + rect2.Size.Y), Colors.White, 1f);`
      `				}`
- [x] Step U.4.1 - In src/RimWorldGodot/Main.cs, find this exact line:
      `				DrawRect(rect6, color5);`
      (it is inside the `for (int num6 = 0; num6 < _world.Pawns.Count; num6++)`
      pawn-drawing loop). Immediately AFTER that line, insert this new line:
      `				DrawRect(new Rect2(pawn.X * 16 + 4, pawn.Y * 16 + 1, 8f, 4f), color5 * 0.6f);`
- [x] Step U.4.2 - In src/RimWorldGodot/Main.cs, find this exact line:
      `			DrawRect(rect5, raider.IsBrute ? new Color(0.5f, 0.05f, 0.5f) : new Color(0.85f, 0.1f, 0.1f));`
      (it is inside the `foreach (Raider raider in _raiders)` drawing loop).
      Immediately AFTER that line, insert this new line:
      `			DrawRect(new Rect2(rect5.Position.X + rect5.Size.X / 2f - 2f, rect5.Position.Y + 1f, 4f, 4f), raider.IsBrute ? new Color(0.3f, 0.0f, 0.3f) : new Color(0.5f, 0.05f, 0.05f));`
- [x] Step U.5 - Polish pass once U.3.x/U.4.x are done: review the new
      icon shapes for consistent scale/contrast across resources,
      furniture and pawns, and tweak colors/sizes for readability. Small,
      single-shape tweaks only - one per dev-loop iteration.

## VISION 2: hexagonal grid + planet-scale region map
This is a FOUNDATION change (touches GameMap, Pathfinder, Main.cs._Draw,
and every system using X/Y tile coords) - too big for one dev-loop step.
Break into small, sequential, individually-buildable steps. Do NOT start
step N+1 until N builds and runs correctly.

- [x] Step V.1 - Added `HexCoord` (axial Q,R) in `HexGrid.cs`: Neighbors(),
      ToPixel/FromPixel for pointy-top hexes, DistanceTo. Pure helper, not
      yet wired into GameMap/Pathfinder/rendering - existing square-grid
      game is untouched.
- [x] Step V.2 - Add a `GridShape` property to GameMap with a default value of "Square".
- [x] Step V.3 - Main.cs._Draw: when GridShape==Hex, draw each tile as a
      flat-top hexagon (DrawColoredPolygon with 6 points from HexToPixel)
      instead of a square Rect2. Update click-to-tile (PixelToHex) in
      _UnhandledInput. Switch the default map to Hex once this renders
      correctly and pawns path/move visibly on the hex grid.
- [x] Step V.4 - Planet/region map: add a new class `RegionMap` with a private field `List<(int X, int Y, string Biome)> _regions` in `src/RimWorldLab.Core/RegionMap.cs`.
- [ ] Step V.5.1 - Add the `IsAtEdge` method signature in `GameWorld.cs`.

## VISION: push toward "best version of this game" (atmosphere + emergence)

A true 3D isometric engine is out of scope (would require rewriting the
renderer from Node2D to a 3D/iso pipeline) - but we CAN make the current
2D view feel much more alive and add emergent mechanics. Small steps:

- [x] Step O - Atmosphere: subtle grid lines drawn over all tiles, plus a
      warm radial glow around Lighting-category furniture that appears at
      night (drawn over the darkness overlay).
- [ ] Step P1 - Add a `Mood` float (0-100) to Pawn class in `src/RimWorldLab.Core/Pawn.cs`.
- [x] Step Q1 - Add a method to check if a pawn is at the edge of the current region's hex map in GameWorld.cs.
- [x] Step R - Weather: every few in-game days, toggle a "Rain" state that
      tints the map blue-grey and slightly slows pawn movement; show
      "Raining" in the header.
- [x] Step S - Ambient sound hooks: add an `AudioStreamPlayer` node that
      plays a soft loop, with volume dipping during raids (purely additive,
      skip if no audio asset available - log a TODO instead of failing).
- [x] Step T (partial) - Furniture now draws a soft drop-shadow (offset
      dark rect). TODO: extend the same shadow treatment to pawns and
      raiders for full consistency.

## After UI cleanup: core gameplay loop

- [x] Step E - Day/night cycle implemented: GameWorldManager.TotalTicks ->
      DayNumber/HourOfDay (1 day = 1000 ticks). "Day N, HH:00" shown
      top-left of the map; dark overlay fades in 20:00-06:00.
- [x] Step F - Random events: every ~60-120s a Raider spawns at a random
      map edge and walks toward the nearest pawn, with a "RAIDERS
      INCOMING!" banner.
- [x] Step G - Basic combat: Pawn.HP (default 100), raiders and pawns
      damage each other on contact (raider HP=30). HP bars shown for
      damaged pawns/raiders; banners on death/defeat.
- [x] Step H - Resource cost: chopping a Tree gives +1 Wood (start with 5),
      building walls / Structural furniture costs 1 Wood (blocked at 0).
      Wood count shown in the map header.
- [x] Step I - Win condition: header shows "Goal: 3 functional rooms (X/3)";
      a green banner "OBJECTIVE COMPLETE" appears once
      `GetRooms().Count(r => r.Function != Empty) >= 3`.
- [x] Step J - Already covered by existing PawnTaskDriver.Step: when
      TryMove fails mid-path (e.g. a new wall blocks the next tile), the
      task is marked Failed and released, so the pawn goes idle and picks
      a new task next tick instead of getting stuck.
- [x] Step K - Renewable trees: chopping a Tree drops 0-2 seeds onto nearby
      plantable tiles (GameMap.AddSapling); each sapling grows back into a
      Tree after 1 in-game week (7000 ticks, GameMap.TickSaplings, called
      from GameWorldManager.Tick). Saplings render as small green dots.
- [x] Step L - Real consequences for needs and the resource loop: a maxed
      Hunger or Fatigue (100) now drains HP (NeedRates.StarvationDamage
      PerTick) - a neglected pawn can starve/collapse and die. Wood
      auto-harvest target raised 8 -> 30 with up to 2 trees queued at once
      so chopping (and tree regrowth) actually keeps happening instead of
      stalling forever once Wood hit the old cap. Population growth: a new
      Settler joins every 3 in-game days if Wood >= 5 and pop < 12.
- [x] Step M - Fixed the auto-build queue getting permanently stuck: a
      regrown sapling (Step K) could land inside a planned room footprint
      and block the FIFO queue forever (only 1-2 walls ever got built).
      GameMap.MarkNoGrow now excludes every planned-room tile from
      sapling placement, and a build-queue item that still fails to queue
      is moved to the back instead of blocking everything behind it.

- [x] Step N2 - Pawns/Skills/Stone overhaul: pawns now have a `Sex` (M/F,
      shown on their Colony card) and per-pawn Skills (Construction,
      Mining, Woodcutting) that gain XP (and level up) from completing
      the matching task - shown as "Skill: Lv N" on each pawn card.
      Rocks are now actually harvested: chopping a Rock gives +1 Stone
      (auto-mine keeps a Stone stockpile flowing like Wood) and trains
      Mining. Walls now cost 2 Wood + 1 Stone to build (digging one up
      refunds half, rounded down), shown in the header as
      "Wood: X   Stone: Y". Population growth additionally requires a
      free Bed (1 bed per pawn) before a new Settler joins.

- [x] Step N3 - Mines: a new "Mine" Production furniture (build cost 20
      Wood) can be placed; any pawn standing on/adjacent to a built Mine
      counts as a worker, and each worker accumulates toward +1 Stone
      every 5 seconds (100 ticks) - multiple workers stack in parallel,
      and mining trains the Mining skill.
- [x] Step N4 - Autonomous dev loop fixed: scripts/dev_loop.ps1 was
      sandboxed to only ever write to src/RimWorldLab.Core and built/ran
      the console RimWorldLab project, while the current roadmap focus
      (Step U.x) requires editing src/RimWorldGodot/Main.cs - causing
      ~190/200 reverted iterations. Now Resolve-TargetPath allows
      Main.cs in RimWorldGodot, Invoke-Build builds via the Godot project
      (dotnet build -c ExportRelease, validates both projects), and the
      prompt feeds Main.cs content (instead of Jobs.cs) when the first
      unchecked roadmap item is a Step U.x / UI item.

- [x] Step N5 - Personal furniture & terrain economy: Bed and Chair are
      now assigned to a living pawn for life (GameMap.Furniture is
      mutable with OwnerId, freed when the owner dies, reassigned every
      50 ticks via AssignPersonalFurniture). A diagonal river of
      impassable Water tiles now crosses the map (rendered blue); pawns
      periodically haul +1 Water from the riverbank (TaskKind.HaulWater),
      shown in the header alongside Wood/Stone. Build queue is now
      self-correcting: when a wall/build can't afford its Wood/Stone
      cost, EmergencyGather immediately sends a pawn after the missing
      resource. Once the starter 3 rooms are done and Wood/Stone allow
      it, TryPlanOrganicRoom plans an extra Bedroom (more beds -> more
      population) - the colony keeps expanding organically.

- [x] Step N6 - Bridges & water-aware expansion: the river was a 2-tile
      diagonal band with no crossing, splitting the map in two and
      stranding several organic-room slots on the far bank (idle pawns).
      Added GameMap._bridges + AddBridge/HasBridge, IsPassable now treats
      bridged Water tiles as passable, and a new TaskKind.BuildBridge
      (3 Wood, walks adjacent then builds). TryAutoBridge() runs every 500
      ticks and queues the nearest un-bridged Water tile to the colony
      center that has a passable neighbor - bridges grow toward the river
      organically as Wood allows, no hardcoded crossing point. Bridges
      render as a brown tile over the water. TryPlanOrganicRoom now skips
      any 5x5 slot whose footprint overlaps Water, scanning forward up to
      36 slots instead of blindly using the next grid slot - rooms no
      longer get planned inside the river.

## NEXT: deeper village simulation (per latest player feedback)
- [x] Step W.0 - Meals & cooking: Stove (already buildable) consumes raw
      Food to produce 4 Meals per cook cycle, and requires an idle pawn
      to staff it (a "Cook" task, gated on a Food resource from W.3).
      Eating a Meal restores Hunger faster than the current direct
      recovery. Needs Step W.3 (Food resource) first.
- [ ] Step W.7.1.1 - Add properties for Wood, Stone, Food, Metal, Tools, and ResearchPoints to the GameWorld class.
- [ ] Step W.8a - Add missing resource fields (Wood, Stone, Food, Metal, Tools) to GameWorld.cs.

## Ecology & survival loop (next major arc)

The colony currently has an infinite map of Trees/Rocks and no real
pressure beyond raiders. To make this a proper "easy to learn, hard to
master" loop, work through these in order - each is independently testable:

- [x] Step W.2 - Water tiles: add Cell.TileType "Water" patches to
      GameMap.InitializeMap (a few lakes/rivers). Water tiles are
      impassable but a pawn can "Haul Water" from an adjacent tile to a
      Canteen/Crate, producing a new "Water" resource counter.
- [ ] Step W.3.1 - Add Food resource: Define a new resource `Food` in `GameWorld.cs` with an initial value of 0.
- [ ] Step W.4.1.1 - Add a method to create a new herbivore pawn with a specific type (e.g., "Boar") at a random location on the map.
- [x] Step W.5 - Tie it together: Wood/Stone/Water/Food become the four
      core resources shown in the header; rooms/furniture upkeep can start
      consuming them slowly so the colony must keep the loop running
      (forage/farm/hunt/mine) rather than just building once and idling.

## Done
- Player click-to-select + right-click order (Main.cs _UnhandledInput)
- Zone system (GameWorld.cs, Needs.cs) - Canteen/SleepingQuarters,
  player-placed via tools 5/6
- Scattered Tree/Rock resource nodes
- Build/Dig/Chop tools (tools 2/3/4), open-terrain map (no pre-built base)
- UI: side panel with header, tabs (Colony/Build/Rooms/Dev), per-pawn cards
- Room detection (RoomDetection.cs, flood-fill, capped at 400 tiles, run
  1x/sec) + RoomFunction classification (Bedroom/Dormitory/Kitchen/DiningRoom)
  + tinted overlay on the map
- Furniture catalog: 120 items across 10 categories (FurnitureCatalog.cs),
  tool 7 = Place Furniture, "Build" tab = clickable category grid with
  tooltips and mouse-wheel scrolling
- Dev tab: roadmap progress bar + done/next lists parsed from this file
- [x] Step E.7 - Add a method to randomly generate small animal populations in GameWorld.cs
- [ ] Step E.12.1 - Add a constructor to the Pawn class that accepts 5 parameters: name, x, y, sex, and skills.
- [ ] Step E.21 - Add a constructor to the `Pawn` class that accepts four parameters: name, x, y, and sex. (src/RimWorldLab.Core/Pawn.cs)
- [ ] Step E.27a - Add a method to randomly generate a single small animal in GameWorldManager.cs (src/RimWorldLab.Core/GameWorld.cs) by creating a new Pawn and adding it to the list of pawns without using the registry.
- [ ] Step E.33 - Add a method to randomly generate small animal populations in GameWorldManager.cs (src/RimWorldLab.Core/GameWorld.cs) - Ensure the Pawn constructor is called with the correct number of arguments. (Verify the correct number of arguments for the Pawn constructor.)
- [x] Step E.39 - Implement a simple weather system that affects resource availability in src/RimWorldLab.Core/GameWorld.cs
- [ ] Step C.15.1 - Implement a method to check if a tile is part of a room in the colony. (src/RimWorldLab.Core/GameWorld.cs) - Add a new method signature for checking if a tile is part of a room.
- [ ] Step C.30 - Implement basic room detection logic in GameWorld.cs by adding a method to check if a cell is adjacent to another cell. Start by adding a method signature for IsAdjacent.
- [x] Step C.45 - Add a basic room detection system to identify functional rooms in GameWorld.cs by defining a method to check if a given tile is part of a room.
- [x] Step C.60 - Add properties X and Y to the Cell class. (src/RimWorldLab.Core/GameWorld.cs)
- [ ] Step C.75.1 - Ensure the Cell class in GameWorld.cs has properties X and Y defined only once.
- [ ] Step C.15 - Implement a basic room detection system to identify functional rooms in GameWorld.cs
- [ ] Step C.45 - Implement basic room detection to track functional rooms in GameWorld.cs
- [ ] Step C.60 - Implement room detection and validation logic in GameWorld.cs to ensure functional rooms are counted towards win conditions.
- [ ] Step C.75 - Implement a basic room detection system in GameWorld.cs to count functional rooms.
- [ ] Step C.90 - Implement a basic room detection system in GameWorld.cs to identify functional rooms based on connected walkable tiles.
- [ ] Step C.105 - Implement a basic room detection system to count functional rooms and trigger win condition in GameWorld.cs
- [ ] Step C.135 - Implement a basic room detection system to count functional rooms and track progress towards win conditions in GameWorld.cs
- [ ] Step C.15 - Implement a system to generate functional rooms automatically to meet the win condition.
- [ ] Step C.15 - Implement a basic room detection algorithm in GameWorld.cs to identify functional rooms.
- [ ] Step C.30 - Implement basic room detection logic in GameWorld.cs to identify functional rooms.
- [ ] Step C.45 - Implement basic room detection to ensure players can achieve the win condition.
- [ ] Step C.60 - Implement a basic room detection system to count functional rooms and update the win condition logic.
- [ ] Step C.75 - Implement basic room detection logic to identify functional rooms in the colony.
- [ ] Step C.90 - Implement a basic room detection system in GameWorld.cs to identify functional rooms.

## CONTINUATION RULES AFTER THE 3D SUPERPASS (2026-06-11)
The game is now 3D (Boot3D.tscn + Game3D.cs + UiShell.cs + RenderCatalog.cs).
- UiShell.cs, Boot3D.tscn and RenderCatalog.cs are FROZEN (docs/UI_FREEZE_CONTRACT.md);
  the dev loop rejects patches against them.
- Extend gameplay in src/RimWorldLab.Core/GameWorld.cs, WorldModel.cs, Jobs.cs,
  Needs.cs - everything those expose appears automatically in HUD/dev tab.
- Threat/visual behaviors live in src/RimWorldGodot/Game3D.cs (open to patches).
- The old 2D Main.cs/Main.tscn are LEGACY: do not extend them anymore.

- [ ] Step Z.1 - In src/RimWorldLab.Core/WorldModel.cs, ExternalSite has a
      TradeDemand but nothing sells goods yet. Add to GameWorldManager (in
      src/RimWorldLab.Core/GameWorld.cs) a periodic trade: every 4000 ticks,
      if Tools >= 2 and Macro.TradeDemand > 0.5f, remove 2 Tools, add 8 Food
      and call LogEvent("Caravan trade: 2 tools sold for 8 food.").
- [ ] Step Z.2 - Wildlife pressure: in src/RimWorldLab.Core/WorldModel.cs,
      add a float WildlifePressure (0..1) to WorldRegion, drift it in
      UpdateRegions, and surface a WorldEvents entry when it exceeds 0.8.
- [ ] Step Z.3 - Memories of construction: in GameWorld.cs, when a Build task
      completes (the PlaceFurniture branch in Tick), call
      pawn.Remember(TotalTicks, $"built a {kind}", +1.5f).
- [ ] Step C.15 - Implement a system to automatically generate functional rooms to meet the win condition.
- [ ] Step C.60 - Implement a system to automatically generate functional rooms to ensure win conditions can be reached.
- [ ] Step C.75 - Implement a system to automatically generate functional rooms to meet the win condition, ensuring player progress is not hindered by resource scarcity. (GameWorld.cs)
- [ ] Step C.90 - Implement a room detection system to identify functional rooms in the colony.
- [ ] Step C.120 - Implement a system to automatically generate functional rooms based on furniture placement in GameWorld.cs
- [ ] Step C.15 - Implement a system to generate resources over time to encourage sustainable resource management.
- [ ] Step C.30 - Implement a resource generation system to ensure players have access to materials over time, improving sustainability and reducing frustration. (GameWorld.cs)
- [ ] Step C.45 - Implement a system to generate resources over time, such as trees regrowing or rocks respawning, to provide a steady stream of materials for the player to use. (GameWorld.cs)
- [ ] Step C.60 - Implement a system to generate resources over time to encourage sustainable colony management. (GameWorld.cs)
- [ ] Step C.90 - Implement a resource consumption system that forces players to manage their colony's needs, such as food and shelter, to progress. (GameWorld.cs)
- [ ] Step C.105 - Implement a system to automatically generate functional rooms as pawns complete tasks, ensuring the win condition is reachable through gameplay.
- [ ] Step C.180 - Implement a resource management system to ensure players gather and store resources efficiently.
