using System;
using System.Collections.Generic;
using System.Linq;

// =====================================================================
// 1. Core Data Structures (Map & Collision)
// =====================================================================

/// <summary>
/// Represents a map of regions on the planet.
/// </summary>
public class RegionMap
{
    private readonly List<(int X, int Y, string Biome)> _regions = new();

    public RegionMap()
    {
        // Initialize with some example regions
        _regions.Add((0, 0, "Forest"));
        _regions.Add((10, 10, "Desert"));
        _regions.Add((20, 20, "Mountain"));
    }

    public List<(int X, int Y, string Biome)> Regions => _regions;
}

/// <summary>
/// Represents a single cell in the 2D map.
/// </summary>
public class Cell
{
    public bool IsSolid { get; set; }
    public string TileType { get; set; } // e.g., "Grass", "Water", "Wall"
    public int X { get; set; }
    public int Y { get; set; }

    public Cell(bool isSolid = false, string tileType = "Ground", int x = 0, int y = 0)
    {
        IsSolid = isSolid;
        TileType = tileType;
        X = x;
        Y = y;
    }
}

/// <summary>
/// Represents a region on the planet map.
/// </summary>
public class Region
{
    public int X { get; }
    public int Y { get; }
    public string Biome { get; }
    public GameMap LocalMap { get; }

    public Region(int x, int y, string biome)
    {
        X = x;
        Y = y;
        Biome = biome;
        // Initialize a small local map for each region
        LocalMap = new GameMap(10, 10); // Example size
    }
}

/// <summary>
/// Kinds of named functional areas pawns can be sent to in order to
/// recover a specific need.
/// </summary>
public enum ZoneKind
{
    Canteen,
    SleepingQuarters
}

/// <summary>
/// A named rectangular area on the map (e.g. a Canteen or Sleeping Quarters)
/// that tasks can target by kind.
/// </summary>
public class Zone
{
    public ZoneKind Kind { get; }
    public int X { get; }
    public int Y { get; }
    public int Width { get; }
    public int Height { get; }

    public Zone(ZoneKind kind, int x, int y, int width, int height)
    {
        Kind = kind;
        X = x;
        Y = y;
        Width = width;
        Height = height;
    }

    public bool Contains(int x, int y) => x >= X && x < X + Width && y >= Y && y < Y + Height;

    /// <summary>Center tile of the zone, used as the default task target.</summary>
    public (int X, int Y) CenterTile => (X + Width / 2, Y + Height / 2);
}

/// <summary>
/// Kinds of static resource nodes scattered across the map for visual
/// variety and future gathering tasks.
/// </summary>
public enum ResourceKind
{
    Tree,
    Rock
}

/// <summary>A single resource node at a fixed map tile.</summary>
public record ResourceNode(ResourceKind Kind, int X, int Y);

/// <summary>A single piece of furniture placed at a fixed map tile. Personal
/// items (Bed, Chair) get assigned to a pawn for life via OwnerId.</summary>
public class Furniture
{
    public FurnitureKind Kind { get; }
    public int X { get; }
    public int Y { get; }
    public Guid? OwnerId { get; set; }

    public Furniture(FurnitureKind kind, int x, int y)
    {
        Kind = kind;
        X = x;
        Y = y;
    }
}

/// <summary>
/// Manages the 2D environment and collision checks.
/// </summary>
public class GameMap
{
    private readonly Cell[,] _grid;
    private readonly List<Zone> _zones = new();
    private readonly List<ResourceNode> _resources = new();
    private readonly List<Furniture> _furniture = new();
    private readonly List<(int X, int Y, int TicksRemaining)> _saplings = new();
    private readonly HashSet<(int X, int Y)> _noGrowTiles = new();
    private readonly HashSet<(int X, int Y)> _bridges = new();
    private bool _isRaining = false;

    private GridShape _gridShape = GridShape.Square;

    public GridShape GridShape
    {
        get => _gridShape;
        set => _gridShape = value;
    }

    public IReadOnlyCollection<(int X, int Y)> Bridges => _bridges;
    public int Width { get; }
    public int Height { get; }
    public IReadOnlyList<Zone> Zones => _zones;
    public IReadOnlyList<ResourceNode> Resources => _resources;
    public IReadOnlyList<Furniture> Furniture => _furniture;
    /// <summary>Tiles where a tree seed has taken root and is growing back into a Tree.</summary>
    public IReadOnlyList<(int X, int Y, int TicksRemaining)> Saplings => _saplings;
    public bool IsRaining => _isRaining;

    public GameMap(int width, int height)
    {
        Width = width;
        Height = height;
        _grid = new Cell[height, width];
        InitializeMap();
    }

public void ToggleRain()
{
    _isRaining = !_isRaining;
    if (_isRaining)
    {
        // Reduce resource availability during rain
        foreach (var resource in _resources.ToList())
        {
            if (resource.Kind == ResourceKind.Tree)
            {
                RemoveResourceAt(resource.X, resource.Y);
            }
        }
    }
}

public void AddZone(Zone zone) => _zones.Add(zone);

public bool IsTilePartOfRoom(int x, int y)
{
    foreach (var zone in _zones)
    {
        if (zone.Contains(x, y))
        {
            return true;
        }
    }
    return false;
}


    /// <summary>
    /// Returns the passable tile closest to (fromX, fromY) inside the nearest
    /// zone of the given kind, or null if no such zone has a passable tile.
    /// </summary>
    public (int X, int Y)? FindNearestZoneTile(ZoneKind kind, int fromX, int fromY)
    {
        Zone? best = null;
        int bestDist = int.MaxValue;
        foreach (var zone in _zones)
        {
            if (zone.Kind != kind) continue;
            var (cx, cy) = zone.CenterTile;
            int dist = Math.Abs(cx - fromX) + Math.Abs(cy - fromY);
            if (dist < bestDist)
            {
                bestDist = dist;
                best = zone;
            }
        }

        if (best == null) return null;

        // Prefer the center tile if passable, otherwise scan the zone for a passable tile.
        var (centerX, centerY) = best.CenterTile;
        if (IsPassable(centerX, centerY)) return (centerX, centerY);

        for (int y = best.Y; y < best.Y + best.Height; y++)
        {
            for (int x = best.X; x < best.X + best.Width; x++)
            {
                if (IsPassable(x, y)) return (x, y);
            }
        }

        return null;
    }

    private void InitializeMap()
    {
        // Open terrain bounded by an outer wall. No pre-built rooms - the
        // player builds their own base using the Build/Dig tools.
        for (int y = 0; y < Height; y++)
        {
            for (int x = 0; x < Width; x++)
            {
                bool isSolid = x == 0 || y == 0 || x == Width - 1 || y == Height - 1;
                _grid[y, x] = new Cell(isSolid, isSolid ? "Wall" : "Grass");
            }
        }

        // Carve a diagonal river across the map - impassable Water tiles
        // pawns must walk along the bank of to haul Water from.
        for (int y = 1; y < Height - 1; y++)
        {
            for (int x = 1; x < Width - 1; x++)
            {
                int diag = x - y;
                // Add a river along the center of the map
                if (y == Height / 2)
                {
                    _grid[y, x] = new Cell(true, "Water");
                }

                // Add lakes at specific coordinates
                if ((x >= Width / 4 && x <= Width / 3 && y >= Height / 4 && y <= Height / 3) ||
                    (x >= 2 * Width / 3 && x < 3 * Width / 4 && y >= 2 * Height / 3 && y < 3 * Height / 4))
                {
                    _grid[y, x] = new Cell(true, "Water");
                }
                

                // Add a lake in the center of the map
                for (int ly = Height / 2 - 3; ly < Height / 2 + 3; ly++)
                {
                    for (int lx = Width / 2 - 3; lx < Width / 2 + 3; lx++)
                    {
                        _grid[ly, lx].IsSolid = true;
                        _grid[ly, lx].TileType = "Water";
                    }
                }

                // Add a river near the bottom of the map
                for (int ry = Height - 5; ry < Height - 3; ry++)
                {
                    for (int rx = 2; rx < Width - 2; rx++)
                    {
                        _grid[ry, rx].IsSolid = true;
                        _grid[ry, rx].TileType = "Water";
                    }
                }

                // Add a few lakes/rivers
                for (int i = 0; i < Width; i++)
                {
                    if ((y == Height / 4 && Math.Abs(x - Width / 2) <= 3) ||
                        (y == Height * 3 / 4 && Math.Abs(x - Width / 2) <= 3))
                    {
                        _grid[y, x].IsSolid = true;
                        _grid[y, x].TileType = "Water";
                    }
                }

                for (int i = 0; i < Height; i++)
                {
                    if ((x == Width / 4 && Math.Abs(y - Height / 2) <= 3) ||
                        (x == Width * 3 / 4 && Math.Abs(y - Height / 2) <= 3))
                    {
                        _grid[y, x].IsSolid = true;
                        _grid[y, x].TileType = "Water";
                    }
                }
            }
        }

        // Scatter resource nodes on passable tiles, avoiding the top-left
        // rooms reserved for the Canteen/Sleeping Quarters zones.
        for (int y = 0; y < Height; y++)
        {
            for (int x = 0; x < Width; x++)
            {
                if (_grid[y, x].IsSolid) continue;
                if (x < 11 && y < 5) continue;

                int hash = (x * 73856093) ^ (y * 19349663);
                int bucket = ((hash % 100) + 100) % 100;
                if (bucket < 4)
                    _resources.Add(new ResourceNode(ResourceKind.Tree, x, y));
                else if (bucket < 6)
                    _resources.Add(new ResourceNode(ResourceKind.Rock, x, y));
            }
        }
    }

