using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

// =====================================================================
// Multi-slot save system (Down Here! design charter, chantier 1).
// The map itself is deterministic (fixed seed), so a save stores the
// DIFF state: stocks, time, goals, pawns (body+mind), built walls,
// furniture, and which resource nodes were consumed.
// =====================================================================

public class SaveData
{
    public int Version { get; set; } = 1;
    public string SavedAt { get; set; }
    public long TotalTicks { get; set; }
    public int Wood { get; set; }
    public int Stone { get; set; }
    public int Water { get; set; }
    public int Food { get; set; }
    public int Metal { get; set; }
    public int Tools { get; set; }
    public int ResearchPoints { get; set; }
    public List<string> UnlockedTech { get; set; } = new();
    public int GoalIndex { get; set; }
    public List<PawnData> Pawns { get; set; } = new();
    public List<int[]> Walls { get; set; } = new();          // built interior walls [x,y]
    public List<FurnitureData> Furniture { get; set; } = new();
    public List<int[]> Resources { get; set; } = new();      // surviving nodes [kind,x,y]
    public List<string> ColonyEvents { get; set; } = new();

    public class PawnData
    {
        public string Name { get; set; }
        public int X { get; set; }
        public int Y { get; set; }
        public float HP { get; set; }
        public float Hunger { get; set; }
        public float Thirst { get; set; }
        public float Fatigue { get; set; }
        public float Mood { get; set; }
        public float Stress { get; set; }
        public List<string> Traits { get; set; } = new();
        public Dictionary<string, float> Skills { get; set; } = new();
    }

    public class FurnitureData
    {
        public string Kind { get; set; }
        public int X { get; set; }
        public int Y { get; set; }
    }
}

public static class SaveLoad
{
    public static string Describe(string path)
    {
        try
        {
            var d = JsonSerializer.Deserialize<SaveData>(File.ReadAllText(path));
            return $"Jour {d.TotalTicks / 1000 + 1} — {d.Pawns.Count(p => p.HP > 0)} colons — {d.SavedAt}";
        }
        catch { return null; }
    }

    public static void Save(GameWorldManager w, string path)
    {
        var d = new SaveData
        {
            SavedAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm"),
            TotalTicks = w.TotalTicks,
            Wood = w.Wood, Stone = w.Stone, Water = w.Water,
            Food = w.Food, Metal = w.Metal, Tools = w.Tools,
            ResearchPoints = w.ResearchPoints,
            UnlockedTech = w.UnlockedTech.ToList(),
            GoalIndex = w.GoalIndex,
            ColonyEvents = w.ColonyEvents.TakeLast(20).ToList(),
        };
        foreach (var p in w.Pawns)
        {
            d.Pawns.Add(new SaveData.PawnData
            {
                Name = p.Name, X = p.X, Y = p.Y, HP = p.HP,
                Hunger = p.Hunger, Thirst = p.Thirst, Fatigue = p.Fatigue,
                Mood = p.Mood, Stress = p.Stress,
                Traits = p.Traits.ToList(),
                Skills = p.SkillXP.ToDictionary(kv => kv.Key.ToString(), kv => kv.Value),
            });
        }
        // Interior solid tiles that are not water = player/pawn-built walls.
        var fresh = new GameMap(w.Map.Width, w.Map.Height);
        for (int y = 1; y < w.Map.Height - 1; y++)
            for (int x = 1; x < w.Map.Width - 1; x++)
                if (!w.Map.IsPassable(x, y) && !w.Map.IsWater(x, y) && fresh.IsPassable(x, y))
                    d.Walls.Add(new[] { x, y });
        foreach (var f in w.Map.Furniture)
            d.Furniture.Add(new SaveData.FurnitureData { Kind = f.Kind.ToString(), X = f.X, Y = f.Y });
        foreach (var r in w.Map.Resources)
            d.Resources.Add(new[] { (int)r.Kind, r.X, r.Y });

        Directory.CreateDirectory(Path.GetDirectoryName(path));
        File.WriteAllText(path, JsonSerializer.Serialize(d, new JsonSerializerOptions { WriteIndented = false }));
    }

    public static GameWorldManager Load(string path)
    {
        var d = JsonSerializer.Deserialize<SaveData>(File.ReadAllText(path));
        var w = new GameWorldManager(50, 50);
        w.RestoreFrom(d);
        return w;
    }
}
