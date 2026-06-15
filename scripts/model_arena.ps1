<#
DOWN HERE! - ARENE DE SELECTION NATURELLE DES LLM.

Idee (directeur): on fait un jeu sur la selection naturelle, alors on
l'applique a notre propre dev. Il y a des MILLIERS de LLM dans l'ocean
HuggingFace - peut-etre LE bon est dedans. L'arene:
  1. CRAWLE l'ocean HF (plusieurs requetes) pour decouvrir des coders recents
  2. telecharge les challengers qui TIENNENT sur 16 Go (auto-fit possible)
  3. les fait COMBATTRE sur NOTRE vraie tache (patch SEARCH/REPLACE sur des
     fichiers de donnees Thrive reels, valide instantanement par parse JSON
     + application verbatim - rapide, pas de build lent)
  4. COURONNE le champion -> scripts/llm_champion.txt (lu par startup_all)
  5. SUPPRIME les perdants pour liberer de la place et tenter d'autres
  6. en mode -Forever: recommence sans fin = selection naturelle perpetuelle

Usage:
  pwsh -File model_arena.ps1                 # un cycle
  pwsh -File model_arena.ps1 -Forever        # selection naturelle continue
  pwsh -File model_arena.ps1 -Only qwen3     # un seul candidat
#>
param(
    [string]$Only = "",
    [int]$KeepTop = 2,            # combien de modeles on garde sur le disque
    [int]$NewPerCycle = 2,        # nouveaux challengers crawles par cycle
    [switch]$Forever,             # selection naturelle continue
    [int]$CycleRestSec = 10       # micro-pause entre cycles (continu: ne s'arrete jamais)
)

$ErrorActionPreference = "Continue"
# GPU EXCLUSIF: le champion 30B occupe ~14.7 Go sur 16 -> impossible de charger
# un challenger A COTE. L'arene benche donc UN modele a la fois sur le port prod
# (1234), puis rend la main au champion. La boucle de dev tolere ces swaps brefs.
# Source de verite unique (paths/url) - voir scripts/lib/Config.ps1.
. "$PSScriptRoot\lib\Config.ps1"
. "$PSScriptRoot\lib\Llm.ps1"   # Start-LlamaServer : lancement PERSISTANT (vs nohup& qui meurt)
$cfg = Get-DownHereConfig
$llm = $cfg.Llm.BaseUrl
$arenaLog = Join-Path $cfg.Paths.Logs 'model_arena.json'
$championFile = $cfg.Llm.ChampionFile
$pinFile = Join-Path $cfg.Paths.Logs 'llm_pinned.txt'      # choix MANUEL (interface): l'arene ne le remplace pas
$triedFile = Join-Path $cfg.Paths.Logs 'arena_tried.txt'   # memoire des modeles deja juges
$arenaStatus = Join-Path $cfg.Paths.Logs 'arena_status.json' # statut LIVE pour le dashboard
$thrive = $cfg.Paths.ActiveGame
$script:cycleNo = 0

# Publie l'etat LIVE de l'arene (lu par le dashboard) : phase, modele en cours,
# classement courant, meilleur connu a l'instant T.
function Write-ArenaStatus($o) {
    try { $o['updatedAt'] = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); ($o | ConvertTo-Json -Depth 6) | Set-Content $arenaStatus -Encoding utf8 } catch {}
}

# HISTORIQUE PERSISTANT : classement de TOUS les modeles jamais juges (le systeme
# n'oublie plus a chaque redemarrage). Le cycle est persistant aussi.
$leaderFile = Join-Path $cfg.Paths.Logs 'arena_leaderboard.json'
function Get-Leaderboard {
    if (Test-Path $leaderFile) { try { return (Get-Content $leaderFile -Raw | ConvertFrom-Json) } catch {} }
    return [pscustomobject]@{ cycle = 0; models = @() }
}
function Save-Leaderboard($cycle, $models) {
    try { [pscustomobject]@{ cycle = $cycle; updatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); models = @($models) } |
        ConvertTo-Json -Depth 6 | Set-Content $leaderFile -Encoding utf8 } catch {}
}
function Get-Rank($models) {
    @($models | Sort-Object -Property total -Descending | ForEach-Object {
        @{ key = $_.key; total = $_.total; score = $_.score; speedPts = $_.speedPts; secs = $_.secs; details = $_.details; file = $_.file; lastCycle = $_.lastCycle } })
}