    /// <summary>
    /// Checks if a specific coordinate (x, y) is within bounds and not solid.
    /// </summary>
    public bool IsPassable(int x, int y)
    {
        if (x < 0 || x >= Width || y < 0 || y >= Height)
        {
            return false; // Out of bounds
        }

        if (_bridges.Contains((x, y))) return true;

        return !_grid[y, x].IsSolid;
    }

    /// <summary>True if a bridge has been built over the Water tile at (x, y).</summary>
    public bool HasBridge(int x, int y) => _bridges.Contains((x, y));

    /// <summary>Builds a bridge over a Water tile, making it passable while keeping its TileType for rendering.</summary>
    public bool AddBridge(int x, int y)
    {
        if (x < 0 || x >= Width || y < 0 || y >= Height) return false;
        if (!IsWater(x, y)) return false;
        return _bridges.Add((x, y));
    }

    public Cell GetCell(int x, int y)
    {
        if (x >= 0 && x < Width && y >= 0 && y < Height)
        {
            return _grid[y, x];
        }
        throw new IndexOutOfRangeException("Coordinates are outside map bounds.");
    }

    /// <summary>
    /// Player-driven terraforming: build a wall or dig it out at the given tile.
    /// Returns false if the coordinate is out of bounds.
    /// </summary>
    public bool SetSolid(int x, int y, bool solid)
    {
        if (x < 0 || x >= Width || y < 0 || y >= Height)
            return false;

        _grid[y, x].IsSolid = solid;
        _grid[y, x].TileType = solid ? "Wall" : "Grass";
        return true;
    }

    /// <summary>Removes any resource node at the given tile (e.g. chopping a tree). Returns true if one was removed.</summary>
    public bool RemoveResourceAt(int x, int y)
    {
        return _resources.RemoveAll(r => r.X == x && r.Y == y) > 0;
    }

    /// <summary>True if a tile is passable, empty ground with no resource, furniture, or sapling already growing on it.</summary>
public bool IsPlantable(int x, int y)
{
    if (!IsPassable(x, y)) return false;
    if (_resources.Exists(r => r.X == x && r.Y == y)) return false;
    if (_furniture.Exists(f => f.X == x && f.Y == y)) return false;
    if (_saplings.Exists(s => s.X == x && s.Y == y)) return false;
    if (_noGrowTiles.Contains((x, y))) return false;
    return true;
}

public List<Pawn> FindNearbyThreatenedPawns(Pawn pawn, int threatRange)
{
    // Placeholder for actual implementation
    return new List<Pawn>();
}

    /// <summary>Marks a tile as part of the planned colony footprint - seeds will never sprout here.</summary>
    public void MarkNoGrow(int x, int y) => _noGrowTiles.Add((x, y));

    /// <summary>Plants a seed at the given tile that grows into a Tree after the given number of ticks.</summary>
    public void AddSapling(int x, int y, int ticksToGrow) => _saplings.Add((x, y, ticksToGrow));

    /// <summary>Advances every growing sapling by one tick, turning ripe ones into Trees.</summary>
    public void TickSaplings()
    {
        for (int i = _saplings.Count - 1; i >= 0; i--)
        {
            var (x, y, ticksRemaining) = _saplings[i];
            if (ticksRemaining <= 1)
            {
                _saplings.RemoveAt(i);
                if (IsPlantable(x, y))
                    _resources.Add(new ResourceNode(ResourceKind.Tree, x, y));
            }
            else
            {
                _saplings[i] = (x, y, ticksRemaining - 1);
            }
        }
    }

    /// <summary>
    /// Places a piece of furniture at the given tile. Fails if the tile is
    /// solid, already has furniture, or has a resource node on it.
    /// </summary>
    public bool PlaceFurniture(FurnitureKind kind, int x, int y)
    {
        if (!IsPassable(x, y)) return false;
        if (_furniture.Exists(f => f.X == x && f.Y == y)) return false;
        if (_resources.Exists(r => r.X == x && r.Y == y)) return false;

        _furniture.Add(new Furniture(kind, x, y));
        return true;
    }

    /// <summary>Removes any furniture at the given tile. Returns true if one was removed.</summary>
    public bool RemoveFurnitureAt(int x, int y)
    {
        return _furniture.RemoveAll(f => f.X == x && f.Y == y) > 0;
    }

    /// <summary>True if the given tile is a Water tile.</summary>
    public bool IsWater(int x, int y)
    {
        if (x < 0 || x >= Width || y < 0 || y >= Height) return false;
        return _grid[y, x].TileType == "Water";
    }

    /// <summary>Finds the nearest passable tile adjacent to a Water tile, for hauling water.</summary>
    public (int X, int Y)? FindNearestWaterAdjacentTile(int fromX, int fromY)
    {
        (int X, int Y)? best = null;
        int bestDist = int.MaxValue;
        for (int y = 0; y < Height; y++)
        {
            for (int x = 0; x < Width; x++)
            {
                if (!IsPassable(x, y)) continue;
                if (!IsWater(x + 1, y) && !IsWater(x - 1, y) && !IsWater(x, y + 1) && !IsWater(x, y - 1)) continue;

                int dist = Math.Abs(x - fromX) + Math.Abs(y - fromY);
                if (dist < bestDist)
                {
                    bestDist = dist;
                    best = (x, y);
                }
            }
        }
        return best;
    }
}


// =====================================================================
// 2. Entity Classes (Thing Registry & Pawn)
// =====================================================================

/// <summary>
/// Base class for all entities in the game world.
/// </summary>
public abstract class Thing
{
    public Guid Id { get; }
    public string Name { get; set; }

    protected Thing(string name)
    {
        Id = Guid.NewGuid();
        Name = name;
    }
}

/// <summary>Biological sex of a pawn - cosmetic for now (name/portrait), but a
/// hook for future reproduction/relationship mechanics.</summary>
public enum PawnSex
{
    Male,
    Female
}

/// <summary>Skills that improve with practice and speed up related tasks.</summary>
public enum SkillKind
{
    Construction,
    Mining,
    Woodcutting
}

/// <summary>
/// Represents a movable entity with position and collision awareness.
/// </summary>
public class Pawn : Thing
{
    private static readonly Random _sexRng = new();

    public int X { get; set; }
    public int Y { get; set; }
    public int Speed { get; set; } = 1; // Units per tick

    public PawnSex Sex { get; set; }

    /// <summary>XP per skill. Level = XP / 100 (uncapped); higher level speeds up related tasks.</summary>
    public Dictionary<SkillKind, float> SkillXP { get; } = new()
    {
        [SkillKind.Construction] = 0f,
        [SkillKind.Mining] = 0f,
        [SkillKind.Woodcutting] = 0f,
    };

    /// <summary>0 (fine) to 100 (critical). Rises over time.</summary>
    public float Hunger { get; set; } = 0f;

    /// <summary>0 (miserable) to 100 (happy). Driven by needs and events.</summary>
    public float Mood { get; set; } = 70f;

