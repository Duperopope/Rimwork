<#
DOWN HERE - Snapshot d'etat (Phase 7, substrat world-model).

Ajoute UN instantane de l'etat consolide dans logs/state_history.jsonl.
L'orchestrateur en logue un ~chaque minute ; ce CLI permet d'en forcer un.
Series temporelles -> futur modele predictif de l'etat (cap JEPA, pas le present).

  pwsh -File scripts/snapshot-state.ps1
#>
. "$PSScriptRoot\lib\State.ps1"
$f = Add-StateSnapshot
Write-Host "Snapshot ajoute -> $f"
