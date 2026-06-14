using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using DownHere.Origins;

/// <summary>
/// ORIGINES — l'éditeur d'assemblage cellulaire (le cœur "Thrive" du jeu,
/// notre code). Plein écran, ouvert à chaque division: une grille
/// HEXAGONALE où le joueur POSE/RETIRE ses organites (palette à droite),
/// avec un budget de points de mutation et les stats DÉRIVÉES recalculées
/// en direct depuis le modèle DownHere.Origins.Microbe. 100% procédural.
/// </summary>
public partial class CellEditor : Control
{
    private readonly Microbe _cell;
    private OrganelleType _brush;     // organite sélectionné dans la palette
    private bool _removeMode;
    private int _spentMp;

    private const float Hex = 30f;    // rayon d'un hex à l'écran
    private Vector2 _gridCenter;
    private Label _statsLabel, _mpLabel, _hint;
    private VBoxContainer _palette;

    public event Action<Microbe> Confirmed;   // l'édition est validée

    public CellEditor(Microbe cell)
    {
        _cell = cell;
        _brush = OrganelleRegistry.Cytoplasm;
    }

    public override void _Ready()
    {
        AnchorRight = 1; AnchorBottom = 1;
        MouseFilter = MouseFilterEnum.Stop;

        // ---- Fond sombre type laboratoire ----
        var bg = new ColorRect { Color = new Color(0.02f, 0.06f, 0.10f, 1f) };
        bg.SetAnchorsPreset(LayoutPreset.FullRect);
        bg.MouseFilter = MouseFilterEnum.Ignore;
        AddChild(bg);

        // ---- Titre ----
        var title = new Label { Text = "🧬 ÉDITEUR CELLULAIRE — assemble ton organisme" };
        title.AddThemeFontSizeOverride("font_size", 24);
        title.AddThemeColorOverride("font_color", new Color(0.55f, 0.95f, 0.75f));
        title.Position = new Vector2(24, 16);
        AddChild(title);

        _hint = new Label
        {
            Text = "Clic gauche: poser l'organite sélectionné · doit toucher la cellule · clic droit: retirer",
            Position = new Vector2(24, 50)
        };
        _hint.AddThemeColorOverride("font_color", new Color(0.55f, 0.65f, 0.72f));
        AddChild(_hint);

        BuildPalette();
        BuildStatsPanel();
        BuildButtons();

        _gridCenter = new Vector2(GetViewportRect().Size.X * 0.42f, GetViewportRect().Size.Y * 0.55f);
        RecomputeSpentMp();
    }

    // ==================================================================
    // Palette d'organites (droite)
    // ==================================================================
    private void BuildPalette()
    {
        var panel = new PanelContainer();
        panel.SetAnchorsPreset(LayoutPreset.RightWide);
        panel.AnchorLeft = 1; panel.OffsetLeft = -320; panel.OffsetRight = -16;
        panel.AnchorTop = 0; panel.OffsetTop = 84; panel.AnchorBottom = 1; panel.OffsetBottom = -96;
        var st = new StyleBoxFlat { BgColor = new Color(0.05f, 0.10f, 0.15f, 0.95f), ContentMarginLeft = 12, ContentMarginRight = 12, ContentMarginTop = 10, ContentMarginBottom = 10, CornerRadiusTopLeft = 8, CornerRadiusBottomLeft = 8 };
        panel.AddThemeStyleboxOverride("panel", st);
        AddChild(panel);

        var scroll = new ScrollContainer { SizeFlagsVertical = SizeFlags.ExpandFill };
        panel.AddChild(scroll);
        _palette = new VBoxContainer { SizeFlagsHorizontal = SizeFlags.ExpandFill };
        _palette.AddThemeConstantOverride("separation", 6);
        scroll.AddChild(_palette);

        var head = new Label { Text = "ORGANITES" };
        head.AddThemeColorOverride("font_color", new Color(0.55f, 0.95f, 0.75f));
        head.AddThemeFontSizeOverride("font_size", 15);
        _palette.AddChild(head);

        foreach (var t in OrganelleRegistry.All)
        {
            var b = new Button
            {
                Text = $"{t.DisplayName}  ({t.MpCost:0} PM)",
                CustomMinimumSize = new Vector2(0, 38),
                ToggleMode = true,
            };
            b.TooltipText = OrganelleSummary(t);
            var tl = t;
            b.Pressed += () =>
            {
                _brush = tl; _removeMode = false;
                foreach (var c in _palette.GetChildren())
                    if (c is Button bb) bb.ButtonPressed = bb == b;
            };
            if (t == _brush) b.ButtonPressed = true;
            _palette.AddChild(b);
        }
    }

