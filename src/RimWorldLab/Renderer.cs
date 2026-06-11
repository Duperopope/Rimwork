using System;
using System.Text;

// =====================================================================
// Live ASCII renderer: redraws the map + pawns in place each frame.
// =====================================================================

public static class AsciiRenderer
{
    public static void Draw(GameWorldManager world, int tick, double ticksPerSec)
    {
        var map = world.Map;
        var sb = new StringBuilder();

        sb.Append("\x1b[H"); // move cursor to top-left, redraw in place

        sb.AppendLine($"Tick {tick,6}  |  {ticksPerSec,5:F1} ticks/sec  |  pawns: {world.Pawns.Count}   ");
        sb.AppendLine();

        // Build a grid of chars, then stamp pawns on top
        var chars = new char[map.Height, map.Width];
        for (int y = 0; y < map.Height; y++)
            for (int x = 0; x < map.Width; x++)
                chars[y, x] = map.GetCell(x, y).IsSolid ? '#' : '.';

        char[] symbols = { '@', 'G', 'S', 'A', 'B', 'C', 'D', 'E' };
        for (int i = 0; i < world.Pawns.Count; i++)
        {
            var p = world.Pawns[i];
            if (p.X >= 0 && p.X < map.Width && p.Y >= 0 && p.Y < map.Height)
                chars[p.Y, p.X] = symbols[i % symbols.Length];
        }

        for (int y = 0; y < map.Height; y++)
        {
            for (int x = 0; x < map.Width; x++)
                sb.Append(chars[y, x]);
            sb.Append("   "); // clear leftover chars from terminal resize
            sb.AppendLine();
        }

        sb.AppendLine();
        for (int i = 0; i < world.Pawns.Count; i++)
            sb.AppendLine($"{symbols[i % symbols.Length]} = {world.Pawns[i]}                    ");

        Console.Write(sb.ToString());
    }
}
