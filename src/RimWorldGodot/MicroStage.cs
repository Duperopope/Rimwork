using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

/// <summary>
/// DOWN HERE! opening stage: the primordial pool (Spore-like, 2.5D).
/// 100% PROCEDURAL - zero assets: every organism is generated geometry
/// (wobbling membrane polygons), the water is a shader gradient, food and
/// creatures are code. You are a bacterium: eat what is smaller, flee what
/// is bigger, fill your energy, reproduce, pick mutations. After 10
/// evolutions the next scale unlocks. Deterministic per world seed.
/// </summary>
public partial class MicroStage : Node2D
{
    // ---------- Tunables ----------
    private const float WorldR = 1600f;          // pool radius
    private int _seed = 12345;
    private Random _rng;

    // ---------- Organism model (player + AI share it) ----------
    public class Organism
    {
        public Vector2 Pos, Vel;
        public float Size = 14f;                  // radius
        public float Energy = 50f, EnergyMax = 100f;
        public float Speed = 90f;
        public int Spikes = 0;                    // defense
        public int Cilia = 0;                     // speed organelles
        public bool Photosynthesis = false;
        public Color Tint = new(0.5f, 0.8f, 0.9f);
        public float Phase;                       // wobble phase
        public bool IsPlayer;
        public bool Dead;
        public float DigestCooldown;
    }

    private Organism _player;
    private readonly List<Organism> _critters = new();
    private readonly List<Vector2> _algae = new();
    private readonly List<Vector2> _motes = new(); // ambient particles

    // ---------- Evolution ----------
    public int Evolutions { get; private set; } = 0;
    public const int EvolutionsToAscend = 10;
    private bool _choosing;
    private readonly List<(string Name, string Desc, Action<Organism> Apply)> _traitPool = new();
    private (string, string, Action<Organism>)[] _choices;

    // ---------- UI ----------
    private CanvasLayer _ui;
    private Label _hud;
    private Control _evolveBox;
    private Camera2D _cam;
    public event Action StageCompleted;
    public event Action ExitRequested;

    public override void _Ready()
    {
        _rng = new Random(_seed);
        BuildTraitPool();

        _player = new Organism { Pos = Vector2.Zero, IsPlayer = true, Tint = new Color(0.55f, 0.95f, 0.75f) };

        for (int i = 0; i < 110; i++) _algae.Add(RandPos(0.95f));
        for (int i = 0; i < 26; i++) SpawnCritter(prey: _rng.Next(2) == 0);
        for (int i = 0; i < 160; i++) _motes.Add(RandPos(1f));

        _cam = new Camera2D { Zoom = new Vector2(1.1f, 1.1f), PositionSmoothingEnabled = true, PositionSmoothingSpeed = 4f };
        AddChild(_cam);
        _cam.MakeCurrent();

        BuildUi();
    }

    public void Configure(int seed)
    {
        _seed = seed;
    }

    private Vector2 RandPos(float r) =>
        new Vector2((float)(_rng.NextDouble() * 2 - 1), (float)(_rng.NextDouble() * 2 - 1)).Normalized()
        * (float)Math.Sqrt(_rng.NextDouble()) * WorldR * r;

    private void SpawnCritter(bool prey)
    {
        float playerS = _player?.Size ?? 14f;
        var o = new Organism
        {
            Pos = RandPos(0.9f),
            Size = prey ? playerS * (0.45f + (float)_rng.NextDouble() * 0.4f)
                        : playerS * (1.25f + (float)_rng.NextDouble() * 0.9f),
            Speed = 55f + (float)_rng.NextDouble() * 50f,
            Tint = prey ? new Color(0.45f, 0.65f, 0.95f) : new Color(0.95f, 0.4f, 0.4f),
            Phase = (float)_rng.NextDouble() * 10f,
            Spikes = prey ? 0 : _rng.Next(3)
        };
        _critters.Add(o);
    }