    private static string OrganelleSummary(OrganelleType t)
    {
        var parts = new List<string>();
        if (t.SpeedBonus != 0) parts.Add($"vitesse +{t.SpeedBonus:0}");
        if (t.StorageBonus != 0) parts.Add($"stockage +{t.StorageBonus:0}");
        if (t.HpBonus != 0) parts.Add($"PV +{t.HpBonus:0}");
        foreach (var p in t.Processes) parts.Add(p.Name);
        return parts.Count > 0 ? string.Join(", ", parts) : "structure";
    }

    // ==================================================================
    // Panneau de stats (gauche), recalculé en direct
    // ==================================================================
    private void BuildStatsPanel()
    {
        var panel = new PanelContainer();
        panel.Position = new Vector2(24, 84);
        panel.CustomMinimumSize = new Vector2(300, 0);
        var st = new StyleBoxFlat { BgColor = new Color(0.05f, 0.10f, 0.15f, 0.95f), ContentMarginLeft = 12, ContentMarginRight = 12, ContentMarginTop = 10, ContentMarginBottom = 10, CornerRadiusTopLeft = 8, CornerRadiusTopRight = 8, CornerRadiusBottomLeft = 8, CornerRadiusBottomRight = 8 };
        panel.AddThemeStyleboxOverride("panel", st);
        AddChild(panel);
        var box = new VBoxContainer();
        box.AddThemeConstantOverride("separation", 4);
        panel.AddChild(box);
        var head = new Label { Text = "STATS (dérivées de la forme)" };
        head.AddThemeColorOverride("font_color", new Color(0.55f, 0.95f, 0.75f));
        box.AddChild(head);
        _mpLabel = new Label();
        box.AddChild(_mpLabel);
        _statsLabel = new Label { AutowrapMode = TextServer.AutowrapMode.WordSmart };
        box.AddChild(_statsLabel);
    }

    private void BuildButtons()
    {
        var row = new HBoxContainer();
        row.SetAnchorsPreset(LayoutPreset.BottomWide);
        row.GrowVertical = GrowDirection.Begin;
        row.Alignment = BoxContainer.AlignmentMode.Center;
        row.AddThemeConstantOverride("separation", 16);
        row.OffsetBottom = -20;

        var confirm = new Button { Text = "✓ Valider et se diviser", CustomMinimumSize = new Vector2(280, 46) };
        confirm.Pressed += () =>
        {
            _cell.RefillToCapacity();
            Confirmed?.Invoke(_cell);
            QueueFree();
        };
        row.AddChild(confirm);
        AddChild(row);
    }

    // ==================================================================
    // Interaction grille hexagonale
    // ==================================================================
    public override void _GuiInput(InputEvent ev)
    {
        if (ev is InputEventMouseButton mb && mb.Pressed)
        {
            var (q, r) = PixelToHex(mb.Position - _gridCenter);
            if (mb.ButtonIndex == MouseButton.Left)
            {
                if (_cell.Occupied(q, r)) return;
                int cost = (int)_brush.MpCost;
                if (_spentMp + cost > Microbe.MpBudget) { Flash("Budget de points de mutation dépassé !"); return; }
                if (_cell.Place(_brush, q, r))
                {
                    RecomputeSpentMp();
                    QueueRedraw();
                }
                else Flash("L'organite doit toucher la cellule.");
            }
            else if (mb.ButtonIndex == MouseButton.Right)
            {
                RemoveAt(q, r);
            }
        }
    }

    private void RemoveAt(int q, int r)
    {
        // On ne retire pas le dernier hex (la cellule doit exister).
        int idx = _cell.Organelles.FindIndex(o => o.Q == q && o.R == r);
        if (idx < 0) return;
        if (_cell.Organelles.Count <= 1) { Flash("Impossible: il faut au moins un organite."); return; }
        _cell.Organelles.RemoveAt(idx);
        RecomputeSpentMp();
        QueueRedraw();
    }

    private void RecomputeSpentMp()
    {
        _spentMp = _cell.Organelles.Sum(o => (int)o.Type.MpCost);
        var s = _cell.ComputeStats();
        _mpLabel.Text = $"Points de mutation: {_spentMp}/{Microbe.MpBudget}";
        _statsLabel.Text =
            $"Taille: {s.HexSize} hex\n" +
            $"Vitesse: {s.BaseSpeed:0.0}\n" +
            $"PV max: {s.MaxHp:0}\n" +
            $"Stockage: {s.StorageCapacity:0}\n" +
            $"Entretien: {s.OsmoregulationCost:0.0} ATP/s\n" +
            $"Bilan ATP: {s.AtpBalance:+0.0;-0.0}/s" +
            (s.AtpBalance < 0 ? "  ⚠ déficit (tu mourras !)" : "  ✓ viable");
    }