# ---- Candidats de depart (GGUF tenant sur RX 7800 XT 16 Go) ----
$baseCandidates = @(
    @{ key = "qwen3-coder-30b"; file = "Qwen3-Coder-30B-A3B-Instruct-Q3_K_M.gguf"; repo = "unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF" }
    @{ key = "qwen25-14b";      file = "Qwen2.5-Coder-14B-Instruct-Q4_K_S.gguf";   repo = "bartowski/Qwen2.5-Coder-14B-Instruct-GGUF" }
    @{ key = "yi-coder-9b";     file = "Yi-Coder-9B-Chat-Q4_K_M.gguf";             repo = "" }
)

# ---- CRAWLER: decouvre des coders recents dans l'ocean HF ----
# Plus de requetes = on ratisse plus large. On ne garde que les GGUF Q4_K_M /
# Q3_K_M tenant en VRAM (4-15.5 Go), tries par popularite.
function Get-CrawledCandidates([int]$Want = 4) {
    # ROBUSTE + RAPIDE + OBSERVABLE. Avant: jusqu'a 120 lookups d'arbre a 60s ->
    # le crawl ne finissait JAMAIS (bloque en phase "crawl", 0 challenger telecharge).
    # Maintenant: timeouts courts, on SAUTE les modeles deja connus AVANT le lookup,
    # on s'ARRETE des qu'on a assez de challengers frais, et on publie la decouverte.
    $found = @{}
    $tried = if (Test-Path $triedFile) { @(Get-Content $triedFile) } else { @() }
    $known = @($baseCandidates.file) + $tried
    $queries = @("coder gguf", "code instruct gguf", "qwen coder gguf",
                 "deepseek coder gguf", "codestral gguf", "granite code gguf",
                 "starcoder gguf", "code llama gguf")
    foreach ($q in $queries) {
        if ($found.Count -ge $Want) { break }
        try {
            $hits = Invoke-RestMethod "https://huggingface.co/api/models?search=$([uri]::EscapeDataString($q))&sort=downloads&direction=-1&limit=12" -TimeoutSec 20
        } catch { continue }
        foreach ($m in $hits) {
            if ($found.Count -ge $Want) { break }
            if ($m.id -match "embed|rerank|vision|VL|abliterat|base-gguf|-1\.5B|-3B") { continue }
            if ($found.ContainsKey($m.id)) { continue }
            try { $tree = Invoke-RestMethod "https://huggingface.co/api/models/$($m.id)/tree/main" -TimeoutSec 15 } catch { continue }
            $gg = $tree | Where-Object { $_.path -match "Q4_K_M\.gguf$|Q3_K_M\.gguf$" -and $_.path -notmatch "of-000|00001-of" } |
                  Where-Object { ($_.lfs.size ?? $_.size) -gt 4e9 -and ($_.lfs.size ?? $_.size) -lt 15.5e9 } |
                  Sort-Object { $_.lfs.size ?? $_.size } -Descending | Select-Object -First 1
            if (-not $gg) { continue }
            $fname = [System.IO.Path]::GetFileName($gg.path)
            if ($known -contains $fname) { continue }   # base ou deja juge -> on n'y revient pas
            $found[$m.id] = @{ key = ($m.id -replace '.*/', ''); file = $fname; repo = $m.id }
            Write-Host "  ocean: $($m.id) -> $fname ($([math]::Round((($gg.lfs.size ?? $gg.size))/1e9,1)) Go)" -ForegroundColor DarkCyan
            Write-ArenaStatus @{ phase = 'crawl'; cycle = $script:cycleNo; current = @{ key = ($m.id -replace '.*/', '') }; tested = @(); best = $null; queue = @($found.Values.key) }
        }
    }
    return @($found.Values)
}

