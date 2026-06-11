using System;
using System.Diagnostics;

class Program
{
    static void Main(string[] args)
    {
        // Headless diagnostic mode: replicate the Godot game's exact world
        // setup (50x50, 8 pawns, seed 12345) and tick it N times, reporting
        // colony progress - used to verify pawns actually finish the
        // auto-planned starter rooms. Usage: dotnet run -- --diag [ticks]
        if (Array.IndexOf(args, "--diag") >= 0)
        {
            int ticks = 20000;
            int idx = Array.IndexOf(args, "--diag");
            if (idx + 1 < args.Length && int.TryParse(args[idx + 1], out int t)) ticks = t;
            RunDiagSim(ticks);
            return;
        }

        Console.WriteLine("╔════════════════════════════════════════════╗");
        Console.WriteLine("║  RimWorld Lab - Tick Loop + Game World     ║");
        Console.WriteLine("╚════════════════════════════════════════════╝");
        Console.WriteLine("");

        // Run tests first
        GameWorldTests.RunAllTests();

        // Now run the main game loop with live visualization
        RunGameLoop();
    }

    static void RunDiagSim(int totalTicks)
    {
        var world = new GameWorldManager(50, 50);
        var rng = new Random(12345);
        string[] names = { "Aiden", "Brynn", "Corwin", "Dara", "Elsie", "Finn", "Greta", "Holt" };
        foreach (string name in names)
        {
            int x, y;
            do { x = rng.Next(0, world.Map.Width); y = rng.Next(0, world.Map.Height); }
            while (!world.Map.IsPassable(x, y));
            world.RegisterThing(new Pawn(name, x, y));
        }

        Console.WriteLine($"DIAG: ticking {totalTicks} ticks (Godot-equivalent world, seed 12345)");
        for (int i = 1; i <= totalTicks; i++)
        {
            world.Tick();
            if (i % (totalTicks / 10) == 0)
            {
                var pending = world.Tasks.Pending;
                int build = 0, wall = 0, harvest = 0, other = 0;
                foreach (var ta in pending)
                {
                    if (ta.Kind == TaskKind.Build) build++;
                    else if (ta.Kind == TaskKind.BuildWall) wall++;
                    else if (ta.Kind == TaskKind.Harvest) harvest++;
                    else other++;
                }
                int idle = 0;
                foreach (var p in world.Pawns)
                    if (world.GetDriver(p).Current == null) idle++;
                int trees = 0, rocks = 0;
                foreach (var r in world.Map.Resources)
                {
                    if (r.Kind == ResourceKind.Tree) trees++;
                    else if (r.Kind == ResourceKind.Rock) rocks++;
                }
                int builtWalls = 0;
                for (int wy = 1; wy < world.Map.Height - 1; wy++)
                    for (int wx = 1; wx < world.Map.Width - 1; wx++)
                        if (!world.Map.IsPassable(wx, wy) && !world.Map.IsWater(wx, wy)) builtWalls++;
                Console.WriteLine($"[tick {i,6}] Wood={world.Wood,3} Stone={world.Stone,3} pawns={world.Pawns.Count} idle={idle} " +
                    $"furniture={world.Map.Furniture.Count,2} walls={builtWalls} trees={trees} rocks={rocks} pendingTasks: build={build} wall={wall} harvest={harvest} other={other}");
            }
        }

        Console.WriteLine("--- final furniture ---");
        var byKind = new System.Collections.Generic.Dictionary<FurnitureKind, int>();
        foreach (var f in world.Map.Furniture)
            byKind[f.Kind] = byKind.TryGetValue(f.Kind, out int c) ? c + 1 : 1;
        foreach (var kv in byKind)
            Console.WriteLine($"  {kv.Key}: {kv.Value}");

        Console.WriteLine("--- colony area map (rows 1-9, cols 1-23: #=wall ~=water D=door f=furniture .=open) ---");
        for (int my = 1; my <= 9; my++)
        {
            var sb = new System.Text.StringBuilder();
            for (int mx = 1; mx <= 23; mx++)
            {
                var furn = world.Map.Furniture.FirstOrDefault(f => f.X == mx && f.Y == my);
                if (furn != null) sb.Append(furn.Kind == FurnitureKind.Door ? 'D' : 'f');
                else if (world.Map.IsWater(mx, my)) sb.Append('~');
                else if (!world.Map.IsPassable(mx, my)) sb.Append('#');
                else sb.Append('.');
            }
            Console.WriteLine($"  y={my,2} {sb}");
        }

        Console.WriteLine("--- rooms detected ---");
        world.RefreshRooms();
        int functional = 0;
        foreach (var room in world.GetRooms())
        {
            Console.WriteLine($"  {room.Function} ({room.Tiles.Count} tiles)");
            if (room.Function != RoomFunction.Empty) functional++;
        }
        Console.WriteLine($"VERDICT: {functional} functional rooms " +
            (functional >= 3 ? "- WIN CONDITION REACHED" : "- win condition (3 rooms) NOT reached"));
    }

    static void RunGameLoop()
    {
        const int TARGET_TICKS_PER_SEC = 20;
        const int TARGET_TICK_MS = 1000 / TARGET_TICKS_PER_SEC;

        var world = new GameWorldManager(50, 50);

        var rng = new Random(12345);
        char[] symbols = { '@', 'G', 'S', 'A', 'B', 'C', 'D', 'E' };
        string[] names = { "Player", "NPC_Guard", "Scout", "Wanderer", "Hauler", "Builder", "Hunter", "Medic" };

        for (int i = 0; i < names.Length; i++)
        {
            int x, y;
            do
            {
                x = rng.Next(0, world.Map.Width);
                y = rng.Next(0, world.Map.Height);
            } while (!world.Map.IsPassable(x, y));

            world.RegisterThing(new Pawn(names[i], x, y));
        }

        Console.Clear();
        Console.CursorVisible = false;

        var sw = Stopwatch.StartNew();
        int ticks = 0;

        while (true)
        {
            // Keep pawns busy: assign a random passable destination when the board is empty.
            if (world.Tasks.Pending.Count == 0)
            {
                int tx, ty;
                do
                {
                    tx = rng.Next(0, world.Map.Width);
                    ty = rng.Next(0, world.Map.Height);
                } while (!world.Map.IsPassable(tx, ty));

                world.Tasks.Enqueue(new TaskOrder(TaskKind.MoveTo, tx, ty, priority: 5));
            }

            world.Tick();
            ticks++;

            double rate = ticks / (sw.ElapsedMilliseconds / 1000.0 + 0.0001);
            AsciiRenderer.Draw(world, ticks, rate);

            int elapsed = (int)(sw.ElapsedMilliseconds % TARGET_TICK_MS);
            int sleep = TARGET_TICK_MS - elapsed;
            if (sleep > 0)
                System.Threading.Thread.Sleep(sleep);
        }
    }
}
