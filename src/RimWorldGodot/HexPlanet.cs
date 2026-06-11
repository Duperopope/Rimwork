using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

/// <summary>
/// Goldberg-polyhedron hex-tile planet generator (the technique behind
/// hex-tiled planet spheres: subdivide an icosahedron, project onto the
/// sphere, then take the DUAL - every vertex becomes a tile whose polygon
/// is the ring of surrounding triangle centroids. Twelve tiles are
/// pentagons (the original icosahedron vertices), the rest are hexagons.
/// Reference approach: truncated-icosahedron subdivision as discussed in
/// the Godot community (hex tile planet generators, e.g. SirChett's FD).
/// </summary>
public static class HexPlanet
{
    public class Tile
    {
        public Vector3 Center;       // unit sphere
        public Vector3[] Polygon;    // unit sphere ring, wound CCW seen from outside
    }

    /// <summary>Generate tiles for a unit sphere. frequency 4 -> 162 tiles,
    /// 5 -> 252 tiles, 6 -> 362 tiles.</summary>
    public static List<Tile> Generate(int frequency)
    {
        // --- Icosahedron ---
        float t = (1f + Mathf.Sqrt(5f)) / 2f;
        var verts = new List<Vector3>
        {
            new(-1,  t,  0), new( 1,  t,  0), new(-1, -t,  0), new( 1, -t,  0),
            new( 0, -1,  t), new( 0,  1,  t), new( 0, -1, -t), new( 0,  1, -t),
            new( t,  0, -1), new( t,  0,  1), new(-t,  0, -1), new(-t,  0,  1),
        };
        for (int i = 0; i < verts.Count; i++) verts[i] = verts[i].Normalized();
        int[][] faces =
        {
            new[]{0,11,5}, new[]{0,5,1}, new[]{0,1,7}, new[]{0,7,10}, new[]{0,10,11},
            new[]{1,5,9}, new[]{5,11,4}, new[]{11,10,2}, new[]{10,7,6}, new[]{7,1,8},
            new[]{3,9,4}, new[]{3,4,2}, new[]{3,2,6}, new[]{3,6,8}, new[]{3,8,9},
            new[]{4,9,5}, new[]{2,4,11}, new[]{6,2,10}, new[]{8,6,7}, new[]{9,8,1},
        };

        // --- Subdivide each face into frequency^2 triangles ---
        var vertIndex = new Dictionary<(int, int, int), int>(); // quantized pos -> index
        var allVerts = new List<Vector3>();
        var tris = new List<int[]>();

        int Key(Vector3 v)
        {
            var q = ((int)Math.Round(v.X * 50000), (int)Math.Round(v.Y * 50000), (int)Math.Round(v.Z * 50000));
            if (vertIndex.TryGetValue(q, out int idx)) return idx;
            vertIndex[q] = allVerts.Count;
            allVerts.Add(v);
            return allVerts.Count - 1;
        }

        foreach (var f in faces)
        {
            Vector3 a = verts[f[0]], b = verts[f[1]], c = verts[f[2]];
            // grid of points on the face, projected to the sphere
            var grid = new int[frequency + 1][];
            for (int i = 0; i <= frequency; i++)
            {
                grid[i] = new int[i + 1];
                for (int j = 0; j <= i; j++)
                {
                    float fi = (float)i / frequency;
                    Vector3 edgeL = a.Lerp(b, fi);
                    Vector3 edgeR = a.Lerp(c, fi);
                    Vector3 p = i == 0 ? a : edgeL.Lerp(edgeR, (float)j / Math.Max(1, i));
                    grid[i][j] = Key(p.Normalized());
                }
            }
            for (int i = 0; i < frequency; i++)
                for (int j = 0; j <= i; j++)
                {
                    tris.Add(new[] { grid[i][j], grid[i + 1][j], grid[i + 1][j + 1] });
                    if (j < i)
                        tris.Add(new[] { grid[i][j], grid[i + 1][j + 1], grid[i][j + 1] });
                }
        }

        // --- Dual: vertex -> ring of adjacent triangle centroids ---
        var vertTris = new List<List<int>>(allVerts.Count);
        for (int i = 0; i < allVerts.Count; i++) vertTris.Add(new List<int>());
        var centroids = new Vector3[tris.Count];
        for (int ti = 0; ti < tris.Count; ti++)
        {
            var tr = tris[ti];
            centroids[ti] = ((allVerts[tr[0]] + allVerts[tr[1]] + allVerts[tr[2]]) / 3f).Normalized();
            foreach (int v in tr) vertTris[v].Add(ti);
        }

        var tiles = new List<Tile>(allVerts.Count);
        for (int vi = 0; vi < allVerts.Count; vi++)
        {
            var center = allVerts[vi];
            // Sort surrounding centroids by angle around the vertex normal.
            var axisX = center.Cross(Math.Abs(center.Y) < 0.99f ? Vector3.Up : Vector3.Right).Normalized();
            var axisY = center.Cross(axisX);
            var ring = vertTris[vi]
                .Select(ti => centroids[ti])
                .OrderBy(p => Mathf.Atan2(p.Dot(axisY), p.Dot(axisX)))
                .ToArray();
            if (ring.Length < 5) continue; // degenerate (should not happen)
            tiles.Add(new Tile { Center = center, Polygon = ring });
        }
        return tiles;
    }

    /// <summary>Build one mesh for a whole tiled planet: each tile is a fan
    /// (slightly extruded), vertex-colored. Returns the MeshInstance3D and
    /// exposes tile centers for picking.</summary>
    public static MeshInstance3D BuildMesh(List<Tile> tiles, Func<Tile, Color> colorOf, float radius, float relief = 0.015f)
    {
        var st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Triangles);
        foreach (var tile in tiles)
        {
            var col = colorOf(tile);
            st.SetColor(col);
            var c = tile.Center * radius * (1f + relief);
            int n = tile.Polygon.Length;
            for (int i = 0; i < n; i++)
            {
                var p0 = tile.Polygon[i] * radius * (1f + relief);
                var p1 = tile.Polygon[(i + 1) % n] * radius * (1f + relief);
                st.SetNormal(tile.Center);
                st.AddVertex(c);
                st.SetNormal(tile.Center);
                st.AddVertex(p1);
                st.SetNormal(tile.Center);
                st.AddVertex(p0);
                // skirt down to the ocean radius for a beveled tile edge
                st.SetNormal((p0 - c).Normalized());
                st.AddVertex(p0);
                st.SetNormal((p1 - c).Normalized());
                st.AddVertex(p1);
                st.SetNormal((p1 - c).Normalized());
                st.AddVertex(p1 * (1f / (1f + relief)));
            }
        }
        var mesh = st.Commit();
        return new MeshInstance3D
        {
            Mesh = mesh,
            MaterialOverride = new StandardMaterial3D
            {
                VertexColorUseAsAlbedo = true,
                Roughness = 0.85f
            }
        };
    }
}