    private void BuildTraitPool()
    {
        _traitPool.Add(("Cils vibratiles", "+25% vitesse", o => { o.Cilia++; o.Speed *= 1.25f; }));
        _traitPool.Add(("Membrane épaisse", "+1 pointe défensive", o => o.Spikes++));
        _traitPool.Add(("Croissance", "+30% taille (proies plus grosses, mais prédateurs te voient)", o => o.Size *= 1.3f));
        _traitPool.Add(("Métabolisme lent", "+40 énergie max", o => o.EnergyMax += 40f));
        _traitPool.Add(("Chloroplastes", "Photosynthèse: régénère à la lumière", o => o.Photosynthesis = true));
        _traitPool.Add(("Bioluminescence", "Teinte vive (style!)", o => o.Tint = new Color(0.6f + (float)_rng.NextDouble() * 0.4f, 0.5f + (float)_rng.NextDouble() * 0.5f, 0.9f)));
        _traitPool.Add(("Flagelle", "+15% vitesse, -10 énergie max", o => { o.Speed *= 1.15f; o.EnergyMax -= 10f; }));
        _traitPool.Add(("Vacuole", "Digestion 2x plus rapide", o => o.DigestCooldown = -1f));
        _traitPool.Add(("Compacité", "-15% taille (discret), +10% vitesse", o => { o.Size *= 0.85f; o.Speed *= 1.1f; }));
    }

    // ==================================================================
    public override void _Process(double dt)
    {
        float d = (float)dt;
        if (_choosing) { QueueRedraw(); return; }

        // ---- Player control: swim toward the mouse ----
        var target = GetGlobalMousePosition();
        var dir = target - _player.Pos;
        if (dir.Length() > 8f)
            _player.Vel = _player.Vel.Lerp(dir.Normalized() * EffSpeed(_player), d * 3f);
        else _player.Vel = _player.Vel.Lerp(Vector2.Zero, d * 4f);
        Integrate(_player, d);
        _cam.Position = _player.Pos;

        // ---- Metabolism: bigger costs more; photosynthesis trickles ----
        float upkeep = 1.1f + _player.Size * 0.045f;
        _player.Energy -= upkeep * d;
        if (_player.Photosynthesis) _player.Energy += 0.8f * d;
        _player.Energy = Mathf.Clamp(_player.Energy, 0f, _player.EnergyMax);
        if (_player.Energy <= 0f) Die("Tu t'es éteint, à court d'énergie... Un descendant prend le relais.");

        // ---- Eat algae ----
        for (int i = _algae.Count - 1; i >= 0; i--)
            if (_algae[i].DistanceTo(_player.Pos) < _player.Size + 7f)
            {
                _algae.RemoveAt(i);
                _player.Energy = Mathf.Min(_player.EnergyMax, _player.Energy + 9f);
                _algae.Add(RandPos(0.97f)); // the pool regrows elsewhere
            }

        // ---- Critters AI + predation ----
        foreach (var c in _critters)
        {
            if (c.Dead) continue;
            var toPlayer = _player.Pos - c.Pos;
            float dist = toPlayer.Length();
            bool cIsPrey = c.Size < _player.Size * 0.85f;
            bool cIsPredator = c.Size > _player.Size * 1.15f;

            Vector2 want;
            if (cIsPredator && dist < 420f) want = toPlayer.Normalized();              // hunts you
            else if (cIsPrey && dist < 320f) want = -toPlayer.Normalized();            // flees you
            else { c.Phase += d * 0.6f; want = new Vector2(Mathf.Cos(c.Phase), Mathf.Sin(c.Phase * 0.8f)); }
            c.Vel = c.Vel.Lerp(want * EffSpeed(c) * 0.8f, d * 2f);
            Integrate(c, d);

            // contact resolution
            if (dist < c.Size + _player.Size - 4f)
            {
                if (cIsPrey)
                {
                    c.Dead = true;
                    _player.Energy = Mathf.Min(_player.EnergyMax, _player.Energy + 14f + c.Size * 0.5f);
                }
                else if (cIsPredator)
                {
                    float bite = Math.Max(4f, 10f - _player.Spikes * 3f) * d * 8f;
                    _player.Energy -= bite;
                    if (_player.Spikes > 0) c.Vel = -toPlayer.Normalized() * 260f; // spiked! it recoils
                    if (_player.Energy <= 0f) Die("Dévoré par plus gros que toi. Un descendant prend le relais.");
                }
            }
        }
        _critters.RemoveAll(c => c.Dead);
        while (_critters.Count < 26) SpawnCritter(prey: _rng.Next(5) > 1);

        QueueRedraw();
        UpdateHud();
    }

    private float EffSpeed(Organism o) => o.Speed * (1f + o.Cilia * 0.0f) * Mathf.Clamp(18f / o.Size + 0.6f, 0.6f, 1.6f);

    private void Integrate(Organism o, float d)
    {
        o.Pos += o.Vel * d;
        if (o.Pos.Length() > WorldR) o.Pos = o.Pos.Normalized() * WorldR; // pool edge
        o.Phase += d * (2f + o.Vel.Length() * 0.01f);
    }

