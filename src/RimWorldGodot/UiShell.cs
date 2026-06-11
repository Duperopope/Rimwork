using Godot;
using System;
using System.Linq;

/// <summary>
/// FROZEN UI shell (see docs/UI_FREEZE_CONTRACT.md): main menu, in-game HUD,
/// options (persisted to user://options.cfg) and the jury-readable Dev tab.
/// Built entirely with containers/anchors so it survives any window size.
/// The local LLM extends CONTENT through the marked extension points only.
/// </summary>
public partial class UiShell : CanvasLayer
{
    private Game3D _game;

    // Screens
    private Control _menu, _hud, _options, _devTab, _credits;

    // HUD live labels
    private Label _resources, _clock, _objective, _alert, _macro, _events;
    private Label _inspector;
    private Button _pauseBtn;
    private PanelContainer _visitPanel;
    private Button _visitBtn;
    private int _pendingTile = -1;
    private string _pendingBiome = "";

    // Options state
    private ConfigFile _cfg = new();
    private const string CfgPath = "user://options.cfg";

    private const string Version = "down-here-0.2";
    private Control _saveScreen;
    private bool _saveMode; // true = saving, false = loading
    private static string SlotPath(int n) => System.IO.Path.Combine(OS.GetUserDataDir(), "saves", $"slot{n}.json");

    public override void _Ready()
    {
        _game = GetParent().GetNode<Game3D>("Game3D");
        bool unattended = OS.GetEnvironment("RIMWORK_AUTOSTART") == "1" || System.IO.File.Exists(@"g:/Rimwork/scripts/autostart.flag");
        _game.ThreatSpawned += () => { if (PauseOnThreat && _hud.Visible && !unattended) _game.Paused = true; };
        BuildMenu();
        BuildHud();
        BuildOptions();
        BuildDevTab();
        BuildCredits();
        LoadOptions();
        ShowOnly(_menu);
        // Unattended verification mode: the watchdog sets RIMWORK_AUTOSTART
        // so self-screenshots capture real gameplay, not the menu.
        if (OS.GetEnvironment("RIMWORK_AUTOSTART") == "1" || System.IO.File.Exists(@"g:/Rimwork/scripts/autostart.flag"))
        {
            GD.Print("[FLOW] Autostart: New Game (verification mode).");
            _game.AlertText = "Colonie fondée — bonne chance !";
            ShowOnly(_hud);
        }
    }

    // ==================================================================
    // Helpers (consistent visual identity)
    // ==================================================================
    private static readonly Color PanelBg = new(0.08f, 0.10f, 0.13f, 0.92f);
    private static readonly Color Accent = new(0.36f, 0.78f, 0.46f);

    private PanelContainer Panel()
    {
        var p = new PanelContainer();
        var style = new StyleBoxFlat { BgColor = PanelBg, CornerRadiusBottomLeft = 8, CornerRadiusBottomRight = 8, CornerRadiusTopLeft = 8, CornerRadiusTopRight = 8, ContentMarginLeft = 12, ContentMarginRight = 12, ContentMarginTop = 8, ContentMarginBottom = 8 };
        p.AddThemeStyleboxOverride("panel", style);
        return p;
    }

    private Label Title(string text, int size = 22)
    {
        var l = new Label { Text = text };
        l.AddThemeFontSizeOverride("font_size", size);
        l.AddThemeColorOverride("font_color", Accent);
        return l;
    }

    private Button Btn(string text, Action onPress, bool disabled = false, string tooltip = null)
    {
        var b = new Button { Text = text, Disabled = disabled, CustomMinimumSize = new Vector2(240, 40) };
        if (tooltip != null) b.TooltipText = tooltip;
        b.Pressed += () => onPress();
        return b;
    }

    private void ShowOnly(Control screen)
    {
        foreach (var c in new[] { _menu, _hud, _options, _devTab, _credits, _saveScreen, _genScreen })
            if (c != null) c.Visible = c == screen;
        _game.Paused = screen != _hud;
    }