    private void Flash(string msg)
    {
        _hint.Text = msg;
        _hint.AddThemeColorOverride("font_color", new Color(1f, 0.5f, 0.4f));
    }

    // ==================================================================
    // Conversion hexagone <-> pixel (axial pointy-top)
    // ==================================================================
    private static (int q, int r) PixelToHex(Vector2 p)
    {
        float q = (Mathf.Sqrt(3f) / 3f * p.X - 1f / 3f * p.Y) / Hex;
        float r = (2f / 3f * p.Y) / Hex;
        return AxialRound(q, r);
    }

    private static Vector2 HexToPixel(int q, int r) =>
        new Vector2(Hex * (Mathf.Sqrt(3f) * q + Mathf.Sqrt(3f) / 2f * r), Hex * (1.5f * r));

    private static (int, int) AxialRound(float q, float r)
    {
        float x = q, z = r, y = -x - z;
        int rx = Mathf.RoundToInt(x), ry = Mathf.RoundToInt(y), rz = Mathf.RoundToInt(z);
        float dx = Math.Abs(rx - x), dy = Math.Abs(ry - y), dz = Math.Abs(rz - z);
        if (dx > dy && dx > dz) rx = -ry - rz;
        else if (dy > dz) ry = -rx - rz;
        else rz = -rx - ry;
        return (rx, rz);
    }

    // ==================================================================
    // Rendu de la grille + cellule assemblée
    // ==================================================================
    public override void _Draw()
    {
        // Grille hexagonale de fond (zone constructible)
        for (int r = -4; r <= 4; r++)
            for (int q = -5; q <= 5; q++)
            {
                var c = _gridCenter + HexToPixel(q, r);
                DrawHexOutline(c, Hex * 0.96f, new Color(0.18f, 0.30f, 0.36f, 0.35f));
            }

        // Organites posés
        foreach (var po in _cell.Organelles)
        {
            var c = _gridCenter + HexToPixel(po.Q, po.R);
            DrawHexFilled(c, Hex * 0.92f, OrganelleColor(po.Type));
            DrawHexOutline(c, Hex * 0.92f, new Color(1, 1, 1, 0.25f));
            // glyphe central simple
            DrawCircle(c, Hex * 0.22f, OrganelleColor(po.Type) * 1.4f);
        }

        // Aperçu sous la souris
        var (mq, mr) = PixelToHex(GetLocalMousePosition() - _gridCenter);
        if (!_cell.Occupied(mq, mr) && _cell.CanPlace(_brush, mq, mr))
        {
            var c = _gridCenter + HexToPixel(mq, mr);
            DrawHexFilled(c, Hex * 0.92f, OrganelleColor(_brush) with { A = 0.35f });
        }
    }

    private void DrawHexOutline(Vector2 c, float radius, Color col)
    {
        var pts = HexCorners(c, radius);
        DrawPolyline(pts.Append(pts[0]).ToArray(), col, 1.5f);
    }

    private void DrawHexFilled(Vector2 c, float radius, Color col)
    {
        DrawColoredPolygon(HexCorners(c, radius), col);
    }

    private static Vector2[] HexCorners(Vector2 c, float radius)
    {
        var pts = new Vector2[6];
        for (int i = 0; i < 6; i++)
        {
            float ang = Mathf.Pi / 180f * (60 * i - 30);
            pts[i] = c + new Vector2(Mathf.Cos(ang), Mathf.Sin(ang)) * radius;
        }
        return pts;
    }

    private static Color OrganelleColor(OrganelleType t) => t.Id switch
    {
        "cytoplasm" => new Color(0.45f, 0.65f, 0.55f),
        "mitochondrion" => new Color(0.85f, 0.55f, 0.40f),
        "chloroplast" => new Color(0.35f, 0.80f, 0.40f),
        "thylakoid" => new Color(0.45f, 0.85f, 0.55f),
        "chemoplast" => new Color(0.80f, 0.75f, 0.35f),
        "vacuole" => new Color(0.40f, 0.60f, 0.85f),
        "flagellum" => new Color(0.70f, 0.50f, 0.85f),
        "pilus" => new Color(0.85f, 0.40f, 0.45f),
        "double_membrane" => new Color(0.60f, 0.65f, 0.70f),
        "toxin_vacuole" => new Color(0.75f, 0.35f, 0.65f),
        _ => new Color(0.5f, 0.5f, 0.5f),
    };

    public override void _Process(double delta) => QueueRedraw();
}