    /// <summary>0 (rested) to 100 (exhausted). Rises over time.</summary>
    public float Fatigue { get; set; } = 0f;

    /// <summary>Hit points. 0 means the pawn is dead.</summary>
    public float HP { get; set; } = 100f;

    /// <summary>0 (hydrated) to 100 (parched). Rises over time; drinking resets it.</summary>
    public float Thirst { get; set; } = 0f;

    /// <summary>0 (calm) to 100 (panicking). Driven by wounds, hunger and danger.</summary>
    public float Stress { get; set; } = 0f;

    /// <summary>Two fixed personality tags rolled at creation (affect mood dynamics).</summary>
    public List<string> Traits { get; } = new();

    /// <summary>Recent memorable events: (tick, what happened, mood delta). Capped at 20.</summary>
    public List<(long Tick, string What, float MoodDelta)> Memories { get; } = new();

    /// <summary>Opinion of other pawns (-1..+1), built from shared time and events.</summary>
    public Dictionary<Guid, float> Relationships { get; } = new();

    /// <summary>Record a life event and apply its mood effect.</summary>
    public void Remember(long tick, string what, float moodDelta)
    {
        Memories.Add((tick, what, moodDelta));
        if (Memories.Count > 20) Memories.RemoveAt(0);
        Mood = Math.Clamp(Mood + moodDelta, 0f, 100f);
    }

    private static readonly string[] TraitPool = { "hardy", "gloomy", "jovial", "loner", "diligent", "anxious" };

    public Pawn(string name, int startX, int startY) : base(name)
    {
        X = startX;
        Y = startY;
        Sex = _sexRng.Next(2) == 0 ? PawnSex.Male : PawnSex.Female;
        Traits.Add(TraitPool[_sexRng.Next(TraitPool.Length)]);
        string second = TraitPool[_sexRng.Next(TraitPool.Length)];
        if (!Traits.Contains(second)) Traits.Add(second);
    }

    /// <summary>Adds XP to a skill and returns the resulting level (XP / 100).</summary>
    public int GainSkill(SkillKind kind, float amount)
    {
        SkillXP[kind] += amount;
        return GetSkillLevel(kind);
    }

public int GetSkillLevel(SkillKind kind) => (int)(SkillXP[kind] / 100f);

    /// <summary>Checks if a pawn is at the edge of the current region's hex map.</summary>
    public bool IsPawnAtEdge(Pawn pawn, Region region)
    {
        int pawnX = pawn.X;
        int pawnY = pawn.Y;
        int regionX = region.X;
        int regionY = region.Y;

        // Assuming the region is a square of size 10x10
        int regionWidth = 10;
        int regionHeight = 10;

        return pawnX == regionX || pawnX == regionX + regionWidth - 1 ||
               pawnY == regionY || pawnY == regionY + regionHeight - 1;
    }

    /// <summary>Highest-level skill, for display purposes.</summary>
    public SkillKind TopSkill => SkillXP.OrderByDescending(kv => kv.Value).First().Key;

    /// <summary>
    /// Attempts to move the pawn by a specified delta.
    /// </summary>
    public bool TryMove(int dx, int dy, GameMap map)
    {
        int newX = X + dx;
        int newY = Y + dy;

        // Check collision for the potential new position
        if (map.IsPassable(newX, newY))
        {
            X = newX;
            Y = newY;
            return true; // Move successful
        }
        else
        {
            // Collision detected - movement blocked
            return false; 
        }
    }

    public override string ToString() => $"Pawn ({Name}): Pos=({X}, {Y})";
}


// =====================================================================
// 3. Game World Manager (The Deterministic Loop)
// =====================================================================

/// <summary>
/// The central manager that runs the deterministic tick loop and holds all state.
/// </summary>
public class GameWorldManager
{
    private readonly GameMap _map;
    private readonly Dictionary<Guid, Thing> _registry;
    private List<Pawn> _pawns;
    private readonly Dictionary<Guid, PawnTaskDriver> _drivers;
    private readonly Random _rng = new(12345);

    private bool _isRaining = false;
    private int _rainToggleCounter = 0; // Counter to track in-game days

    // Method to generate small animal populations
public void GenerateSmallAnimalPopulation()
{
    int numberOfAnimals = _rng.Next(1, 6); // Random number between 1 and 5
    for (int i = 0; i < numberOfAnimals; i++)
    {
        int x = _rng.Next(_map.Width);
        int y = _rng.Next(_map.Height);
        if (_map.IsPassable(x, y))
        {
            // Create a new small animal pawn and add it to the list of pawns
            Pawn animalPawn = new Pawn("SmallAnimal", x, y);
            _pawns.Add(animalPawn);
        }
    }
}

public bool IsRaining => _isRaining;

// Method to toggle rain state
public void ToggleRain()
{
    if (_rainToggleCounter % 5 == 0) // Every few in-game days (e.g., every 5 days)
    {
        _isRaining = !_isRaining;
        UpdateHeaderText();
    }
    _rainToggleCounter++;
}

// Method to update the header text
private void UpdateHeaderText()
{
    if (_isRaining)
    {
        Console.WriteLine("Raining");
    }
    else
    {
        Console.WriteLine("Not Raining");
    }
}

    /// <summary>Accumulated worker-ticks per Mine tile, toward the next Stone (see MineTicksPerStone).</summary>
    private readonly Dictionary<(int X, int Y), int> _mineProgress = new();

    public GameMap Map => _map;
    public Dictionary<Guid, Thing> Registry => _registry;
    public List<Pawn> Pawns => _pawns;
    public TaskBoard Tasks { get; }
    public NeedsSystem Needs { get; }

    /// <summary>Wood stockpile. Structural builds consume 1, digging walls/removing structural furniture refunds 1.</summary>
    public int Wood { get; set; } = 15;

    /// <summary>Stone stockpile, harvested from Rock resources (Mining skill).</summary>
    public int Stone { get; set; } = 5;

    /// <summary>Water stockpile, hauled from river tiles.</summary>
    public int Water { get; set; } = 10;

    /// <summary>Food stockpile - cooked at Stoves, eaten periodically by pawns.</summary>
    public int Food { get; set; } = 24;

    /// <summary>Metal stockpile - byproduct of sustained mining.</summary>
    public int Metal { get; set; } = 0;

    /// <summary>Tool stockpile - crafted at the Workbench, speeds up future crafting.</summary>
    public int Tools { get; set; } = 0;

    /// <summary>Research insight accrued by crafting and building.</summary>
    public int ResearchPoints { get; private set; } = 0;

    /// <summary>Unlocked technologies (gates real effects, see Tick).</summary>
    public List<string> UnlockedTech { get; } = new();

    /// <summary>Colony-level event feed (newest last, capped at 60).</summary>
    public List<string> ColonyEvents { get; } = new();

    /// <summary>Multi-scale world simulation (solar/planet/region layers).</summary>
    public MacroSim Macro { get; } = new();

    /// <summary>How many Macro.WorldEvents have been surfaced into ColonyEvents.</summary>
    private int _surfacedWorldEvents = 0;

    private void LogEvent(string text)
    {
        ColonyEvents.Add($"Day {DayNumber}: {text}");
        if (ColonyEvents.Count > 60) ColonyEvents.RemoveAt(0);
    }

    private void GainResearch(int points)
    {
        ResearchPoints += points;
        (int Cost, string Tech)[] ladder = { (5, "Metal tools"), (15, "Watch post"), (30, "Granary") };
        foreach (var (cost, tech) in ladder)
            if (ResearchPoints >= cost && !UnlockedTech.Contains(tech))
            {
                UnlockedTech.Add(tech);
                LogEvent($"Research breakthrough: {tech} unlocked!");
            }
    }

    /// <summary>Queues a HaulWater task: a pawn walks to a tile next to the river and brings back +1 Water.</summary>
    public bool QueueHaulWater(int x, int y)
    {
        Tasks.Enqueue(new TaskOrder(TaskKind.HaulWater, x, y, priority: 55));
        return true;
    }

    public const int WallWoodCost = 2;
    public const int WallStoneCost = 1;

    /// <summary>True if there's enough Wood+Stone to build a wall tile.</summary>
    public bool CanAffordWall() => Wood >= WallWoodCost && Stone >= WallStoneCost;

