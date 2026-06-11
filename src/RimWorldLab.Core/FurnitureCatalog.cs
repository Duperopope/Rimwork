using System.Collections.Generic;

// =====================================================================
// Furniture catalog: every placeable object, grouped into categories.
// Room function (RoomDetection.cs) is derived from which categories/kinds
// are present in an enclosed room.
// =====================================================================

public enum FurnitureCategory
{
    Beds,
    Seating,
    Tables,
    Storage,
    Production,
    Power,
    Lighting,
    Structural,
    Recreation,
    Medical
}

public enum FurnitureKind
{
    // --- Beds ---
    Bed, BedDouble, BedRoyal, Bunk, Cot, Crib, Hammock, BedFrame, Mattress, SleepingBag, Cradle, BedCanopy,

    // --- Seating ---
    Chair, Armchair, Stool, Bench, Sofa, Loveseat, Recliner, ThroneChair, Beanbag, Rocker, Pew, FoldingChair,

    // --- Tables ---
    Table, DiningTable, CoffeeTable, Desk, EndTable, PicnicTable, AltarTable, ConferenceTable, Counter, Nightstand, DraftingTable, BarTable,

    // --- Storage ---
    Shelf, Cabinet, Wardrobe, Crate, Locker, Bookcase, Chest, Dresser, ToolRack, WeaponRack, Pantry, Safe,

    // --- Production ---
    Stove, Workbench, Furnace, Forge, Loom, Lathe, Sawmill, BrewingStand, ButcherTable, ResearchBench, ElectricSmelter, TanningRack, Mine,

    // --- Power ---
    Generator, SolarPanel, WindTurbine, Battery, PowerConduit, FuelGenerator, GeothermalVent, NuclearReactor, Capacitor, Transformer, BackupGenerator, HydroTurbine,

    // --- Lighting ---
    Torch, Lamp, Chandelier, Floodlight, CeilingLight, WallSconce, LanternStand, NeonSign, Spotlight, CandleHolder, GlowLamp, EmergencyLight,

    // --- Structural ---
    Door, ReinforcedDoor, Gate, Window, Fence, Pillar, Trapdoor, Hatch, Airlock, Skylight, Archway, RetractableWall,

    // --- Recreation ---
    TVScreen, PoolTable, Dartboard, Jukebox, ChessTable, ArcadeMachine, Bar, GymEquipment, BasketballHoop, CardTable, MusicStand, HorseshoePit,

    // --- Medical ---
    MedicalBed, OperatingTable, IVStand, Defibrillator, Stretcher, MedicineCabinet, Sterilizer, MedicalScanner, SurgicalLight, Wheelchair, Incubator, BloodBank
}

public record FurnitureInfo(FurnitureKind Kind, FurnitureCategory Category, string DisplayName);

/// <summary>
/// Static metadata for every FurnitureKind: which category it belongs to
/// and its display name. Used by the placement UI and by room-function
/// classification.
/// </summary>
public static class FurnitureCatalog
{
    public static readonly IReadOnlyList<FurnitureInfo> All = Build();

    private static readonly Dictionary<FurnitureKind, FurnitureInfo> ByKind = BuildLookup();

    public static FurnitureInfo Get(FurnitureKind kind) => ByKind[kind];

