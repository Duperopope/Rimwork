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
    Solar,    // long-pulse global modifiers (climate cycle, system events)
    Planet,   // per-body climate/habitability drift
    Region,   // external sites: trade/raid/migration pressure
    Local,    // the playable colony map - full per-pawn simulation
    Detail,   // pawn body/mind (runs inside Local each tick)
    Organism, // single-creature stage (Spore-like, pre-tribal) - future
    Micro     // microbial biomass per region: the primordial layer
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

    /// <summary>This body's own surface regions (5x5 hex grid, biome
    /// palette depends on the body's climate).</summary>
    public WorldRegion[,] Regions { get; } = new WorldRegion[5, 5];

    public WorldBody(string name, string kind, float habitability, float richness, float danger, float temp)
    {
        Name = name; Kind = kind; Habitability = habitability;
        ResourceRichness = richness; DangerLevel = danger; ClimateTemp = temp;

        string[] palette = temp > 0.4f
            ? new[] { "ash", "dunes", "scorched", "lava rock", "crater" }
            : temp < -0.3f
                ? new[] { "ice", "tundra", "snowfield", "frost rock", "crevasse" }
                : new[] { "forest", "plains", "hills", "marsh", "rocky" };
        var rng = new Random(name.GetHashCode() & 0x7fffffff);
        for (int y = 0; y < 5; y++)
            for (int x = 0; x < 5; x++)
                Regions[x, y] = new WorldRegion(x, y, palette[(x + y * 5 + rng.Next(2)) % palette.Length],
                    habitability * (0.4f + (float)rng.NextDouble() * 0.6f),
                    danger * (0.4f + (float)rng.NextDouble() * 0.8f));
    }
}

/// <summary>All the knobs of the world-creation screen (Down Here!).
/// Fully deterministic: same settings = same universe.</summary>
public class WorldGenSettings
{
    public int Seed { get; set; } = 12345;
    public int PlanetCount { get; set; } = 3;       // 2..6 bodies
    public float OrbitSpeedMult { get; set; } = 1f; // 0.25..4
    public float BiomeShift { get; set; } = 0f;     // -1 cold .. +1 hot universe
    public int PawnCount { get; set; } = 8;         // 4..16 starting colonists
    public float AnimalDensity { get; set; } = 1f;  // 0..3
    public int MapSize { get; set; } = 50;          // 50..128 local map side
}

/// <summary>The star system the whole game lives in (Scale 0).</summary>
public class SolarSystem
{
    private static readonly string[] StarNames = { "Kerel", "Vanya", "Osmund", "Thara", "Belun", "Ciris" };
    private static readonly string[] BodyNames = { "Rim", "Cinder", "Palemoon", "Verdis", "Holt", "Ashka", "Nivis", "Drossa" };

    public string StarName { get; } = "Kerel";
    public List<WorldBody> Bodies { get; } = new();

    /// <summary>Default universe (legacy save/test compatibility).</summary>
    public SolarSystem()
    {
        Bodies.Add(new WorldBody("Rim", "planet", 0.72f, 0.6f, 0.35f, 0.1f));
        Bodies.Add(new WorldBody("Cinder", "planet", 0.15f, 0.9f, 0.70f, 0.8f));
        Bodies.Add(new WorldBody("Palemoon", "moon", 0.30f, 0.4f, 0.50f, -0.6f));
    }

    /// <summary>Procedural universe from the world-creation settings.</summary>
    public SolarSystem(WorldGenSettings gen)
    {
        var rng = new Random(gen.Seed);
        StarName = StarNames[rng.Next(StarNames.Length)];
        int count = Math.Clamp(gen.PlanetCount, 2, 6);
        for (int i = 0; i < count; i++)
        {
            string name = BodyNames[(rng.Next(BodyNames.Length) + i) % BodyNames.Length] + (i > 0 && rng.Next(3) == 0 ? $"-{i}" : "");
            bool moon = i > 0 && rng.Next(4) == 0;
            float temp = Math.Clamp((float)(rng.NextDouble() * 2 - 1) * 0.8f + gen.BiomeShift * 0.5f, -1f, 1f);
            float hab = i == 0
                ? 0.6f + (float)rng.NextDouble() * 0.3f   // home stays livable
                : (float)rng.NextDouble() * 0.7f;
            Bodies.Add(new WorldBody(name, moon ? "moon" : "planet",
                hab, 0.3f + (float)rng.NextDouble() * 0.7f,
                (float)rng.NextDouble() * 0.8f,
                i == 0 ? Math.Clamp(temp * 0.4f, -0.25f, 0.25f) : temp));
        }
        // A system without a moon is a sad system: guarantee one (it also
        // drives tides/night raids in the design charter).
        if (!Bodies.Any(b => b.Kind == "moon") && Bodies.Count >= 2)
        {
            var converted = Bodies[Bodies.Count - 1];
            Bodies[Bodies.Count - 1] = new WorldBody(converted.Name, "moon",
                converted.Habitability, converted.ResourceRichness, converted.DangerLevel, converted.ClimateTemp);
        }
    }

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
    public float WildlifePressure { get; set; } // 0..1, drives wildlife pressure
    /// <summary>Microbial biomass 0..1 (SimLOD.Micro): the primordial soil
    /// layer - it FEEDS Fertility (bacteria -> soil -> plants -> us).</summary>
    public float MicrobialBiomass { get; set; } = 0.5f;
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