    /// <summary>Spends the Wood+Stone cost of one wall tile. Caller must check CanAffordWall first.</summary>
    public void SpendWallCost()
    {
        Wood -= WallWoodCost;
        Stone -= WallStoneCost;
    }

    /// <summary>Refunds half the Wood+Stone cost of a wall tile (rounded down) when it's dug up.</summary>
    public void RefundWallCost()
    {
        Wood += WallWoodCost / 2;
        Stone += WallStoneCost / 2;
    }

    /// <summary>Wood cost to build a Mine.</summary>
    public const int MineWoodCost = 10;

    /// <summary>Ticks of worker-presence needed for a Mine to produce 1 Stone (5 seconds at 20 ticks/sec, per worker).</summary>
    public const int MineTicksPerStone = 100;

    /// <summary>Queues a Build task: a pawn will walk to (x,y) and place the given furniture there.</summary>
    public bool QueueBuild(FurnitureKind kind, int x, int y)
    {
        if (!_map.IsPassable(x, y)) return false;
        if (_map.Furniture.Any(f => f.X == x && f.Y == y)) return false;
        if (_map.Resources.Any(r => r.X == x && r.Y == y)) return false;

        if (kind == FurnitureKind.Mine && Wood < MineWoodCost) return false;

        bool isStructural = FurnitureCatalog.Get(kind).Category == FurnitureCategory.Structural;
        if (isStructural && Wood <= 0) return false;

        Tasks.Enqueue(new TaskOrder(TaskKind.Build, x, y, priority: 70, buildKind: kind));
        return true;
    }

    /// <summary>Queues a BuildWall task: a pawn will walk adjacent to (x,y) and turn that tile solid.</summary>
    public bool QueueBuildWall(int x, int y)
    {
        if (!_map.IsPassable(x, y)) return false;
        if (_map.Furniture.Any(f => f.X == x && f.Y == y)) return false;
        if (_map.Resources.Any(r => r.X == x && r.Y == y)) return false;
        if (!CanAffordWall()) return false;

        bool hasPassableNeighbor =
            _map.IsPassable(x + 1, y) || _map.IsPassable(x - 1, y) ||
            _map.IsPassable(x, y + 1) || _map.IsPassable(x, y - 1);
        if (!hasPassableNeighbor) return false;

        Tasks.Enqueue(new TaskOrder(TaskKind.BuildWall, x, y, priority: 70));
        return true;
    }

    /// <summary>Wood cost to build one Bridge tile over Water.</summary>
    public const int BridgeWoodCost = 3;

    /// <summary>True while a BuildBridge task is queued or being carried out by a pawn.</summary>
    private bool _bridgeTaskActive = false;

    /// <summary>True when organic expansion found no dry room slot - the only reason to bridge the river.</summary>
    private bool _needsBridgeToExpand = false;

    /// <summary>Queues a BuildBridge task: a pawn walks adjacent to a Water tile and builds a Bridge over it, making it passable.</summary>
    public bool QueueBuildBridge(int x, int y)
    {
        if (!_map.IsWater(x, y)) return false;
        if (_map.HasBridge(x, y)) return false;
        if (Wood < BridgeWoodCost) return false;

        bool hasPassableNeighbor =
            _map.IsPassable(x + 1, y) || _map.IsPassable(x - 1, y) ||
            _map.IsPassable(x, y + 1) || _map.IsPassable(x, y - 1);
        if (!hasPassableNeighbor) return false;

        Tasks.Enqueue(new TaskOrder(TaskKind.BuildBridge, x, y, priority: 70));
        _bridgeTaskActive = true;
        return true;
    }

    /// <summary>
    /// Periodically extends the colony's bridges across the river, one tile
    /// at a time, starting from the tile closest to the colony center -
    /// pawns naturally gain a crossing without a hardcoded bridge layout.
    /// </summary>
    private void TryAutoBridge()
    {
        if (Wood < BridgeWoodCost) return;
        // Only one bridge tile is worked on at a time. Tasks.Pending alone
        // isn't enough here - once a pawn claims the task it leaves Pending
        // while still in progress, which previously let this fire again
        // every 500 ticks and queue a second, competing bridge tile.
        if (_bridgeTaskActive || Tasks.Pending.Any(t => t.Kind == TaskKind.BuildBridge)) return;

        (int X, int Y)? best = null;
        int bestDist = int.MaxValue;
        for (int y = 1; y < _map.Height - 1; y++)
        {
            for (int x = 1; x < _map.Width - 1; x++)
            {
                if (!_map.IsWater(x, y) || _map.HasBridge(x, y)) continue;

                bool hasPassableNeighbor =
                    _map.IsPassable(x + 1, y) || _map.IsPassable(x - 1, y) ||
                    _map.IsPassable(x, y + 1) || _map.IsPassable(x, y - 1);
                if (!hasPassableNeighbor) continue;

                int dist = Math.Abs(x - 12) + Math.Abs(y - 4);
                if (dist < bestDist)
                {
                    bestDist = dist;
                    best = (x, y);
                }
            }
        }

        if (best != null)
            QueueBuildBridge(best.Value.X, best.Value.Y);
    }

    /// <summary>Queues a Harvest task: a pawn will walk to a Tree (+1 Wood) or Rock (+1 Stone) at (x,y).</summary>
    public bool QueueHarvest(int x, int y)
    {
        if (!_map.Resources.Any(r => r.X == x && r.Y == y && (r.Kind == ResourceKind.Tree || r.Kind == ResourceKind.Rock))) return false;

        Tasks.Enqueue(new TaskOrder(TaskKind.Harvest, x, y, priority: 60));
        return true;
    }

    public GameWorldManager(int mapWidth, int mapHeight)
    {
        _map = new GameMap(mapWidth, mapHeight);

        // No pre-placed zones - the player designates Canteen/Sleeping
        // Quarters areas themselves using the zone-placement tool.

        _registry = new Dictionary<Guid, Thing>();
        _pawns = new List<Pawn>();
        _drivers = new Dictionary<Guid, PawnTaskDriver>();
        Tasks = new TaskBoard();
        Needs = new NeedsSystem();

        SetupAutoColonyPlan();
    }

    /// <summary>Drip-feed queue of (X, Y, FurnitureKind) for furniture, or (X, Y, null) to mark a wall tile to be built.</summary>
    private readonly List<(int X, int Y, FurnitureKind? Kind)> _autoBuildQueue = new();

    /// <summary>
    /// Plans three small starter rooms (Bedroom, Kitchen, Dining Room) with
    /// a door gap and a Crate storage spot each, and queues every wall
    /// tile + piece of furniture as Build/BuildWall tasks so pawns walk
    /// over and construct the whole colony themselves - nothing is
    /// pre-built. Tile interiors are kept clear of resource nodes so the
    /// plan is always reachable.
    /// </summary>
    private void SetupAutoColonyPlan()
    {
        var rooms = new (int Ox, int Oy, (int Dx, int Dy, FurnitureKind Kind)[] Items)[]
        {
            (2, 2, new[] { (2, 4, FurnitureKind.Door), (2, 2, FurnitureKind.Bed), (1, 1, FurnitureKind.Crate) }),
            (9, 2, new[] { (2, 4, FurnitureKind.Door), (1, 2, FurnitureKind.Stove), (3, 2, FurnitureKind.Workbench), (1, 1, FurnitureKind.Crate) }),
            (16, 2, new[] { (2, 4, FurnitureKind.Door), (1, 2, FurnitureKind.DiningTable), (3, 2, FurnitureKind.Chair), (3, 1, FurnitureKind.Crate) }),
        };

        foreach (var (ox, oy, items) in rooms)
            PlanRoom(ox, oy, items);
    }

    /// <summary>Room slots already built or claimed (slots tile a 6x6 grid; slots 0-2 are the starter rooms).</summary>
    private readonly HashSet<int> _usedRoomSlots = new() { 0, 1, 2 };