    private static List<FurnitureInfo> Build()
    {
        var list = new List<FurnitureInfo>();

        void Add(FurnitureCategory category, params FurnitureKind[] kinds)
        {
            foreach (var kind in kinds)
                list.Add(new FurnitureInfo(kind, category, SplitName(kind.ToString())));
        }

        Add(FurnitureCategory.Beds,
            FurnitureKind.Bed, FurnitureKind.BedDouble, FurnitureKind.BedRoyal, FurnitureKind.Bunk,
            FurnitureKind.Cot, FurnitureKind.Crib, FurnitureKind.Hammock, FurnitureKind.BedFrame,
            FurnitureKind.Mattress, FurnitureKind.SleepingBag, FurnitureKind.Cradle, FurnitureKind.BedCanopy);

        Add(FurnitureCategory.Seating,
            FurnitureKind.Chair, FurnitureKind.Armchair, FurnitureKind.Stool, FurnitureKind.Bench,
            FurnitureKind.Sofa, FurnitureKind.Loveseat, FurnitureKind.Recliner, FurnitureKind.ThroneChair,
            FurnitureKind.Beanbag, FurnitureKind.Rocker, FurnitureKind.Pew, FurnitureKind.FoldingChair);

        Add(FurnitureCategory.Tables,
            FurnitureKind.Table, FurnitureKind.DiningTable, FurnitureKind.CoffeeTable, FurnitureKind.Desk,
            FurnitureKind.EndTable, FurnitureKind.PicnicTable, FurnitureKind.AltarTable, FurnitureKind.ConferenceTable,
            FurnitureKind.Counter, FurnitureKind.Nightstand, FurnitureKind.DraftingTable, FurnitureKind.BarTable);

        Add(FurnitureCategory.Storage,
            FurnitureKind.Shelf, FurnitureKind.Cabinet, FurnitureKind.Wardrobe, FurnitureKind.Crate,
            FurnitureKind.Locker, FurnitureKind.Bookcase, FurnitureKind.Chest, FurnitureKind.Dresser,
            FurnitureKind.ToolRack, FurnitureKind.WeaponRack, FurnitureKind.Pantry, FurnitureKind.Safe);

        Add(FurnitureCategory.Production,
            FurnitureKind.Stove, FurnitureKind.Workbench, FurnitureKind.Furnace, FurnitureKind.Forge,
            FurnitureKind.Loom, FurnitureKind.Lathe, FurnitureKind.Sawmill, FurnitureKind.BrewingStand,
            FurnitureKind.ButcherTable, FurnitureKind.ResearchBench, FurnitureKind.ElectricSmelter, FurnitureKind.TanningRack,
            FurnitureKind.Mine);

        Add(FurnitureCategory.Power,
            FurnitureKind.Generator, FurnitureKind.SolarPanel, FurnitureKind.WindTurbine, FurnitureKind.Battery,
            FurnitureKind.PowerConduit, FurnitureKind.FuelGenerator, FurnitureKind.GeothermalVent, FurnitureKind.NuclearReactor,
            FurnitureKind.Capacitor, FurnitureKind.Transformer, FurnitureKind.BackupGenerator, FurnitureKind.HydroTurbine);

        Add(FurnitureCategory.Lighting,
            FurnitureKind.Torch, FurnitureKind.Lamp, FurnitureKind.Chandelier, FurnitureKind.Floodlight,
            FurnitureKind.CeilingLight, FurnitureKind.WallSconce, FurnitureKind.LanternStand, FurnitureKind.NeonSign,
            FurnitureKind.Spotlight, FurnitureKind.CandleHolder, FurnitureKind.GlowLamp, FurnitureKind.EmergencyLight);

        Add(FurnitureCategory.Structural,
            FurnitureKind.Door, FurnitureKind.ReinforcedDoor, FurnitureKind.Gate, FurnitureKind.Window,
            FurnitureKind.Fence, FurnitureKind.Pillar, FurnitureKind.Trapdoor, FurnitureKind.Hatch,
            FurnitureKind.Airlock, FurnitureKind.Skylight, FurnitureKind.Archway, FurnitureKind.RetractableWall);

        Add(FurnitureCategory.Recreation,
            FurnitureKind.TVScreen, FurnitureKind.PoolTable, FurnitureKind.Dartboard, FurnitureKind.Jukebox,
            FurnitureKind.ChessTable, FurnitureKind.ArcadeMachine, FurnitureKind.Bar, FurnitureKind.GymEquipment,
            FurnitureKind.BasketballHoop, FurnitureKind.CardTable, FurnitureKind.MusicStand, FurnitureKind.HorseshoePit);

        Add(FurnitureCategory.Medical,
            FurnitureKind.MedicalBed, FurnitureKind.OperatingTable, FurnitureKind.IVStand, FurnitureKind.Defibrillator,
            FurnitureKind.Stretcher, FurnitureKind.MedicineCabinet, FurnitureKind.Sterilizer, FurnitureKind.MedicalScanner,
            FurnitureKind.SurgicalLight, FurnitureKind.Wheelchair, FurnitureKind.Incubator, FurnitureKind.BloodBank);

        return list;
    }

    private static Dictionary<FurnitureKind, FurnitureInfo> BuildLookup()
    {
        var map = new Dictionary<FurnitureKind, FurnitureInfo>();
        foreach (var info in All)
            map[info.Kind] = info;
        return map;
    }

    /// <summary>Inserts spaces before capital letters: "BedDouble" -> "Bed Double".</summary>
    private static string SplitName(string name)
    {
        var sb = new System.Text.StringBuilder();
        for (int i = 0; i < name.Length; i++)
        {
            if (i > 0 && char.IsUpper(name[i]))
                sb.Append(' ');
            sb.Append(name[i]);
        }
        return sb.ToString();
    }
}
