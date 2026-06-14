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
    [int]$DecisionMs = 1000
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

    # 5) En vie, en jeu: SURVIE. Mouvement DETERMINISTE (reflexe fiable, instantane):
    #    on fonce vers la nourriture percue, on engloutit quand elle est proche,
    #    on explore sinon. (Un LLM 9B en temps reel est trop lent/bavard pour le
    #    pilotage twitch; il reviendra comme couche STRATEGIE, pas reflexe.)
    $mx = 0.0; $mz = 0.0; $engulf = $false; $why = "explore"
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
        # Pas de nourriture percue: exploration douce (direction qui tourne lentement).
        $ang = ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() % 16) / 16.0 * 6.283
        $mx = [math]::Round([math]::Cos($ang), 3); $mz = [math]::Round([math]::Sin($ang), 3)
    }

    Write-Action @{ moveX = $mx; moveZ = $mz; engulf = $engulf }
    Log "move=($mx,$mz) engulf=$engulf $why"
    Write-Host "survie: move=($mx,$mz) engulf=$engulf | $why" -ForegroundColor Green
    Start-Sleep -Milliseconds 400
}
