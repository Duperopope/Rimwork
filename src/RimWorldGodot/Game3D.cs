using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

/// <summary>
/// 3D isometric presentation layer. The simulation (GameWorldManager) is
/// authoritative; this node only READS state and mirrors it into KayKit
/// 3D entities. ARPG-readable fixed-angle camera with pan/zoom.
/// Threat layer: skeleton war bands whose spawn rate is driven by the
/// macro world simulation (Macro.RaidPressure) - macro to local, visible.
/// </summary>
public partial class Game3D : Node3D
{
    public GameWorldManager World { get; private set; }
    public bool Paused { get; set; } = true;   // menu shows first
    public float SpeedMultiplier { get; set; } = 1f;
    public Pawn SelectedPawn { get; private set; }
    public string AlertText { get; private set; } = "";

    private double _accumulator;
    private double _roomTimer;
    private Camera3D _cam;
    private Node3D _camRig;
    private float _zoom = 22f;
    public float CamPanSpeed { get; set; } = 18f;
    public float CamZoomSpeed { get; set; } = 2.5f;

    private readonly Dictionary<Guid, Node3D> _pawnNodes = new();
    private readonly Dictionary<(int, int), Node3D> _staticNodes = new(); // walls/resources/furniture/saplings keyed by tile
    private readonly Dictionary<(int, int), string> _staticKind = new();
    private MeshInstance3D _selectionRing;

    // --- Threat slice (skeleton war bands, macro-driven) ---
    public class Threat
    {
        public float X, Y, HP = 30f;
        public Node3D Node;
    }
    public List<Threat> Threats { get; } = new();
    private double _threatTimer = 45.0;
    private double _threatMoveTimer;
    private readonly Random _rng = new(4242);

    public override void _Ready()
    {
        World = new GameWorldManager(50, 50);
        string[] names = { "Aiden", "Brynn", "Corwin", "Dara", "Elsie", "Finn", "Greta", "Holt" };
        var rng = new Random(12345);
        foreach (string n in names)
        {
            int x, y;
            do { x = rng.Next(0, 50); y = rng.Next(0, 50); } while (!World.Map.IsPassable(x, y));
            World.RegisterThing(new Pawn(n, x, y));
        }

        BuildEnvironment();
        BuildTerrain();
        SyncStatics(force: true);
        BuildSelectionRing();
    }

    private void BuildEnvironment()
    {
        _camRig = new Node3D { Position = new Vector3(25, 0, 25) };
        AddChild(_camRig);
        _cam = new Camera3D { Projection = Camera3D.ProjectionType.Orthogonal, Size = _zoom };
        _camRig.AddChild(_cam);
        // ARPG-readable: yaw 45, pitch -42 (PoE-like readability, not a clone)
        _cam.Position = new Vector3(30, 38, 30);
        _cam.LookAt(new Vector3(0, 0, 0), Vector3.Up);
        _cam.Current = true;

        var sun = new DirectionalLight3D { ShadowEnabled = true, LightEnergy = 1.2f };
        sun.RotationDegrees = new Vector3(-55, -35, 0);
        AddChild(sun);

        var env = new Godot.Environment
        {
            BackgroundMode = Godot.Environment.BGMode.Color,
            BackgroundColor = new Color(0.07f, 0.09f, 0.12f),
            AmbientLightSource = Godot.Environment.AmbientSource.Color,
            AmbientLightColor = new Color(0.55f, 0.6f, 0.7f),
            AmbientLightEnergy = 0.7f
        };
        AddChild(new WorldEnvironment { Environment = env });
    }