    /// <summary>
    /// Once the colony has finished its current build queue and has at
    /// least one Wood/Stone to spare, plan another small Bedroom so
    /// population can keep growing. Rooms expand organically outward from
    /// wherever the colony's existing furniture already is, instead of
    /// always tiling from the map's top-left corner - the closest free,
    /// dry-land slot to the colony's current footprint is picked.
    /// </summary>
    private void TryPlanOrganicRoom()
    {
        if (_autoBuildQueue.Count > 0) return;
        if (Wood < 20 || Stone < 5) return;

        int bedCount = _map.Furniture.Count(f => f.Kind == FurnitureKind.Bed);
        if (bedCount > _pawns.Count) return;

        // Centroid of the colony's existing furniture - new rooms grow
        // outward from here rather than from a fixed map corner.
        double cx = 12, cy = 4;
        if (_map.Furniture.Count > 0)
        {
            cx = _map.Furniture.Average(f => f.X);
            cy = _map.Furniture.Average(f => f.Y);
        }

        int bestSlot = -1;
        double bestDist = double.MaxValue;
        for (int slot = 0; slot < 36; slot++)
        {
            if (_usedRoomSlots.Contains(slot)) continue;

            int col = slot % 6;
            int row = slot / 6;
            int ox = 2 + col * 7;
            int oy = 2 + row * 7;
            if (ox + 5 > _map.Width - 1 || oy + 5 > _map.Height - 1) continue;

            // Rooms can't be planned across the river until a bridge
            // connects the two banks.
            bool hasWater = false;
            for (int x = ox; x < ox + 5 && !hasWater; x++)
                for (int y = oy; y < oy + 5 && !hasWater; y++)
                    if (_map.IsWater(x, y)) hasWater = true;
            if (hasWater) continue;

            double dist = Math.Abs((ox + 2) - cx) + Math.Abs((oy + 2) - cy);
            if (dist < bestDist)
            {
                bestDist = dist;
                bestSlot = slot;
            }
        }

        if (bestSlot < 0)
        {
            _needsBridgeToExpand = true;
            return;
        }
        _needsBridgeToExpand = false;

        int bcol = bestSlot % 6;
        int brow = bestSlot / 6;
        PlanRoom(2 + bcol * 7, 2 + brow * 7, new[] { (2, 4, FurnitureKind.Door), (2, 2, FurnitureKind.Bed), (1, 1, FurnitureKind.Crate) });
        _usedRoomSlots.Add(bestSlot);
    }

    /// <summary>
    /// Once the colony can afford it, automatically queue a Mine building
    /// near home so pawns standing near it produce a steady Stone income
    /// instead of relying solely on one-off Rock harvesting. Only the
    /// first Mine is auto-planned this way.
    /// </summary>
    private void TryPlanMine()
    {
        if (Wood < MineWoodCost) return;
        if (_map.Furniture.Any(f => f.Kind == FurnitureKind.Mine)) return;
        if (Tasks.Pending.Any(t => t.Kind == TaskKind.Build && t.BuildKind == FurnitureKind.Mine)) return;

        for (int radius = 0; radius < 20; radius++)
        {
            for (int dx = -radius; dx <= radius; dx++)
            {
                for (int dy = -radius; dy <= radius; dy++)
                {
                    if (Math.Max(Math.Abs(dx), Math.Abs(dy)) != radius) continue;
                    int x = 12 + dx;
                    int y = 4 + dy;
                    if (QueueBuild(FurnitureKind.Mine, x, y)) return;
                }
            }
        }
    }

    /// <summary>Marks a 5x5 footprint clear/no-grow, queues its perimeter walls (with a door gap), and queues its furniture.</summary>
    private void PlanRoom(int ox, int oy, (int Dx, int Dy, FurnitureKind Kind)[] items)
    {
        for (int x = ox; x < ox + 5; x++)
            for (int y = oy; y < oy + 5; y++)
            {
                _map.RemoveResourceAt(x, y);
                _map.MarkNoGrow(x, y);
            }

        var door = items[0];

        for (int i = 0; i < 5; i++)
        {
            QueueWallTile(ox + i, oy, door, ox, oy);
            QueueWallTile(ox + i, oy + 4, door, ox, oy);
            QueueWallTile(ox, oy + i, door, ox, oy);
            QueueWallTile(ox + 4, oy + i, door, ox, oy);
        }

        foreach (var (dx, dy, kind) in items)
            _autoBuildQueue.Add((ox + dx, oy + dy, kind));
    }

    /// <summary>Queues a perimeter tile as a wall to build, unless it's the room's door tile.</summary>
    private void QueueWallTile(int x, int y, (int Dx, int Dy, FurnitureKind Kind) door, int ox, int oy)
    {
        if (x == ox + door.Dx && y == oy + door.Dy) return; // door gap stays open
        _autoBuildQueue.Add((x, y, null));
    }

    /// <summary>
    /// When a planned Build/BuildWall can't be queued because Wood/Stone is
    /// short, immediately send a pawn after the missing resource instead of
    /// waiting for the slow background auto-harvest tick - "create what you
    /// lack" so the colony unblocks itself.
    /// </summary>
    private void EmergencyGather(bool needWood, bool needStone)
    {
        if (Tasks.Pending.Count(t => t.Kind == TaskKind.Harvest) >= 3) return;

        var targeted = Tasks.Pending.Where(t => t.Kind == TaskKind.Harvest).Select(t => (t.TargetX, t.TargetY)).ToHashSet();

        if (needWood)
        {
            var tree = _map.Resources.Where(r => r.Kind == ResourceKind.Tree && !targeted.Contains((r.X, r.Y)))
                .OrderBy(r => Math.Abs(r.X - 12) + Math.Abs(r.Y - 4)).FirstOrDefault();
            if (tree != null) QueueHarvest(tree.X, tree.Y);
        }

        if (needStone)
        {
            var rock = _map.Resources.Where(r => r.Kind == ResourceKind.Rock && !targeted.Contains((r.X, r.Y)))
                .OrderBy(r => Math.Abs(r.X - 12) + Math.Abs(r.Y - 4)).FirstOrDefault();
            if (rock != null) QueueHarvest(rock.X, rock.Y);
        }
    }

    public void RegisterThing(Thing thing)
    {
        _registry.Add(thing.Id, thing);
        if (thing is Pawn pawn)
        {
            _pawns.Add(pawn);
            _drivers[pawn.Id] = new PawnTaskDriver();
        }
    }

    /// <summary>
    /// The deterministic tick function. This runs at a fixed rate.
    /// Steps each pawn's current task and assigns new tasks from the board when idle.
    /// </summary>
    /// <summary>Total ticks elapsed since world start.</summary>
    public long TotalTicks { get; private set; }

    /// <summary>One in-game day = 1000 ticks. Hour = 0-23.</summary>
    public int DayNumber => (int)(TotalTicks / 1000) + 1;
    public int HourOfDay => (int)(TotalTicks % 1000 / 1000.0 * 24);
    public bool IsNight => HourOfDay >= 20 || HourOfDay < 6;

    /// <summary>Personal furniture kinds: each gets assigned to one living pawn for life.</summary>
    private static readonly FurnitureKind[] PersonalFurnitureKinds = { FurnitureKind.Bed, FurnitureKind.Chair };

    /// <summary>Assigns any unowned Bed/Chair to a pawn that doesn't have one of that kind yet.</summary>
    private void AssignPersonalFurniture()
    {
        foreach (var kind in PersonalFurnitureKinds)
        {
            var owners = _map.Furniture.Where(f => f.Kind == kind && f.OwnerId.HasValue).Select(f => f.OwnerId!.Value).ToHashSet();
            var unowned = _map.Furniture.Where(f => f.Kind == kind && !f.OwnerId.HasValue).ToList();
            var unassigned = _pawns.Where(p => p.HP > 0 && !owners.Contains(p.Id)).ToList();

            foreach (var item in unowned)
            {
                if (unassigned.Count == 0) break;
                item.OwnerId = unassigned[0].Id;
                unassigned.RemoveAt(0);
            }
        }
    }

