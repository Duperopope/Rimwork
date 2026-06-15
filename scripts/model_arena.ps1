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
    [int]$CycleRestSec = 1800     # repos entre cycles (mode Forever)
)

$ErrorActionPreference = "Continue"
# GPU EXCLUSIF: le champion 30B occupe ~14.7 Go sur 16 -> impossible de charger
# un challenger A COTE. L'arene benche donc UN modele a la fois sur le port prod
# (1234), puis rend la main au champion. La boucle de dev tolere ces swaps brefs.
# Source de verite unique (paths/url) - voir scripts/lib/Config.ps1.
. "$PSScriptRoot\lib\Config.ps1"
$cfg = Get-DownHereConfig
$prodPort = 1234
$llm = $cfg.Llm.BaseUrl
$arenaLog = Join-Path $cfg.Paths.Logs 'model_arena.json'
$championFile = $cfg.Llm.ChampionFile
$triedFile = Join-Path $cfg.Paths.Logs 'arena_tried.txt'   # memoire des modeles deja juges
$arenaStatus = Join-Path $cfg.Paths.Logs 'arena_status.json' # statut LIVE pour le dashboard
$thrive = $cfg.Paths.ActiveGame
$script:cycleNo = 0

# Publie l'etat LIVE de l'arene (lu par le dashboard) : phase, modele en cours,
# classement courant, meilleur connu a l'instant T.
function Write-ArenaStatus($o) {
    try { $o['updatedAt'] = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); ($o | ConvertTo-Json -Depth 6) | Set-Content $arenaStatus -Encoding utf8 } catch {}
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
function Get-CrawledCandidates {
    $found = @{}
    $queries = @("coder gguf", "code instruct gguf", "qwen coder gguf",
                 "deepseek coder gguf", "codestral gguf", "starcoder gguf",
                 "code llama gguf", "granite code gguf")
    foreach ($q in $queries) {
        try {
            $hits = Invoke-RestMethod "https://huggingface.co/api/models?search=$([uri]::EscapeDataString($q))&sort=downloads&direction=-1&limit=15" -TimeoutSec 60
        } catch { continue }
        foreach ($m in $hits) {
            if ($m.id -match "embed|rerank|vision|VL|abliterat|base-gguf") { continue }
            if ($found.ContainsKey($m.id)) { continue }
            try { $tree = Invoke-RestMethod "https://huggingface.co/api/models/$($m.id)/tree/main" -TimeoutSec 60 } catch { continue }
            $gg = $tree | Where-Object { $_.path -match "Q4_K_M\.gguf$|Q3_K_M\.gguf$" -and $_.path -notmatch "of-000|00001-of" } |
                  Where-Object { ($_.lfs.size ?? $_.size) -gt 4e9 -and ($_.lfs.size ?? $_.size) -lt 15.5e9 } |
                  Sort-Object { $_.lfs.size ?? $_.size } -Descending | Select-Object -First 1
            if ($gg) {
                $found[$m.id] = @{ key = ($m.id -replace '.*/', ''); file = [System.IO.Path]::GetFileName($gg.path); repo = $m.id }
            }
        }
    }
    return @($found.Values)
}

