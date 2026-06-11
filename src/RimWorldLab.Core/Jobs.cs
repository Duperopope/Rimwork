using System;
using System.Collections.Generic;
using System.Linq;

// =====================================================================
// Task System: TaskKind, TaskOrder, TaskBoard, and per-pawn execution
// =====================================================================

    public enum TaskKind
    {
        MoveTo,
        Wait,
        Build,
        BuildWall,
        Harvest,
        HaulWater,
        BuildBridge,
        GatherWater
    }

    /// <summary>
    /// Represents the grid shape for the map (Square, Hex, or RegionMap).
    /// </summary>
    public enum GridShape
    {
        Square,
        Hex,
        RegionMap,
        CoarseHex
    }

    /// <summary>
    /// Represents the weather state for the game.
    /// </summary>
    public enum WeatherState
    {
        Clear,
        Rain,
        Snow,
        Storm,
        Fog
    }

    /// <summary>
    /// Represents different types of moods for pawns.
    /// </summary>
    public enum MoodType
    {
        Neutral,
        Happy,
        Sad,
        Angry,
        Fearful,
        Lonely
    }

    /// <summary>
    /// Indicates that the map uses a coarse hexagonal grid for region-based mapping.
    /// </summary>
    public enum RegionMapGrid
    {
        CoarseHex,
        Water
    }

internal static class TaskKindExtensions
{
    /// <summary>True for tasks that move the pawn along a precomputed path to (or adjacent to) their target tile.</summary>
    public static bool IsMovementTask(this TaskKind kind) =>
        kind == TaskKind.MoveTo || kind == TaskKind.Build || kind == TaskKind.BuildWall || kind == TaskKind.Harvest || kind == TaskKind.HaulWater || kind == TaskKind.BuildBridge;
}

/// <summary>
/// A unit of work that can be assigned to a pawn.
/// </summary>
public class TaskOrder
{
    public Guid Id { get; }
    public TaskKind Kind { get; }
    public int TargetX { get; }
    public int TargetY { get; }
    public int Priority { get; }
    public int DurationTicks { get; }
    public FurnitureKind? BuildKind { get; }
    
    /// <summary>
    /// The grid shape for the map (Square or Hex).
    /// </summary>
    public GridShape GridShape { get; set; }

    public TaskOrder(TaskKind kind, int targetX, int targetY, int priority = 0, int durationTicks = 0, FurnitureKind? buildKind = null)
    {
        Id = Guid.NewGuid();
        Kind = kind;
        TargetX = targetX;
        TargetY = targetY;
        Priority = priority;
        DurationTicks = durationTicks;
        BuildKind = buildKind;
    }

    public override string ToString() => $"Task[{Kind}] -> ({TargetX},{TargetY}) prio={Priority}";
}

/// <summary>
/// Tracks a pawn's currently assigned task and execution progress.
/// </summary>
public class TaskExecution
{
    public TaskOrder Order { get; }
    public List<(int X, int Y)> Path { get; set; } = new();
    public int PathIndex { get; set; } = 0;
    public int TicksRemaining { get; set; }
    public bool Failed { get; set; } = false;

    public TaskExecution(TaskOrder order, int ticksRemaining)
    {
        Order = order;
        TicksRemaining = ticksRemaining;
    }

    public bool IsComplete => Failed || (Path.Count == 0 && TicksRemaining <= 0 && !Order.Kind.IsMovementTask()) ||
                               (Order.Kind.IsMovementTask() && PathIndex >= Path.Count);

    public static int CalculateDistance(int x1, int y1, int x2, int y2)
    {
        return Math.Abs(x1 - x2) + Math.Abs(y1 - y2);
    }
}

/// <summary>
/// Central queue of pending tasks, ordered by priority.
/// </summary>
public class TaskBoard
{
    private readonly List<TaskOrder> _pending = new();
    private readonly HashSet<(int X, int Y)> _reservedTiles = new();

    public IReadOnlyList<TaskOrder> Pending => _pending;

    public void Enqueue(TaskOrder task)
    {
        _pending.Add(task);
    }

    /// <summary>
    /// Returns true if the given tile is currently reserved by another pawn's task.
    /// </summary>
    public bool IsTileReserved(int x, int y)
    {
        return _reservedTiles.Contains((x, y));
    }

    public bool IsTileReservedByBuildTask(int x, int y)
    {
        return _reservedTiles.Any(t => t == (x, y) && IsBuildTaskReservingTile(x, y));
    }

    private bool IsBuildTaskReservingTile(int x, int y)
    {
        // Check if the tile is reserved by a build task
        // This is a placeholder implementation - actual logic would depend on task data
        return _reservedTiles.Any(t => t == (x, y) && IsBuildTaskReservingTile(x, y));
    }

    public void ReserveTile(int x, int y)
    {
        _reservedTiles.Add((x, y));
    }

    public void ReleaseTile(int x, int y)
    {
        _reservedTiles.Remove((x, y));
    }