    // ==================================================================
    // MAIN MENU
    // ==================================================================
    private void BuildMenu()
    {
        _menu = new Control { AnchorRight = 1, AnchorBottom = 1 };
        AddChild(_menu);

        var center = new CenterContainer { AnchorRight = 1, AnchorBottom = 1 };
        _menu.AddChild(center);
        var box = new VBoxContainer { CustomMinimumSize = new Vector2(420, 0) };
        box.AddThemeConstantOverride("separation", 10);
        center.AddChild(box);

        var t = Title("DOWN HERE !", 54);
        t.HorizontalAlignment = HorizontalAlignment.Center;
        box.AddChild(t);
        var sub = new Label { Text = "Une colonie, une planète, un système.\nChaque ligne de gameplay écrite par une IA locale autonome.", HorizontalAlignment = HorizontalAlignment.Center };
        sub.AddThemeColorOverride("font_color", new Color(0.7f, 0.74f, 0.8f));
        box.AddChild(sub);
        box.AddChild(new Control { CustomMinimumSize = new Vector2(0, 16) });

        box.AddChild(Btn("Nouvelle partie", () => OpenWorldGenScreen()));
        box.AddChild(Btn("Continuer", () => OpenSaveScreen(saveMode: false)));
        box.AddChild(Btn("Options", () => ShowOnly(_options)));
        box.AddChild(Btn("Dev / Diagnostics", () => ShowOnly(_devTab)));
        box.AddChild(Btn("Crédits", () => ShowOnly(_credits)));
        box.AddChild(Btn("Quitter", () => GetTree().Quit()));

        var ver = new Label { Text = $"build {Version}", HorizontalAlignment = HorizontalAlignment.Center };
        ver.AddThemeColorOverride("font_color", new Color(0.45f, 0.5f, 0.55f));
        box.AddChild(ver);
    }