    public SolarSystem System { get; }
    public WorldGenSettings Gen { get; }
    public WorldRegion[,] Regions => System.HomeBody.Regions;
    public List<ExternalSite> Sites { get; } = new();
    public List<string> WorldEvents { get; } = new();

    // ---- The pressures the local colony actually feels ----
    /// <summary>Multiplies raider spawn frequency (1 = baseline).</summary>
    public float RaidPressure { get; private set; } = 1f;
    /// <summary>Scales vegetation regrowth speed (1 = baseline).</summary>
    public float ClimatePulse { get; private set; } = 1f;
    /// <summary>0..1 external demand for colony goods (drives objectives/trade).</summary>
    public float TradeDemand { get; private set; } = 0.3f;

    /// <summary>Deterministic weather over the colony tile right now.</summary>
    public WeatherKind ColonyWeather { get; private set; } = WeatherKind.Clear;
    public const float ColonyLat = 25f;
    public const float ColonyLon = 0f;

    /// <summary>Last tick each LOD layer was updated (for the dev tab).</summary>
    public Dictionary<SimLOD, long> LastUpdate { get; } = new()
    {
        [SimLOD.Solar] = 0, [SimLOD.Planet] = 0, [SimLOD.Region] = 0, [SimLOD.Local] = 0, [SimLOD.Micro] = 0
    };

    public MacroSim() : this(new WorldGenSettings()) { }

    public MacroSim(WorldGenSettings gen)
    {
        Gen = gen ?? new WorldGenSettings();
        System = new SolarSystem(Gen);
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
        if (worldTick % 800 == 0) UpdateMicro(worldTick);
        if (worldTick % 250 == 0)
        {
            var before = ColonyWeather;
            ColonyWeather = WeatherSystem.At(Gen.Seed, ColonyLat, ColonyLon, worldTick);
            if (ColonyWeather != before && ColonyWeather == WeatherKind.Storm)
                WorldEvents.Add($"[t{worldTick}] Storm front over the colony - everyone on edge.");
        }
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

    /// <summary>LOD Micro: bacteria bloom with warmth+wet, and slowly pull
    /// regional Fertility toward their own level (primordial engine).</summary>
    public void UpdateMicro(long tick)
    {
        var home = System.HomeBody;
        foreach (var reg in Regions)
        {
            float warmth = 1f - Math.Abs(home.ClimateTemp - 0.2f);
            float drift = (warmth * 0.6f + ClimatePulse * 0.4f - 0.5f) * 0.05f;
            reg.MicrobialBiomass = Math.Clamp(reg.MicrobialBiomass + drift + ((float)_rng.NextDouble() - 0.5f) * 0.02f, 0.05f, 1f);
            reg.Fertility = Math.Clamp(reg.Fertility * 0.95f + reg.MicrobialBiomass * 0.05f, 0f, 1f);
        }
        LastUpdate[SimLOD.Micro] = tick;
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

/// <summary>Deterministic weather: same seed + same tile + same day =
/// same sky, everywhere, forever (Dwarf Fortress principle).</summary>
public enum WeatherKind { Clear, Rain, Fog, Storm }

public static class WeatherSystem
{
    public static WeatherKind At(int seed, float latDeg, float lonDeg, long tick)
    {
        long day = tick / 1000;
        int h = HashCode.Combine(seed, (int)(latDeg / 8f), (int)(lonDeg / 8f), day);
        int roll = Math.Abs(h) % 100;
        // Latitude shapes climate: equator wetter, poles foggier.
        float wet = 25f + 15f * MathF.Cos(MathF.Abs(latDeg) * MathF.PI / 180f);
        if (roll < wet * 0.15f) return WeatherKind.Storm;
        if (roll < wet) return WeatherKind.Rain;
        if (roll < wet + (MathF.Abs(latDeg) > 50f ? 18f : 8f)) return WeatherKind.Fog;
        return WeatherKind.Clear;
    }

    /// <summary>Local solar hour for a tile: planet rotation (1 day = 1000
    /// ticks) offset by longitude - two tiles 180 deg apart live in
    /// opposite day phases.</summary>
    public static float LocalHour(long tick, float lonDeg)
    {
        float baseHour = (tick % 1000) / 1000f * 24f;
        return ((baseHour + lonDeg / 15f) % 24f + 24f) % 24f;
    }
}
