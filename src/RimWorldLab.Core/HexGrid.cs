using System;
using System.Collections.Generic;

/// <summary>
/// Axial coordinates for a pointy-top hex grid (Q, R), plus conversions
/// to/from pixel space and neighbor lookup. Purely additive - not yet
/// wired into GameMap/Pathfinder/rendering (see ROADMAP Step V.2/V.3).
/// </summary>
public readonly struct HexCoord : IEquatable<HexCoord>
{
    public readonly int Q;
    public readonly int R;

    public HexCoord(int q, int r)
    {
        Q = q;
        R = r;
    }

    /// <summary>The six axial neighbor offsets for a pointy-top hex grid.</summary>
    private static readonly (int Dq, int Dr)[] Directions =
    {
        (1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)
    };

    public IEnumerable<HexCoord> Neighbors()
    {
        foreach (var (dq, dr) in Directions)
            yield return new HexCoord(Q + dq, R + dr);
    }

    /// <summary>Converts axial hex coords to pixel center, for a pointy-top hex of the given size (center-to-corner radius).</summary>
    public (float X, float Y) ToPixel(float size)
    {
        float x = size * (MathF.Sqrt(3f) * Q + MathF.Sqrt(3f) / 2f * R);
        float y = size * (3f / 2f * R);
        return (x, y);
    }

    /// <summary>Converts a pixel position back to the nearest axial hex coord, for a pointy-top hex of the given size.</summary>
    public static HexCoord FromPixel(float x, float y, float size)
    {
        float q = (MathF.Sqrt(3f) / 3f * x - 1f / 3f * y) / size;
        float r = (2f / 3f * y) / size;
        return Round(q, r);
    }

    private static HexCoord Round(float q, float r)
    {
        float x = q;
        float z = r;
        float yAxis = -x - z;

        int rx = (int)MathF.Round(x);
        int ry = (int)MathF.Round(yAxis);
        int rz = (int)MathF.Round(z);

        float xDiff = MathF.Abs(rx - x);
        float yDiff = MathF.Abs(ry - yAxis);
        float zDiff = MathF.Abs(rz - z);

        if (xDiff > yDiff && xDiff > zDiff)
            rx = -ry - rz;
        else if (yDiff > zDiff)
            ry = -rx - rz;
        else
            rz = -rx - ry;

        return new HexCoord(rx, rz);
    }

    /// <summary>Distance in hex steps between two axial coordinates.</summary>
    public int DistanceTo(HexCoord other)
    {
        int dq = Q - other.Q;
        int dr = R - other.R;
        return (Math.Abs(dq) + Math.Abs(dr) + Math.Abs(dq + dr)) / 2;
    }

    public bool Equals(HexCoord other) => Q == other.Q && R == other.R;
    public override bool Equals(object? obj) => obj is HexCoord other && Equals(other);
    public override int GetHashCode() => HashCode.Combine(Q, R);
    public override string ToString() => $"Hex({Q},{R})";
}