    // ==================================================================
    // IN-GAME HUD
    // ==================================================================
    private void BuildHud()
    {
        _hud = new Control { AnchorRight = 1, AnchorBottom = 1, MouseFilter = Control.MouseFilterEnum.Ignore };
        AddChild(_hud);

        // ---- Top bar: resources + clock + speed ----
        var top = Panel();
        top.SetAnchorsPreset(Control.LayoutPreset.TopWide);
        top.MouseFilter = Control.MouseFilterEnum.Stop;
        _hud.AddChild(top);
        var topRow = new HBoxContainer();
        topRow.AddThemeConstantOverride("separation", 18);
        top.AddChild(topRow);
        _resources = new Label();
        topRow.AddChild(_resources);
        topRow.AddChild(new Control { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill });
        _clock = new Label();
        topRow.AddChild(_clock);
        _pauseBtn = new Button { Text = "II" };
        _pauseBtn.Pressed += () => { _game.Paused = !_game.Paused; };
        topRow.AddChild(_pauseBtn);
        var s1 = new Button { Text = "1x" }; s1.Pressed += () => _game.SpeedMultiplier = 1f; topRow.AddChild(s1);
        var s3 = new Button { Text = "3x" }; s3.Pressed += () => _game.SpeedMultiplier = 3f; topRow.AddChild(s3);
        var saveBtn = new Button { Text = "Sauver" }; saveBtn.Pressed += () => OpenSaveScreen(saveMode: true); topRow.AddChild(saveBtn);
        var menuBtn = new Button { Text = "Menu" }; menuBtn.Pressed += () => ShowOnly(_menu); topRow.AddChild(menuBtn);

        // ---- Left column: objective + macro/LOD + events ----
        var left = new VBoxContainer { AnchorTop = 0.12f, AnchorBottom = 0.95f, AnchorLeft = 0, AnchorRight = 0 };
        left.OffsetLeft = 10; left.OffsetRight = 330;
        left.AddThemeConstantOverride("separation", 8);
        left.MouseFilter = Control.MouseFilterEnum.Ignore;
        _hud.AddChild(left);

        var objP = Panel(); left.AddChild(objP);
        var objBox = new VBoxContainer(); objP.AddChild(objBox);
        objBox.AddChild(Title("OBJECTIF", 13));
        _objective = new Label { AutowrapMode = TextServer.AutowrapMode.WordSmart };
        objBox.AddChild(_objective);

        var macroP = Panel(); left.AddChild(macroP);
        var macroBox = new VBoxContainer(); macroP.AddChild(macroBox);
        macroBox.AddChild(Title("MONDE (macro → local)", 13));
        _macro = new Label { AutowrapMode = TextServer.AutowrapMode.WordSmart };
        macroBox.AddChild(_macro);

        var evP = Panel(); left.AddChild(evP);
        var evBox = new VBoxContainer(); evP.AddChild(evBox);
        evBox.AddChild(Title("ÉVÉNEMENTS", 13));
        _events = new Label { AutowrapMode = TextServer.AutowrapMode.WordSmart };
        evBox.AddChild(_events);

        // ---- Right column: pawn inspector ----
        var right = Panel();
        right.SetAnchorsPreset(Control.LayoutPreset.RightWide);
        right.AnchorLeft = 1; right.OffsetLeft = -340; right.OffsetRight = -10;
        right.AnchorTop = 0.12f; right.AnchorBottom = 0.7f;
        right.MouseFilter = Control.MouseFilterEnum.Ignore;
        _hud.AddChild(right);
        var insBox = new VBoxContainer(); right.AddChild(insBox);
        insBox.AddChild(Title("COLON SÉLECTIONNÉ", 13));
        _inspector = new Label { AutowrapMode = TextServer.AutowrapMode.WordSmart };
        insBox.AddChild(_inspector);

        // ---- Alert banner ----
        var alertP = Panel();
        alertP.SetAnchorsPreset(Control.LayoutPreset.CenterTop);
        alertP.AnchorTop = 0.07f; alertP.AnchorBottom = 0.07f;
        _alert = new Label();
        _alert.AddThemeColorOverride("font_color", new Color(1f, 0.45f, 0.35f));
        _alert.AddThemeFontSizeOverride("font_size", 16);
        alertP.AddChild(_alert);
        _hud.AddChild(alertP);

        // ---- Visit button (appears when a planet tile is selected) ----
        _visitPanel = Panel();
        _visitPanel.SetAnchorsPreset(Control.LayoutPreset.CenterBottom);
        _visitPanel.AnchorTop = 0.86f; _visitPanel.AnchorBottom = 0.86f;
        _visitPanel.Visible = false;
        _visitBtn = new Button { Text = "Visiter cette tuile", CustomMinimumSize = new Vector2(260, 44) };
        _visitBtn.Pressed += () =>
        {
            _visitPanel.Visible = false;
            if (_pendingTile >= 0) _game.VisitTile(_pendingTile, _pendingBiome);
        };
        _visitPanel.AddChild(_visitBtn);
        _hud.AddChild(_visitPanel);
        _game.TileSelected += (idx, biome, isColony) =>
        {
            _pendingTile = idx; _pendingBiome = biome;
            _visitBtn.Text = isColony ? "Retourner à la colonie" : $"Visiter cette tuile ({biome})";
            _visitPanel.Visible = true;
        };

        // ---- Bottom hint ----
        var hint = new Label
        {
            Text = "clic: sélection/ordre récolte  |  Shift+clic: mur  |  Ctrl+clic: lit  |  Tab/M: planète (hex cliquables)  |  molette: zoom  |  Échap: menu",
            HorizontalAlignment = HorizontalAlignment.Center
        };
        hint.SetAnchorsPreset(Control.LayoutPreset.BottomWide);
        hint.AddThemeColorOverride("font_color", new Color(0.5f, 0.55f, 0.6f));
        _hud.AddChild(hint);
    }

    public override void _UnhandledKeyInput(InputEvent ev)
    {
        if (ev is InputEventKey k && k.Pressed && !k.Echo && k.Keycode == Key.Escape)
        {
            if (_hud.Visible) ShowOnly(_menu);
            else if (_options.Visible || _devTab.Visible || _credits.Visible)
                ShowOnly(_game.World != null && _game.World.TotalTicks > 0 ? _hud : _menu);
        }
    }