# ---- BENCHMARK de combat: fichiers Thrive REELS + difficulte GRADUEE, scoring
# deterministe et instantane. On teste la competence cle du dev: produire un
# SEARCH/REPLACE qui (a) matche le fichier VERBATIM, (b) donne un JSON VALIDE,
# (c) fait EXACTEMENT le changement demande. Les epreuves vont du facile (ajouter
# un champ au 1er objet) au plus dur (champ string, 2 champs, cibler le 2e objet)
# -> un vrai gradient qui separe les bons des chanceux. Pas de build lent: l'arene
# juge vite; le champion est ensuite confirme en prod par la vraie boucle de dev.
$tasks = @(
    @{ file = "simulation_parameters/microbe_stage/compounds.json"; lines = 60; kind = "json"
       ask = 'Add a new field "ArenaTag": 1 to the VERY FIRST compound object. Keep the JSON valid.'; expect = 'ArenaTag' }
    @{ file = "simulation_parameters/microbe_stage/membranes.json"; lines = 60; kind = "json"
       ask = 'Add a new STRING field "ArenaNote": "ok" to the VERY FIRST membrane object. Keep the JSON valid.'; expect = 'ArenaNote' }
    @{ file = "simulation_parameters/microbe_stage/biomes.json"; lines = 80; kind = "json"
       ask = 'Add a new field "ArenaTag": 2 to the VERY FIRST top-level object. Keep the JSON valid.'; expect = 'ArenaTag' }
    @{ file = "simulation_parameters/microbe_stage/organelles.json"; lines = 80; kind = "json"
       ask = 'Add TWO new fields "ArenaA": 1 and "ArenaB": 2 to the VERY FIRST organelle object. Keep the JSON valid.'; expect = 'ArenaB' }
    @{ file = "simulation_parameters/microbe_stage/compounds.json"; lines = 120; kind = "json"
       ask = 'Add a new field "ArenaDeep": 9 to the SECOND compound object (NOT the first one). Keep the JSON valid.'; expect = 'ArenaDeep' }
)

function Wait-Llm([int]$timeoutSec = 240) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $timeoutSec) {
        try { if ((Invoke-RestMethod "$llm/health" -TimeoutSec 5).status -eq "ok") { return $true } } catch {}
        Start-Sleep 5
    }
    return $false
}

function Start-Model([string]$file, [int]$port = 1234) {
    # Lancement PERSISTANT (Start-Process wsl + /root/start-llm.sh, voir lib/Llm.ps1).
    # L'ancien `nohup ... &` via `wsl bash -c` NE survivait PAS a la fin de la
    # session wsl: le serveur mourait aussitot -> Wait-Llm timeout -> 0 resultat
    # pour TOUS les modeles (cause du "arene sans gagnant + LLM down" en ARENA).
    # L'arene benche sur le port prod (1234), comme Start-LlamaServer.
    Start-LlamaServer -Model $file
    return (Wait-Llm)
}

function Get-HfFile([string]$repo, [string]$file) {
    try { $tree = Invoke-RestMethod "https://huggingface.co/api/models/$repo/tree/main" -TimeoutSec 60 } catch { return $null }
    $entry = $tree | Where-Object { $_.path -ieq $file } | Select-Object -First 1
    if (-not $entry) {
        $pat = ($file -replace '.*(Q\d_K_[MS]).*', '$1')
        $entry = $tree | Where-Object { $_.path -match "$pat.*\.gguf$" -and $_.path -notmatch "0000\d-of" } | Select-Object -First 1
    }
    if (-not $entry) { return $null }
    $name = [System.IO.Path]::GetFileName($entry.path)
    $want = [long]($entry.lfs.size ?? $entry.size)
    Write-Host "  telechargement $repo / $($entry.path) ($([math]::Round($want/1GB,1)) Go)..."
    wsl -d Ubuntu -u root -- bash -c "cd /root/models && wget -q -c --tries=3 'https://huggingface.co/$repo/resolve/main/$($entry.path)' -O '$name'" | Out-Null
    $size = [long](wsl -d Ubuntu -u root -- bash -c "stat -c%s /root/models/$name 2>/dev/null || echo 0")
    if ($size -eq $want -and $want -gt 3e9) { return $name }
    wsl -d Ubuntu -u root -- bash -c "rm -f /root/models/$name" | Out-Null
    return $null
}

