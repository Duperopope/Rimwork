# DOWN HERE! - AI playtester: the local LLM PLAYS the game like a human
# through the agent bridge (agent_cmd.txt / agent_state.json), pursuing the
# colony goal, and reports bugs/anomalies the dev loop can act on.
# Deterministic anomaly checks run alongside the LLM so a bad model answer
# never hides a real problem.
param(
    [int]$Steps = 10,
    [int]$StepWaitSec = 8,
    [string]$LlmUrl = "http://localhost:1234/v1/chat/completions"
)

$statePath = "g:\Rimwork\scripts\logs\agent_state.json"
$cmdPath = "g:\Rimwork\scripts\agent_cmd.txt"
$reportPath = "g:\Rimwork\scripts\logs\playtest_report.json"

function Read-State {
    try { Get-Content $statePath -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null }
}

# --- Preconditions: game running and state fresh ---
$st = Read-State
if (-not $st) { Write-Host "playtest: no agent state (game not running?)"; exit 2 }
$age = (Get-Date) - (Get-Item $statePath).LastWriteTime
if ($age.TotalSeconds -gt 20) { Write-Host "playtest: state stale ($([int]$age.TotalSeconds)s)"; exit 2 }

# Fresh deterministic world so playtests are comparable
Set-Content $cmdPath "newgame 777`nspeed 3" -Encoding ascii
Start-Sleep 6

$anomalies = New-Object System.Collections.Generic.List[string]
$notes = New-Object System.Collections.Generic.List[string]
$issued = New-Object System.Collections.Generic.List[string]
$lastTicks = -1; $idleStreak = 0

$sysPrompt = @"
Tu joues a DOWN HERE!, un jeu de colonie. Tu recois l'etat JSON du jeu.
Objectif: $($st.goal). Donne UNE seule commande par tour pour progresser, parmi:
harvest x y | wall x y | bed x y | move x y | select i | speed 1|3 | view Planet | view Local | shot test
Strategie: recolter du bois/pierre proche des pawns, puis construire des murs
pour former des pieces fermees, et des lits dedans. Coordonnees = positions
des pawns +-5. Si tu vois un bug ou une incoherence (ressources negatives,
pawns bloques, valeurs absurdes), commence ta ligne par BUG: description.
Reponds UNIQUEMENT avec la commande (ou BUG: ...), rien d'autre.
"@

for ($s = 1; $s -le $Steps; $s++) {
    $st = Read-State
    if (-not $st) { $anomalies.Add("state file unreadable at step $s"); break }

    # --- Deterministic anomaly checks (the real safety net) ---
    if (-not $st.paused -and $st.ticks -eq $lastTicks) { $anomalies.Add("SIM FROZEN: ticks stuck at $($st.ticks) (step $s)") }
    $lastTicks = $st.ticks
    foreach ($r in 'wood','stone','water','food','metal','tools') {
        if ($st.$r -lt 0) { $anomalies.Add("NEGATIVE RESOURCE: $r=$($st.$r) (step $s)") }
    }
    $idle = @($st.pawns | Where-Object task -eq 'idle').Count
    if ($idle -eq @($st.pawns).Count -and $st.pendingTasks -gt 0) { $idleStreak++ } else { $idleStreak = 0 }
    if ($idleStreak -ge 3) { $anomalies.Add("ALL PAWNS IDLE with $($st.pendingTasks) pending tasks (3 polls)"); $idleStreak = 0 }
    if (@($st.pawns).Count -eq 0) { $anomalies.Add("COLONY DEAD at step $s"); break }

    # --- Ask the local LLM for the next move ---
    $stateJson = $st | ConvertTo-Json -Compress -Depth 4
    $body = @{ model = "qwen2.5-coder-14b-instruct"; max_tokens = 60; temperature = 0.4
               messages = @(
                   @{ role = "system"; content = $sysPrompt },
                   @{ role = "user"; content = "Etat: $stateJson`nTour $s/$Steps. Ta commande:" }
               ) } | ConvertTo-Json -Depth 6
    $cmd = $null
    try {
        $resp = Invoke-RestMethod -Uri $LlmUrl -Method Post -Body $body -ContentType "application/json" -TimeoutSec 90
        $cmd = ($resp.choices[0].message.content -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 1).Trim()
    } catch { $notes.Add("LLM unreachable at step ${s}: $_") }

    if ($cmd) {
        if ($cmd -match '^BUG:') { $notes.Add($cmd); continue }
        # Whitelist validation - never let the model run arbitrary text
        if ($cmd -match '^(harvest|wall|bed|move) -?\d+ -?\d+$' -or $cmd -match '^select \d+$' -or
            $cmd -match '^speed [13]$' -or $cmd -match '^view (Local|Planet|Solar)$' -or $cmd -match '^shot \w+$') {
            Set-Content $cmdPath $cmd -Encoding ascii
            $issued.Add($cmd)
        } else { $notes.Add("rejected model output: $cmd") }
    }
    Start-Sleep $StepWaitSec
}

# --- Final verdict ---
$final = Read-State
$report = [ordered]@{
    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    steps     = $Steps
    issued    = $issued
    anomalies = $anomalies
    llmNotes  = $notes
    final     = if ($final) { @{ ticks = $final.ticks; rooms = $final.rooms; goalsDone = $final.goalsDone
                                 pawns = @($final.pawns).Count; wood = $final.wood; stone = $final.stone } } else { $null }
}
$report | ConvertTo-Json -Depth 5 | Set-Content $reportPath -Encoding utf8
Write-Host "playtest done: $($issued.Count) commands, $($anomalies.Count) anomalies, $($notes.Count) notes"
exit ($(if ($anomalies.Count -eq 0) { 0 } else { 1 }))
