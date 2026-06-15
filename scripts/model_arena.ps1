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
        @{ key = $_.key; total = $_.total; score = $_.score; speedPts = $_.speedPts; secs = $_.secs; details = $_.details; cats = $_.cats; file = $_.file; lastCycle = $_.lastCycle } })
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
            # exclut les archis exotiques / non chargeables par ce llama.cpp:
            # MTP (multi-token-prediction), vision, abliterated, tout petits, etc.
            if ($m.id -match "embed|rerank|vision|VL|abliterat|base-gguf|MTP|draft|bnb|awq|gptq|-1\.5B|-0\.5B|-3B") { continue }
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

# ---- BENCHMARK multi-categories (esprit des evals de modeles frontiere). Chaque
# CATEGORIE teste une competence reelle du dev, en ANGLAIS (meilleur pour les LLM),
# scoring deterministe et instantane. Categories:
#   JSON patch  : SEARCH/REPLACE verbatim + JSON valide (coeur du dev)
#   Precision   : cibler le bon objet / multi-champs (plus dur)
#   Code edit   : SEARCH/REPLACE sur un snippet C#
#   Instruction : suivre une consigne a la lettre (sortie exacte)
#   Reasoning   : raisonnement deterministe (sortie exacte)
# Le score final = MOYENNE des taux par categorie (chaque categorie compte autant)
# x3 essais -> un classement fiable, pas un coup de chance. Le champion est ensuite
# confirme en prod par la vraie boucle de dev.
$tasks = @(
    @{ cat = 'JSON patch'; kind = 'json'; file = 'simulation_parameters/microbe_stage/compounds.json'; lines = 60
       ask = 'Add a new field "ArenaTag": 1 to the VERY FIRST compound object. Keep the JSON valid.'; expect = 'ArenaTag' }
    @{ cat = 'JSON patch'; kind = 'json'; file = 'simulation_parameters/microbe_stage/membranes.json'; lines = 60
       ask = 'Add a new STRING field "ArenaNote": "ok" to the VERY FIRST membrane object. Keep the JSON valid.'; expect = 'ArenaNote' }
    @{ cat = 'Precision'; kind = 'json'; file = 'simulation_parameters/microbe_stage/compounds.json'; lines = 120
       ask = 'Add a new field "ArenaDeep": 9 to the SECOND compound object (NOT the first one). Keep the JSON valid.'; expect = 'ArenaDeep' }
    @{ cat = 'Precision'; kind = 'json'; file = 'simulation_parameters/microbe_stage/organelles.json'; lines = 80
       ask = 'Add TWO new fields "ArenaA": 1 and "ArenaB": 2 to the VERY FIRST organelle object. Keep the JSON valid.'; expect = 'ArenaB' }
    @{ cat = 'Code edit'; kind = 'codeinline'; lines = 0
       snippet = "public int Energy()`n{`n    int baseValue = 10;`n    return baseValue * 2;`n}"
       ask = 'In this C# snippet, change baseValue from 10 to 25. Keep everything else identical.'; expect = '25' }
    @{ cat = 'Instruction'; kind = 'exact'
       ask = 'Reply with ONLY the single word READY in uppercase. No punctuation, no quotes, no other text.'; expect = '^\s*READY\s*$' }
    @{ cat = 'Logic'; kind = 'exact'
       ask = 'Given C#: int x = 7; x += 5; x *= 2; What is the final value of x? Reply with ONLY the number.'; expect = '\b24\b' }

    # --- VRAI benchmark coder public: problemes HumanEval, code EXECUTE dans WSL ---
    @{ cat = 'HumanEval'; kind = 'humaneval'; entry = 'truncate_number'
       ask = 'Write a complete Python function truncate_number(number: float) -> float that returns the decimal part (the part after the decimal point) of a positive float. Example: truncate_number(3.5) returns 0.5.'
       test = "def check(c):`n    assert c(3.5)==0.5`n    assert abs(c(1.33)-0.33)<1e-6`n    assert abs(c(123.456)-0.456)<1e-6" }
    @{ cat = 'HumanEval'; kind = 'humaneval'; entry = 'sum_product'
       ask = 'Write a complete Python function sum_product(numbers: list) that returns a tuple (sum_of_all_numbers, product_of_all_numbers). For an empty list, the sum is 0 and the product is 1.'
       test = "def check(c):`n    assert c([])==(0,1)`n    assert c([1,2,3,4])==(10,24)`n    assert c([1,1,1])==(3,1)" }
    @{ cat = 'HumanEval'; kind = 'humaneval'; entry = 'below_zero'
       ask = 'Write a complete Python function below_zero(operations: list) that returns True if the running balance (starting from 0) ever falls below zero, otherwise returns False.'
       test = "def check(c):`n    assert c([1,2,3])==False`n    assert c([1,2,-4,5])==True`n    assert c([1,-1])==False" }

    # --- VRAI benchmark raisonnement public: problemes GSM8K, nombre final exact ---
    @{ cat = 'GSM8K'; kind = 'exact'
       ask = 'Natalia sold clips to 48 of her friends in April, and then she sold half as many clips in May. How many clips did Natalia sell altogether in April and May? Reply with ONLY the final number.'; expect = '\b72\b' }
    @{ cat = 'GSM8K'; kind = 'exact'
       ask = 'Weng earns $12 an hour for babysitting. Yesterday she did 50 minutes of babysitting. How many dollars did she earn? Reply with ONLY the final number.'; expect = '\b10\b' }
    @{ cat = 'GSM8K'; kind = 'exact'
       ask = 'Betty needs $100 for a wallet and currently has only half of that. Her parents give her $15, and her grandparents give twice as much as her parents. How many more dollars does Betty need? Reply with ONLY the final number.'; expect = '\b5\b' }
)