    public override void _Process(double delta)
    {
        if (!_hud.Visible) return;
        var w = _game.World;

        _resources.Text = $"Bois {w.Wood}   Pierre {w.Stone}   Eau {w.Water}   Nourriture {w.Food}   Métal {w.Metal}   Outils {w.Tools}   Pop {w.Pawns.Count(p => p.HP > 0)}";
        string meteo = _game.LocalWeather switch { WeatherKind.Rain => "🌧 pluie", WeatherKind.Storm => "⛈ orage", WeatherKind.Fog => "🌫 brume", _ => "☀ clair" };
        _clock.Text = $"[{_game.ViewLayer}] Jour {w.DayNumber}, {(int)_game.LocalHourF:00}:00  {meteo}" + (_game.Paused ? "  [PAUSE]" : $"  [{_game.SpeedMultiplier:0}x]");
        _pauseBtn.Text = _game.Paused ? "▶" : "II";

        int rooms = w.GetRooms().Count(r => r.Function != RoomFunction.Empty);
        _objective.Text = $"{w.CurrentGoalText}\nPièces fonctionnelles: {rooms}   Objectifs accomplis: {w.GoalIndex}\nRecherche: {w.ResearchPoints} pts ({string.Join(", ", w.UnlockedTech.DefaultIfEmpty("aucune tech"))})";

        var m = w.Macro;
        _macro.Text = $"Système {m.System.StarName} — colonie sur {m.System.HomeBody.Name}\n" +
            $"Pression de raid: {m.RaidPressure:0.0}x   Climat: {m.ClimatePulse:0.00}\n" +
            $"Demande commerciale: {m.TradeDemand:P0}\n" +
            $"Sites extérieurs: {string.Join(", ", m.Sites.Select(s => s.Name))}";

        _events.Text = string.Join("\n", w.ColonyEvents.TakeLast(6));
        _alert.Text = _game.AlertText;

        var p = _game.SelectedPawn;
        if (p == null || p.HP <= 0)
            _inspector.Text = "(cliquez sur un colon)";
        else
        {
            string mem = string.Join("\n", p.Memories.TakeLast(4).Select(mm => $"  • {mm.What} ({mm.MoodDelta:+0;-0})"));
            string skills = string.Join(", ", p.SkillXP.Where(s => s.Value > 0).Select(s => $"{s.Key} {(int)(s.Value / 100)}"));
            _inspector.Text =
                $"{p.Name} ({p.Sex})\nTraits: {string.Join(", ", p.Traits)}\n" +
                $"PV {p.HP:0}/100   Humeur {p.Mood:0}   Stress {p.Stress:0}\n" +
                $"Faim {p.Hunger:0}   Soif {p.Thirst:0}   Fatigue {p.Fatigue:0}\n" +
                $"Compétences: {(skills.Length > 0 ? skills : "novice")}\n" +
                $"Relations: {p.Relationships.Count} connaissances\n" +
                $"Souvenirs récents:\n{(mem.Length > 0 ? mem : "  (aucun)")}";
        }
    }

    // ==================================================================
    // WORLD CREATION SCREEN (Down Here! - seed-driven universe)
    // ==================================================================
    private Control _genScreen;

    private (HSlider Slider, Label Val) GenRow(VBoxContainer box, string label, double min, double max, double val, double step = 1)
    {
        var row = new HBoxContainer();
        row.AddChild(new Label { Text = label, CustomMinimumSize = new Vector2(230, 0) });
        var sl = new HSlider { MinValue = min, MaxValue = max, Step = step, Value = val, CustomMinimumSize = new Vector2(220, 20) };
        var vl = new Label { Text = val.ToString("0.##"), CustomMinimumSize = new Vector2(60, 0) };
        sl.ValueChanged += v => vl.Text = v.ToString("0.##");
        row.AddChild(sl); row.AddChild(vl);
        box.AddChild(row);
        return (sl, vl);
    }