    public void Tick()
    {
        TotalTicks++;

        // Macro layers tick at their own LOD cadence; the colony then FEELS
        // them: ClimatePulse throttles vegetation regrowth (macro -> local).
        Macro.Tick(TotalTicks);
        if (_rng.NextDouble() < Macro.ClimatePulse)
            _map.TickSaplings();

        if (TotalTicks % 50 == 0)
            AssignPersonalFurniture();

        // --- Survival economy: food & water are consumed by living pawns ---
        int mealInterval = UnlockedTech.Contains("Granary") ? 2600 : 2000;
        if (TotalTicks % mealInterval == 0)
        {
            foreach (var p in _pawns.Where(p => p.HP > 0))
            {
                if (Food > 0) { Food--; p.Remember(TotalTicks, "ate a warm meal", +2f); p.Hunger = Math.Max(0f, p.Hunger - 30f); }
                else { p.Remember(TotalTicks, "went hungry - no food in store", -4f); p.Stress = Math.Clamp(p.Stress + 10f, 0f, 100f); }
            }
            if (Food == 0) LogEvent("Food stores are empty!");
        }
        if (TotalTicks % 1500 == 0)
        {
            foreach (var p in _pawns.Where(p => p.HP > 0))
            {
                if (Water > 0) { Water--; p.Thirst = 0f; }
                else p.Thirst = Math.Clamp(p.Thirst + 25f, 0f, 100f);
            }
        }

        // --- Cooking: a built Stove slowly turns Wood into Food ---
        if (TotalTicks % 800 == 0 && Wood >= 1 && Food < _pawns.Count * 3 &&
            _map.Furniture.Any(f => f.Kind == FurnitureKind.Stove))
        {
            Wood--; Food += 2;
        }

        // --- Crafting: a Workbench turns Wood+Stone into Tools (+research) ---
        int craftInterval = UnlockedTech.Contains("Metal tools") ? 200 : 300;
        if (TotalTicks % craftInterval == 0 && Wood >= 2 && Stone >= 1 && Tools < _pawns.Count &&
            _map.Furniture.Any(f => f.Kind == FurnitureKind.Workbench))
        {
            Wood -= 2; Stone -= 1; Tools++;
            GainResearch(2);
            if (Tools % 4 == 0) LogEvent($"Workshop output: tool stock at {Tools}.");
        }

        // --- Metallurgy: sustained mining smelts Metal from Stone ---
        if (TotalTicks % 1000 == 0 && Stone >= 5 && _map.Furniture.Any(f => f.Kind == FurnitureKind.Mine))
        {
            Stone -= 5; Metal++;
        }

        // --- Pawn minds: stress, relationships, shared time ---
        if (TotalTicks % 100 == 0)
        {
            var alive = _pawns.Where(p => p.HP > 0).ToList();
            foreach (var p in alive)
            {
                float stressDrive = (p.HP < 50f ? 1.5f : 0f) + (p.Hunger > 80f ? 1f : 0f) + (p.Thirst > 80f ? 1f : 0f);
                float calm = p.Traits.Contains("hardy") ? 1.5f : (p.Traits.Contains("anxious") ? 0.5f : 1f);
                p.Stress = Math.Clamp(p.Stress + stressDrive - 0.8f * calm, 0f, 100f);
                if (p.Stress > 80f) p.Mood = Math.Clamp(p.Mood - 0.5f, 0f, 100f);

                foreach (var other in alive)
                {
                    if (other.Id == p.Id) continue;
                    if (Math.Abs(other.X - p.X) <= 1 && Math.Abs(other.Y - p.Y) <= 1)
                    {
                        p.Relationships.TryGetValue(other.Id, out float rel);
                        float social = p.Traits.Contains("loner") ? 0.005f : 0.02f;
                        p.Relationships[other.Id] = Math.Clamp(rel + social, -1f, 1f);
                    }
                }
            }
        }

        // Surface fresh macro world events into the colony feed.
        while (_surfacedWorldEvents < Macro.WorldEvents.Count)
        {
            LogEvent(Macro.WorldEvents[_surfacedWorldEvents]);
            _surfacedWorldEvents++;
        }

        // Drip-feed the starter colony plan into the build queue so pawns
        // walk over and construct it piece by piece. If an item can't be
        // queued yet (e.g. a tree regrew on the tile, or no Wood), send it
        // to the back of the queue instead of blocking everything behind it.
        if (TotalTicks % 60 == 0 && _autoBuildQueue.Count > 0)
        {
            var (x, y, kind) = _autoBuildQueue[0];
            _autoBuildQueue.RemoveAt(0);
            bool queued = kind.HasValue ? QueueBuild(kind.Value, x, y) : QueueBuildWall(x, y);
            if (!queued)
            {
                if (!kind.HasValue)
                {
                    _map.RemoveResourceAt(x, y);
                    if (!CanAffordWall())
                        EmergencyGather(needWood: Wood < WallWoodCost, needStone: Stone < WallStoneCost);
                }
                else if (FurnitureCatalog.Get(kind.Value).Category == FurnitureCategory.Structural && Wood <= 0)
                {
                    EmergencyGather(needWood: true, needStone: false);
                }
                _autoBuildQueue.Add((x, y, kind));
            }
        }

        if (TotalTicks % 1000 == 0)
            TryPlanOrganicRoom();

        if (TotalTicks % 1000 == 500)
            TryPlanMine();

        // Slowly extend a bridge across the river so the colony isn't
        // bisected - one tile at a time, closest to home first.
        if (TotalTicks % 500 == 0)
            TryAutoBridge();

        // Auto-harvest: keep a steady stockpile of Wood so building never
        // permanently stalls once the colony hits its old cap. Up to 2
        // harvest tasks can be queued at once so wood keeps flowing while
        // a pawn is mid-walk to a far tree.
        if (TotalTicks % 30 == 0 && Wood < 30 && Tasks.Pending.Count(t => t.Kind == TaskKind.Harvest) < 2)
        {
            var choppedOrTargeted = Tasks.Pending
                .Where(t => t.Kind == TaskKind.Harvest)
                .Select(t => (t.TargetX, t.TargetY))
                .ToHashSet();
            var nearestTree = _map.Resources
                .Where(r => r.Kind == ResourceKind.Tree && !choppedOrTargeted.Contains((r.X, r.Y)))
                .OrderBy(r => Math.Abs(r.X - 12) + Math.Abs(r.Y - 4))
                .FirstOrDefault();
            if (nearestTree != null)
                QueueHarvest(nearestTree.X, nearestTree.Y);
        }

        // Auto-mine: keep a small Stone stockpile flowing too, so walls
        // (which now cost Stone) don't stall the build queue forever.
        if (TotalTicks % 30 == 0 && Stone < 20 && Tasks.Pending.Count(t => t.Kind == TaskKind.Harvest) < 2)
        {
            var choppedOrTargeted = Tasks.Pending
                .Where(t => t.Kind == TaskKind.Harvest)
                .Select(t => (t.TargetX, t.TargetY))
                .ToHashSet();
            var nearestRock = _map.Resources
                .Where(r => r.Kind == ResourceKind.Rock && !choppedOrTargeted.Contains((r.X, r.Y)))
                .OrderBy(r => Math.Abs(r.X - 12) + Math.Abs(r.Y - 4))
                .FirstOrDefault();
            if (nearestRock != null)
                QueueHarvest(nearestRock.X, nearestRock.Y);
        }

        // Auto-haul water: every so often, send a pawn to the river bank
        // to fetch +1 Water - their job is to keep this stockpile flowing.
        if (TotalTicks % 30 == 0 && Water < 20 && Tasks.Pending.Count(t => t.Kind == TaskKind.HaulWater) < 1)
        {
            var tile = _map.FindNearestWaterAdjacentTile(12, 4);
            if (tile != null)
                QueueHaulWater(tile.Value.X, tile.Value.Y);
        }

        // Population growth: a wanderer joins the colony every few in-game
        // days as long as there's enough Wood to support them, there's a
        // free Bed for them (1 bed per pawn, or they stop developing), and
        // the colony isn't already overcrowded.
        int bedCount = _map.Furniture.Count(f => f.Kind == FurnitureKind.Bed);
        if (TotalTicks % 3000 == 0 && Wood >= 5 && _pawns.Count < bedCount && _pawns.Count < 12)
        {
            // New settlers arrive near the colony's home base, not at a
            // random spot on the map - so they actually join in rather
            // than starting life stranded across the river.
            int x, y;
            int attempts = 0;
            do
            {
                x = 12 + _rng.Next(-8, 9);
                y = 4 + _rng.Next(-8, 9);
                attempts++;
            } while ((!_map.IsPassable(x, y) || _map.IsWater(x, y)) && attempts < 100);

            if (_map.IsPassable(x, y) && !_map.IsWater(x, y))
                RegisterThing(new Pawn($"Settler{_pawns.Count + 1}", x, y));
        }

        // Mine furniture: every pawn standing on or adjacent to a built Mine
        // counts as a worker. Each worker contributes 1 tick/tick toward
        // that mine's progress; once MineTicksPerStone (5s) of worker-ticks
        // accumulate, the mine yields +1 Stone (per worker, in parallel).
        if (TotalTicks % 200 == 0 && _map.Furniture.Any(f => f.Kind == FurnitureKind.Mine))
            Stone++;

        foreach (var mine in _map.Furniture.Where(f => f.Kind == FurnitureKind.Mine))
        {
            var workers = _pawns.Where(p => p.HP > 0 && Math.Abs(p.X - mine.X) <= 1 && Math.Abs(p.Y - mine.Y) <= 1).ToList();
            if (workers.Count == 0) continue;

            var key = (mine.X, mine.Y);
            _mineProgress.TryGetValue(key, out int progress);
            progress += workers.Count;
            while (progress >= MineTicksPerStone)
            {
                progress -= MineTicksPerStone;
                Stone++;
                workers[_rng.Next(workers.Count)].GainSkill(SkillKind.Mining, 10f);
            }
            _mineProgress[key] = progress;
        }

        foreach (var pawn in _pawns)
        {
            if (pawn.HP <= 0) continue;

            var driver = _drivers[pawn.Id];

            Needs.Tick(this, driver, pawn, _rng);
            pawn.Mood = Math.Max(Math.Min(pawn.Mood + (pawn.Hunger > 70f ? -0.01f : 0.002f) + (pawn.HP < 50f ? -0.01f : 0f), 100f), 0f);

            if (driver.IsIdle)
            {
                var next = Tasks.TryClaimBest(pawn);
                if (next != null)
                {
                    driver.Assign(next, pawn, _map);
                }
            }
            else
            {
                var order = driver.Current.Order;
                bool finished = driver.Step(pawn, _map, Tasks);
                if (finished && order.Kind == TaskKind.Build && order.BuildKind.HasValue)
                {
                    var kind = order.BuildKind.Value;
                    if (kind == FurnitureKind.Mine)
                    {
                        if (Wood >= MineWoodCost && _map.PlaceFurniture(kind, order.TargetX, order.TargetY))
                        {
                            Wood -= MineWoodCost;
                            pawn.GainSkill(SkillKind.Construction, 10f);
                        }
                    }
                    else
                    {
                        bool isStructural = FurnitureCatalog.Get(kind).Category == FurnitureCategory.Structural;
                        if (!isStructural || Wood > 0)
                        {
                            if (_map.PlaceFurniture(kind, order.TargetX, order.TargetY) && isStructural)
                            {
                                Wood--;
                                pawn.GainSkill(SkillKind.Construction, 10f);
                            }
                        }
                    }
                }
                else if (finished && order.Kind == TaskKind.BuildWall)
                {
                    if (CanAffordWall() && _map.IsPassable(order.TargetX, order.TargetY))
                    {
                        _map.SetSolid(order.TargetX, order.TargetY, true);
                        SpendWallCost();
                        pawn.GainSkill(SkillKind.Construction, 10f);
                    }
                    else if (_map.IsPassable(order.TargetX, order.TargetY))
                    {
                        _autoBuildQueue.Add((order.TargetX, order.TargetY, null));
                    }
                    else if (_map.IsPassable(order.TargetX, order.TargetY))
                    {
                        _autoBuildQueue.Add((order.TargetX, order.TargetY, null));
                    }
                }
                else if (finished && order.Kind == TaskKind.BuildBridge)
                {
                    if (Wood >= BridgeWoodCost && _map.AddBridge(order.TargetX, order.TargetY))
                    {
                        Wood -= BridgeWoodCost;
                        pawn.GainSkill(SkillKind.Construction, 10f);
                    }
                    _bridgeTaskActive = false;
                }
                else if (finished && order.Kind == TaskKind.Harvest)
                {
                    var resource = _map.Resources.FirstOrDefault(r => r.X == order.TargetX && r.Y == order.TargetY);
                    if (resource != null && _map.RemoveResourceAt(order.TargetX, order.TargetY))
                    {
                        if (resource.Kind == ResourceKind.Tree)
                        {
                            Wood++;
                            if (TotalTicks % 3 == 0) Food++; // foraged berries

                            pawn.GainSkill(SkillKind.Woodcutting, 10f);
                            DropTreeSeeds(order.TargetX, order.TargetY);
                        }
                        else if (resource.Kind == ResourceKind.Rock)
                        {
                            Stone++;
                            pawn.GainSkill(SkillKind.Mining, 10f);
                        }
                    }
                }
                else if (finished && order.Kind == TaskKind.HaulWater)
                {
                    Water++;
                }
            }
        }

        if (_pawns.RemoveAll(p => p.HP <= 0) > 0)
        {
            foreach (var deadId in _registry.Keys.Where(k => _registry[k] is Pawn dp && dp.HP <= 0).ToList())
            {
                _registry.Remove(deadId);
                _drivers.Remove(deadId);
                foreach (var item in _map.Furniture.Where(f => f.OwnerId == deadId))
                    item.OwnerId = null;
            }
        }
    }