function Wait-Llm([int]$timeoutSec = 240) {
    # /health "ok" NE SUFFIT PAS: un vieux serveur (modele precedent) peut encore
    # repondre pendant que le nouveau charge -> le bench partirait dans le vide
    # (FAIL vides). On exige une VRAIE completion: le modele genere = il est pret.
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $timeoutSec) {
        try {
            if ((Invoke-RestMethod "$llm/health" -TimeoutSec 5).status -eq "ok") {
                $b = @{ model = 'arena'; max_tokens = 1; messages = @(@{ role = 'user'; content = 'hi' }) } | ConvertTo-Json
                $r = Invoke-RestMethod "$llm/v1/chat/completions" -Method Post -Body $b -ContentType 'application/json' -TimeoutSec 30
                if ($r.choices) { return $true }
            }
        } catch {}
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
    $have = wsl -d Ubuntu -u root -- bash -c "test -s /root/models/$file && echo OK"
    if ($have -notmatch 'OK') { Write-Host "  modele absent sur disque: $file -> skip" -ForegroundColor DarkYellow; return $false }
    Start-LlamaServer -Model $file
    Start-Sleep -Seconds 8   # laisse le pkill tuer l'ancien serveur + le nouveau commencer a charger
    return (Wait-Llm)        # ne rend la main que si une VRAIE completion passe
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
    wsl -d Ubuntu -u root -- bash -c "cd /root/models && timeout 1200 wget -q -c --tries=2 --timeout=30 'https://huggingface.co/$repo/resolve/main/$($entry.path)' -O '$name'" | Out-Null
    $size = [long](wsl -d Ubuntu -u root -- bash -c "stat -c%s /root/models/$name 2>/dev/null || echo 0")
    if ($size -eq $want -and $want -gt 3e9) { return $name }
    wsl -d Ubuntu -u root -- bash -c "rm -f /root/models/$name" | Out-Null
    return $null
}

# Execute le code Python du modele contre le test OFFICIEL du benchmark (HumanEval)
# dans WSL python3, avec timeout. Retourne $true si tous les asserts passent.
function Test-PyCode([string]$code, [string]$test, [string]$entry) {
    $prog = "$code`n`n$test`n`ntry:`n    check($entry)`n    print('PASS_OK')`nexcept Exception as _e:`n    print('FAIL', _e)"
    try {
        $res = ($prog -replace "`r", '') | wsl -d Ubuntu -u root -- bash -c "cat > /tmp/arena_he.py && timeout 12 python3 /tmp/arena_he.py 2>&1" | Out-String
        return ($res -match 'PASS_OK')
    } catch { return $false }
}