    private void OpenWorldGenScreen()
    {
        if (_genScreen != null) _genScreen.QueueFree();
        _genScreen = new Control { AnchorRight = 1, AnchorBottom = 1 };
        AddChild(_genScreen);
        var center = new CenterContainer { AnchorRight = 1, AnchorBottom = 1 };
        _genScreen.AddChild(center);
        var panel = Panel(); center.AddChild(panel);
        var box = new VBoxContainer(); panel.AddChild(box);
        box.AddThemeConstantOverride("separation", 6);
        box.AddChild(Title("CRÉATION DU MONDE"));
        box.AddChild(new Label { Text = "Le même seed produit toujours le même univers (déterministe)." });

        var seedRow = new HBoxContainer();
        seedRow.AddChild(new Label { Text = "Seed", CustomMinimumSize = new Vector2(230, 0) });
        var seedEdit = new LineEdit { Text = new Random().Next(1, 999999).ToString(), CustomMinimumSize = new Vector2(150, 0) };
        var dice = new Button { Text = "🎲" };
        dice.Pressed += () => seedEdit.Text = new Random().Next(1, 999999).ToString();
        seedRow.AddChild(seedEdit); seedRow.AddChild(dice);
        box.AddChild(seedRow);

        var planets = GenRow(box, "Corps du système", 2, 6, 3);
        var orbit = GenRow(box, "Vitesse d'orbite", 0.25, 4, 1, 0.25);
        var biome = GenRow(box, "Climat de l'univers (froid↔chaud)", -1, 1, 0, 0.1);
        var pawns = GenRow(box, "Colons de départ", 4, 16, 8);
        var animals = GenRow(box, "Densité de faune", 0, 3, 1, 0.25);
        var mapSize = GenRow(box, "Taille des cartes locales", 50, 128, 64, 2);

        box.AddChild(new Control { CustomMinimumSize = new Vector2(0, 10) });
        var create = new Button { Text = "Créer le monde", CustomMinimumSize = new Vector2(260, 46) };
        create.Pressed += () =>
        {
            int seed = int.TryParse(seedEdit.Text, out var sv) ? sv : 12345;
            var gen = new WorldGenSettings
            {
                Seed = seed,
                PlanetCount = (int)planets.Slider.Value,
                OrbitSpeedMult = (float)orbit.Slider.Value,
                BiomeShift = (float)biome.Slider.Value,
                PawnCount = (int)pawns.Slider.Value,
                AnimalDensity = (float)animals.Slider.Value,
                MapSize = (int)mapSize.Slider.Value,
            };
            GD.Print($"[FLOW] New Game: world created (seed {seed}).");
            _game.NewGame(gen);
            ShowOnly(_hud);
        };
        box.AddChild(create);
        box.AddChild(Btn("Retour", () => ShowOnly(_menu)));
        ShowOnly(_genScreen);
    }

    // ==================================================================
    // SAVE SLOTS (3 slots, save or load depending on entry point)
    // ==================================================================
    private void OpenSaveScreen(bool saveMode)
    {
        _saveMode = saveMode;
        if (_saveScreen != null) { _saveScreen.QueueFree(); }
        _saveScreen = new Control { AnchorRight = 1, AnchorBottom = 1 };
        AddChild(_saveScreen);
        var center = new CenterContainer { AnchorRight = 1, AnchorBottom = 1 };
        _saveScreen.AddChild(center);
        var panel = Panel(); center.AddChild(panel);
        var box = new VBoxContainer(); panel.AddChild(box);
        box.AddThemeConstantOverride("separation", 8);
        box.AddChild(Title(saveMode ? "SAUVEGARDER" : "CHARGER UNE PARTIE"));
        for (int i = 1; i <= 3; i++)
        {
            int slot = i;
            string desc = System.IO.File.Exists(SlotPath(slot)) ? SaveLoad.Describe(SlotPath(slot)) : null;
            string label = $"Slot {slot} — " + (desc ?? "(vide)");
            bool disabled = !saveMode && desc == null;
            box.AddChild(Btn(label, () =>
            {
                if (_saveMode)
                {
                    SaveLoad.Save(_game.World, SlotPath(slot));
                    _game.AlertText = $"Partie sauvegardée (slot {slot}).";
                    ShowOnly(_hud);
                }
                else
                {
                    var w = SaveLoad.Load(SlotPath(slot));
                    _game.LoadWorld(w);
                    _game.AlertText = $"Partie chargée (slot {slot}) — jour {w.DayNumber}.";
                    ShowOnly(_hud);
                }
            }, disabled: disabled));
        }
        box.AddChild(Btn("Retour", () => ShowOnly(_game.World != null && _game.World.TotalTicks > 0 ? _hud : _menu)));
        ShowOnly(_saveScreen);
    }

