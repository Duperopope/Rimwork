using System;
using System.Collections.Generic;

// =====================================================================
// A* Pathfinding over GameMap
// =====================================================================

public static class Pathfinder
{
    private class Node
    {
        public int X, Y;
        public int G;
        public int H;
        public int F => G + H;
        public Node Parent;

        public Node(int x, int y, int g, int h, Node parent)
        {
            X = x; Y = y; G = g; H = h; Parent = parent;
        }
    }

    private static int Heuristic(int x1, int y1, int x2, int y2)
    {
        return Math.Abs(x1 - x2) + Math.Abs(y1 - y2);
    }

    /// <summary>
    /// Finds a path from (startX, startY) to (goalX, goalY) using A* with 4-directional movement.
    /// Returns an empty list if no path exists or start == goal.
    /// </summary>
    public static List<(int X, int Y)> FindPath(GameMap map, int startX, int startY, int goalX, int goalY)
    {
        var result = new List<(int X, int Y)>();

        if (startX == goalX && startY == goalY)
            return result;

        if (!map.IsPassable(goalX, goalY))
            return result;

        var open = new List<Node>();
        var closed = new HashSet<(int, int)>();
        var openLookup = new Dictionary<(int, int), Node>();

        var startNode = new Node(startX, startY, 0, Heuristic(startX, startY, goalX, goalY), null);
        open.Add(startNode);
        openLookup[(startX, startY)] = startNode;

        (int dx, int dy)[] directions = { (0, -1), (0, 1), (-1, 0), (1, 0) };

        while (open.Count > 0)
        {
            // Pick node with lowest F (and lowest H as tiebreaker)
            int bestIndex = 0;
            for (int i = 1; i < open.Count; i++)
            {
                if (open[i].F < open[bestIndex].F ||
                    (open[i].F == open[bestIndex].F && open[i].H < open[bestIndex].H))
                {
                    bestIndex = i;
                }
            }

            var current = open[bestIndex];
            open.RemoveAt(bestIndex);
            openLookup.Remove((current.X, current.Y));
            closed.Add((current.X, current.Y));

            if (current.X == goalX && current.Y == goalY)
            {
                // Reconstruct path (excluding start cell)
                var node = current;
                while (node.Parent != null)
                {
                    result.Insert(0, (node.X, node.Y));
                    node = node.Parent;
                }
                return result;
            }

            foreach (var (dx, dy) in directions)
            {
                int nx = current.X + dx;
                int ny = current.Y + dy;

                if (!map.IsPassable(nx, ny))
                    continue;

                if (closed.Contains((nx, ny)))
                    continue;

                int g = current.G + 1;

                if (openLookup.TryGetValue((nx, ny), out var existing))
                {
                    if (g < existing.G)
                    {
                        existing.G = g;
                        existing.Parent = current;
                    }
                }
                else
                {
                    var neighbor = new Node(nx, ny, g, Heuristic(nx, ny, goalX, goalY), current);
                    open.Add(neighbor);
                    openLookup[(nx, ny)] = neighbor;
                }
            }
        }

        // No path found
        return result;
    }
}
