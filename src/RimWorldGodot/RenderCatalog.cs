using Godot;
using System.Collections.Generic;

/// <summary>
/// THE mapping table between simulation kinds and KayKit 3D assets.
/// This is the frozen extension point: the local LLM adds entity types by
/// adding rows here - never by touching the renderer or the UI.
/// Paths point at the already-imported KayKit packs (see docs/ASSET_CATALOG.md).
/// </summary>
public static class RenderCatalog
{
    public const string Characters = "res://assets/models/characters/";
    public const string Skeletons = "res://assets/models/skeletons/";
    public const string Nature = "res://assets/models/nature/";
    public const string Dungeon = "res://assets/models/dungeon/";
    public const string RpgTools = "res://assets/models/rpgtools/";
    public const string Restaurant = "res://assets/models/restaurant/";

    /// <summary>Pawns cycle through the KayKit Adventurers cast.</summary>
    public static readonly string[] PawnModels =
    {
        Characters + "Knight.glb",
        Characters + "Barbarian.glb",
        Characters + "Mage.glb",
        Characters + "Ranger.glb",
        Characters + "Rogue.glb",
    };

    /// <summary>Hostiles come from the KayKit Skeletons pack.</summary>
    public static readonly string[] ThreatModels =
    {
        Skeletons + "Skeleton_Warrior.glb",
        Skeletons + "Skeleton_Minion.glb",
        Skeletons + "Skeleton_Rogue.glb",
    };

    public static readonly Dictionary<ResourceKind, string> ResourceModels = new()
    {
        [ResourceKind.Tree] = Nature + "Tree_1_A_Color1.gltf",
        [ResourceKind.Rock] = Nature + "Rock_1_A_Color1.gltf",
    };

    public static readonly Dictionary<FurnitureKind, string> FurnitureModels = new()
    {
        [FurnitureKind.Bed] = Dungeon + "bed_decorated.gltf",
        [FurnitureKind.Crate] = Dungeon + "barrel_large.gltf",
        [FurnitureKind.Stove] = Restaurant + "stove_multi.gltf",
        [FurnitureKind.Workbench] = RpgTools + "anvil.gltf",
        [FurnitureKind.DiningTable] = Dungeon + "table_long.gltf",
        [FurnitureKind.Chair] = Dungeon + "chair.gltf",
        [FurnitureKind.Door] = Dungeon + "wall_doorway.gltf",
        [FurnitureKind.Mine] = Dungeon + "stairs_walled.gltf",
    };

    public const string WallModel = Dungeon + "wall.gltf";
    public const string SaplingModel = Nature + "Bush_1_A_Color1.gltf";

    private static readonly Dictionary<string, PackedScene> _cache = new();
    private static readonly Dictionary<FurnitureKind, string> _furnitureFallbackUsed = new();

    /// <summary>Load (cached) a model; null if missing so the renderer can use a fallback box.</summary>
    public static PackedScene Load(string path)
    {
        if (_cache.TryGetValue(path, out var cached)) return cached;
        var scene = ResourceLoader.Exists(path) ? ResourceLoader.Load<PackedScene>(path) : null;
        _cache[path] = scene;
        return scene;
    }

    /// <summary>Instantiate a model or a colored fallback box (never invisible, never crash).</summary>
    public static Node3D Instantiate(string path, Color fallbackColor, float fallbackHeight = 0.8f)
    {
        var scene = Load(path);
        if (scene != null && scene.Instantiate() is Node3D node) return node;
        var mesh = new MeshInstance3D
        {
            Mesh = new BoxMesh { Size = new Vector3(0.6f, fallbackHeight, 0.6f) },
            MaterialOverride = new StandardMaterial3D { AlbedoColor = fallbackColor }
        };
        var holder = new Node3D();
        holder.AddChild(mesh);
        mesh.Position = new Vector3(0, fallbackHeight / 2f, 0);
        return holder;
    }
}
