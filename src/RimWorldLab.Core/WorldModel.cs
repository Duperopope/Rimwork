using System;
using System.Collections.Generic;
using System.Linq;

// =====================================================================
// Multi-scale world model: SolarSystem -> WorldBody -> WorldRegion ->
// (LocalMap lives in GameWorld.cs) — plus the MacroSim that ticks each
// layer at its own LOD cadence and feeds pressure DOWN into the colony.
// =====================================================================

/// <summary>Simulation levels of detail, coarsest to finest.</summary>
public enum SimLOD
{
    Solar,   // long-pulse global modifiers (climate cycle, system events)
    Planet,  // per-body climate/habitability drift
    Region,  // external sites: trade/raid/migration pressure
    Local,   // the playable colony map - full per-pawn simulation
    Detail   // pawn body/mind (runs inside Local each tick)
}

/// <summary>A star-system body the colony could live on.</summary>
public class WorldBody
{
    public string Name { get; }
    public string Kind { get; }            // "planet", "moon"
    public float Habitability { get; set; } // 0..1
    public float ResourceRichness { get; set; } // 0..1
    public float DangerLevel { get; set; }  // 0..1
    public float ClimateTemp { get; set; }  // abstract -1 cold .. +1 hot

    public WorldBody(string name, string kind, float habitability, float richness, float danger, float temp)
    {
        Name = name; Kind = kind; Habitability = habitability;
        ResourceRichness = richness; DangerLevel = danger; ClimateTemp = temp;
    }
}

/// <summary>The star system the whole game lives in (Scale 0).</summary>
public class SolarSystem
{
    public string StarName { get; } = "Kerel";
    public List<WorldBody> Bodies { get; } = new()
    {
        new WorldBody("Rim",      "planet", 0.72f, 0.6f, 0.35f,  0.1f),
        new WorldBody("Cinder",   "planet", 0.15f, 0.9f, 0.70f,  0.8f),
        new WorldBody("Palemoon", "moon",   0.30f, 0.4f, 0.50f, -0.6f),
    };
    /// <summary>Index into Bodies of the world the colony lives on.</summary>
    public int HomeBodyIndex { get; } = 0;
    public WorldBody HomeBody => Bodies[HomeBodyIndex];
    /// <summary>0..1 solar activity cycle; high activity = harsher climate pulses.</summary>
    public float SolarActivity { get; set; } = 0.5f;
}

/// <summary>One coarse region of the home planet (Scale 1).</summary>
public class WorldRegion
{
    public int X { get; }
    public int Y { get; }
    public string Biome { get; }
    public float Fertility { get; set; }   // 0..1, drives regrowth
    public float Danger { get; set; }      // 0..1, drives raid pressure
    public bool IsColonyRegion { get; set; }

    public WorldRegion(int x, int y, string biome, float fertility, float danger)
    {
        X = x; Y = y; Biome = biome; Fertility = fertility; Danger = danger;
    }
}

/// <summary>An abstract external settlement/site (Scale 2) - simulated as
/// counters, never as individual pawns (quanta-style aggregate agent).</summary>
public class ExternalSite
{
    public string Name { get; }
    public string Faction { get; }
    public float Attitude { get; set; }     // -1 hostile .. +1 friendly
    public float Population { get; set; }   // abstract heads
    public float TradeDemand { get; set; }  // 0..1 demand for colony goods
    public float RaidAppetite { get; set; } // 0..1 likelihood to raid

    public ExternalSite(string name, string faction, float attitude, float population)
    {
        Name = name; Faction = faction; Attitude = attitude; Population = population;
        TradeDemand = 0.3f; RaidAppetite = Math.Max(0f, -attitude * 0.5f);
    }
}

/// <summary>
/// Ticks every layer above the local map at its own cadence and exposes
/// the three pressures the colony actually feels. Deterministic: seeded RNG.
/// </summary>
public class MacroSim
{
    private readonly Random _rng = new(777);

    public SolarSystem System { get; } = new();
    public WorldRegion[,] Regions { get; } = new WorldRegion[5, 5];
    public List<ExternalSite> Sites { get; } = new();
    public List<string> WorldEvents { get; } = new();

    // ---- The pressures the local colony actually feels ----
    /// <summary>Multiplies raider spawn frequency (1 = baseline).</summary>
    public float RaidPressure { get; private set; } = 1f;
    /// <summary>Scales vegetation regrowth speed (1 = baseline).</summary>
    public float ClimatePulse { get; private set; } = 1f;
    /// <summary>0..1 external demand for colony goods (drives objectives/trade).</summary>
    public float TradeDemand { get; private set; } = 0.3f;

    /// <summary>Last tick each LOD layer was updated (for the dev tab).</summary>
    public Dictionary<SimLOD, long> LastUpdate { get; } = new()
    {
        [SimLOD.Solar] = 0, [SimLOD.Planet] = 0, [SimLOD.Region] = 0, [SimLOD.Local] = 0
    };