    /// <summary>
    /// Picks the highest-priority task whose destination tile is not already reserved.
    /// Removes it from the pending queue and reserves its destination.
    /// Returns null if no eligible task is available.
    /// </summary>
    public TaskOrder TryClaimNext()
    {
        var candidates = _pending
            .OrderByDescending(t => t.Priority)
            .ToList();

        foreach (var task in candidates)
        {
            if (task.Kind.IsMovementTask() && IsTileReserved(task.TargetX, task.TargetY))
                continue;

            _pending.Remove(task);

            if (task.Kind.IsMovementTask())
                ReserveTile(task.TargetX, task.TargetY);

            return task;
        }

        return null;
    }

    /// <summary>
    /// Claims the best task for THIS pawn instead of the first available
    /// one: priority dominates, then skill affinity, then proximity. This
    /// is what makes the best builder take build jobs near them rather
    /// than everyone popping a global queue.
    /// </summary>
    public TaskOrder TryClaimBest(Pawn pawn)
    {
        TaskOrder best = null;
        double bestScore = double.MinValue;
        foreach (var task in _pending)
        {
            if (task.Kind.IsMovementTask() && IsTileReserved(task.TargetX, task.TargetY))
                continue;
            double score = task.Priority * 10.0;
            score += (pawn.Mood - 50.0) / 25.0;
            score -= Math.Abs(task.TargetX - pawn.X) + Math.Abs(task.TargetY - pawn.Y);
            if ((task.Kind == TaskKind.Build || task.Kind == TaskKind.BuildWall || task.Kind == TaskKind.BuildBridge)
                && pawn.SkillXP.TryGetValue(SkillKind.Construction, out float cxp))
                score += cxp / 100.0;
            if (task.Kind == TaskKind.Harvest && pawn.SkillXP.TryGetValue(SkillKind.Woodcutting, out float wxp))
                score += wxp / 100.0;
            if (score > bestScore) { bestScore = score; best = task; }
        }
        if (best == null) return null;
        _pending.Remove(best);
        if (best.Kind.IsMovementTask())
            ReserveTile(best.TargetX, best.TargetY);
        return best;
    }
}

/// <summary>
/// Drives a single pawn through its assigned task, step by step, each tick.
/// </summary>
public class PawnTaskDriver
{
    public TaskExecution Current { get; private set; }

    /// <summary>
    /// Assigns a new task to this driver, computing a path if needed.
    /// </summary>
    public void Assign(TaskOrder task, Pawn pawn, GameMap map)
    {
        var execution = new TaskExecution(task, task.DurationTicks);

        if (task.Kind == TaskKind.BuildWall || task.Kind == TaskKind.BuildBridge)
        {
            // Walls/bridges occupy or sit on an impassable tile, so the pawn
            // must end up on an adjacent passable tile rather than on the target itself.
            bool found = false;
            foreach (var (nx, ny) in new[] { (task.TargetX + 1, task.TargetY), (task.TargetX - 1, task.TargetY), (task.TargetX, task.TargetY + 1), (task.TargetX, task.TargetY - 1) })
            {
                if (!map.IsPassable(nx, ny)) continue;

                if (pawn.X == nx && pawn.Y == ny)
                {
                    execution.Path = new List<(int, int)>();
                    found = true;
                    break;
                }

                var p = Pathfinder.FindPath(map, pawn.X, pawn.Y, nx, ny);
                if (p.Count > 0)
                {
                    execution.Path = p;
                    found = true;
                    break;
                }
            }

            if (!found)
                execution.Failed = true;
        }
        else if (task.Kind.IsMovementTask())
        {
            execution.Path = Pathfinder.FindPath(map, pawn.X, pawn.Y, task.TargetX, task.TargetY);
            if (execution.Path.Count == 0 && (pawn.X != task.TargetX || pawn.Y != task.TargetY))
            {
                execution.Failed = true;
            }
        }

        Current = execution;
    }

    /// <summary>
    /// Advances the current task by one tick. Returns true if the task finished this tick
    /// (either completed or failed).
    /// </summary>
    public bool Step(Pawn pawn, GameMap map, TaskBoard board)
    {
        if (Current == null)
            return false;

        if (Current.Failed)
        {
            ReleaseReservation(board);
            return true;
        }

        switch (Current.Order.Kind)
        {
            case TaskKind.MoveTo:
            case TaskKind.Build:
            case TaskKind.BuildWall:
            case TaskKind.Harvest:
            case TaskKind.HaulWater:
            case TaskKind.BuildBridge:
                if (Current.PathIndex < Current.Path.Count)
                {
                    var (nx, ny) = Current.Path[Current.PathIndex];
                    int dx = nx - pawn.X;
                    int dy = ny - pawn.Y;

                    if (pawn.TryMove(dx, dy, map))
                    {
                        Current.PathIndex++;
                    }
                    else
                    {
                        // Blocked mid-path (e.g. another pawn occupies the tile) - abandon task.
                        Current.Failed = true;
                        ReleaseReservation(board);
                        return true;
                    }
                }
                break;

            case TaskKind.Wait:
                if (Current.TicksRemaining > 0)
                    Current.TicksRemaining--;
                break;
        }

        if (Current.IsComplete)
        {
            ReleaseReservation(board);
            return true;
        }

        return false;
    }

    private void ReleaseReservation(TaskBoard board)
    {
        if (Current.Order.Kind.IsMovementTask())
            board.ReleaseTile(Current.Order.TargetX, Current.Order.TargetY);

        Current = null;
    }

    public bool IsIdle => Current == null;
}