    public PawnTaskDriver GetDriver(Pawn pawn) => _drivers[pawn.Id];

    private List<Room> _rooms = new();

    /// <summary>
    /// Returns the most recently detected set of enclosed rooms. Detection
    /// is O(map size), so call <see cref="RefreshRooms"/> periodically
    /// (e.g. once per second) rather than every tick.
    /// </summary>
    public List<Room> GetRooms() => _rooms;

    public void RefreshRooms() => _rooms = RoomDetector.DetectRooms(_map);

    public int GoalIndex { get; private set; } = 0;

    public string CurrentGoalText => GoalIndex switch
    {
        0 => "Build 3 functional rooms",
        1 => "Grow the colony to 4 pawns",
        2 => "Stockpile 50 Stone",
        3 => "Build 6 functional rooms",
        4 => "Survive to day 100",
        _ => "Colony thriving - endless mode"
    };

    /// <summary>Advances the goal ladder when the current objective is met.</summary>
    public void TickGoals()
    {
        bool met = GoalIndex switch
        {
            0 => _rooms.Count(r => r.Function != RoomFunction.Empty) >= 3,
            1 => _pawns.Count(p => p.HP > 0) >= 4,
            2 => Stone >= 50,
            3 => _rooms.Count(r => r.Function != RoomFunction.Empty) >= 6,
            4 => DayNumber >= 100,
            _ => false
        };
        if (met)
        {
            GoalIndex++;
            LogEvent($"Objective complete! Next: {CurrentGoalText}");
            GainResearch(3);
        }
    }

    /// <summary>
    /// When a tree is chopped, it has a chance to drop 0-2 seeds onto nearby
    /// plantable tiles. Each seed grows back into a Tree after one in-game
    /// week (7 days * 1000 ticks/day), keeping wood a renewable resource.
    /// </summary>
    private void DropTreeSeeds(int x, int y)
    {
        const int TicksPerWeek = 7000;
        int seedCount = _rng.Next(0, 3);
        for (int i = 0; i < seedCount; i++)
        {
            var candidates = new List<(int X, int Y)>();
            for (int dx = -2; dx <= 2; dx++)
                for (int dy = -2; dy <= 2; dy++)
                    if ((dx != 0 || dy != 0) && _map.IsPlantable(x + dx, y + dy))
                        candidates.Add((x + dx, y + dy));

            if (candidates.Count == 0) continue;

            var (sx, sy) = candidates[_rng.Next(candidates.Count)];
            _map.AddSapling(sx, sy, TicksPerWeek);
        }
    }

    public void PrintState()
    {
        Console.WriteLine("\n=== GAME STATE ===");
        Console.WriteLine($"Map Dimensions: {_map.Width}x{_map.Height}");
        Console.WriteLine($"Registered Things: {_registry.Count}");
        
        foreach (var pawn in _pawns)
        {
            Console.WriteLine(pawn);
        }
    }
}

// =====================================================================
// 4. Simple Test Suite (Verification)
// =====================================================================

