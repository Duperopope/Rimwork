# Godot 4 C# API reference (subset used by this project)
# Drawing (inside a CanvasItem._Draw() override ONLY - these are INSTANCE methods, never static):
void DrawRect(Rect2 rect, Color color, bool filled = true, float width = -1f)
void DrawCircle(Vector2 position, float radius, Color color)
void DrawLine(Vector2 from, Vector2 to, Color color, float width = -1f)
void DrawColoredPolygon(Vector2[] points, Color color)
void DrawString(Font font, Vector2 pos, string text, HorizontalAlignment alignment, float width, int fontSize, Color modulate, ...)
void DrawTexture(Texture2D texture, Vector2 position, Color? modulate = null)
void QueueRedraw()  // request a redraw; never call _Draw directly

# Core types:
Vector2(float x, float y) - fields are .X and .Y (UPPERCASE in C#!)
Rect2(float x, float y, float w, float h) / Rect2(Vector2 position, Vector2 size) - .Position and .Size are Vector2
Color(float r, float g, float b, float a = 1f) - components 0..1
Colors.White, Colors.Black, Colors.Red ... (static palette)
Color * float scales brightness: color * 0.6f

# Node lifecycle (this project):
public override void _Ready()          // once at scene start
public override void _Process(double delta)  // every frame
public override void _Draw()           // when QueueRedraw was requested
ThemeDB.FallbackFont                    // default font for DrawString
ResourceLoader.Load<Texture2D>("res://path.png")  // returns null if missing

# Input:
Input.IsMouseButtonPressed(MouseButton.Left)
GetGlobalMousePosition() / GetLocalMousePosition()

# RULES:
- Draw* methods only work inside _Draw() of the same CanvasItem.
- Vector2 members are .X/.Y - lowercase .x/.y DOES NOT COMPILE in C#.
- There is no DrawTriangle: use DrawColoredPolygon with 3 points.
- AudioStreamPlayer/SubViewport/Camera3D nodes cannot be added from this
  code-only patch loop (they need .tscn edits) - do not propose them.