    // ==================================================================
    // OPTIONS (persisted)
    // ==================================================================
    private HSlider AddSlider(VBoxContainer box, string label, double min, double max, double value, Action<double> apply)
    {
        box.AddChild(new Label { Text = label });
        var s = new HSlider { MinValue = min, MaxValue = max, Step = 0.05, Value = value, CustomMinimumSize = new Vector2(280, 20) };
        s.ValueChanged += v => { apply(v); SaveOptions(); };
        box.AddChild(s);
        return s;
    }

    private CheckButton AddToggle(VBoxContainer box, string label, bool value, Action<bool> apply)
    {
        var c = new CheckButton { Text = label, ButtonPressed = value };
        c.Toggled += v => { apply(v); SaveOptions(); };
        box.AddChild(c);
        return c;
    }

    private HSlider _uiScale, _volume, _panSpeed, _zoomSpeed;
    private CheckButton _fullscreen, _pauseOnThreat, _highContrast;
    public bool PauseOnThreat { get; private set; } = true;

    private void BuildOptions()
    {
        _options = new Control { AnchorRight = 1, AnchorBottom = 1 };
        AddChild(_options);
        var center = new CenterContainer { AnchorRight = 1, AnchorBottom = 1 };
        _options.AddChild(center);
        var panel = Panel(); center.AddChild(panel);
        var box = new VBoxContainer(); panel.AddChild(box);
        box.AddThemeConstantOverride("separation", 6);

        box.AddChild(Title("OPTIONS"));
        _uiScale = AddSlider(box, "Échelle de l'interface", 0.7, 1.6, 1.0, v => GetTree().Root.ContentScaleFactor = (float)v);
        _volume = AddSlider(box, "Volume principal", 0, 1, 0.8, v => AudioServer.SetBusVolumeDb(0, Mathf.LinearToDb((float)Math.Max(0.001, v))));
        _panSpeed = AddSlider(box, "Vitesse de caméra", 6, 40, 18, v => _game.CamPanSpeed = (float)v);
        _zoomSpeed = AddSlider(box, "Vitesse de zoom", 1, 6, 2.5, v => _game.CamZoomSpeed = (float)v);
        _fullscreen = AddToggle(box, "Plein écran", false, v =>
            DisplayServer.WindowSetMode(v ? DisplayServer.WindowMode.Fullscreen : DisplayServer.WindowMode.Windowed));
        _pauseOnThreat = AddToggle(box, "Pause en cas de menace", true, v => PauseOnThreat = v);
        _highContrast = AddToggle(box, "Contraste élevé (UI)", false, v =>
            GetTree().Root.ContentScaleFactor = GetTree().Root.ContentScaleFactor); // visual identity kept; reserved slot

        box.AddChild(new Control { CustomMinimumSize = new Vector2(0, 10) });
        box.AddChild(Btn("Retour", () => ShowOnly(_game.World.TotalTicks > 0 ? _hud : _menu)));
    }

    private void SaveOptions()
    {
        _cfg.SetValue("ui", "scale", _uiScale.Value);
        _cfg.SetValue("audio", "master", _volume.Value);
        _cfg.SetValue("camera", "pan", _panSpeed.Value);
        _cfg.SetValue("camera", "zoom", _zoomSpeed.Value);
        _cfg.SetValue("game", "pause_on_threat", _pauseOnThreat.ButtonPressed);
        _cfg.SetValue("video", "fullscreen", _fullscreen.ButtonPressed);
        _cfg.Save(CfgPath);
    }