public static class GameWorldTests
{
    public static void RunAllTests()
    {
        Console.WriteLine("\n╔════════════════════════════════════════════╗");
        Console.WriteLine("║          Running Unit Tests                ║");
        Console.WriteLine("╚════════════════════════════════════════════╝\n");

        int passed = 0;
        int failed = 0;

        // Test 1: Map Initialization
        try
        {
            var world = new GameWorldManager(50, 50);
            if (world.Map != null && world.Map.Width == 50 && world.Map.Height == 50)
            {
                var cell = world.Map.GetCell(1, 1);
                if (!cell.IsSolid)
                {
                    Console.WriteLine("✓ [PASS] MapInitializationTest");
                    passed++;
                }
                else
                {
                    Console.WriteLine("✗ [FAIL] MapInitializationTest - Cell (1,1) should not be solid");
                    failed++;
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"✗ [FAIL] MapInitializationTest - {ex.Message}");
            failed++;
        }

        // Test 2: Pawn Movement & Collision
        try
        {
            var world = new GameWorldManager(10, 10);
            world.RegisterThing(new Pawn("Player", 1, 1));

            bool result1 = world.Pawns[0].TryMove(-1, -1, world.Map); // Should fail (solid cell at 0,0)
            bool result2 = world.Pawns[0].TryMove(0, 1, world.Map);   // Should succeed

            if (!result1 && result2 && world.Pawns[0].X == 1 && world.Pawns[0].Y == 2)
            {
                Console.WriteLine("✓ [PASS] PawnMovementAndCollisionTest");
                passed++;
            }
            else
            {
                Console.WriteLine($"✗ [FAIL] PawnMovementAndCollisionTest");
                failed++;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"✗ [FAIL] PawnMovementAndCollisionTest - {ex.Message}");
            failed++;
        }

        // Test 3: Registry
        try
        {
            var world = new GameWorldManager(10, 10);
            var player = new Pawn("Hero", 5, 5);
            world.RegisterThing(player);

            if (world.Registry.ContainsKey(player.Id))
            {
                var duplicate = new Pawn("Hero", 0, 0);
                world.RegisterThing(duplicate);
                
                if (world.Registry.Count == 2)
                {
                    Console.WriteLine("✓ [PASS] RegistryTest");
                    passed++;
                }
                else
                {
                    Console.WriteLine("✗ [FAIL] RegistryTest - Registry count should be 2");
                    failed++;
                }
            }
            else
            {
                Console.WriteLine("✗ [FAIL] RegistryTest - Player not in registry");
                failed++;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"✗ [FAIL] RegistryTest - {ex.Message}");
            failed++;
        }

        // Test 4: Mine passive Stone production (regression test for the
        // verified W.1b deadlock: Stone stayed 0 forever, no wall was ever
        // built and no room could close - see docs/AUTONOMOUS_AUDIT.md).
        try
        {
            var world = new GameWorldManager(50, 50);
            bool minePlaced = false;
            for (int y = 2; y < 48 && !minePlaced; y++)
                for (int x = 2; x < 48 && !minePlaced; x++)
                    if (world.Map.IsPassable(x, y) && world.Map.PlaceFurniture(FurnitureKind.Mine, x, y))
                        minePlaced = true;
            int stoneBefore = world.Stone;
            for (int t = 0; t < 450; t++) world.Tick();
            if (minePlaced && world.Stone > stoneBefore)
            {
                Console.WriteLine("✓ [PASS] MinePassiveStoneTest");
                passed++;
            }
            else
            {
                Console.WriteLine($"✗ [FAIL] MinePassiveStoneTest - Stone did not increase (before={stoneBefore}, after={world.Stone}, minePlaced={minePlaced})");
                failed++;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"✗ [FAIL] MinePassiveStoneTest - {ex.Message}");
            failed++;
        }

        // Test 5: Functional room detection (regression test for the
        // observed "walls+door+bed built but 0 rooms reported" bug class).
        try
        {
            var map = new GameMap(20, 20);
            // Deterministic arena: clear generated water/resources inside
            // the future room so furniture placement cannot silently fail.
            for (int x = 5; x <= 9; x++)
                for (int y = 5; y <= 9; y++) { map.SetSolid(x, y, false); map.RemoveResourceAt(x, y); }
            for (int x = 5; x <= 9; x++) { map.SetSolid(x, 5, true); map.SetSolid(x, 9, true); }
            for (int y = 5; y <= 9; y++) { map.SetSolid(5, y, true); map.SetSolid(9, y, true); }
            map.SetSolid(7, 9, false); // door gap
            bool doorOk = map.PlaceFurniture(FurnitureKind.Door, 7, 9);
            bool bedOk = map.PlaceFurniture(FurnitureKind.Bed, 7, 7);
            var rooms = RoomDetector.DetectRooms(map);
            bool hasBedroom = doorOk && bedOk && rooms.Exists(r => r.Function == RoomFunction.Bedroom);
            if (hasBedroom)
            {
                Console.WriteLine("✓ [PASS] FunctionalRoomDetectionTest");
                passed++;
            }
            else
            {
                Console.WriteLine($"✗ [FAIL] FunctionalRoomDetectionTest - expected 1 Bedroom, rooms found: {rooms.Count}");
                failed++;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"✗ [FAIL] FunctionalRoomDetectionTest - {ex.Message}");
            failed++;
        }

        // Test 6: TryClaimBest must prefer the nearby task over a distant
        // equal-priority one (regression of the first-task-only AI and of
        // the stubbed TryClaimBest incident).
        try
        {
            var board = new TaskBoard();
            board.Enqueue(new TaskOrder(TaskKind.MoveTo, 40, 40, priority: 50));
            board.Enqueue(new TaskOrder(TaskKind.MoveTo, 6, 5, priority: 50));
            var pawn6 = new Pawn("Tester", 5, 5);
            var picked = board.TryClaimBest(pawn6);
            if (picked != null && picked.TargetX == 6 && picked.TargetY == 5)
            {
                Console.WriteLine("✓ [PASS] TryClaimBestPrefersNearTaskTest");
                passed++;
            }
            else
            {
                Console.WriteLine($"✗ [FAIL] TryClaimBestPrefersNearTaskTest - picked {picked?.TargetX},{picked?.TargetY}");
                failed++;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"✗ [FAIL] TryClaimBestPrefersNearTaskTest - {ex.Message}");
            failed++;
        }

        // Test 7: the macro layers must actually tick at their LOD cadences
        // and keep their pressures in sane bounds (multi-scale spine proof).
        try
        {
            var macro = new MacroSim();
            for (long t = 1; t <= 5001; t++) macro.Tick(t);
            bool layersTicked = macro.LastUpdate[SimLOD.Solar] >= 5000
                && macro.LastUpdate[SimLOD.Planet] >= 4000
                && macro.LastUpdate[SimLOD.Region] >= 4500;
            bool sane = macro.RaidPressure >= 0.5f && macro.RaidPressure <= 2.5f
                && macro.ClimatePulse >= 0.4f && macro.ClimatePulse <= 1.2f;
            if (layersTicked && sane && macro.Sites.Count >= 3)
            {
                Console.WriteLine("✓ [PASS] MacroLodLayersTest");
                passed++;
            }
            else
            {
                Console.WriteLine($"✗ [FAIL] MacroLodLayersTest - ticked={layersTicked} sane={sane}");
                failed++;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"✗ [FAIL] MacroLodLayersTest - {ex.Message}");
            failed++;
        }

        // Test 8: with no Water in store, pawns must get thirsty (survival
        // economy proof - needs are consumed, not cosmetic).
        try
        {
            var world8 = new GameWorldManager(50, 50);
            var p8 = new Pawn("Dusty", 5, 5);
            world8.RegisterThing(p8);
            // Enforced drought: pawns may auto-haul water, so the shortage
            // is reasserted every tick (we test thirst, not logistics).
            for (int t = 0; t < 1600; t++) { world8.Water = 0; world8.Tick(); }
            if (p8.Thirst > 0f)
            {
                Console.WriteLine("✓ [PASS] ThirstRisesWithoutWaterTest");
                passed++;
            }
            else
            {
                Console.WriteLine($"✗ [FAIL] ThirstRisesWithoutWaterTest - thirst={p8.Thirst}");
                failed++;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"✗ [FAIL] ThirstRisesWithoutWaterTest - {ex.Message}");
            failed++;
        }

        Console.WriteLine($"\n{passed + failed} tests ran: {passed} passed, {failed} failed\n");
    }
}