function Invoke-Bench([string]$key, [double]$temp = 0.3, [int]$reps = 3) {
    # ROBUSTESSE STATISTIQUE: chaque epreuve est tentee $reps fois; le score =
    # TAUX de reussite x10 (pas un coup de chance unique). Un modele qui ne
    # passe que 1 fois sur 3 marque 3.3/10, pas 10. La selection devient
    # statistique - un gagnant doit etre REGULIEREMENT bon, pas chanceux.
    $score = 0.0; $details = @(); $t0 = Get-Date
    $sys = "You write minimal SEARCH/REPLACE patches. Format STRICTLY:`nFILE: <path>`n<<<<<<< SEARCH`n(exact verbatim lines from the file)`n=======`n(replacement)`n>>>>>>> REPLACE`nNEVER write '...' or 'omitted' inside SEARCH. SEARCH must be copied character-for-character from the provided file."
    foreach ($t in $tasks) {
        $abs = Join-Path $thrive ($t.file -replace '/', '\')
        if (-not (Test-Path $abs)) { continue }
        $src = (Get-Content $abs -TotalCount $t.lines) -join "`n"
        $full = (Get-Content $abs -Raw) -replace "`r", ""
        $passes = 0
        for ($rep = 1; $rep -le $reps; $rep++) {
            $body = @{ model = "arena"; max_tokens = 600; temperature = $temp; messages = @(
                @{ role = "system"; content = $sys },
                @{ role = "user"; content = "FILE $($t.file) (first $($t.lines) lines):`n$src`n`nTASK: $($t.ask)`nProduce ONE patch." }
            ) } | ConvertTo-Json -Depth 6
            $ok = $false
            try {
                $r = Invoke-RestMethod "$llm/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 180
                $out = $r.choices[0].message.content
                if ($out -match '(?s)<<<<<<< SEARCH\r?\n(.*?)\r?\n=======\r?\n(.*?)\r?\n>>>>>>> REPLACE') {
                    $search = $Matches[1] -replace "`r", ""; $replace = $Matches[2] -replace "`r", ""
                    # (a) SEARCH verbatim, (b) pas de '...', (c) vrai changement,
                    # (d) resultat valide + contient le changement attendu
                    if ($full.Contains($search) -and $search.Trim().Length -gt 10 -and $search -notmatch '\.\.\.|omitted' -and $replace -ne $search) {
                        $patched = $full.Replace($search, $replace)
                        if ($t.kind -eq "json") {
                            try { $null = $patched | ConvertFrom-Json; if ($patched -match [regex]::Escape($t.expect)) { $ok = $true } } catch {}
                        } else {
                            if ($patched -match [regex]::Escape($t.expect)) { $ok = $true }
                        }
                    }
                }
            } catch {}
            if ($ok) { $passes++ }
        }
        $frac = $passes / $reps
        $score += 10 * $frac
        $details += "$([int]($frac*100))% ($passes/$reps) $($t.file)"
        Write-Host "  [$key] $($details[-1])"
    }
    $secs = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    $speedPts = [Math]::Max(0, 5 - [int]($secs / 60))   # tiebreaker vitesse
    return @{ key = $key; score = [math]::Round($score, 1); speedPts = $speedPts; total = [math]::Round($score + $speedPts, 1); secs = $secs; details = $details }
}

function Invoke-ArenaCycle {
    # HISTORIQUE PERSISTANT: on charge le classement de TOUS les temps. Le cycle ne
    # repart pas a 1, le champion = meilleur jamais vu, et on NE re-benche PAS un
    # modele juge il y a moins de 5 cycles -> fini "il oublie et relance qwen".
    $lb = Get-Leaderboard
    $cycle = [int]$lb.cycle + 1
    $script:cycleNo = $cycle
    $models = @($lb.models)
    $bestEver = if ($models.Count) { @($models | Sort-Object total -Descending)[0] } else { $null }
    Write-ArenaStatus @{ phase = 'crawl'; cycle = $cycle; current = $null; tested = (Get-Rank $models); best = $bestEver; queue = @() }

    # 1. Candidats: base + nouveaux crawles (Get-CrawledCandidates lit arena_tried).
    $candidates = @($baseCandidates)
    if (-not $Only) {
        $crawled = @(Get-CrawledCandidates -Want ($NewPerCycle * 2))
        $newOnes = @($crawled | Select-Object -First $NewPerCycle)
        if ($newOnes.Count) { Write-Host "OCEAN: $($newOnes.key -join ', ')" -ForegroundColor Cyan; $candidates += $newOnes }
    } else {
        $candidates = @($candidates | Where-Object { $_.key -match $Only })
    }

    # 2. Combats. On SAUTE ce qui a ete juge recemment (historique garde), et on
    #    promeut le meilleur de TOUS LES TEMPS apres chaque combat.
    foreach ($c in $candidates) {
        $prev = @($models | Where-Object { $_.key -eq $c.key })[0]
        if ($prev -and (($cycle - [int]$prev.lastCycle) -lt 5)) {
            Write-Host "  $($c.key): deja juge (cycle $($prev.lastCycle), $($prev.total) pts) - garde l'historique, skip" -ForegroundColor DarkGray
            continue
        }
        $file = $c.file
        $have = wsl -d Ubuntu -u root -- bash -c "test -s /root/models/$file && echo OK"
        if ($have -notmatch "OK") {
            if (-not $c.repo) { Write-Host "skip $($c.key): pas de repo"; continue }
            Write-ArenaStatus @{ phase = 'download'; cycle = $cycle; current = @{ key = $c.key; file = $c.file }; tested = (Get-Rank $models); best = $bestEver; queue = @($candidates.key) }
            $file = Get-HfFile $c.repo $c.file
            if (-not $file) { Write-Host "skip $($c.key): telechargement echoue"; continue }
        }
        Write-Host "=== ARENE: $($c.key) ($file) ===" -ForegroundColor Cyan
        Write-ArenaStatus @{ phase = 'bench'; cycle = $cycle; current = @{ key = $c.key; file = $file }; tested = (Get-Rank $models); best = $bestEver; queue = @($candidates.key) }
        if (-not (Start-Model $file)) { Write-Host "  modele n'a pas demarre"; continue }
        $r = Invoke-Bench $c.key
        $r.file = $file; $r.lastCycle = $cycle; $r.repo = $c.repo
        if ($file -notmatch '^(Qwen3-Coder-30B|Qwen2.5-Coder-14B|Yi-Coder-9B)') {
            if (@(Get-Content $triedFile -ErrorAction SilentlyContinue) -notcontains $file) { Add-Content $triedFile $file }
        }
        # UPSERT dans l'historique persistant + champion = meilleur de tous les temps
        $models = @($models | Where-Object { $_.key -ne $r.key }) + ([pscustomobject]$r)
        $bestEver = @($models | Sort-Object total -Descending)[0]
        if (-not (Test-Path $pinFile)) { Set-Content $championFile $bestEver.file -Encoding ascii }  # respecte le choix manuel
        Save-Leaderboard $cycle $models
        @(Get-Rank $models) | ConvertTo-Json -Depth 5 | Set-Content $arenaLog -Encoding utf8
        Write-Host "  -> champion all-time: $($bestEver.key) ($($bestEver.total))" -ForegroundColor Green
        Write-ArenaStatus @{ phase = 'bench'; cycle = $cycle; current = $null; tested = (Get-Rank $models); best = $bestEver; queue = @($candidates.key) }
    }

    Save-Leaderboard $cycle $models
    if (-not $bestEver) { Write-Host "aucun modele juge."; Write-ArenaStatus @{ phase = 'idle'; cycle = $cycle; current = $null; tested = @(); best = $null; queue = @() }; return }

    # 3. Purge: garde KeepTop du classement ALL-TIME (jamais les modeles de base).
    $protect = @($baseCandidates.file)
    foreach ($r in (Get-Rank $models | Select-Object -Skip $KeepTop)) {
        if ($protect -contains $r.file) { continue }
        Write-Host "  selection naturelle: suppression du perdant $($r.file)" -ForegroundColor DarkYellow
        wsl -d Ubuntu -u root -- bash -c "rm -f /root/models/$($r.file)" | Out-Null
    }

    # 4. En PROD: le choix MANUEL (pin via l'interface) a la PRIORITE; sinon le
    # champion all-time (le plus fort jamais vu). Lancement persistant.
    if (Test-Path $pinFile) {
        $pinned = (Get-Content $pinFile -Raw).Trim()
        Write-Host "Champion EPINGLE manuellement: $pinned (l'arene continue de bencher mais ne le remplace pas)" -ForegroundColor Yellow
        Start-LlamaServer -Model $pinned
    } else {
        Set-Content $championFile $bestEver.file -Encoding ascii
        Write-Host "CHAMPION ALL-TIME: $($bestEver.key) ($($bestEver.total)) -> $championFile" -ForegroundColor Green
        Start-LlamaServer -Model $bestEver.file
    }
    Write-ArenaStatus @{ phase = 'done'; cycle = $cycle; current = $null; tested = (Get-Rank $models); best = $bestEver; queue = @() }
}

Write-Host "=== ARENE DE SELECTION NATURELLE DES LLM ===" -ForegroundColor Magenta
if ($Forever) {
    while ($true) {
        Invoke-ArenaCycle
        Write-Host "--- cycle termine, repos $CycleRestSec s avant la prochaine generation ---" -ForegroundColor DarkGray
        Start-Sleep -Seconds $CycleRestSec
    }
} else {
    Invoke-ArenaCycle
}
