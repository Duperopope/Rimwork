<#
DOWN HERE - Source de verite UNIQUE (paths, ports, modele, modes).

But: tuer les chemins "g:\Rimwork\..." codes en dur eparpilles dans tous les
scripts. Tout script du systeme commence par:

    . "$PSScriptRoot\lib\Config.ps1"     # (ajuste le chemin relatif)
    $cfg = Get-DownHereConfig

Le ROOT est CALCULE depuis l'emplacement de ce fichier (aucun chemin absolu
code en dur), donc le depot est relocalisable / clonable ailleurs sans edition.
#>

function Get-DownHereConfig {
    # lib/ est sous scripts/, donc root = deux niveaux au-dessus.
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

    return [pscustomobject]@{
        Root = $root

        Paths = @{
            ActiveGame   = Join-Path $root 'reference\thrive'   # LE jeu actif (Thrive)
            ParkedGame   = Join-Path $root 'src'                # RimWork parke (futur 4X)
            Scripts      = Join-Path $root 'scripts'
            Lib          = Join-Path $root 'scripts\lib'
            Logs         = Join-Path $root 'scripts\logs'
            Datasets     = Join-Path $root 'datasets'
            Docs         = Join-Path $root 'docs'
            Roadmap      = Join-Path $root 'ROADMAP.md'
            DevLog       = Join-Path $root 'DEV_LOG.md'
            SystemPrompt = Join-Path $root 'LM_STUDIO_SYSTEM_PROMPT.md'  # TODO: renommer LLM_SYSTEM_PROMPT.md
        }

        # Cerveau LLM = llama-server (llama.cpp ROCm) DANS WSL. JAMAIS LM Studio.
        Llm = @{
            BaseUrl       = 'http://localhost:1234'
            ChatPath      = '/v1/chat/completions'
            ModelsPath    = '/v1/models'
            HealthPath    = '/health'
            Provider      = 'llama-server-wsl'
            ChampionFile  = Join-Path $root 'scripts\llm_champion.txt'
            FallbackModel = 'Qwen2.5-Coder-14B-Instruct-Q4_K_S.gguf'
        }

        Dashboard = @{ Port = 8765; Url = 'http://localhost:8765' }

        # Modes MUTUELLEMENT EXCLUSIFS (le jeu et le dev ne tournent pas ensemble).
        Modes    = @('IDLE', 'DEV', 'PLAY', 'ARENA')
        ModeFile = Join-Path $root 'scripts\logs\mode.json'
    }
}

# Helper: le modele actuellement servi (champion), avec repli.
function Get-DownHereChampion {
    param($Config = (Get-DownHereConfig))
    try {
        $c = (Get-Content $Config.Llm.ChampionFile -Raw -ErrorAction Stop).Trim()
        if ($c) { return $c }
    } catch {}
    return $Config.Llm.FallbackModel
}
