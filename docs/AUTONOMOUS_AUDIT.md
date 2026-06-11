# Autonomous Dev Audit — 2026-06-11

Data sources: DEV_LOG.md (2 524 logged iteration outcomes), scripts/logs/
(failed_searches.log: 168 dumps, failed_builds.log, bad_identifiers.txt),
git history, headless simulation runs. No intuition — every claim below has
a number behind it.

## 1. The 5 riskiest files

| File | Risk | Evidence |
|---|---|---|
| src/RimWorldGodot/Main.cs | Highest churn (1 574 loop events), ~1 400 lines, mixes rendering/input/raiders/UI; duplicated-block damage happened here (6x Crate, 5x head, 4x Bed) | DEV_LOG counts |
| src/RimWorldLab.Core/GameWorld.cs | 929+218 events across two paths; god-object (map, economy, pawns, weather, goals, mines); model planted a stub `TryClaimBest` here | grep, iter log |
| src/RimWorldLab.Core/Jobs.cs | Model fixated on its enums for hours pre-excerpt-collapse; real TryClaimBest belongs here and is still pending | DEV_LOG, U-series history |
| scripts/dev_loop.ps1 | Single point of failure for the whole factory; duplicated-instance bug occurred 3x today | watchdog logs |
| src/RimWorldLab.Core/Needs.cs | Received misrouted Mood patches (routing keyword bug); contains a misplaced `Mood` on PawnNeedState | iter 136-140 |

## 2. The 5 places the AI loop already went wrong (observed, not theoretical)

1. **Stub that satisfies the judge**: `TryClaimBest` placeholder returning
   null, marked done because build+tests pass (iter ~P.2 era).
2. **Roadmap checked without code**: P.3 marked `[x]` while `Pawn.Mood`
   never existed in the file (done-detection trusted KEPT history).
3. **Misrouted patches**: 71 events targeted non-existent
   `src/RimWorldLab.Core/Main.cs`; Mood items routed to Needs.cs by keyword.
4. **Duplicated insertions**: keptStreak re-applied near-identical blocks
   (6x Crate icon, 5x pawn head, 4x Bed pillow) before dedup guards existed.
5. **False BUILD OK**: regex `"0 Erreur"` substring-matched "2**0** Erreur(s)",
   letting 20 compile errors through (fixed with word boundary).

## 3. The 5 most frequent error types (full history)

| Type | Count | Share of failures |
|---|---|---|
| SEARCH mismatch (patch didn't match file) | 477 | ~37% |
| Build fail after patch (hallucinated APIs) | 629 | ~48% |
| No-op patches | 49 | ~4% |
| Blocked items (4 strikes) | 115 | — |
| Stub/placeholder accepted | ≥2 known (TryClaimBest, ConsumeResourcesForUpkeep) | undetected before today |

Counter-measures already active: predictive identifier gate (39 rejections
at zero build cost), failure feedback, lessons, self-rewrite, done-detection.

## 4. Next priority change (data-driven)

**Anti-false-success verification at done-marking time.** Reason: error
types 1-2 are already gated and shrinking; the only *undetected* failure
class left is "roadmap says done, code disagrees" (2 confirmed cases). Every
other failure self-heals; this one silently corrupts the roadmap, the
training dataset and the player-facing progress bar. Implemented today as
`Test-ItemEvidence` (see Task B): an item can only be checked off if the
code lines it quotes actually exist in the target file.