    private void BuildTerrain()
    {
        // One MultiMesh per tile type: cheap, single draw call each.
        foreach (var (type, color, height) in new[]
        {
            ("Grass", new Color(0.22f, 0.34f, 0.18f), 0.20f),
            ("Water", new Color(0.15f, 0.30f, 0.55f), 0.12f),
        })
        {
            var tiles = new List<Vector3>();
            for (int y = 0; y < World.Map.Height; y++)
                for (int x = 0; x < World.Map.Width; x++)
                {
                    bool isWater = World.Map.IsWater(x, y);
                    if (type == "Water" ? isWater : !isWater)
                        tiles.Add(new Vector3(x, 0, y));
                }
            var mm = new MultiMesh
            {
                TransformFormat = MultiMesh.TransformFormatEnum.Transform3D,
                Mesh = new BoxMesh { Size = new Vector3(1f, height, 1f) },
                InstanceCount = tiles.Count
            };
            for (int idx = 0; idx < tiles.Count; idx++)
                mm.SetInstanceTransform(idx, new Transform3D(Basis.Identity, tiles[idx] + new Vector3(0.5f, -height / 2f, 0.5f)));
            AddChild(new MultiMeshInstance3D
            {
                Multimesh = mm,
                MaterialOverride = new StandardMaterial3D { AlbedoColor = color }
            });
        }
    }

    private void BuildSelectionRing()
    {
        _selectionRing = new MeshInstance3D
        {
            Mesh = new TorusMesh { InnerRadius = 0.45f, OuterRadius = 0.6f },
            MaterialOverride = new StandardMaterial3D
            {
                AlbedoColor = new Color(1f, 0.85f, 0.2f),
                ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded
            },
            Visible = false
        };
        AddChild(_selectionRing);
    }

    public override void _Process(double delta)
    {
        HandleCamera(delta);

        if (!Paused)
        {
            _accumulator += delta * SpeedMultiplier;
            const double step = 0.05;
            int safety = 0;
            while (_accumulator >= step && safety++ < 40)
            {
                _accumulator -= step;
                World.Tick();
                TickThreats(step);
            }
            _roomTimer -= delta;
            if (_roomTimer <= 0)
            {
                _roomTimer = 1.0;
                World.RefreshRooms();
                World.TickGoals();
                SyncStatics(force: false);
            }
        }

        SyncPawns(delta);
        SyncThreatNodes(delta);

        if (SelectedPawn != null && SelectedPawn.HP > 0 && _pawnNodes.TryGetValue(SelectedPawn.Id, out var sel))
        {
            _selectionRing.Visible = true;
            _selectionRing.Position = sel.Position + new Vector3(0, 0.05f, 0);
        }
        else _selectionRing.Visible = false;
    }

    private void HandleCamera(double delta)
    {
        var move = Vector3.Zero;
        if (Input.IsKeyPressed(Key.W) || Input.IsKeyPressed(Key.Up)) move += new Vector3(-1, 0, -1);
        if (Input.IsKeyPressed(Key.S) || Input.IsKeyPressed(Key.Down)) move += new Vector3(1, 0, 1);
        if (Input.IsKeyPressed(Key.A) || Input.IsKeyPressed(Key.Left)) move += new Vector3(-1, 0, 1);
        if (Input.IsKeyPressed(Key.D) || Input.IsKeyPressed(Key.Right)) move += new Vector3(1, 0, -1);
        if (move != Vector3.Zero)
            _camRig.Position += move.Normalized() * (float)delta * CamPanSpeed * (_zoom / 22f);
        _camRig.Position = new Vector3(Math.Clamp(_camRig.Position.X, 0, 50), 0, Math.Clamp(_camRig.Position.Z, 0, 50));
        _cam.Size = Mathf.Lerp(_cam.Size, _zoom, (float)delta * 8f);
    }

    public override void _UnhandledInput(InputEvent ev)
    {
        if (ev is InputEventMouseButton mb && mb.Pressed)
        {
            if (mb.ButtonIndex == MouseButton.WheelUp) _zoom = Math.Clamp(_zoom - CamZoomSpeed, 8f, 45f);
            if (mb.ButtonIndex == MouseButton.WheelDown) _zoom = Math.Clamp(_zoom + CamZoomSpeed, 8f, 45f);
            if (mb.ButtonIndex == MouseButton.Left) PickPawn(mb.Position);
        }
        if (ev is InputEventMouseMotion mm && Input.IsMouseButtonPressed(MouseButton.Middle))
        {
            var d = mm.Relative * 0.03f * (_zoom / 22f);
            _camRig.Position += new Vector3(-d.X - d.Y, 0, d.X - d.Y) * 0.7f;
        }
    }

