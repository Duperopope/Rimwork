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
    public string AlertText { get; set; } = "";
    // Agent bridge / UI handshake: UiShell keeps MenuOpen in sync and
    // listens to GameStarted so an agent 'newgame' also dismisses the menu.
    public bool MenuOpen { get; set; } = true;
    public event Action GameStarted;

    /// <summary>Active zoom layer: "Local" or "Planet" (Tab/M to toggle).</summary>
    public string ViewLayer { get; private set; } = "Local";
    private Node3D _worldViewRoot;
    private readonly Dictionary<(int, int), Vector3> _hexCenters = new();
    private Vector3 _savedRigPos;
    private float _savedZoom;

    private double _accumulator;
    private double _shotTimer = 5.0;
    private double _viewCmdTimer = 3.0;
    private int _shotIndex = 0;
    private double _roomTimer;
    private Camera3D _cam;
    private Node3D _camRig;
    private float _zoom = 22f;
    public float CamPanSpeed { get; set; } = 18f;
    public float CamZoomSpeed { get; set; } = 2.5f;

    private readonly Dictionary<Guid, Node3D> _pawnNodes = new();
    private readonly Dictionary<Guid, AnimationPlayer> _pawnAnims = new();
    private readonly Dictionary<Guid, string> _pawnAnimState = new();

    private static AnimationPlayer FindAnim(Node node)
    {
        if (node is AnimationPlayer ap) return ap;
        foreach (var child in node.GetChildren())
        {
            var found = FindAnim(child);
            if (found != null) return found;
        }
        return null;
    }

    private void PlayAnim(Guid id, Node3D node, bool moving)
    {
        if (!_pawnAnims.TryGetValue(id, out var ap))
        {
            ap = FindAnim(node);
            _pawnAnims[id] = ap;
        }
        if (ap == null) return;
        string want = null;
        foreach (var name in ap.GetAnimationList())
        {
            string n = name.ToString();
            if (moving && (n.Contains("Walk") || n.Contains("Run"))) { want = n; break; }
            if (!moving && n.Contains("Idle")) { want = n; break; }
        }
        if (want == null) return;
        _pawnAnimState.TryGetValue(id, out var cur);
        if (cur != want)
        {
            ap.Play(want, customBlend: 0.2f);
            var anim = ap.GetAnimation(want);
            if (anim != null) anim.LoopMode = Animation.LoopModeEnum.Linear;
            _pawnAnimState[id] = want;
        }
    }
    private readonly Dictionary<(int, int), Node3D> _staticNodes = new(); // walls/resources/furniture/saplings keyed by tile
    private readonly Dictionary<(int, int), string> _staticKind = new();
    private MeshInstance3D _selectionRing;
    private DirectionalLight3D _sun;
    private Godot.Environment _envRes;

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

    [Signal] public delegate void ThreatSpawnedEventHandler();
    public event Action<int, string, bool> TileSelected;

    private GameWorldManager _colonyWorld;
    /// <summary>Tile index currently visited; -1 = home colony.</summary>
    public int VisitedTileIdx { get; private set; } = -1;

    /// <summary>Load the local map of a planet tile (expedition). The colony
    /// world is kept intact and restored via ReturnToColony().</summary>
    public void VisitTile(int tileIdx, string biome)
    {
        if (_colonyWorld == null) _colonyWorld = World;
        if (tileIdx == _colonyTileIdx) { ReturnToColony(); return; }

        int msize = Math.Clamp(World.Macro.Gen.MapSize, 50, 128);
        var w = new GameWorldManager(msize, msize, biome, World.Macro.Gen.Seed * 31 + tileIdx);
        w.ApplyGenSettings(World.Macro.Gen);
        var rng2 = new Random(World.Macro.Gen.Seed * 31 + tileIdx);
        string[] scouts = { "Eclaireur A", "Eclaireur B", "Eclaireur C" };
        foreach (var n in scouts)
        {
            int x, y;
            do { x = rng2.Next(0, msize); y = rng2.Next(0, msize); } while (!w.Map.IsPassable(x, y));
            w.RegisterThing(new Pawn(n, x, y));
        }
        World = w;
        VisitedTileIdx = tileIdx;
        if (_tiles != null && tileIdx < _tiles.Count)
            LocalLonDeg = Mathf.RadToDeg(Mathf.Atan2(_tiles[tileIdx].Center.X, _tiles[tileIdx].Center.Z));
        RebuildLocalVisuals();
        SetViewLayer("Local");
        _camRig.Position = new Vector3(msize / 2f, 0, msize / 2f);
        AlertText = $"Expédition sur la tuile #{tileIdx} ({biome}) — molette arrière à fond: retour planète";
    }

    /// <summary>Down Here! world creation: build a fresh universe from the
    /// creation-screen settings (seed, size, pawns, planets, orbits).</summary>
    public void NewGame(WorldGenSettings gen)
    {
        var w = new GameWorldManager(gen.MapSize, gen.MapSize, "forest", gen.Seed);
        w.ApplyGenSettings(gen);
        var rng = new Random(gen.Seed);
        string[] names = { "Aiden", "Brynn", "Corwin", "Dara", "Elsie", "Finn", "Greta", "Holt", "Iris", "Joren", "Kira", "Lund", "Mara", "Nils", "Opal", "Pell" };
        for (int i = 0; i < Math.Clamp(gen.PawnCount, 4, 16); i++)
        {
            int x, y;
            do { x = rng.Next(0, gen.MapSize); y = rng.Next(0, gen.MapSize); } while (!w.Map.IsPassable(x, y));
            w.RegisterThing(new Pawn(names[i % names.Length], x, y));
        }
        World = w;
        _colonyWorld = w;
        VisitedTileIdx = -1;
        OrbitSpeedMult = gen.OrbitSpeedMult;
        RebuildLocalVisuals();
        // Rebuild macro views for the new universe
        _worldViewRoot?.QueueFree();
        _solarRoot?.QueueFree();
        _orbiters.Clear();
        _hexCenters.Clear();
        BuildWorldView();
        SetViewLayer("Local");
        _camRig.Position = new Vector3(gen.MapSize * 0.28f, 0, gen.MapSize * 0.24f);
        AlertText = $"Monde créé (seed {gen.Seed}) — système {World.Macro.System.StarName}, {World.Macro.System.Bodies.Count} corps.";
        GameStarted?.Invoke();
    }

    public float OrbitSpeedMult { get; set; } = 1f;

    /// <summary>Longitude of the tile we are currently living on - shifts
    /// the local solar hour (orbital day/night, Down Here! charter).</summary>
    public float LocalLonDeg { get; private set; } = MacroSim.ColonyLon;
    public float LocalHourF => WeatherSystem.LocalHour(World.TotalTicks, LocalLonDeg);
    public WeatherKind LocalWeather => WeatherSystem.At(World.Macro.Gen.Seed,
        VisitedTileIdx >= 0 && _tiles != null ? Mathf.RadToDeg(Mathf.Asin(Mathf.Clamp(_tiles[VisitedTileIdx].Center.Y, -1f, 1f))) : MacroSim.ColonyLat,
        LocalLonDeg, World.TotalTicks);

    /// <summary>Swap in a loaded world (save system) and rebuild visuals.</summary>
    public void LoadWorld(GameWorldManager w)
    {
        World = w;
        _colonyWorld = w;
        VisitedTileIdx = -1;
        RebuildLocalVisuals();
        SetViewLayer("Local");
        _camRig.Position = new Vector3(14, 0, 12);
    }

    public void ReturnToColony()
    {
        if (_colonyWorld != null) World = _colonyWorld;
        VisitedTileIdx = -1;
        LocalLonDeg = MacroSim.ColonyLon;
        RebuildLocalVisuals();
        SetViewLayer("Local");
        _camRig.Position = new Vector3(14, 0, 12);
        AlertText = "Retour à la colonie.";
    }

    private void RebuildLocalVisuals()
    {
        foreach (var n in _pawnNodes.Values) n.QueueFree();
        _pawnNodes.Clear(); _pawnAnims.Clear(); _pawnAnimState.Clear();
        foreach (var n in _staticNodes.Values) n.QueueFree();
        _staticNodes.Clear(); _staticKind.Clear();
        foreach (var t in Threats) t.Node?.QueueFree();
        Threats.Clear();
        SelectedPawn = null;
        BuildTerrain();
        SyncStatics(force: true);
    }

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
        BuildWorldView();
        _camRig.Position = new Vector3(14, 0, 12); // start over the starter rooms
        // Re-aim AFTER the rig move: LookAt uses global coords, so the
        // rotation computed in BuildEnvironment pointed at the old spot.
        _cam.Position = new Vector3(20, 26, 20);
        _cam.LookAt(_camRig.GlobalPosition, Vector3.Up);
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

        _sun = new DirectionalLight3D { ShadowEnabled = true, LightEnergy = 1.2f };
        _sun.RotationDegrees = new Vector3(-55, -35, 0);
        AddChild(_sun);

        var env = new Godot.Environment
        {
            BackgroundMode = Godot.Environment.BGMode.Color,
            BackgroundColor = new Color(0.07f, 0.09f, 0.12f),
            AmbientLightSource = Godot.Environment.AmbientSource.Color,
            AmbientLightColor = new Color(0.55f, 0.6f, 0.7f),
            AmbientLightEnergy = 0.7f
        };
        _envRes = env;
        AddChild(new WorldEnvironment { Environment = env });
    }

    private Node3D _terrainRoot;

    private void BuildTerrain()
    {
        if (_terrainRoot != null) _terrainRoot.QueueFree();
        _terrainRoot = new Node3D();
        AddChild(_terrainRoot);
        // One MultiMesh per tile type: cheap, single draw call each.
        Color groundCol = World.Map.Biome switch
        {
            "dunes" or "scorched" or "ash" => new Color(0.55f, 0.45f, 0.28f),
            "lava rock" or "crater" => new Color(0.3f, 0.22f, 0.18f),
            "tundra" or "snowfield" or "ice" or "frost rock" or "crevasse" => new Color(0.75f, 0.8f, 0.86f),
            "marsh" => new Color(0.2f, 0.3f, 0.22f),
            "hills" or "rocky" => new Color(0.36f, 0.34f, 0.28f),
            _ => new Color(0.22f, 0.34f, 0.18f)
        };
        foreach (var (type, color, height) in new[]
        {
            ("Grass", groundCol, 0.20f),
            ("Water", new Color(0.15f, 0.30f, 0.55f), 0.12f),
            ("Ice", new Color(0.65f, 0.8f, 0.95f), 0.16f),
        })
        {
            var tiles = new List<Vector3>();
            for (int y = 0; y < World.Map.Height; y++)
                for (int x = 0; x < World.Map.Width; x++)
                {
                    bool isWater = World.Map.IsWater(x, y);
                    bool isIce = World.Map.GetCell(x, y).TileType == "Ice";
                    bool match = type switch { "Water" => isWater, "Ice" => isIce, _ => !isWater && !isIce };
                    if (match) tiles.Add(new Vector3(x, 0, y));
                }
            var mm = new MultiMesh
            {
                TransformFormat = MultiMesh.TransformFormatEnum.Transform3D,
                Mesh = new BoxMesh { Size = new Vector3(1f, height, 1f) },
                InstanceCount = tiles.Count
            };
            for (int idx = 0; idx < tiles.Count; idx++)
                mm.SetInstanceTransform(idx, new Transform3D(Basis.Identity, tiles[idx] + new Vector3(0.5f, -height / 2f, 0.5f)));
            _terrainRoot.AddChild(new MultiMeshInstance3D
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

        // Self-verification: periodic viewport screenshots so the AI
        // supervisor can SEE the real game instead of trusting the build.
        _shotTimer -= delta;
        if (_shotTimer <= 0)
        {
            _shotTimer = 12.0;
            try
            {
                var img = GetViewport().GetTexture().GetImage();
                System.IO.Directory.CreateDirectory(@"g:/Rimwork/scripts/logs/shots");
                img.SavePng($"g:/Rimwork/scripts/logs/shots/shot_{_shotIndex % 8}.png");
                _shotIndex++;
            }
            catch { }
        }

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

        // Day/night cycle: HourOfDay 0-23 -> sun energy and ambient tint.
        if (_sun != null && World != null && ViewLayer == "Local")
        {
            float h = LocalHourF;
            float dayness = Mathf.Clamp(1f - Math.Abs(h - 13f) / 9f, 0.12f, 1f);
            if (LocalWeather == WeatherKind.Fog) dayness *= 0.75f;
            if (LocalWeather == WeatherKind.Storm) dayness *= 0.55f;
            if (LocalWeather == WeatherKind.Rain) dayness *= 0.85f;
            _sun.LightEnergy = 0.25f + dayness * 1.1f;
            _sun.LightColor = new Color(1f, 0.75f + dayness * 0.25f, 0.55f + dayness * 0.45f);
            if (_envRes != null)
            {
                _envRes.AmbientLightEnergy = 0.25f + dayness * 0.5f;
                _envRes.BackgroundColor = new Color(0.04f + dayness * 0.05f, 0.05f + dayness * 0.06f, 0.10f + dayness * 0.06f);
            }
        }

        // Living macro layers: planet spins, bodies orbit the star.
        if (_planetSpin != null && _worldViewRoot.Visible && !Input.IsMouseButtonPressed(MouseButton.Right))
            _planetSpin.RotateY((float)delta * 0.01f);
        if (_moonHolder != null && _worldViewRoot.Visible)
            _moonHolder.RotateY((float)delta * 0.06f);
        if (_cloudHolder != null && _worldViewRoot.Visible)
            _cloudHolder.RotateY((float)delta * 0.004f);
        if (_solarRoot != null && _solarRoot.Visible)
            foreach (var (nodeO, _, speed, _) in _orbiters)
                nodeO.RotateY((float)delta * speed * OrbitSpeedMult);

        // Remote view control for visual self-verification:
        // scripts/viewcmd.txt containing Local/Planet/Solar switches the layer.
        _viewCmdTimer -= delta;
        if (_viewCmdTimer <= 0)
        {
            _viewCmdTimer = 3.0;
            try
            {
                if (System.IO.File.Exists(@"g:/Rimwork/scripts/viewcmd.txt"))
                {
                    var want = System.IO.File.ReadAllText(@"g:/Rimwork/scripts/viewcmd.txt").Trim();
                    System.IO.File.Delete(@"g:/Rimwork/scripts/viewcmd.txt"); // one-shot command, never hijack the player
                    if (want.StartsWith("Planet:"))
                    {
                        int bodyN = int.Parse(want.Substring(7));
                        if (bodyN != _currentBodyIdx || ViewLayer != "Planet")
                        {
                            if (ViewLayer == "Local") { _savedRigPos = _camRig.Position; _savedZoom = _zoom; }
                            BuildGlobeFor(bodyN);
                            SetViewLayer("Planet");
                        }
                    }
                    else if ((want == "Local" || want == "Planet" || want == "Solar") && want != ViewLayer)
                    {
                        if (ViewLayer == "Local") { _savedRigPos = _camRig.Position; _savedZoom = _zoom; }
                        SetViewLayer(want);
                    }
                }
            }
            catch { }
        }

        // Agent bridge: full game control + machine-readable state, so an AI
        // can play the game like a human (commands in scripts/agent_cmd.txt,
        // state in scripts/logs/agent_state.json).
        ProcessAgentCommands();
        WriteAgentState(delta);

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
        if (ViewLayer == "Local")
            _camRig.Position = new Vector3(Math.Clamp(_camRig.Position.X, 0, 50), 0, Math.Clamp(_camRig.Position.Z, 0, 50));
        _cam.Size = Mathf.Lerp(_cam.Size, _zoom, (float)delta * 8f);
    }

    public override void _UnhandledInput(InputEvent ev)
    {
        if (ev is InputEventKey k && k.Pressed && !k.Echo && (k.Keycode == Key.Tab || k.Keycode == Key.M))
            ToggleWorldView();
        if (ev is InputEventKey kc && kc.Pressed && !kc.Echo && kc.Keycode == Key.C && _cloudHolder != null)
            _cloudHolder.Visible = !_cloudHolder.Visible;
        if (ev is InputEventMouseButton mb && mb.Pressed)
        {
            if (mb.ButtonIndex == MouseButton.WheelUp) _zoom = Math.Clamp(_zoom - CamZoomSpeed, 8f, 45f);
            if (mb.ButtonIndex == MouseButton.WheelDown)
            {
                if (ViewLayer == "Local" && _zoom >= 44.5f)
                {
                    _savedRigPos = _camRig.Position; _savedZoom = 30f;
                    SetViewLayer("Planet");
                }
                else if (ViewLayer == "Planet" && _zoom >= 58f)
                    SetViewLayer("Solar");
                else _zoom = Math.Clamp(_zoom + CamZoomSpeed, 8f, ViewLayer == "Solar" ? 90f : 60f);
            }
            if (mb.ButtonIndex == MouseButton.Left) PickPawn(mb.Position);
        }
        if (ev is InputEventMouseMotion mm)
        {
            if (Input.IsMouseButtonPressed(MouseButton.Middle))
            {
                var d = mm.Relative * 0.03f * (_zoom / 22f);
                _camRig.Position += new Vector3(-d.X - d.Y, 0, d.X - d.Y) * 0.7f;
            }
            // RimWorld-style: hold RIGHT CLICK to rotate the planet.
            if (ViewLayer == "Planet" && Input.IsMouseButtonPressed(MouseButton.Right) && _planetSpin != null)
            {
                _planetSpin.RotateY(mm.Relative.X * 0.008f);
                _planetSpin.RotateObjectLocal(Vector3.Right, mm.Relative.Y * 0.006f);
            }
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

        // Solar view: click a planet to visit its tiled globe.
        if (ViewLayer == "Solar")
        {
            int pi = 0;
            foreach (var (holder, _, _, _) in _orbiters)
            {
                var planetNode = holder.GetChild<Node3D>(0);
                var sp2 = _cam.UnprojectPosition(planetNode.GlobalPosition);
                if (sp2.DistanceTo(screenPos) < 50f)
                {
                    BuildGlobeFor(pi);
                    SetViewLayer("Planet");
                    return;
                }
                pi++;
            }
        }

        // Threat under the cursor? Order a defense: idle colonists converge.
        if (best == null && ViewLayer == "Local")
        {
            foreach (var th in Threats)
            {
                if (th.Node == null) continue;
                var tsp = _cam.UnprojectPosition(th.Node.GlobalPosition + new Vector3(0, 0.8f, 0));
                if (tsp.DistanceTo(screenPos) < 40f)
                {
                    int tx = (int)th.X, ty = (int)th.Y;
                    for (int i = 0; i < 3; i++)
                        World.Tasks.Enqueue(new TaskOrder(TaskKind.MoveTo, tx, ty, priority: 90));
                    AlertText = "Ordre: défendre la colonie ! Les colons convergent.";
                    return;
                }
            }
        }

        // No pawn under the cursor: this is a TILE ORDER (RimWorld-like).
        if (best == null && ViewLayer == "Local")
            OrderAtTile(screenPos);
        else if (best == null && ViewLayer == "Planet")
            PickRegion(screenPos);
    }

    /// <summary>Left-click on the globe: ray-sphere intersection, then
    /// nearest Goldberg tile; shows its sheet and highlights it.</summary>
    private void PickRegion(Vector2 screenPos)
    {
        if (_tiles == null) return;
        var origin = _cam.ProjectRayOrigin(screenPos);
        var dir = _cam.ProjectRayNormal(screenPos);
        var center = _worldViewRoot.GlobalPosition;
        var oc = origin - center;
        float b = oc.Dot(dir);
        float disc = b * b - (oc.LengthSquared() - GlobeRadius * GlobeRadius);
        if (disc < 0) return;
        var hit = origin + dir * (-b - Mathf.Sqrt(disc));
        // into planet-local (un-spin) unit space
        var local = (_planetSpin.GlobalTransform.AffineInverse() * hit).Normalized();

        int best = -1; float bd = float.MaxValue;
        for (int i = 0; i < _tiles.Count; i++)
        {
            float d = _tiles[i].Center.DistanceSquaredTo(local);
            if (d < bd) { bd = d; best = i; }
        }
        if (best < 0) return;
        var (rx, ry) = TileToRegion(_tiles[best].Center);
        var body = World.Macro.System.Bodies[_currentBodyIdx];
        var reg = body.Regions[rx, ry];
        string bio = _tileBiomes[best];
        string res = bio switch
        {
            "forest" => "bois, gibier, baies",
            "plains" => "terres arables, gibier",
            "hills" => "pierre, minerai",
            "rocky" => "pierre, métal",
            "marsh" => "eau, tourbe",
            "dunes" => "sable, silice",
            "tundra" => "fourrure, lichen",
            "ocean" => "poisson, sel",
            _ => "minéraux rares"
        };
        _selectedTileIdx = best;
        var st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Triangles);
        var tile = _tiles[best];
        float hr = GlobeRadius * 1.022f;
        for (int k = 0; k < tile.Polygon.Length; k++)
        {
            st.SetNormal(tile.Center); st.AddVertex(tile.Center * hr);
            st.SetNormal(tile.Center); st.AddVertex(tile.Polygon[(k + 1) % tile.Polygon.Length] * hr);
            st.SetNormal(tile.Center); st.AddVertex(tile.Polygon[k] * hr);
        }
        _tileHighlight.Mesh = st.Commit();
        _tileHighlight.MaterialOverride = new StandardMaterial3D
        {
            AlbedoColor = new Color(1f, 0.9f, 0.35f, 0.55f),
            EmissionEnabled = true, Emission = new Color(1f, 0.85f, 0.3f), EmissionEnergyMultiplier = 1.6f,
            Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
            ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded
        };
        _tileHighlight.Visible = true;
        AlertText = $"{body.Name} — tuile #{best}  biome {bio}  ressources: {res}  (fertilité {reg.Fertility:P0}, danger {reg.Danger:P0})" +
            (best == _colonyTileIdx ? "  ← VOTRE COLONIE" : "");
        TileSelected?.Invoke(best, bio, best == _colonyTileIdx);
    }

    /// <summary>Math ray->ground intersection: screen position to tile coords.</summary>
    private (int X, int Y)? ScreenToTile(Vector2 screenPos)
    {
        var origin = _cam.ProjectRayOrigin(screenPos);
        var normal = _cam.ProjectRayNormal(screenPos);
        if (Math.Abs(normal.Y) < 0.0001f) return null;
        float t = -origin.Y / normal.Y;
        if (t < 0) return null;
        var hit = origin + normal * t;
        int tx = (int)Math.Floor(hit.X), ty = (int)Math.Floor(hit.Z);
        if (tx < 0 || ty < 0 || tx >= World.Map.Width || ty >= World.Map.Height) return null;
        return (tx, ty);
    }

    /// <summary>Player orders: click a tree/rock = harvest; Shift+click open
    /// ground = build wall; Ctrl+click open ground = build a bed.</summary>
    // ------------------------------------------------------------------
    // AGENT BRIDGE - lets an AI play the game like a human player.
    // Commands (scripts/agent_cmd.txt, one per line, consumed once):
    //   newgame [seed] | pause | resume | speed <f>
    //   view <Local|Planet|Solar|Planet:N> | select <i>
    //   harvest <x> <y> | wall <x> <y> | bed <x> <y> | move <x> <y>
    //   save <1-3> | load <1-3> | visit <tileIdx> [biome] | return | shot <name>
    // Observation: scripts/logs/agent_state.json rewritten every second.
    // ------------------------------------------------------------------
    private double _agentStateTimer;

    private void ProcessAgentCommands()
    {
        const string cmdPath = @"g:/Rimwork/scripts/agent_cmd.txt";
        if (!System.IO.File.Exists(cmdPath)) return;
        string[] lines;
        try { lines = System.IO.File.ReadAllLines(cmdPath); System.IO.File.Delete(cmdPath); }
        catch { return; }
        foreach (var raw in lines)
        {
            var c = raw.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (c.Length == 0) continue;
            try
            {
                RunAgentCommand(c);
                GD.Print($"[AGENT] ok: {raw}");
            }
            catch (Exception e) { GD.Print($"[AGENT] failed: {raw} -> {e.Message}"); }
        }
    }

    private static string AgentSlot(int n) =>
        System.IO.Path.Combine(OS.GetUserDataDir(), "saves", $"slot{n}.json");

    private void RunAgentCommand(string[] c)
    {
        var inv = System.Globalization.CultureInfo.InvariantCulture;
        switch (c[0].ToLowerInvariant())
        {
            case "newgame":
                NewGame(new WorldGenSettings { Seed = c.Length > 1 ? int.Parse(c[1]) : new Random().Next(1, 999999) });
                Paused = false;
                break;
            case "pause": Paused = true; break;
            case "resume": Paused = false; break;
            case "speed": SpeedMultiplier = float.Parse(c[1], inv); break;
            case "view":
                System.IO.File.WriteAllText(@"g:/Rimwork/scripts/viewcmd.txt", c[1]);
                _viewCmdTimer = 0; // reuse the one-shot view protocol immediately
                break;
            case "select":
            {
                var alive = World.Pawns.Where(p => p.HP > 0).ToList();
                int i = int.Parse(c[1]);
                if (i >= 0 && i < alive.Count) SelectedPawn = alive[i];
                break;
            }
            case "harvest": World.QueueHarvest(int.Parse(c[1]), int.Parse(c[2])); break;
            case "wall": World.QueueBuildWall(int.Parse(c[1]), int.Parse(c[2])); break;
            case "bed": World.QueueBuild(FurnitureKind.Bed, int.Parse(c[1]), int.Parse(c[2])); break;
            case "move": World.Tasks.Enqueue(new TaskOrder(TaskKind.MoveTo, int.Parse(c[1]), int.Parse(c[2]), priority: 90)); break;
            case "save": SaveLoad.Save(World, AgentSlot(int.Parse(c[1]))); break;
            case "load": LoadWorld(SaveLoad.Load(AgentSlot(int.Parse(c[1])))); break;
            case "visit": VisitTile(int.Parse(c[1]), c.Length > 2 ? c[2] : "Forest"); break;
            case "return": ReturnToColony(); break;
            case "shot":
            {
                var img = GetViewport().GetTexture().GetImage();
                System.IO.Directory.CreateDirectory(@"g:/Rimwork/scripts/logs/shots");
                img.SavePng($@"g:/Rimwork/scripts/logs/shots/{c[1]}.png");
                break;
            }
        }
    }

    private void WriteAgentState(double delta)
    {
        _agentStateTimer -= delta;
        if (_agentStateTimer > 0) return;
        _agentStateTimer = 1.0;
        if (World == null) return;
        try
        {
            var alive = World.Pawns.Where(p => p.HP > 0).ToList();
            var state = new
            {
                ticks = World.TotalTicks,
                day = World.DayNumber,
                hour = (int)LocalHourF,
                paused = Paused,
                menuOpen = MenuOpen,
                speed = SpeedMultiplier,
                view = ViewLayer,
                weather = LocalWeather.ToString(),
                wood = World.Wood,
                stone = World.Stone,
                water = World.Water,
                food = World.Food,
                metal = World.Metal,
                tools = World.Tools,
                goal = World.CurrentGoalText,
                goalsDone = World.GoalIndex,
                rooms = World.GetRooms().Count(r => r.Function != RoomFunction.Empty),
                pendingTasks = World.Tasks.Pending.Count,
                threats = Threats.Count,
                alert = AlertText,
                events = World.ColonyEvents.TakeLast(4).ToArray(),
                pawns = alive.Take(12).Select((p, i) => new
                {
                    i,
                    name = p.Name,
                    hp = (int)p.HP,
                    hunger = (int)p.Hunger,
                    thirst = (int)p.Thirst,
                    mood = (int)p.Mood,
                    task = World.GetDriver(p).Current?.Order.Kind.ToString() ?? "idle",
                    x = p.X,
                    y = p.Y,
                }).ToArray(),
            };
            System.IO.File.WriteAllText(@"g:/Rimwork/scripts/logs/agent_state.json",
                System.Text.Json.JsonSerializer.Serialize(state));
        }
        catch { }
    }

    private void OrderAtTile(Vector2 screenPos)
    {
        var tile = ScreenToTile(screenPos);
        if (tile == null) return;
        var (tx, ty) = tile.Value;

        var res = World.Map.Resources.FirstOrDefault(r => r.X == tx && r.Y == ty);
        if (res != null)
        {
            if (World.QueueHarvest(tx, ty))
                AlertText = $"Ordre: récolter {(res.Kind == ResourceKind.Tree ? "l'arbre" : "le rocher")} en ({tx},{ty})";
            return;
        }
        if (Input.IsKeyPressed(Key.Shift))
        {
            if (World.QueueBuildWall(tx, ty))
                AlertText = $"Ordre: construire un mur en ({tx},{ty})";
            else
                AlertText = "Impossible: ressources insuffisantes ou case invalide";
            return;
        }
        if (Input.IsKeyPressed(Key.Ctrl))
        {
            if (World.QueueBuild(FurnitureKind.Bed, tx, ty))
                AlertText = $"Ordre: construire un lit en ({tx},{ty})";
            else
                AlertText = "Impossible: case occupée ou bois insuffisant";
            return;
        }
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
                var tag = new Label3D
                {
                    Name = "tag",
                    FontSize = 56,
                    OutlineSize = 14,
                    Billboard = BaseMaterial3D.BillboardModeEnum.Enabled,
                    Position = new Vector3(0, 2.6f, 0)
                };
                node.AddChild(tag);
            }
            var target = new Vector3(p.X + 0.5f, 0.1f, p.Y + 0.5f);
            bool moving = node.Position.DistanceTo(target) > 0.15f;
            if (node.Position.DistanceTo(target) > 0.01f)
            {
                var dir = target - node.Position;
                node.Position = node.Position.Lerp(target, (float)delta * 6f);
                if (new Vector2(dir.X, dir.Z).Length() > 0.05f)
                    node.Rotation = new Vector3(0, Mathf.Atan2(dir.X, dir.Z), 0);
            }
            PlayAnim(p.Id, node, moving);
            if (node.GetNodeOrNull<Label3D>("tag") is Label3D tagL)
            {
                var drv = World.GetDriver(p);
                string job = drv?.Current?.Order != null ? drv.Current.Order.Kind.ToString() : "repos";
                tagL.Text = $"{p.Name}\n{job}";
                tagL.Modulate = p.HP < 40 ? new Color(1f, 0.4f, 0.35f) : (p.Mood < 30 ? new Color(1f, 0.75f, 0.3f) : new Color(0.9f, 0.95f, 1f));
            }
            modelIdx++;
        }
    }

    /// <summary>Walls, resources, furniture, saplings - diffed by tile each second.</summary>
    private void SyncStatics(bool force)
    {
        var wanted = new Dictionary<(int, int), (string KindTag, string Path, Color Fallback, float Scale, int Yaw)>();

        for (int y = 1; y < World.Map.Height - 1; y++)
            for (int x = 1; x < World.Map.Width - 1; x++)
                if (!World.Map.IsPassable(x, y) && !World.Map.IsWater(x, y))
                {
                    bool SolidAt(int ax, int ay) => !World.Map.IsPassable(ax, ay) && !World.Map.IsWater(ax, ay);
                    int yaw = RenderOrientation.WallYaw(SolidAt(x, y - 1), SolidAt(x, y + 1), SolidAt(x + 1, y), SolidAt(x - 1, y));
                    wanted[(x, y)] = ("wall" + yaw, RenderCatalog.WallModel, new Color(0.45f, 0.42f, 0.4f), 0.42f, yaw);
                }

        foreach (var r in World.Map.Resources)
            wanted[(r.X, r.Y)] = (r.Kind.ToString(), RenderCatalog.ResourceModels[r.Kind],
                r.Kind == ResourceKind.Tree ? new Color(0.15f, 0.45f, 0.2f) : new Color(0.5f, 0.5f, 0.55f),
                r.Kind == ResourceKind.Tree ? 0.7f : 0.6f, 0);

        foreach (var (sx, sy, _) in World.Map.Saplings)
            wanted[(sx, sy)] = ("sapling", RenderCatalog.SaplingModel, new Color(0.3f, 0.6f, 0.3f), 0.4f, 0);

        foreach (var room in World.GetRooms())
        {
            foreach (var (rxx, ryy) in room.Tiles)
                if (!wanted.ContainsKey((rxx, ryy)))
                    wanted[(rxx, ryy)] = ("floor", RenderCatalog.Dungeon + "floor_tile_large.gltf",
                        new Color(0.35f, 0.3f, 0.28f), 0.5f, 0);
        }

        foreach (var f in World.Map.Furniture)
        {
            string path = RenderCatalog.FurnitureModels.TryGetValue(f.Kind, out var pp) ? pp : null;
            int fyaw = 0;
            if (f.Kind == FurnitureKind.Door)
            {
                bool SolidAt(int ax, int ay) => !World.Map.IsPassable(ax, ay) && !World.Map.IsWater(ax, ay);
                fyaw = RenderOrientation.DoorYaw(SolidAt(f.X, f.Y - 1), SolidAt(f.X, f.Y + 1), SolidAt(f.X + 1, f.Y), SolidAt(f.X - 1, f.Y));
            }
            wanted[(f.X, f.Y)] = (f.Kind.ToString(), path, new Color(0.7f, 0.5f, 0.3f), 0.55f, fyaw);
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
            node.RotationDegrees = new Vector3(0, w.Yaw, 0);
            node.Position = new Vector3(key.Item1 + 0.5f, 0.1f, key.Item2 + 0.5f);
            AddChild(node);
            _staticNodes[key] = node;
            _staticKind[key] = w.KindTag;
        }
    }

    // ------------------------------------------------------------------
    // Threat slice: skeleton war bands, spawn rate driven by macro layer
    // ------------------------------------------------------------------

    /// <summary>Planet layer: hex regions WRAPPED onto a globe (each hex
    /// sits on the sphere surface, oriented along its normal). Solar layer:
    /// star + orbiting bodies, navigable via Tab cycle.</summary>
    private const float GlobeRadius = 16f;
    private Node3D _solarRoot;
    private Node3D _planetSpin;

    private Vector3 LatLon(float latDeg, float lonDeg, float r)
    {
        float lat = Mathf.DegToRad(latDeg);
        float lon = Mathf.DegToRad(lonDeg);
        return new Vector3(
            r * Mathf.Cos(lat) * Mathf.Sin(lon),
            r * Mathf.Sin(lat),
            r * Mathf.Cos(lat) * Mathf.Cos(lon));
    }

    private void PlaceOnGlobe(Node3D node, float latDeg, float lonDeg, float height = 0f)
    {
        // Pure LOCAL-space placement (LookAtFromPosition works in GLOBAL
        // coords and teleported everything off the globe - seen on screen).
        var pos = LatLon(latDeg, lonDeg, GlobeRadius + height);
        var up = pos.Normalized();                  // radial = local Y
        var east = up.Cross(Vector3.Forward);
        if (east.LengthSquared() < 0.001f) east = Vector3.Right;
        east = east.Normalized();
        var north = east.Cross(up).Normalized();
        node.Transform = new Transform3D(new Basis(east, up, north), pos);
    }

    private int _currentBodyIdx = 0;
    private List<HexPlanet.Tile> _tiles;
    private int _colonyTileIdx = -1;
    private string[] _tileBiomes;
    private int _selectedTileIdx = -1;
    private MeshInstance3D _tileHighlight;
    private Node3D _tileMarker;
    private Label3D _planetTitle;
    private Node3D _moonHolder;
    private Node3D _cloudHolder;

    private static readonly Dictionary<string, Color> BiomeColors = new()
    {
        ["forest"] = new Color(0.16f, 0.42f, 0.18f),
        ["plains"] = new Color(0.45f, 0.52f, 0.24f),
        ["hills"] = new Color(0.42f, 0.36f, 0.26f),
        ["marsh"] = new Color(0.2f, 0.38f, 0.32f),
        ["rocky"] = new Color(0.45f, 0.45f, 0.48f),
        ["ash"] = new Color(0.32f, 0.28f, 0.28f),
        ["dunes"] = new Color(0.72f, 0.55f, 0.32f),
        ["scorched"] = new Color(0.5f, 0.3f, 0.2f),
        ["lava rock"] = new Color(0.35f, 0.18f, 0.14f),
        ["crater"] = new Color(0.42f, 0.36f, 0.33f),
        ["ice"] = new Color(0.82f, 0.88f, 0.95f),
        ["tundra"] = new Color(0.55f, 0.62f, 0.6f),
        ["snowfield"] = new Color(0.9f, 0.92f, 0.96f),
        ["frost rock"] = new Color(0.6f, 0.66f, 0.75f),
        ["crevasse"] = new Color(0.4f, 0.5f, 0.65f),
    };

    /// <summary>Map a unit-sphere tile center to one of the body's 5x5 sim
    /// regions (whole sphere bucketed by lat/lon).</summary>
    private (int X, int Y) TileToRegion(Vector3 c)
    {
        float lat = Mathf.RadToDeg(Mathf.Asin(Mathf.Clamp(c.Y, -1f, 1f)));
        float lon = Mathf.RadToDeg(Mathf.Atan2(c.X, c.Z));
        int rx = Math.Clamp((int)((lon + 180f) / 72f), 0, 4);
        int ry = Math.Clamp((int)((lat + 90f) / 36f), 0, 4);
        return (rx, ry);
    }

    private void BuildWorldView()
    {
        _worldViewRoot = new Node3D { Position = new Vector3(200, 0, 200), Visible = false };
        AddChild(_worldViewRoot);
        _planetSpin = new Node3D();
        _worldViewRoot.AddChild(_planetSpin);
        _planetTitle = new Label3D
        {
            Position = new Vector3(0, GlobeRadius + 6f, 0),
            FontSize = 96,
            Billboard = BaseMaterial3D.BillboardModeEnum.Enabled
        };
        _worldViewRoot.AddChild(_planetTitle);
        BuildGlobeFor(World.Macro.System.HomeBodyIndex);
        BuildSolarView();
    }

    /// <summary>(Re)build the tiled Goldberg globe for any system body -
    /// every planet is fully tiled with its own biome palette.</summary>
    public void BuildGlobeFor(int bodyIdx)
    {
        _currentBodyIdx = bodyIdx;
        var body = World.Macro.System.Bodies[bodyIdx];
        foreach (Node child in _planetSpin.GetChildren()) child.QueueFree();

        _tiles = HexPlanet.Generate(11); // ~1212 tiles per planet
        bool isHome = bodyIdx == World.Macro.System.HomeBodyIndex;
        var rng = new Random(body.Name.GetHashCode() & 0x7fffffff);
        _colonyTileIdx = -1;
        float bestColonyDist = float.MaxValue;

        var tileColors = new Color[_tiles.Count];
        _tileBiomes = new string[_tiles.Count];
        for (int i = 0; i < _tiles.Count; i++)
        {
            var cc = _tiles[i].Center;
            float lat = Mathf.Abs(Mathf.RadToDeg(Mathf.Asin(Mathf.Clamp(cc.Y, -1f, 1f))));
            float n = Mathf.Sin(cc.X * 3.1f + cc.Y * 1.7f) + Mathf.Sin(cc.Y * 2.3f - cc.Z * 2.9f) + Mathf.Sin(cc.Z * 3.7f + cc.X * 1.3f);
            float n2 = Mathf.Sin(cc.X * 5.3f - cc.Z * 4.1f) + Mathf.Sin(cc.Y * 6.7f + cc.X * 2.9f);
            bool ocean = n < -0.55f + (1f - body.Habitability) * 1.1f;

            string biome;
            if (ocean) biome = "ocean";
            else if (body.ClimateTemp > 0.4f)
                biome = n2 > 0.8f ? "lava rock" : (n2 > 0f ? "scorched" : (n2 > -0.9f ? "dunes" : "ash"));
            else if (body.ClimateTemp < -0.3f)
                biome = lat > 50f ? "ice" : (n2 > 0.5f ? "frost rock" : (n2 > -0.5f ? "snowfield" : "tundra"));
            else
                biome = lat > 62f ? "ice"
                    : lat > 50f ? "tundra"
                    : n2 > 1.0f ? "rocky"
                    : n2 > 0.35f ? "hills"
                    : n2 > -0.45f ? "forest"
                    : lat < 18f ? "dunes" : "plains";
            _tileBiomes[i] = biome;
            var baseCol = biome == "ocean"
                ? new Color(0.09f, 0.27f, 0.52f) * (1f + 0.25f * Mathf.Clamp(n + 1f, -1f, 0f))
                : (BiomeColors.TryGetValue(biome, out var bc) ? bc : new Color(0.4f, 0.4f, 0.4f));
            tileColors[i] = biome == "ocean" ? baseCol : baseCol * (0.95f + (float)rng.NextDouble() * 0.22f);
            if (isHome && !ocean && biome != "ice")
            {
                var (rx, ry) = TileToRegion(cc);
                if (body.Regions[rx, ry].IsColonyRegion)
                {
                    float d = cc.DistanceTo(new Vector3(0, 0.42f, 0.91f));
                    if (d < bestColonyDist) { bestColonyDist = d; _colonyTileIdx = i; }
                }
            }
        }
        int idx = 0;
        var globe = HexPlanet.BuildMesh(_tiles, _ => tileColors[idx++], GlobeRadius);
        _planetSpin.AddChild(globe);

        // --- Biome props: tiny trees on green tiles, boulders on rocky ones
        // (the reference look: tiles dressed with 3D props, not flat color).
        var treeXf = new List<Transform3D>();
        var rockXf = new List<Transform3D>();
        for (int i = 0; i < _tiles.Count; i++)
        {
            string bio = _tileBiomes[i];
            if (bio == "ocean" || bio == "ice" || bio == "snowfield") continue;
            bool green = bio == "forest" || bio == "marsh" || bio == "tundra";
            bool rockyT = bio == "rocky" || bio == "hills" || bio == "frost rock" || bio == "lava rock" || bio == "crater";
            var c = _tiles[i].Center;
            var up = c;
            var east = up.Cross(Math.Abs(up.Y) < 0.99f ? Vector3.Up : Vector3.Right).Normalized();
            var north = east.Cross(up);
            int props = green ? 2 + (i % 2) : (rockyT ? 1 : 0);
            for (int k = 0; k < props; k++)
            {
                float a = (i * 37 + k * 113) % 360 * Mathf.Pi / 180f;
                float r = 0.35f + ((i * 13 + k * 71) % 50) / 100f;
                var offset = (east * Mathf.Cos(a) + north * Mathf.Sin(a)) * r;
                var pos = (c + offset * 0.04f).Normalized() * (GlobeRadius * 1.015f);
                var basis = new Basis(east, up, north).Scaled(Vector3.One * (green ? 0.55f : 0.4f));
                if (green) treeXf.Add(new Transform3D(basis, pos));
                else rockXf.Add(new Transform3D(basis, pos));
            }
        }
        if (treeXf.Count > 0)
        {
            var mmT = new MultiMesh { TransformFormat = MultiMesh.TransformFormatEnum.Transform3D,
                Mesh = new CylinderMesh { TopRadius = 0f, BottomRadius = 0.32f, Height = 0.9f }, InstanceCount = treeXf.Count };
            for (int i = 0; i < treeXf.Count; i++) mmT.SetInstanceTransform(i, treeXf[i]);
            _planetSpin.AddChild(new MultiMeshInstance3D { Multimesh = mmT,
                MaterialOverride = new StandardMaterial3D { AlbedoColor = new Color(0.10f, 0.34f, 0.13f) } });
        }
        if (rockXf.Count > 0)
        {
            var mmR = new MultiMesh { TransformFormat = MultiMesh.TransformFormatEnum.Transform3D,
                Mesh = new BoxMesh { Size = new Vector3(0.35f, 0.3f, 0.35f) }, InstanceCount = rockXf.Count };
            for (int i = 0; i < rockXf.Count; i++) mmR.SetInstanceTransform(i, rockXf[i]);
            _planetSpin.AddChild(new MultiMeshInstance3D { Multimesh = mmR,
                MaterialOverride = new StandardMaterial3D { AlbedoColor = new Color(0.35f, 0.34f, 0.36f) } });
        }

        // --- Clouds: stylized chunky clusters (Before We Leave-inspired:
        // fat rounded puffs in groups, drifting slowly). Toggle with key C.
        _cloudHolder = new Node3D();
        _planetSpin.AddChild(_cloudHolder);
        var crng = new Random(7);
        int clusters = 14;
        var puffXf = new List<Transform3D>();
        for (int ci = 0; ci < clusters; ci++)
        {
            var dir = new Vector3((float)crng.NextDouble() - 0.5f, (float)(crng.NextDouble() - 0.5f) * 0.9f, (float)crng.NextDouble() - 0.5f).Normalized();
            var up2 = dir;
            var e2 = up2.Cross(Math.Abs(up2.Y) < 0.99f ? Vector3.Up : Vector3.Right).Normalized();
            var n3 = e2.Cross(up2);
            int puffs = 3 + crng.Next(4);
            for (int k = 0; k < puffs; k++)
            {
                float ox = ((float)crng.NextDouble() - 0.5f) * 3.2f;
                float oz = ((float)crng.NextDouble() - 0.5f) * 2.0f;
                float sc = 0.9f + (float)crng.NextDouble() * 1.3f;
                var pos = (dir * (GlobeRadius * 1.06f)) + e2 * ox + n3 * oz;
                puffXf.Add(new Transform3D(new Basis(e2 * sc, up2 * (sc * 0.55f), n3 * sc), pos));
            }
        }
        var mmC = new MultiMesh { TransformFormat = MultiMesh.TransformFormatEnum.Transform3D,
            Mesh = new SphereMesh { Radius = 1.0f, Height = 2.0f, RadialSegments = 10, Rings = 6 }, InstanceCount = puffXf.Count };
        for (int i2 = 0; i2 < puffXf.Count; i2++) mmC.SetInstanceTransform(i2, puffXf[i2]);
        _cloudHolder.AddChild(new MultiMeshInstance3D { Multimesh = mmC,
            MaterialOverride = new StandardMaterial3D { AlbedoColor = new Color(0.97f, 0.96f, 0.99f), Roughness = 1f } });

        // --- Atmosphere halo
        _planetSpin.AddChild(new MeshInstance3D
        {
            Mesh = new SphereMesh { Radius = GlobeRadius * 1.07f, Height = GlobeRadius * 2.14f },
            MaterialOverride = new StandardMaterial3D
            {
                AlbedoColor = new Color(0.45f, 0.65f, 1f, 0.10f),
                Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
                ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
                CullMode = BaseMaterial3D.CullModeEnum.Front
            }
        });

        // --- Moons of this body orbit in view
        _moonHolder = new Node3D();
        _planetSpin.AddChild(_moonHolder);
        foreach (var other in World.Macro.System.Bodies)
        {
            if (other.Kind != "moon" || body.Kind == "moon") continue;
            var moon = new MeshInstance3D
            {
                Mesh = new SphereMesh { Radius = 2.2f, Height = 4.4f },
                MaterialOverride = new StandardMaterial3D { AlbedoColor = new Color(0.62f, 0.64f, 0.7f) },
                Position = new Vector3(GlobeRadius * 1.9f, GlobeRadius * 0.35f, 0)
            };
            _moonHolder.AddChild(moon);
            _moonHolder.AddChild(new Label3D { Text = other.Name, FontSize = 56,
                Billboard = BaseMaterial3D.BillboardModeEnum.Enabled,
                Position = new Vector3(GlobeRadius * 1.9f, GlobeRadius * 0.35f + 3.2f, 0) });
        }

        if (_colonyTileIdx >= 0)
        {
            var cpos = _tiles[_colonyTileIdx].Center * (GlobeRadius + 0.6f);
            var marker = new MeshInstance3D
            {
                Mesh = new CylinderMesh { TopRadius = 0f, BottomRadius = 0.6f, Height = 1.6f },
                MaterialOverride = new StandardMaterial3D { AlbedoColor = new Color(0.36f, 0.9f, 0.5f), ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded },
                Position = cpos
            };
            _planetSpin.AddChild(marker);
            var lbl = new Label3D { Text = "COLONIE", FontSize = 72, Billboard = BaseMaterial3D.BillboardModeEnum.Enabled, Position = cpos + cpos.Normalized() * 2.2f };
            _planetSpin.AddChild(lbl);
        }

        // Selected-tile highlight: the tile ITSELF lights up (emissive copy
        // of its polygon, slightly above the surface).
        _tileHighlight = new MeshInstance3D { Visible = false };
        _planetSpin.AddChild(_tileHighlight);

        _planetTitle.Text = body.Name.ToUpper() + " — " + body.Kind + "  (molette: zoom · clic droit: pivoter · clic: tuile · C: nuages · Tab: système)";
        // Face the colony/land toward the camera at first sight.
        _planetSpin.Rotation = Vector3.Zero;
        _planetSpin.RotateY(Mathf.DegToRad(45));
    }

    // ---- Solar system layer: star + animated orbits ----
    private readonly List<(Node3D Node, float Radius, float Speed, float Phase)> _orbiters = new();

    private void BuildSolarView()
    {
        _solarRoot = new Node3D { Position = new Vector3(400, 0, 400), Visible = false };
        AddChild(_solarRoot);
        var m = World.Macro;

        var star = new MeshInstance3D
        {
            Mesh = new SphereMesh { Radius = 5f, Height = 10f },
            MaterialOverride = new StandardMaterial3D { AlbedoColor = new Color(1f, 0.85f, 0.3f), EmissionEnabled = true, Emission = new Color(1f, 0.75f, 0.25f), EmissionEnergyMultiplier = 2.5f }
        };
        _solarRoot.AddChild(star);
        _solarRoot.AddChild(new Label3D { Text = m.System.StarName, Position = new Vector3(0, 7.5f, 0), FontSize = 120, Billboard = BaseMaterial3D.BillboardModeEnum.Enabled });
        _solarRoot.AddChild(new Label3D
        {
            Text = "SYSTÈME " + m.System.StarName.ToUpper() + "   (Tab: retour colonie, molette: zoom)",
            Position = new Vector3(0, 16f, -20f),
            FontSize = 88,
            Billboard = BaseMaterial3D.BillboardModeEnum.Enabled
        });

        float[] radii = { 14f, 24f, 6f };   // moons use a tight orbit around their planet
        float[] sizes = { 2.2f, 1.7f, 0.9f };
        int bi = 0;
        Node3D homeHolder = null;
        foreach (var body in m.System.Bodies)
        {
            bool isMoon = body.Kind == "moon";
            // Orbit ring (thin torus laid flat).
            _solarRoot.AddChild(new MeshInstance3D
            {
                Mesh = new TorusMesh { InnerRadius = radii[bi] - 0.06f, OuterRadius = radii[bi] + 0.06f },
                MaterialOverride = new StandardMaterial3D { AlbedoColor = new Color(0.5f, 0.55f, 0.65f, 0.5f), Transparency = BaseMaterial3D.TransparencyEnum.Alpha }
            });
            var holder = new Node3D();
            if (isMoon && homeHolder != null)
            {
                // moons orbit their PLANET: parent the holder to it
                var anchor = new Node3D { Position = new Vector3(radii[0], 0, 0) };
                homeHolder.AddChild(anchor);
                anchor.AddChild(holder);
            }
            else _solarRoot.AddChild(holder);
            bool home = bi == m.System.HomeBodyIndex;
            var planet = new MeshInstance3D
            {
                Mesh = new SphereMesh { Radius = sizes[bi], Height = sizes[bi] * 2f },
                MaterialOverride = new StandardMaterial3D
                {
                    AlbedoColor = home ? new Color(0.25f, 0.55f, 0.4f) : (body.ClimateTemp > 0.4f ? new Color(0.75f, 0.4f, 0.25f) : new Color(0.55f, 0.5f, 0.5f))
                },
                Position = new Vector3(radii[bi], 0, 0)
            };
            holder.AddChild(planet);
            var lbl = new Label3D
            {
                Text = body.Name + (home ? "  ← COLONIE" : "") + "\nhab " + body.Habitability.ToString("0.0") + "  danger " + body.DangerLevel.ToString("0.0"),
                Position = new Vector3(radii[bi], sizes[bi] + 2.2f, 0),
                FontSize = 64,
                Billboard = BaseMaterial3D.BillboardModeEnum.Enabled
            };
            holder.AddChild(lbl);
            if (!isMoon && bi == m.System.HomeBodyIndex) homeHolder = holder;
            _orbiters.Add((holder, radii[bi], isMoon ? 0.5f : 0.10f - bi * 0.025f, bi * 2.1f));
            bi++;
        }
    }

    /// <summary>Cycle Local -> Planet -> Solar -> Local.</summary>
    public void ToggleWorldView()
    {
        if (ViewLayer == "Local")
        {
            _savedRigPos = _camRig.Position; _savedZoom = _zoom;
            SetViewLayer("Planet");
        }
        else if (ViewLayer == "Planet") SetViewLayer("Solar");
        else SetViewLayer("Local");
    }

    public void SetViewLayer(string layer)
    {
        ViewLayer = layer;
        _worldViewRoot.Visible = layer == "Planet";
        _solarRoot.Visible = layer == "Solar";
        if (layer == "Planet")
        {
            _camRig.Position = _worldViewRoot.Position + new Vector3(0, 6, 0);
            _zoom = 42f;
            _sun.LightEnergy = 1.3f;
            if (_envRes != null) _envRes.AmbientLightEnergy = 0.85f;
        }
        else if (layer == "Solar")
        {
            _camRig.Position = _solarRoot.Position;
            _zoom = 60f;
        }
        else
        {
            _camRig.Position = _savedRigPos; _zoom = _savedZoom;
        }
    }

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
            EmitSignal(SignalName.ThreatSpawned);
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
            bool tmoving = t.Node.Position.DistanceTo(target) > 0.15f;
            t.Node.Position = t.Node.Position.Lerp(target, (float)delta * 6f);
            var tap = FindAnim(t.Node);
            if (tap != null)
            {
                string twant = null;
                foreach (var name in tap.GetAnimationList())
                {
                    string n = name.ToString();
                    if (tmoving && (n.Contains("Walk") || n.Contains("Run"))) { twant = n; break; }
                    if (!tmoving && n.Contains("Idle")) { twant = n; break; }
                }
                if (twant != null && tap.CurrentAnimation != twant) tap.Play(twant, customBlend: 0.2f);
            }
        }
    }
}