    private void Die(string msg)
    {
        _player.Energy = _player.EnergyMax * 0.5f;
        _player.Pos = RandPos(0.3f);
        _hud.Text = msg;
    }

    // ==================================================================
    // 100% procedural rendering: wobbling membrane polygons, no textures.
    // ==================================================================
    private static readonly Color Abyss = new(0.015f, 0.05f, 0.10f);

    public override void _Draw()
    {
        // Water: layered radial gradient circles (cheap fake volumetrics)
        DrawCircle(_cam.Position, 2400f, Abyss);
        DrawCircle(Vector2.Zero, WorldR * 1.05f, new Color(0.02f, 0.09f, 0.16f));
        DrawCircle(Vector2.Zero, WorldR * 0.7f, new Color(0.03f, 0.12f, 0.20f));
        DrawCircle(Vector2.Zero, WorldR * 0.4f, new Color(0.035f, 0.15f, 0.24f));
        // light shafts from above
        for (int i = 0; i < 5; i++)
        {
            float x = -900f + i * 450f;
            DrawColoredPolygon(new[]
            {
                new Vector2(x - 60, -WorldR), new Vector2(x + 60, -WorldR),
                new Vector2(x + 220, WorldR), new Vector2(x - 220, WorldR)
            }, new Color(0.4f, 0.7f, 0.8f, 0.025f));
        }
        // ambient motes
        foreach (var m in _motes)
            DrawCircle(m, 1.6f, new Color(0.5f, 0.75f, 0.8f, 0.18f));

        // algae: little procedural rosettes
        foreach (var a in _algae)
        {
            for (int k = 0; k < 5; k++)
            {
                float ang = k * Mathf.Tau / 5f;
                DrawCircle(a + new Vector2(Mathf.Cos(ang), Mathf.Sin(ang)) * 4f, 3.2f, new Color(0.25f, 0.75f, 0.35f, 0.9f));
            }
            DrawCircle(a, 2.6f, new Color(0.45f, 0.9f, 0.5f));
        }

        foreach (var c in _critters) DrawOrganism(c);
        DrawOrganism(_player);
    }

    /// <summary>The signature look: an organic wobbling membrane - a polygon
    /// whose vertices breathe with layered sines (NOT a circle, NOT a sprite).</summary>
    private void DrawOrganism(Organism o)
    {
        int n = 22;
        var pts = new Vector2[n];
        var swim = o.Vel.Length() * 0.004f;
        for (int i = 0; i < n; i++)
        {
            float a = i * Mathf.Tau / n;
            float wobble = 1f
                + 0.10f * Mathf.Sin(a * 3f + o.Phase * 2.1f)
                + 0.06f * Mathf.Sin(a * 5f - o.Phase * 1.4f)
                + swim * Mathf.Sin(a * 2f + o.Phase * 4f);
            pts[i] = o.Pos + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * o.Size * wobble;
        }
        // halo, membrane, cytoplasm, nucleus
        DrawColoredPolygon(pts, new Color(o.Tint.R, o.Tint.G, o.Tint.B, 0.16f));
        var inner = new Vector2[n];
        for (int i = 0; i < n; i++) inner[i] = o.Pos + (pts[i] - o.Pos) * 0.86f;
        DrawColoredPolygon(inner, new Color(o.Tint.R * 0.7f, o.Tint.G * 0.75f, o.Tint.B * 0.8f, 0.55f));
        DrawCircle(o.Pos + new Vector2(o.Size * 0.18f, -o.Size * 0.12f), o.Size * 0.22f, new Color(0.1f, 0.12f, 0.2f, 0.8f));
        // organelles
        for (int k = 0; k < 3; k++)
        {
            float ang = o.Phase * 0.6f + k * 2.1f;
            DrawCircle(o.Pos + new Vector2(Mathf.Cos(ang), Mathf.Sin(ang)) * o.Size * 0.45f, o.Size * 0.08f,
                new Color(o.Tint.R, o.Tint.G, o.Tint.B, 0.5f));
        }
        // defensive spikes
        for (int k = 0; k < o.Spikes * 4; k++)
        {
            float a = k * Mathf.Tau / Math.Max(1, o.Spikes * 4) + o.Phase * 0.3f;
            var baseP = o.Pos + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * o.Size * 0.95f;
            var tip = o.Pos + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * o.Size * 1.35f;
            DrawLine(baseP, tip, new Color(0.9f, 0.95f, 1f, 0.8f), 2f);
        }
        // photosynthesis glow
        if (o.Photosynthesis)
            DrawCircle(o.Pos, o.Size * 1.15f, new Color(0.4f, 0.9f, 0.4f, 0.07f));
    }

