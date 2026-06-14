<#
DOWN HERE - CONVERSATION avec memoire persistante.

Un agent qui parle librement (LLM local, sans supervision tour-par-tour) ET qui
APPREND de vos echanges via une MEMOIRE persistante - sans re-entrainer le
modele. Technique reelle et documentee : agents a memoire (MemGPT/Letta, Packer
et al. 2023 ; Generative Agents, Park et al. 2023 ; RAG, Lewis et al. 2020).

  - chat_history.jsonl : l'historique brut des tours (user/assistant).
  - chat_memory.jsonl  : des faits DURABLES que l'agent retient (injectes dans
                         le prompt -> il "se souvient" d'une session a l'autre).
  - toutes les ~8 reponses : l'agent RESUME les echanges recents en memoires
    durables (idee MemGPT de compression recursive du contexte).

Tolerant : si le LLM local est absent, renvoie un message clair.
#>

. "$PSScriptRoot\Config.ps1"
. "$PSScriptRoot\State.ps1"   # pour donner le contexte projet a l'agent

function Get-ChatPaths {
    param($Config = (Get-DownHereConfig))
    return @{
        History = Join-Path $Config.Paths.Logs 'chat_history.jsonl'
        Memory  = Join-Path $Config.Paths.Logs 'chat_memory.jsonl'
    }
}

function Get-ChatHistory {
    param([int]$Last = 12, $Config = (Get-DownHereConfig))
    $f = (Get-ChatPaths -Config $Config).History
    if (-not (Test-Path $f)) { return @() }
    $rows = Get-Content $f | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} } | Where-Object { $_ }
    return @($rows | Select-Object -Last $Last)
}

function Add-ChatTurn {
    param([string]$Role, [string]$Content, $Config = (Get-DownHereConfig))
    $f = (Get-ChatPaths -Config $Config).History
    @{ role = $Role; content = $Content; ts = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") } |
        ConvertTo-Json -Compress | Add-Content -Path $f -Encoding utf8
}

function Get-ChatMemories {
    param([int]$Last = 25, $Config = (Get-DownHereConfig))
    $f = (Get-ChatPaths -Config $Config).Memory
    if (-not (Test-Path $f)) { return @() }
    return @(Get-Content $f | Where-Object { $_.Trim() } | Select-Object -Last $Last)
}

function Add-ChatMemory {
    param([string]$Fact, $Config = (Get-DownHereConfig))
    $Fact = ($Fact -replace '\s+', ' ').Trim()
    if ($Fact.Length -lt 4) { return }
    $existing = Get-ChatMemories -Config $Config
    if ($existing -contains $Fact) { return }
    Add-Content -Path (Get-ChatPaths -Config $Config).Memory -Value $Fact -Encoding utf8
}

# Appel brut au LLM local (OpenAI-compatible). $null si injoignable.
function Invoke-LocalLlm {
    param([array]$Messages, [double]$Temperature = 0.7, [int]$MaxTokens = 450, $Config = (Get-DownHereConfig))
    try {
        $body = @{ model = 'local-model'; messages = $Messages; temperature = $Temperature; max_tokens = $MaxTokens } |
            ConvertTo-Json -Depth 6
        $r = Invoke-RestMethod -Uri ($Config.Llm.BaseUrl + $Config.Llm.ChatPath) -Method Post `
            -ContentType 'application/json' -Body $body -TimeoutSec 120
        return $r.choices[0].message.content
    } catch { return $null }
}

function Build-ChatSystemPrompt {
    param($Config = (Get-DownHereConfig))
    $mem = (Get-ChatMemories -Config $Config) -join "`n- "
    $st = $null; try { $st = Get-DownHereState -Config $Config } catch {}
    $stLine = if ($st) { "Etat projet: mode=$($st.mode), roadmap $($st.roadmap.done)/$($st.roadmap.todo) faites, dev kept=$($st.devlog.kept)/reverted=$($st.devlog.reverted)." } else { "" }
    $memBlock = if ($mem) { "Ce que tu SAIS deja (memoire durable):`n- $mem" } else { "" }
    return @"
Tu es DOWN HERE, le compagnon IA d'un projet de jeu (du vivant aux etoiles, base
Thrive, dev par IA locale). Tu paroles en francais, naturellement et librement,
de maniere concise et utile. Tu connais le projet et tu peux discuter de tout.
$stLine
$memBlock

Si tu apprends un fait durable et utile sur l'utilisateur ou le projet, tu peux
le garder en tete pour les prochaines fois.
"@
}

# Un tour de conversation complet : memoire + historique -> reponse -> persistance.
function Invoke-ChatTurn {
    param([Parameter(Mandatory)][string]$Message, $Config = (Get-DownHereConfig))

    $messages = @(@{ role = 'system'; content = (Build-ChatSystemPrompt -Config $Config) })
    foreach ($h in (Get-ChatHistory -Last 12 -Config $Config)) {
        if ($h.role -in @('user', 'assistant')) { $messages += @{ role = $h.role; content = $h.content } }
    }
    $messages += @{ role = 'user'; content = $Message }

    $reply = Invoke-LocalLlm -Messages $messages -Config $Config
    if (-not $reply) {
        return "[LLM local injoignable] Lance la pile : powershell -File scripts/startup_all.ps1 (le serveur met ~1-2 min a charger). Surtout PAS LM Studio."
    }
    $reply = $reply.Trim()
    Add-ChatTurn -Role 'user' -Content $Message -Config $Config
    Add-ChatTurn -Role 'assistant' -Content $reply -Config $Config

    # MemGPT-like : toutes les ~8 entrees d'historique, on compresse les echanges
    # recents en UNE memoire durable (apprentissage sans re-entrainement).
    try {
        $allCount = 0
        $hf = (Get-ChatPaths -Config $Config).History
        if (Test-Path $hf) { $allCount = (Get-Content $hf | Measure-Object -Line).Lines }
        if ($allCount -gt 0 -and ($allCount % 8) -eq 0) {
            $recent = (Get-ChatHistory -Last 8 -Config $Config | ForEach-Object { "$($_.role): $($_.content)" }) -join "`n"
            $exMsg = @(
                @{ role = 'system'; content = "Extrais UN seul fait durable et utile a retenir sur l'utilisateur ou le projet, a partir de l'echange. Reponds par la phrase seule, ou exactement NONE si rien." },
                @{ role = 'user'; content = $recent }
            )
            $fact = Invoke-LocalLlm -Messages $exMsg -Temperature 0.2 -MaxTokens 60 -Config $Config
            if ($fact -and $fact.Trim() -notmatch '^NONE') { Add-ChatMemory -Fact $fact -Config $Config }
        }
    } catch {}

    return $reply
}