# ---- Taches de combat: fichiers Thrive REELS, scoring deterministe INSTANTANE.
# On teste la competence cle du dev: produire un SEARCH/REPLACE qui (a) matche
# le fichier VERBATIM, (b) donne un resultat VALIDE (JSON qui parse), (c) fait
# le changement demande. Pas de build lent: l'arene doit juger vite des dizaines
# de modeles. Le champion est ensuite confirme en prod par la vraie boucle.
$tasks = @(
    @{ file = "simulation_parameters/microbe_stage/compounds.json"; lines = 60; kind = "json"
       ask = 'Add a new field `"ArenaTag": 1` to the VERY FIRST compound object in this JSON, keeping the JSON valid.'; expect = 'ArenaTag' }
    @{ file = "simulation_parameters/microbe_stage/membranes.json"; lines = 60; kind = "json"
       ask = 'Add a new field `"ArenaTag": 1` to the VERY FIRST membrane object in this JSON, keeping the JSON valid.'; expect = 'ArenaTag' }
    @{ file = "simulation_parameters/microbe_stage/biomes.json"; lines = 70; kind = "json"
       ask = 'Add a new field `"ArenaTag": 1` to the VERY FIRST top-level object in this JSON, keeping the JSON valid.'; expect = 'ArenaTag' }
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
    # AUTO-FIT (pas de -ngl force): tient compte de la VRAM libre reelle.
    # --model/--ctx-size en formes LONGUES: le raccourci -m est casse dans ce build
    # (model.path reste vide -> router mode, ne sert pas). Voir startup_all.ps1.
    $cmd = "pkill -f 'llama-server.*$port'; sleep 2; nohup /root/llama.cpp/build/bin/llama-server --model /root/models/$file --ctx-size 8192 --host 0.0.0.0 --port $port > /var/log/llama-arena.log 2>&1 &"
    wsl -d Ubuntu -u root -- bash -c $cmd | Out-Null
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
    $script:cycleNo++
    # 1. Construire la liste des candidats: base + nouveaux crawles (jamais juges)
    $tried = if (Test-Path $triedFile) { @(Get-Content $triedFile) } else { @() }
    $candidates = @($baseCandidates)
    Write-ArenaStatus @{ phase = 'crawl'; cycle = $script:cycleNo; current = $null; tested = @(); best = $null; queue = @($candidates.key) }
    if (-not $Only) {
        $crawled = @(Get-CrawledCandidates | Where-Object { $tried -notcontains $_.file -and ($baseCandidates.file -notcontains $_.file) })
        $newOnes = @($crawled | Select-Object -First $NewPerCycle)
        if ($newOnes.Count) {
            Write-Host "OCEAN: $($newOnes.Count) nouveau(x) challenger(s): $($newOnes.key -join ', ')" -ForegroundColor Cyan
            $candidates += $newOnes
        }
    } else {
        $candidates = @($candidates | Where-Object { $_.key -match $Only })
    }

    # 2. Combats - RECURSIF: apres CHAQUE modele on met a jour le meilleur connu a
    #    l'instant T (champion promu tout de suite, statut live), sans attendre la
    #    fin du cycle. C'est ce que le directeur veut: "le meilleur present a T".
    $results = @()
    $best = $null
    foreach ($c in $candidates) {
        $file = $c.file
        $have = wsl -d Ubuntu -u root -- bash -c "test -s /root/models/$file && echo OK"
        if ($have -notmatch "OK") {
            if (-not $c.repo) { Write-Host "skip $($c.key): pas de fichier local, pas de repo"; continue }
            Write-ArenaStatus @{ phase = 'download'; cycle = $script:cycleNo; current = @{ key = $c.key; file = $c.file }; tested = @($results); best = $best; queue = @($candidates.key) }
            $file = Get-HfFile $c.repo $c.file
            if (-not $file) { Write-Host "skip $($c.key): telechargement echoue"; continue }
        }
        Write-Host "=== ARENE: $($c.key) ($file) ===" -ForegroundColor Cyan
        Write-ArenaStatus @{ phase = 'bench'; cycle = $script:cycleNo; current = @{ key = $c.key; file = $file }; tested = @($results); best = $best; queue = @($candidates.key) }
        if (-not (Start-Model $file)) { Write-Host "  modele n'a pas demarre (trop gros ?)"; continue }
        $r = Invoke-Bench $c.key   # reps internes = robustesse statistique
        $r.file = $file
        $results += [pscustomobject]$r
        # memoriser qu'on a juge ce fichier (pour ne pas le re-crawler sans fin)
        if ($file -notmatch '^(Qwen3-Coder-30B|Qwen2.5-Coder-14B|Yi-Coder-9B)') { Add-Content $triedFile $file }
        # PROMOTION INCREMENTALE: ce modele est-il le meilleur connu ? Il tourne
        # deja sur 1234 -> il devient le champion immediatement.
        if (-not $best -or $r.total -gt $best.total) {
            $best = [pscustomobject]$r
            Set-Content $championFile $best.file -Encoding ascii
            Write-Host "  -> champion provisoire: $($best.key) ($($best.total))" -ForegroundColor Green
        }
        $rankedNow = @($results | Sort-Object -Property total -Descending)
        $rankedNow | ConvertTo-Json -Depth 5 | Set-Content $arenaLog -Encoding utf8
        Write-ArenaStatus @{ phase = 'bench'; cycle = $script:cycleNo; current = $null; tested = @($rankedNow); best = $best; queue = @($candidates.key) }
    }
    if ($results.Count -eq 0) { Write-Host "aucun resultat ce cycle."; Write-ArenaStatus @{ phase = 'idle'; cycle = $script:cycleNo; current = $null; tested = @(); best = $null; queue = @() }; return }

    # 3. Classement final + purge des perdants pour liberer de la place
    $ranked = @($results | Sort-Object -Property total -Descending)
    $ranked | ConvertTo-Json -Depth 5 | Set-Content $arenaLog -Encoding utf8
    $champ = $ranked[0]
    Set-Content $championFile $champ.file -Encoding ascii
    Write-Host "CHAMPION: $($champ.key) ($($champ.score)/$(10*$tasks.Count) + $($champ.speedPts) vitesse) -> $championFile" -ForegroundColor Green

    # ne jamais supprimer les modeles de base (filet de securite)
    $protect = @($baseCandidates.file)
    foreach ($r in ($ranked | Select-Object -Skip $KeepTop)) {
        if ($protect -contains $r.file) { continue }
        Write-Host "  selection naturelle: suppression du perdant $($r.file)" -ForegroundColor DarkYellow
        wsl -d Ubuntu -u root -- bash -c "rm -f /root/models/$($r.file)" | Out-Null
    }

    # 4. Relancer le champion en PROD (port 1234, auto-fit) pour la boucle de dev
    # --model/--ctx-size (formes longues): -m casse dans ce build (router mode).
    wsl -d Ubuntu -u root -- bash -c "pkill -f 'llama-server.*$prodPort'; sleep 2; nohup /root/llama.cpp/build/bin/llama-server --model /root/models/$($champ.file) --ctx-size 8192 --host 0.0.0.0 --port $prodPort > /var/log/llama-server.log 2>&1 &" | Out-Null
    Write-ArenaStatus @{ phase = 'done'; cycle = $script:cycleNo; current = $null; tested = @($ranked); best = $champ; queue = @() }
    $ranked | Format-Table key, score, speedPts, secs
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