    private void PickPawn(Vector2 screenPos)
    {
        // Project each pawn to screen space; select the nearest within 40px.
        Pawn best = null; float bestDist = 40f;
        foreach (var p in World.Pawns.Where(p => p.HP > 0))
        {
            if (!_pawnNodes.TryGetValue(p.Id, out var node)) continue;
            var sp = _cam.UnprojectPosition(node.GlobalPosition + new Vector3(0, 0.8f, 0));
            float d = sp.DistanceTo(screenPos);
            if (d < bestDist) { bestDist = d; best = p; }
        }
        SelectedPawn = best;
    }

    // ------------------------------------------------------------------
    // Entity sync: sim state -> 3D nodes
    // ------------------------------------------------------------------

    private void SyncPawns(double delta)
    {
        int modelIdx = 0;
        foreach (var p in World.Pawns)
        {
            if (p.HP <= 0)
            {
                if (_pawnNodes.TryGetValue(p.Id, out var dead)) { dead.QueueFree(); _pawnNodes.Remove(p.Id); }
                continue;
            }
            if (!_pawnNodes.TryGetValue(p.Id, out var node))
            {
                node = RenderCatalog.Instantiate(
                    RenderCatalog.PawnModels[modelIdx % RenderCatalog.PawnModels.Length],
                    new Color(0.9f, 0.8f, 0.3f), 1.4f);
                node.Scale = Vector3.One * 0.55f;
                AddChild(node);
                _pawnNodes[p.Id] = node;
            }
            var target = new Vector3(p.X + 0.5f, 0.1f, p.Y + 0.5f);
            if (node.Position.DistanceTo(target) > 0.01f)
            {
                var dir = target - node.Position;
                node.Position = node.Position.Lerp(target, (float)delta * 6f);
                if (new Vector2(dir.X, dir.Z).Length() > 0.05f)
                    node.Rotation = new Vector3(0, Mathf.Atan2(dir.X, dir.Z), 0);
            }
            modelIdx++;
        }
    }

    /// <summary>Walls, resources, furniture, saplings - diffed by tile each second.</summary>
    private void SyncStatics(bool force)
    {
        var wanted = new Dictionary<(int, int), (string KindTag, string Path, Color Fallback, float Scale)>();

        for (int y = 1; y < World.Map.Height - 1; y++)
            for (int x = 1; x < World.Map.Width - 1; x++)
                if (!World.Map.IsPassable(x, y) && !World.Map.IsWater(x, y))
                    wanted[(x, y)] = ("wall", RenderCatalog.WallModel, new Color(0.45f, 0.42f, 0.4f), 0.5f);

        foreach (var r in World.Map.Resources)
            wanted[(r.X, r.Y)] = (r.Kind.ToString(), RenderCatalog.ResourceModels[r.Kind],
                r.Kind == ResourceKind.Tree ? new Color(0.15f, 0.45f, 0.2f) : new Color(0.5f, 0.5f, 0.55f),
                r.Kind == ResourceKind.Tree ? 0.7f : 0.6f);

        foreach (var (sx, sy, _) in World.Map.Saplings)
            wanted[(sx, sy)] = ("sapling", RenderCatalog.SaplingModel, new Color(0.3f, 0.6f, 0.3f), 0.4f);

        foreach (var f in World.Map.Furniture)
        {
            string path = RenderCatalog.FurnitureModels.TryGetValue(f.Kind, out var pp) ? pp : null;
            wanted[(f.X, f.Y)] = (f.Kind.ToString(), path, new Color(0.7f, 0.5f, 0.3f), 0.55f);
        }

        foreach (var key in _staticNodes.Keys.ToList())
        {
            if (!wanted.TryGetValue(key, out var w) || _staticKind[key] != w.KindTag)
            {
                _staticNodes[key].QueueFree();
                _staticNodes.Remove(key);
                _staticKind.Remove(key);
            }
        }
        foreach (var (key, w) in wanted)
        {
            if (_staticNodes.ContainsKey(key)) continue;
            var node = w.Path != null
                ? RenderCatalog.Instantiate(w.Path, w.Fallback)
                : RenderCatalog.Instantiate("res://__missing__", w.Fallback);
            node.Scale = Vector3.One * w.Scale;
            node.Position = new Vector3(key.Item1 + 0.5f, 0.1f, key.Item2 + 0.5f);
            AddChild(node);
            _staticNodes[key] = node;
            _staticKind[key] = w.KindTag;
        }
    }