    public MacroSim()
    {
        string[] biomes = { "forest", "plains", "hills", "marsh", "rocky" };
        for (int y = 0; y < 5; y++)
            for (int x = 0; x < 5; x++)
                Regions[x, y] = new WorldRegion(x, y, biomes[(x + y * 5) % biomes.Length],
                    0.3f + (float)_rng.NextDouble() * 0.6f, (float)_rng.NextDouble() * 0.6f);
        Regions[2, 2].IsColonyRegion = true;

        Sites.Add(new ExternalSite("Fort Ashvale", "Iron Compact", -0.6f, 120f));
        Sites.Add(new ExternalSite("Greenhollow", "Free Hamlets", 0.7f, 60f));
        Sites.Add(new ExternalSite("Saltmarket", "Guild of Coin", 0.2f, 200f));
    }

    /// <summary>Advance every macro layer that is due at this world tick.</summary>
    public void Tick(long worldTick)
    {
        if (worldTick % 5000 == 0) UpdateSolar(worldTick);
        if (worldTick % 2000 == 0) UpdatePlanet(worldTick);
        if (worldTick % 500 == 0) UpdateRegions(worldTick);
        LastUpdate[SimLOD.Local] = worldTick;
    }

    /// <summary>LOD 3: solar activity drifts on a long pulse.</summary>
    public void UpdateSolar(long tick)
    {
        System.SolarActivity = Math.Clamp(System.SolarActivity + ((float)_rng.NextDouble() - 0.5f) * 0.3f, 0f, 1f);
        if (System.SolarActivity > 0.8f)
            WorldEvents.Add($"[t{tick}] Solar flare cycle peaking over {System.StarName} - harsher seasons ahead.");
        LastUpdate[SimLOD.Solar] = tick;
    }

    /// <summary>LOD 2: planet climate responds to the star; feeds ClimatePulse.</summary>
    public void UpdatePlanet(long tick)
    {
        var home = System.HomeBody;
        home.ClimateTemp = Math.Clamp(home.ClimateTemp + (System.SolarActivity - 0.5f) * 0.1f, -1f, 1f);
        // Mild temperate climate grows things faster; extremes slow them.
        ClimatePulse = Math.Clamp(1.2f - Math.Abs(home.ClimateTemp), 0.4f, 1.2f);
        if (ClimatePulse < 0.6f)
            WorldEvents.Add($"[t{tick}] Drought pulse on {home.Name}: vegetation regrowth slowed.");
        LastUpdate[SimLOD.Planet] = tick;
    }

    /// <summary>LOD 1: external sites trade, grow, and sharpen their appetites.</summary>
    public void UpdateRegions(long tick)
    {
        float raid = 0f, demand = 0f;
        foreach (var site in Sites)
        {
            site.Population = Math.Max(10f, site.Population + ((float)_rng.NextDouble() - 0.45f) * 8f);
            site.TradeDemand = Math.Clamp(site.TradeDemand + ((float)_rng.NextDouble() - 0.5f) * 0.15f, 0f, 1f);
            if (site.Attitude < 0f)
                site.RaidAppetite = Math.Clamp(site.RaidAppetite + ((float)_rng.NextDouble() - 0.45f) * 0.2f, 0f, 1f);
            raid += site.RaidAppetite * (site.Population / 150f);
            demand += site.TradeDemand;
        }
        RaidPressure = Math.Clamp(0.5f + raid, 0.5f, 2.5f);
        TradeDemand = Math.Clamp(demand / Sites.Count, 0f, 1f);
        if (RaidPressure > 1.8f)
            WorldEvents.Add($"[t{tick}] {Sites.OrderByDescending(s => s.RaidAppetite).First().Faction} war bands massing - raid pressure high.");
        if (WorldEvents.Count > 40) WorldEvents.RemoveRange(0, WorldEvents.Count - 40);
        LastUpdate[SimLOD.Region] = tick;
    }
}

/// <summary>
/// Deterministic mapping from tile neighborhood to 3D model yaw (degrees).
/// Pure function so the test suite can verify it without the engine:
/// a wall segment aligns with its solid neighbors; doors face across
/// their wall axis. 0 deg = model long axis along X (east-west).
/// </summary>
public static class RenderOrientation
{
    public static int WallYaw(bool solidN, bool solidS, bool solidE, bool solidW)
    {
        bool horizontal = solidE || solidW;
        bool vertical = solidN || solidS;
        if (horizontal && !vertical) return 0;
        if (vertical && !horizontal) return 90;
        if (horizontal && vertical) return 0;   // corner/junction: default east-west
        return 0;                                // isolated post
    }

    /// <summary>A door rotates perpendicular to the wall run it sits in.</summary>
    public static int DoorYaw(bool solidN, bool solidS, bool solidE, bool solidW)
        => WallYaw(solidN, solidS, solidE, solidW);
}
