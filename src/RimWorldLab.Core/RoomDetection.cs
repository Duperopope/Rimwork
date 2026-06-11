using System.Collections.Generic;
using System.Linq;

// =====================================================================
// Room detection: flood-fill enclosed areas and classify them by the
// furniture they contain (RimWorld-style room function).
// =====================================================================

public enum RoomFunction
{
    Empty,
    Bedroom,
    Dormitory,
    Kitchen,
    DiningRoom
}

public class Room
{
    public RoomFunction Function { get; }
    public List<(int X, int Y)> Tiles { get; }

    public Room(RoomFunction function, List<(int X, int Y)> tiles)
    {
        Function = function;
        Tiles = tiles;
    }

    public (int X, int Y) CenterTile
    {
        get
        {
            int sx = 0, sy = 0;
            foreach (var (x, y) in Tiles) { sx += x; sy += y; }
            return (sx / Tiles.Count, sy / Tiles.Count);
        }
    }
}

/// <summary>
/// Detects fully enclosed areas (bounded by walls / Door furniture) and
/// classifies each into a RoomFunction based on the furniture inside it.
/// Flood fill is capped so unbounded outdoor areas are never treated as rooms.
/// </summary>
public static class RoomDetector
{
    private const int MaxRoomTiles = 400;

    public static List<Room> DetectRooms(GameMap map)
    {
        var rooms = new List<Room>();
        var visited = new bool[map.Height, map.Width];

        // Tiles occupied by Structural-category furniture (doors, gates,
        // airlocks, ...) count as "walls" for enclosure purposes, even
        // though pawns can pass through them.
        var doorTiles = new HashSet<(int, int)>(
            map.Furniture.Where(f => FurnitureCatalog.Get(f.Kind).Category == FurnitureCategory.Structural)
                .Select(f => (f.X, f.Y)));

        for (int y = 0; y < map.Height; y++)
        {
            for (int x = 0; x < map.Width; x++)
            {
                if (visited[y, x]) continue;
                if (!map.IsPassable(x, y)) { visited[y, x] = true; continue; }
                if (doorTiles.Contains((x, y))) { visited[y, x] = true; continue; }

                var tiles = FloodFill(map, doorTiles, visited, x, y, out bool enclosed);
                if (enclosed)
                {
                    var function = ClassifyRoom(map, tiles);
                    rooms.Add(new Room(function, tiles));
                }
            }
        }

        return rooms;
    }

    private static List<(int, int)> FloodFill(GameMap map, HashSet<(int, int)> doorTiles, bool[,] visited, int startX, int startY, out bool enclosed)
    {
        var tiles = new List<(int, int)>();
        var stack = new Stack<(int, int)>();
        stack.Push((startX, startY));
        visited[startY, startX] = true;
        enclosed = true;

        int[] dx = { 1, -1, 0, 0 };
        int[] dy = { 0, 0, 1, -1 };

        while (stack.Count > 0)
        {
            var (x, y) = stack.Pop();
            tiles.Add((x, y));

            if (tiles.Count > MaxRoomTiles)
                enclosed = false;

            for (int i = 0; i < 4; i++)
            {
                int nx = x + dx[i];
                int ny = y + dy[i];

                if (nx < 0 || nx >= map.Width || ny < 0 || ny >= map.Height)
                {
                    enclosed = false;
                    continue;
                }

                if (visited[ny, nx]) continue;

                // Walls and doors bound the room without being part of it.
                if (!map.IsPassable(nx, ny) || doorTiles.Contains((nx, ny)))
                {
                    visited[ny, nx] = true;
                    continue;
                }

                visited[ny, nx] = true;
                stack.Push((nx, ny));
            }
        }

        return tiles;
    }

    private static RoomFunction ClassifyRoom(GameMap map, List<(int, int)> tiles)
    {
        var tileSet = new HashSet<(int, int)>(tiles);
        var kinds = map.Furniture.Where(f => tileSet.Contains((f.X, f.Y))).Select(f => f.Kind).ToList();
        var categories = kinds.Select(k => FurnitureCatalog.Get(k).Category).ToList();

        int beds = categories.Count(c => c == FurnitureCategory.Beds);
        bool hasStove = kinds.Contains(FurnitureKind.Stove);
        bool hasWorkbench = kinds.Contains(FurnitureKind.Workbench);
        bool hasTable = categories.Contains(FurnitureCategory.Tables);
        bool hasSeating = categories.Contains(FurnitureCategory.Seating);

        if (hasStove && hasWorkbench) return RoomFunction.Kitchen;
        if (hasTable && hasSeating) return RoomFunction.DiningRoom;
        if (beds >= 2) return RoomFunction.Dormitory;
        if (beds == 1) return RoomFunction.Bedroom;

        return RoomFunction.Empty;
    }
}
