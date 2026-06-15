<#
DOWN HERE - L'AGENT QUI JOUE (cycle de vie COMPLET du stade microbe).

Machine a etats, comme un humain qui joue de bout en bout:
  - pas de partie active (menu / mort / chargement) -> command "newgame"
  - game over / cellule morte                       -> command "newgame"
  - dans l'editeur                                  -> command "evolve" (confirme)
  - pret a se reproduire                            -> command "evolve" (entre editeur)
  - en vie, en jeu                                  -> survie: deplacement + engloutir
    (decision LLM, avec le vecteur vers la nourriture pre-calcule)

Etat lu depuis user://agent_state.json (ecrit par le jeu a 4 Hz). Action ecrite
dans user://agent_action.json (lue par le menu / le stade / l'editeur). Une
action de +2-4s est ignoree cote jeu (l'humain reprend la main a tout moment).
#>
param(
    [string]$LlmUrl = "",
    [int]$DecisionMs = 1000,
    [ValidateSet("wm", "reflex")][string]$Brain = "wm"   # wm = pilote par le WORLD MODEL (MPC), repli reflexe tant qu'il manque de donnees
)

# Source de verite unique (paths/url) - voir scripts/lib/Config.ps1.
. "$PSScriptRoot\lib\Config.ps1"
$cfg = Get-DownHereConfig
if (-not $LlmUrl) { $LlmUrl = $cfg.Llm.BaseUrl + $cfg.Llm.ChatPath }
$dir = "$env:APPDATA\DownHereOrigins"
$stateFile = Join-Path $dir "agent_state.json"
$actionFile = Join-Path $dir "agent_action.json"
$logFile = Join-Path $cfg.Paths.Logs 'play_agent.log'
New-Item -ItemType Directory -Force -Path (Split-Path $logFile) | Out-Null

# --- WORLD MODEL (pilotage par modele appris sur le VRAI jeu) ---
# On LOGue chaque transition reelle (etat, action) -> etat suivant, et le cerveau
# (scripts/wm/play_brain.py) apprend la dynamique du jeu puis PLANIFIE (MPC). Tant
# qu'il manque de donnees, decide() retombe sur le reflexe -> ca marche tout de suite.
$transFile = Join-Path $cfg.Paths.Logs 'real_transitions.jsonl'
$brainPy = Join-Path $cfg.Paths.Scripts 'wm\play_brain.py'
$FOODSCALE = 50.0          # echelle de normalisation de la distance a la nourriture/toxine
$prevState = $null; $prevAction = $null; $lastTrain = Get-Date; $lastReport = Get-Date

# Etat normalise (7D, FIXE) depuis l'etat brut du jeu :
#   [energie, foodDx_unit, foodDz_unit, foodDistNorm, toxinDx_unit, toxinDz_unit, toxinDistNorm]
# La toxine (sulfure d'hydrogene) est le sens qui MANQUAIT -> sans lui l'agent fonce
# dans le poison et meurt. Defaut "pas de toxine percue" = [0,0,1] (loin).
function Get-WmState($s) {
    $e = 0.5
    try { if ($s.PSObject.Properties.Name -contains 'health' -and [double]$s.maxHealth -gt 0) { $e = [double]$s.health / [double]$s.maxHealth } } catch {}
    $fx = 0.0; $fz = 0.0; $fd = 1.0
    try {
        if ($s.PSObject.Properties.Name -contains 'foodDx') {
            $rx = [double]$s.foodDx; $rz = [double]$s.foodDz; $len = [math]::Sqrt($rx * $rx + $rz * $rz)
            if ($len -gt 1e-6) { $fx = $rx / $len; $fz = $rz / $len }
            $fd = [math]::Min(1.0, [double]$s.foodDist / $FOODSCALE)
        }
    } catch {}
    $tx = 0.0; $tz = 0.0; $td = 1.0
    try {
        if ($s.PSObject.Properties.Name -contains 'toxinDx') {
            $rx = [double]$s.toxinDx; $rz = [double]$s.toxinDz; $len = [math]::Sqrt($rx * $rx + $rz * $rz)
            if ($len -gt 1e-6) { $tx = $rx / $len; $tz = $rz / $len }
            $td = [math]::Min(1.0, [double]$s.toxinDist / $FOODSCALE)
        }
    } catch {}
    return @([math]::Round($e, 4), [math]::Round($fx, 4), [math]::Round($fz, 4), [math]::Round($fd, 4),
        [math]::Round($tx, 4), [math]::Round($tz, 4), [math]::Round($td, 4))
}
# (moveX,moveZ) -> indice d'action discret le plus proche (pour journaliser la transition).
function Get-ActionIndex($mx, $mz) {
    if ([math]::Abs($mx) -lt 0.2 -and [math]::Abs($mz) -lt 0.2) { return 0 }
    if ([math]::Abs($mx) -ge [math]::Abs($mz)) { return $(if ($mx -ge 0) { 1 } else { 2 }) }
    return $(if ($mz -ge 0) { 3 } else { 4 })
}

$sys = @'
You ARE a single-celled microbe and you control the cell. SURVIVE and GROW.
You are given your state and "toFood" = a unit direction to the nearest food.
- low glucose/energy -> EAT: set (moveX,moveZ) = toFood.
- foodDist small (<5) -> also engulf=true.
- health low + danger -> FLEE: set (moveX,moveZ) = OPPOSITE of toFood.
- else explore.
Just COPY toFood (or negate it). Reply ONLY compact JSON:
{"moveX":<-1..1>,"moveZ":<-1..1>,"engulf":<true|false>,"why":"<max 5 words>"}
'@

function Write-Action([hashtable]$a) {
    $a["t"] = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Set-Content -Path $actionFile -Value (($a | ConvertTo-Json -Compress)) -Encoding utf8 -NoNewline
}
function Log([string]$m) { Add-Content -Path $logFile -Value "[$(Get-Date -Format HH:mm:ss)] $m" }

function Get-Move([string]$state, [string]$hint) {
    $body = @{
        model = "x"; max_tokens = 70; temperature = 0.3
        messages = @(
            @{ role = "system"; content = $sys },
            @{ role = "user"; content = "State:`n$state`n$hint`nAct (JSON only):" }
        )
    } | ConvertTo-Json -Depth 6
    try {
        $r = Invoke-RestMethod -Uri $LlmUrl -Method Post -ContentType "application/json" -Body $body -TimeoutSec 25
        return $r.choices[0].message.content
    } catch { return $null }
}

Write-Host "=== DOWN HERE - agent joueur (cycle complet) ===" -ForegroundColor Cyan
$staleSince = $null
$gameOverSince = $null

while ($true) {
    # 1) Y a-t-il une partie active ? (etat frais < 5s)
    $sObj = $null
    if (Test-Path $stateFile) {
        $age = ((Get-Date) - (Get-Item $stateFile).LastWriteTime).TotalSeconds
        if ($age -le 5) { try { $sObj = Get-Content $stateFile -Raw | ConvertFrom-Json } catch {} }
    }

    if (-not $sObj) {
        # Pas de partie active: menu / mort / chargement. On demande une partie
        # (avec un petit anti-rebond pour ne pas spammer pendant une transition).
        if ($null -eq $staleSince) { $staleSince = Get-Date }
        if (((Get-Date) - $staleSince).TotalSeconds -ge 3) {
            Write-Action @{ command = "newgame" }
            Log "NEWGAME (pas de partie active)"
            Write-Host "demande une nouvelle partie..." -ForegroundColor Magenta
        }
        Start-Sleep -Milliseconds 1500
        continue
    }
    $staleSince = $null

    # 2) EXTINCTION reelle (gameOver) -> nouvelle partie, mais seulement si ca
    #    persiste (anti-rebond, pour ne pas rebooter pendant une transition).
    if ($sObj.gameOver -eq $true) {
        if ($null -eq $gameOverSince) { $gameOverSince = Get-Date }
        if (((Get-Date) - $gameOverSince).TotalSeconds -ge 3) {
            Write-Action @{ command = "newgame" }
            Log "NEWGAME (extinction)"
            Write-Host "extinction -> nouvelle partie" -ForegroundColor Red
        }
        Start-Sleep -Milliseconds 1500
        continue
    }
    $gameOverSince = $null

    # 2b) Cellule morte mais PAS extinction: Thrive fait un respawn automatique.
    #     On NE reboot PAS le jeu - on attend juste de revivre.
    if ($sObj.dead -eq $true) {
        Log "mort - attente du respawn automatique"
        Start-Sleep -Milliseconds 800
        continue
    }

    # 3) Dans l'editeur -> confirmer (evoluer)
    if ($sObj.inEditor -eq $true) {
        Write-Action @{ command = "evolve" }
        Log "EVOLVE (confirme l'editeur)"
        Write-Host "dans l'editeur -> confirme l'evolution" -ForegroundColor Yellow
        Start-Sleep -Milliseconds 1500
        continue
    }

    # 4) Pret a se reproduire -> entrer dans l'editeur
    if ($sObj.ready -eq $true) {
        Write-Action @{ command = "evolve" }
        Log "EVOLVE (pret a se reproduire -> editeur)"
        Write-Host "pret a evoluer -> entre dans l'editeur" -ForegroundColor Yellow
        Start-Sleep -Milliseconds 1500
        continue
    }

    # 5) En vie, en jeu: SURVIE.
    #    Brain=wm  -> le WORLD MODEL appris sur le VRAI jeu PLANIFIE le mouvement
    #                 (MPC, scripts/wm/play_brain.py). Repli reflexe tant qu'il manque
    #                 de donnees -> ca marche tout de suite et s'ameliore en jouant.
    #    Brain=reflex -> ancien reflexe deterministe (fonce vers la nourriture).
    $wmState = Get-WmState $sObj

    # JOURNALISE la transition reelle (etat precedent + action precedente -> etat actuel).
    # C'est ce que le world model APPREND : la vraie dynamique du jeu, pas une maquette.
    if ($null -ne $prevState -and $null -ne $prevAction) {
        try { (@{ s = $prevState; a = $prevAction; ns = $wmState } | ConvertTo-Json -Compress) | Add-Content -Path $transFile -Encoding utf8 } catch {}
    }

    $mx = 0.0; $mz = 0.0; $engulf = $false; $why = "explore"; $src = "reflex"
    $decided = $false
    if ($Brain -eq "wm" -and (Test-Path $brainPy)) {
        try {
            $resp = ($wmState | ConvertTo-Json -Compress) | & python $brainPy 2>$null | Out-String
            $m = $resp.Trim() | ConvertFrom-Json
            if ($null -ne $m -and $m.PSObject.Properties.Name -contains 'moveX') {
                $mx = [math]::Round([double]$m.moveX, 3); $mz = [math]::Round([double]$m.moveZ, 3)
                $engulf = [bool]$m.engulf; $src = "$($m.src)"; $why = "wm"; $decided = $true
            }
        } catch {}
    }
    if (-not $decided) {
        # Repli REFLEXE: fonce vers la nourriture percue, engloutit quand proche, explore sinon.
        $hasFood = $false
        try {
            if ($sObj.PSObject.Properties.Name -contains 'foodDx') {
                $fx = [double]$sObj.foodDx; $fz = [double]$sObj.foodDz
                $len = [math]::Sqrt($fx * $fx + $fz * $fz)
                if ($len -gt 0.0001) {
                    $hasFood = $true
                    $mx = [math]::Round($fx / $len, 3); $mz = [math]::Round($fz / $len, 3)
                    $fd = [double]$sObj.foodDist
                    if ($fd -lt 8) { $engulf = $true; $why = "engulf (dist=$([math]::Round($fd,1)))" }
                    else { $why = "seek food (dist=$([math]::Round($fd,1)))" }
                }
            }
        } catch {}
        if (-not $hasFood) {
            $ang = ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() % 16) / 16.0 * 6.283
            $mx = [math]::Round([math]::Cos($ang), 3); $mz = [math]::Round([math]::Sin($ang), 3)
        }
    }

    Write-Action @{ moveX = $mx; moveZ = $mz; engulf = $engulf }
    $prevState = $wmState; $prevAction = (Get-ActionIndex $mx $mz)
    Log "[$src] move=($mx,$mz) engulf=$engulf $why"
    Write-Host "survie [$src]: move=($mx,$mz) engulf=$engulf | $why" -ForegroundColor Green

    # RE-ENTRAINE le world model du jeu periodiquement, en arriere-plan (non bloquant).
    if ($Brain -eq "wm" -and ((Get-Date) - $lastTrain).TotalSeconds -ge 45) {
        $lastTrain = Get-Date
        try { Start-Process python -ArgumentList $brainPy, '--train' -WindowStyle Hidden } catch {}
    }
    # FERME LA BOUCLE jeu -> dev : toutes les 5 min, agrege friction + bugs reels du
    # log et les remonte au dev (feedback.jsonl). Voir scripts/play_report.ps1.
    if (((Get-Date) - $lastReport).TotalSeconds -ge 300) {
        $lastReport = Get-Date
        try { Start-Process pwsh -ArgumentList '-NoProfile', '-File', (Join-Path $cfg.Paths.Scripts 'play_report.ps1'), '-Emit' -WindowStyle Hidden } catch {}
    }
    Start-Sleep -Milliseconds 600
}