    // ==================================================================
    // UI: energy bar, evolution flow
    // ==================================================================
    private void BuildUi()
    {
        _ui = new CanvasLayer();
        AddChild(_ui);
        var panel = new PanelContainer();
        panel.SetAnchorsPreset(Control.LayoutPreset.TopWide);
        var style = new StyleBoxFlat { BgColor = new Color(0.02f, 0.05f, 0.09f, 0.85f), ContentMarginLeft = 12, ContentMarginTop = 6, ContentMarginBottom = 6 };
        panel.AddThemeStyleboxOverride("panel", style);
        _hud = new Label();
        panel.AddChild(_hud);
        _ui.AddChild(panel);

        var btnRow = new HBoxContainer();
        btnRow.SetAnchorsPreset(Control.LayoutPreset.BottomWide);
        btnRow.GrowVertical = Control.GrowDirection.Begin;
        btnRow.Alignment = BoxContainer.AlignmentMode.Center;
        var repro = new Button { Text = "🧬 Se reproduire (énergie pleine)", CustomMinimumSize = new Vector2(300, 42) };
        repro.Pressed += TryReproduce;
        btnRow.AddChild(repro);
        var quit = new Button { Text = "Quitter la flaque (Échap)", CustomMinimumSize = new Vector2(220, 42) };
        quit.Pressed += () => ExitRequested?.Invoke();
        btnRow.AddChild(quit);
        _ui.AddChild(btnRow);
    }

    private void UpdateHud()
    {
        _hud.Text = $"ORIGINES — la flaque primordiale   |   Énergie {(int)_player.Energy}/{(int)_player.EnergyMax}" +
            $"   Taille {(int)_player.Size}   Évolutions {Evolutions}/{EvolutionsToAscend}" +
            (Evolutions >= EvolutionsToAscend ? "   ✨ STADE SUIVANT DÉBLOQUÉ" : "") +
            "   |   souris: nager · manger plus petit · fuir plus gros";
    }

    private void TryReproduce()
    {
        if (_player.Energy < _player.EnergyMax * 0.95f)
        {
            _hud.Text = "Il te faut une énergie quasi pleine pour te diviser !";
            return;
        }
        _player.Energy *= 0.4f;
        _choosing = true;
        _choices = _traitPool.OrderBy(_ => _rng.Next()).Take(3)
            .Select(t => (t.Name, t.Desc, t.Apply)).ToArray();

        _evolveBox = new PanelContainer();
        _evolveBox.SetAnchorsPreset(Control.LayoutPreset.Center);
        var st = new StyleBoxFlat { BgColor = new Color(0.03f, 0.08f, 0.13f, 0.97f), ContentMarginLeft = 18, ContentMarginRight = 18, ContentMarginTop = 14, ContentMarginBottom = 14, CornerRadiusTopLeft = 10, CornerRadiusTopRight = 10, CornerRadiusBottomLeft = 10, CornerRadiusBottomRight = 10 };
        _evolveBox.AddThemeStyleboxOverride("panel", st);
        var box = new VBoxContainer();
        box.AddThemeConstantOverride("separation", 8);
        var title = new Label { Text = "🧬 DIVISION — choisis ta mutation" };
        title.AddThemeFontSizeOverride("font_size", 20);
        title.AddThemeColorOverride("font_color", new Color(0.55f, 0.95f, 0.75f));
        box.AddChild(title);
        foreach (var (name, desc, apply) in _choices)
        {
            var b = new Button { Text = $"{name} — {desc}", CustomMinimumSize = new Vector2(420, 40) };
            var applyLocal = apply;
            b.Pressed += () =>
            {
                applyLocal(_player);
                Evolutions++;
                _choosing = false;
                _evolveBox.QueueFree();
                if (Evolutions >= EvolutionsToAscend) StageCompleted?.Invoke();
            };
            box.AddChild(b);
        }
        _evolveBox.AddChild(box);
        _ui.AddChild(_evolveBox);
    }

    public override void _UnhandledKeyInput(InputEvent ev)
    {
        if (ev is InputEventKey k && k.Pressed && k.Keycode == Key.Escape)
            ExitRequested?.Invoke();
    }
}
