using System;
using System.Diagnostics;

class Program
{
    static void Main()
    {
        Console.WriteLine("╔════════════════════════════════════╗");
        Console.WriteLine("║  RimWorld Lab - Tick Loop Test     ║");
        Console.WriteLine("╚════════════════════════════════════╝");
        Console.WriteLine("");

        const int TARGET_TICKS_PER_SEC = 60;
        const int TARGET_TICK_MS = 1000 / TARGET_TICKS_PER_SEC;

        var sw = Stopwatch.StartNew();
        int ticks = 0;
        int targetMs = 5000; // 5 second test

        Console.WriteLine($"Target: {TARGET_TICKS_PER_SEC} ticks/sec");
        Console.WriteLine($"Running for {targetMs}ms...");
        Console.WriteLine("");

        while (sw.ElapsedMilliseconds < targetMs)
        {
            OnTick(ticks);
            ticks++;

            // Maintain tick rate
            int elapsed = (int)(sw.ElapsedMilliseconds % TARGET_TICK_MS);
            int sleep = TARGET_TICK_MS - elapsed;
            if (sleep > 0)
                System.Threading.Thread.Sleep(sleep);

            if (ticks % 100 == 0)
                Console.WriteLine($"  Tick {ticks} @ {sw.ElapsedMilliseconds}ms");
        }

        sw.Stop();

        Console.WriteLine("");
        Console.WriteLine("Results:");
        Console.WriteLine($"  Total ticks: {ticks}");
        Console.WriteLine($"  Time: {sw.ElapsedMilliseconds}ms");
        Console.WriteLine($"  Rate: {(double)ticks / (sw.ElapsedMilliseconds / 1000.0):F1} ticks/sec");
        Console.WriteLine($"  Memory: {GC.GetTotalMemory(false) / 1024 / 1024} MB");
        Console.WriteLine("");
        
        if ((double)ticks / (sw.ElapsedMilliseconds / 1000.0) >= 55)
            Console.WriteLine("✓ Tick loop is stable!" );
        else
            Console.WriteLine("⚠ Tick loop may be unstable");
    }

    static void OnTick(int tick)
    {
        // Placeholder for game logic
    }
}