    private void LoadOptions()
    {
        if (_cfg.Load(CfgPath) != Error.Ok) return;
        _uiScale.Value = (double)_cfg.GetValue("ui", "scale", 1.0);
        _volume.Value = (double)_cfg.GetValue("audio", "master", 0.8);
        _panSpeed.Value = (double)_cfg.GetValue("camera", "pan", 18.0);
        _zoomSpeed.Value = (double)_cfg.GetValue("camera", "zoom", 2.5);
        _pauseOnThreat.ButtonPressed = (bool)_cfg.GetValue("game", "pause_on_threat", true);
        _fullscreen.ButtonPressed = (bool)_cfg.GetValue("video", "fullscreen", false);
    }

    // ==================================================================
    // DEV / DIAGNOSTICS TAB (jury-readable, French)
    // ==================================================================
    private RichTextLabel _devText;

    private void BuildDevTab()
    {
        _devTab = new Control { AnchorRight = 1, AnchorBottom = 1 };
        AddChild(_devTab);
        var panel = Panel();
        panel.SetAnchorsPreset(Control.LayoutPreset.FullRect);
        panel.OffsetLeft = 30; panel.OffsetRight = -30; panel.OffsetTop = 24; panel.OffsetBottom = -24;
        _devTab.AddChild(panel);
        var box = new VBoxContainer(); panel.AddChild(box);
        var head = new HBoxContainer(); box.AddChild(head);
        head.AddChild(Title("DEV / DIAGNOSTICS — la simulation prouvée"));
        head.AddChild(new Control { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill });
        var back = new Button { Text = "Retour" }; back.Pressed += () => ShowOnly(_game.World.TotalTicks > 0 ? _hud : _menu); head.AddChild(back);
        var scroll = new ScrollContainer { SizeFlagsVertical = Control.SizeFlags.ExpandFill };
        box.AddChild(scroll);
        _devText = new RichTextLabel { BbcodeEnabled = true, FitContent = true, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill };
        scroll.AddChild(_devText);

        var timer = new Timer { WaitTime = 1.0, Autostart = true };
        timer.Timeout += RefreshDevTab;
        AddChild(timer);
    }