    // ------------------------------------------------------------------
    // Threat slice: skeleton war bands, spawn rate driven by macro layer
    // ------------------------------------------------------------------

    private void TickThreats(double step)
    {
        _threatTimer -= step * World.Macro.RaidPressure; // macro -> local effect #2
        if (_threatTimer <= 0)
        {
            _threatTimer = 60.0 + _rng.NextDouble() * 60.0;
            int edge = _rng.Next(4);
            float tx = edge switch { 0 => 1, 1 => 48, _ => 1 + _rng.Next(47) };
            float ty = edge switch { 2 => 1, 3 => 48, _ => 1 + _rng.Next(47) };
            Threats.Add(new Threat { X = tx, Y = ty });
            AlertText = $"Raid ! Un maraudeur squelette approche (pression {World.Macro.RaidPressure:0.0}x)";
        }

        _threatMoveTimer -= step;
        if (_threatMoveTimer > 0) return;
        _threatMoveTimer = 0.4;

        foreach (var t in Threats.ToList())
        {
            var prey = World.Pawns.Where(p => p.HP > 0)
                .OrderBy(p => Math.Abs(p.X - t.X) + Math.Abs(p.Y - t.Y)).FirstOrDefault();
            if (prey == null) break;
            float dx = prey.X - t.X, dy = prey.Y - t.Y;
            float dist = Math.Max(1f, MathF.Sqrt(dx * dx + dy * dy));
            if (dist <= 1.6f)
            {
                prey.HP = Math.Max(0f, prey.HP - 5f);
                prey.Stress = Math.Clamp(prey.Stress + 15f, 0f, 100f);
                prey.Remember(World.TotalTicks, "fought a skeleton raider", -3f);
                t.HP -= 8f; // pawns fight back
                bool watchPost = World.UnlockedTech.Contains("Watch post");
                if (watchPost) t.HP -= 6f; // research has a real combat effect
                if (prey.HP <= 0) AlertText = $"{prey.Name} est tombé au combat !";
            }
            else { t.X += dx / dist * 0.8f; t.Y += dy / dist * 0.8f; }
            if (t.HP <= 0)
            {
                AlertText = "Le maraudeur a été repoussé !";
                if (t.Node != null) t.Node.QueueFree();
                Threats.Remove(t);
            }
        }
        if (Threats.Count == 0 && AlertText.StartsWith("Raid")) AlertText = "";
    }

    private void SyncThreatNodes(double delta)
    {
        foreach (var t in Threats)
        {
            if (t.Node == null)
            {
                t.Node = RenderCatalog.Instantiate(
                    RenderCatalog.ThreatModels[_rng.Next(RenderCatalog.ThreatModels.Length)],
                    new Color(0.8f, 0.1f, 0.1f), 1.4f);
                t.Node.Scale = Vector3.One * 0.55f;
                AddChild(t.Node);
            }
            var target = new Vector3(t.X + 0.5f, 0.1f, t.Y + 0.5f);
            t.Node.Position = t.Node.Position.Lerp(target, (float)delta * 6f);
        }
    }
}