function Invoke-Bench([string]$key, [double]$temp = 0.2, [int]$reps = 3) {
    # BENCHMARK MULTI-CATEGORIES (esprit evals frontiere). Chaque epreuve x$reps;
    # score final = MOYENNE des taux PAR CATEGORIE (chaque categorie pese pareil) x10
    # -> un gagnant doit etre bon PARTOUT, pas chanceux sur une seule competence.
    $t0 = Get-Date
    $patchSys = "You write minimal SEARCH/REPLACE patches. Format STRICTLY:`nFILE: <path>`n<<<<<<< SEARCH`n(exact verbatim lines)`n=======`n(replacement)`n>>>>>>> REPLACE`nNEVER write '...' or 'omitted'. SEARCH must be copied character-for-character."
    $qaSys = "You are a precise assistant. Follow the instruction exactly and answer as briefly as possible, with no explanation."
    $codeSys = "You are an expert Python programmer. Write the COMPLETE function. Return ONLY Python code (a single code block is fine), no explanation."
    $catPass = @{}; $catTot = @{}; $catOrder = @()
    foreach ($t in $tasks) {
        if ($catOrder -notcontains $t.cat) { $catOrder += $t.cat; $catPass[$t.cat] = 0; $catTot[$t.cat] = 0 }
        # Prepare system prompt + user message + verification context per kind.
        $full = ''
        if ($t.kind -eq 'exact') {
            $sys = $qaSys; $user = $t.ask
        } elseif ($t.kind -eq 'humaneval') {
            $sys = $codeSys; $user = $t.ask
        } elseif ($t.kind -eq 'codeinline') {
            $sys = $patchSys; $full = $t.snippet
            $user = "FILE snippet.cs:`n$($t.snippet)`n`nTASK: $($t.ask)`nProduce ONE patch."
        } else {
            $abs = Join-Path $thrive ($t.file -replace '/', '\')
            if (-not (Test-Path $abs)) { continue }
            $src = (Get-Content $abs -TotalCount $t.lines) -join "`n"
            $full = (Get-Content $abs -Raw) -replace "`r", ""
            $sys = $patchSys
            $user = "FILE $($t.file) (first $($t.lines) lines):`n$src`n`nTASK: $($t.ask)`nProduce ONE patch."
        }
        Write-LlmConsole -Src 'arene' -Model $key -Kind 'test' -Text "[$($t.cat)] $($t.ask)"
        for ($rep = 1; $rep -le $reps; $rep++) {
            $catTot[$t.cat]++
            $ok = $false; $out = ''
            try {
                $body = @{ model = 'arena'; max_tokens = 600; temperature = $temp; messages = @(
                        @{ role = 'system'; content = $sys }, @{ role = 'user'; content = $user }) } | ConvertTo-Json -Depth 6
                $r = Invoke-RestMethod "$llm/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 180
                $out = $r.choices[0].message.content
                if ($t.kind -eq 'humaneval') {
                    $code = $out
                    if ($out -match '(?s)```(?:python)?\s*(.*?)```') { $code = $Matches[1] }
                    if (Test-PyCode $code $t.test $t.entry) { $ok = $true }
                } elseif ($t.kind -eq 'exact') {
                    if ($out.Trim() -match $t.expect) { $ok = $true }
                } elseif ($out -match '(?s)<<<<<<< SEARCH\r?\n(.*?)\r?\n=======\r?\n(.*?)\r?\n>>>>>>> REPLACE') {
                    $search = $Matches[1] -replace "`r", ''; $replace = $Matches[2] -replace "`r", ''
                    if ($full.Contains($search) -and $search.Trim().Length -gt 3 -and $search -notmatch '\.\.\.|omitted' -and $replace -ne $search) {
                        $patched = $full.Replace($search, $replace)
                        if ($t.kind -eq 'json') {
                            try { $null = $patched | ConvertFrom-Json; if ($patched -match [regex]::Escape($t.expect)) { $ok = $true } } catch {}
                        } elseif ($patched -match [regex]::Escape($t.expect)) { $ok = $true }
                    }
                }
            } catch {}
            if ($ok) { $catPass[$t.cat]++ }
            Write-LlmConsole -Src 'arene' -Model $key -Kind $(if ($ok) { 'pass' } else { 'fail' }) -Text $out
        }
    }
    # Score = moyenne des taux par categorie x10 (0-10) + bonus vitesse (0-5).
    $details = @(); $cats = @(); $sum = 0.0
    foreach ($c in $catOrder) {
        $pct = if ($catTot[$c]) { $catPass[$c] / $catTot[$c] } else { 0 }
        $sum += $pct
        $cats += @{ cat = $c; pct = [int]($pct * 100) }
        $details += "$c $([int]($pct*100))%"
        Write-Host "  [$key] $c $([int]($pct*100))%"
    }
    $score = [math]::Round(10 * $sum / [Math]::Max(1, $catOrder.Count), 1)
    $secs = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    $speedPts = [Math]::Max(0, 5 - [int]($secs / 60))
    return @{ key = $key; score = $score; speedPts = $speedPts; total = [math]::Round($score + $speedPts, 1); secs = $secs; details = $details; cats = $cats }
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
        # ANTI-BOUCLE: tout candidat NON-base est marque "juge" DES QU'ON LE TENTE
        # (succes OU echec). Sinon un modele qui rate son telechargement/chargement
        # n'est jamais enregistre -> re-crawle a chaque cycle -> boucle infinie sur
        # les memes ratages (le bug des 34 cycles a 0 ajout).
        $isBase = $baseCandidates.file -contains $c.file
        if (-not $isBase -and (@(Get-Content $triedFile -ErrorAction SilentlyContinue) -notcontains $c.file)) { Add-Content $triedFile $c.file }
        $file = $c.file
        $have = wsl -d Ubuntu -u root -- bash -c "test -s /root/models/$file && echo OK"
        if ($have -notmatch "OK") {
            if (-not $c.repo) { Write-Host "skip $($c.key): pas de repo"; Write-LlmConsole -Src 'arene' -Model $c.key -Kind 'fail' -Text 'pas de repo / fichier introuvable -> marque juge, suivant'; continue }
            Write-ArenaStatus @{ phase = 'download'; cycle = $cycle; current = @{ key = $c.key; file = $c.file }; tested = (Get-Rank $models); best = $bestEver; queue = @($candidates.key) }
            Write-LlmConsole -Src 'arene' -Model $c.key -Kind 'test' -Text "telechargement de $($c.file) depuis $($c.repo)..."
            $file = Get-HfFile $c.repo $c.file
            if (-not $file) { Write-Host "skip $($c.key): telechargement echoue"; Write-LlmConsole -Src 'arene' -Model $c.key -Kind 'fail' -Text "telechargement echoue ($($c.file)) -> marque juge, suivant"; continue }
        }
        Write-Host "=== ARENE: $($c.key) ($file) ===" -ForegroundColor Cyan
        Write-ArenaStatus @{ phase = 'bench'; cycle = $cycle; current = @{ key = $c.key; file = $file }; tested = (Get-Rank $models); best = $bestEver; queue = @($candidates.key) }
        if (-not (Start-Model $file)) {
            # Capture la VRAIE erreur de llama.cpp (archi non supportee, OOM, gguf casse...)
            $errlog = (wsl -d Ubuntu -u root -- bash -lc "grep -iE 'error|unsupported|unknown|not supported|failed|out of memory|cannot' /tmp/llama-server.log 2>/dev/null | tail -2" 2>$null | Out-String).Trim()
            if (-not $errlog) { $errlog = (wsl -d Ubuntu -u root -- bash -lc 'tail -2 /tmp/llama-server.log 2>/dev/null' 2>$null | Out-String).Trim() }
            Write-Host "  modele n'a pas demarre"
            Write-LlmConsole -Src 'arene' -Model $c.key -Kind 'fail' -Text "serveur KO ($file) -> $errlog"
            continue
        }
        $r = Invoke-Bench $c.key
        $r.file = $file; $r.lastCycle = $cycle; $r.repo = $c.repo
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
