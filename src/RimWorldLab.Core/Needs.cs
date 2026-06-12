using System;
using System.Collections.Generic;

// =====================================================================
// Needs system: drives Hunger/Fatigue and turns urgent needs into tasks.
// =====================================================================

public enum NeedKind
{
    Hunger,
    Fatigue
}

/// <summary>
/// Per-tick increments and thresholds for need decay/urgency.
/// </summary>
public static class NeedRates
{
    public const float HungerPerTick = 0.05f;
    public const float FatiguePerTick = 0.03f;

    public const float UrgentThreshold = 70f;
    public const float SatisfiedThreshold = 10f;

    public const float RestRecoveryPerTick = 2f;
    public const float EatRecoveryPerTick = 5f;

    /// <summary>HP lost per tick once a need is fully maxed out (starvation / collapse from exhaustion).</summary>
    public const float StarvationDamagePerTick = 0.05f;
}

/// <summary>
/// Tracks which need (if any) is currently driving a pawn's behavior,
/// so the rest of the simulation (and future dialogue) can react to it.
/// </summary>
public class PawnNeedState
{
    public NeedKind? ActiveNeed { get; set; } = null;

    // Add Mood property
    public float Mood { get; set; } = 70f;
}

/// <summary>
/// Advances Hunger/Fatigue for all pawns and queues TaskOrders for the
/// most urgent unmet need. Resting/eating tasks recover the relevant need
/// while the pawn waits at its target tile.
/// </summary>
public class NeedsSystem
{
    private readonly Dictionary<Guid, PawnNeedState> _states = new();

    public PawnNeedState GetState(Pawn pawn)
    {
        if (!_states.TryGetValue(pawn.Id, out var state))
        {
            state = new PawnNeedState();
            _states[pawn.Id] = state;
        }
        return state;
    }

    /// <summary>
    /// Increments needs for every pawn and, for idle pawns with an urgent
    /// need, enqueues a recovery task on the board.
    /// </summary>
public void Tick(GameWorldManager world, PawnTaskDriver driver, Pawn pawn, Random rng)
{
    // Idle pawns burn fewer calories than working ones.
    float effort = driver.Current != null ? 1f : 0.6f;
    pawn.Hunger = Math.Min(100f, pawn.Hunger + NeedRates.HungerPerTick * effort);
    pawn.Fatigue = Math.Min(100f, pawn.Fatigue + NeedRates.FatiguePerTick * effort);

    // A need maxed out at 100 starts costing HP - starving or collapsing
    // from exhaustion can kill a pawn if left unmet.
    if (pawn.Hunger >= 100f || pawn.Fatigue >= 100f)
        pawn.HP = Math.Max(0f, pawn.HP - NeedRates.StarvationDamagePerTick);

    var state = GetState(pawn);

    // Recover the active need while resting/eating in place.
    if (state.ActiveNeed == NeedKind.Hunger)
        pawn.Hunger = Math.Max(0f, pawn.Hunger - NeedRates.EatRecoveryPerTick);
    else if (state.ActiveNeed == NeedKind.Fatigue)
        pawn.Fatigue = Math.Max(0f, pawn.Fatigue - NeedRates.RestRecoveryPerTick);

    // Clear the active need once satisfied.
    if (state.ActiveNeed == NeedKind.Hunger && pawn.Hunger <= NeedRates.SatisfiedThreshold)
        state.ActiveNeed = null;
    if (state.ActiveNeed == NeedKind.Fatigue && pawn.Fatigue <= NeedRates.SatisfiedThreshold)
        state.ActiveNeed = null;

    if (!driver.IsIdle || state.ActiveNeed != null)
        return;

    // Pick the most urgent need, if any.
    NeedKind? urgent = null;
    if (pawn.Hunger >= NeedRates.UrgentThreshold && pawn.Hunger >= pawn.Fatigue)
        urgent = NeedKind.Hunger;
    else if (pawn.Fatigue >= NeedRates.UrgentThreshold)
        urgent = NeedKind.Fatigue;

    if (urgent == null)
        return;

    var zoneKind = urgent == NeedKind.Hunger ? ZoneKind.Canteen : ZoneKind.SleepingQuarters;
    var target = world.Map.FindNearestZoneTile(zoneKind, pawn.X, pawn.Y);

    int tx, ty;
    if (target != null)
    {
        (tx, ty) = target.Value;
    }
    else
    {
        do
        {
            tx = rng.Next(0, world.Map.Width);
            ty = rng.Next(0, world.Map.Height);
        } while (!world.Map.IsPassable(tx, ty));
    }

    world.Tasks.Enqueue(new TaskOrder(TaskKind.MoveTo, tx, ty, priority: 10, durationTicks: 0));
    state.ActiveNeed = urgent;
}

public void ConsumeMeal(Pawn pawn)
{
    if (pawn.Hunger > 0)
    {
        pawn.Hunger -= NeedRates.EatRecoveryPerTick * 4; // Assuming 4 meals per cook cycle
        pawn.Hunger = Math.Max(0f, pawn.Hunger);
    }
}

public void HandleMealConsumption(Pawn pawn, int mealCount)
{
    if (mealCount > 0 && pawn.Hunger > 0)
    {
        float recoveryAmount = NeedRates.EatRecoveryPerTick * mealCount;
        pawn.Hunger -= recoveryAmount;
        pawn.Hunger = Math.Max(0f, pawn.Hunger);
    }
}

public void ConsumeWater(Pawn pawn, int waterAmount)
{
    if (waterAmount > 0 && pawn.Thirst > 0)
    {
        pawn.Thirst -= waterAmount;
        pawn.Thirst = Math.Max(0f, pawn.Thirst);
    }
}
}