    private void RefreshDevTab()
    {
        if (!_devTab.Visible) return;
        var w = _game.World;
        var m = w.Macro;
        string B(string s) => $"[color=#5cc26e][b]{s}[/b][/color]";

        string health = "(scripts/logs/health.json indisponible)";
        try
        {
            var txt = System.IO.File.ReadAllText(@"g:\Rimwork\scripts\logs\health.json");
            health = txt.Length > 350 ? txt.Substring(0, 350) : txt;
        }
        catch { }
        string lessons = "";
        try { lessons = string.Join("\n", System.IO.File.ReadLines(@"g:\Rimwork\scripts\logs\lessons.md").Take(6)); } catch { }

        int idle = 0, stuck = 0;
        foreach (var p in w.Pawns.Where(p => p.HP > 0))
            if (w.GetDriver(p).Current == null) idle++;

        _devText.Text =
$@"{B("1. CE QUE C'EST")}
Un colony-sim déterministe multi-échelles dont le gameplay est écrit par un LLM local
autonome (boucle: roadmap → patch → build → tests → simulation → commit GitHub).

{B("2. BUILD & VALIDATION")}
{health}

{B("3. COLONIE LOCALE (LOD Local)")}
Pawns vivants: {w.Pawns.Count(p => p.HP > 0)}   oisifs: {idle}   tâches en attente: {w.Tasks.Pending.Count}
Bois {w.Wood}  Pierre {w.Stone}  Eau {w.Water}  Nourriture {w.Food}  Métal {w.Metal}  Outils {w.Tools}
Pièces fonctionnelles: {w.GetRooms().Count(r => r.Function != RoomFunction.Empty)}   Objectif: {w.CurrentGoalText}
Menaces actives: {_game.Threats.Count}
État du jeu: {(_hud.Visible ? "En jeu" : "Menu")} — couche active: {_game.ViewLayer} (Tab/M pour basculer)
Pawns: blessés {w.Pawns.Count(p => p.HP > 0 && p.HP < 60)}  affamés {w.Pawns.Count(p => p.HP > 0 && p.Hunger > 70)}  assoiffés {w.Pawns.Count(p => p.HP > 0 && p.Thirst > 70)}

{B("4. ESPRITS DES PAWNS (LOD Detail)")}
{string.Join("\n", w.Pawns.Where(p => p.HP > 0).Take(8).Select(p =>
    $"{p.Name,-8} PV {p.HP,3:0}  humeur {p.Mood,3:0}  stress {p.Stress,3:0}  faim {p.Hunger,3:0}  soif {p.Thirst,3:0}  [{string.Join("/", p.Traits)}]  souvenirs:{p.Memories.Count} relations:{p.Relationships.Count}"))}

{B("5. MONDE / LOD (Solar → Planet → Region)")}
Étoile {m.System.StarName}, activité solaire {m.System.SolarActivity:0.00}
Corps: {string.Join(" | ", m.System.Bodies.Select(b => $"{b.Name}({b.Kind}, hab {b.Habitability:0.0}, T {b.ClimateTemp:+0.0;-0.0})"))}
Colonie sur {m.System.HomeBody.Name}, région (2,2) d'une grille 5x5
Dernières mises à jour LOD: {string.Join("  ", m.LastUpdate.Select(kv => $"{kv.Key}:t{kv.Value}"))}
Effets macro→local ACTIFS: regrowth x{m.ClimatePulse:0.00} (végétation) ; raids x{m.RaidPressure:0.0} (spawn)

{B("6. ÉCONOMIE / SITES EXTÉRIEURS (LOD Region)")}
{string.Join("\n", m.Sites.Select(s => $"{s.Name,-12} [{s.Faction}]  attitude {s.Attitude:+0.0;-0.0}  pop {s.Population:0}  demande {s.TradeDemand:P0}  appétit de raid {s.RaidAppetite:P0}"))}
Demande commerciale globale: {m.TradeDemand:P0}

{B("7. ASSETS KAYKIT")}
Pawns: Adventurers (Knight/Barbarian/Mage/Ranger/Rogue) — Menaces: Skeletons
Nature: Forest Pack — Bâtiments: Dungeon Remastered — Prod: RPG Tools (enclume), Restaurant (four)
Voir docs/ASSET_CATALOG.md pour le détail et les fallbacks.

{B("8. LE DÉVELOPPEUR IA")}
Leçons apprises (extrait):
{lessons}
Garde-fous: prédiction d'échec avant build, anti-stub, vérification roadmap-vs-code,
détection de doublons, commit+push automatiques après validation.
Refus automatiques: suppressions destructives, réécritures massives, tâches sans preuve.

{B("9. ÉVÉNEMENTS MONDE (brut)")}
{string.Join("\n", m.WorldEvents.TakeLast(8))}";
    }

    // ==================================================================
    // CREDITS
    // ==================================================================
    private void BuildCredits()
    {
        _credits = new Control { AnchorRight = 1, AnchorBottom = 1 };
        AddChild(_credits);
        var center = new CenterContainer { AnchorRight = 1, AnchorBottom = 1 };
        _credits.AddChild(center);
        var panel = Panel(); center.AddChild(panel);
        var box = new VBoxContainer(); panel.AddChild(box);
        box.AddChild(Title("CRÉDITS"));
        box.AddChild(new Label
        {
            Text = "Gameplay: écrit par un LLM local autonome (Qwen2.5-Coder, ROCm)\n" +
                   "Harnais & supervision: Claude (Anthropic) — une seule passe autorisée\n" +
                   "Direction: Duperopope\n\n" +
                   "Assets 3D: KayKit (CC0) — Adventurers, Skeletons, Dungeon Remastered,\n" +
                   "Forest Nature, Furniture/Restaurant/Resource/RPG Tools Bits\n" +
                   "Moteur: Godot 4.6 (.NET)"
        });
        box.AddChild(Btn("Retour", () => ShowOnly(_menu)));
    }
}
