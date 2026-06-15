# DOWN HERE - Gestionnaire des modeles telecharges (GGUF dans WSL /root/models).
#
# L'arene telecharge des modeles ; ce module donne le CONTROLE a l'humain :
# lister ce qui occupe le disque, SUPPRIMER (liberer la place), ARCHIVER (sortir
# du pool actif sans perdre le fichier) et PROTEGER de la purge automatique.
#
# Securite: tout nom de fichier vient de l'interface -> on le VALIDE strictement
# avant de l'injecter dans une commande bash (pas d'injection possible).

$script:ModelsDir  = '/root/models'
$script:ArchiveDir = '/root/models/archive'

# Un nom de GGUF legitime: lettres/chiffres/._- et se termine par .gguf. Tout le
# reste est refuse (pas d'espace, pas de /, pas de .. -> aucune injection shell).
function Test-ModelName([string]$file) {
    return ($file -and $file -match '^[A-Za-z0-9][A-Za-z0-9._-]*\.gguf$')
}

# Quantization (Q3_K_M, Q4_K_S, ...) -> lisible pour un neophyte. Le nombre = bits
# par poids: plus bas = plus petit/rapide mais qualite un peu rognee.
# (Calcul cote interface; ici on ne fait que l'inventaire disque.)

# Inventaire COMPLET du disque (pool actif + archive), enrichi avec le classement
# (score/statut) et les protections. Un seul appel WSL (stat) -> rapide.
function Get-DiskModels {
    param($Config = (Get-DownHereConfig))
    $logs = $Config.Paths.Logs
    $keep = @(); try { $keep = @(Get-Content (Join-Path $logs 'models_keep.txt') -ErrorAction Stop | Where-Object { $_.Trim() }) } catch {}
    $champ = ''; try { $champ = (Get-Content $Config.Llm.ChampionFile -Raw -ErrorAction Stop).Trim() } catch {}
    $base = @('Qwen3-Coder-30B-A3B-Instruct-Q3_K_M.gguf', 'Qwen2.5-Coder-14B-Instruct-Q4_K_S.gguf', 'Yi-Coder-9B-Chat-Q4_K_M.gguf')
    $lb = $null; try { $lb = Get-Content (Join-Path $logs 'arena_leaderboard.json') -Raw -ErrorAction Stop | ConvertFrom-Json } catch {}

    $raw = ''
    try { $raw = (wsl -d Ubuntu -u root -- bash -c "stat -c '%s|%Y|%n' $script:ModelsDir/*.gguf $script:ArchiveDir/*.gguf 2>/dev/null" | Out-String) } catch {}
    $out = @()
    foreach ($line in ($raw -split "`n")) {
        $line = $line.Trim(); if (-not $line) { continue }
        $p = $line -split '\|', 3; if ($p.Count -lt 3) { continue }
        $size = [long]$p[0]; $mtime = [long]$p[1]; $path = $p[2]
        $file = [System.IO.Path]::GetFileName($path)
        $archived = ($path -match '/archive/')
        $m = $null; if ($lb -and $lb.models) { $m = @($lb.models | Where-Object { $_.file -eq $file })[0] }
        $role = if ($file -eq $champ) { 'champion' } elseif ($base -contains $file) { 'base' } elseif ($m) { 'challenger' } else { 'orphelin' }
        $out += [pscustomobject]@{
            file      = $file
            gb        = [math]::Round($size / 1GB, 2)
            archived  = [bool]$archived
            champion  = ($file -eq $champ)
            protected = (($keep -contains $file) -or ($base -contains $file) -or ($file -eq $champ))
            role      = $role
            inBoard   = [bool]$m
            total     = if ($m) { $m.total } else { $null }
            status    = if ($m) { $m.status } else { $null }
            mtime     = ([DateTimeOffset]::FromUnixTimeSeconds($mtime).LocalDateTime.ToString('yyyy-MM-dd HH:mm'))
        }
    }
    # Total occupe (pour l'en-tete "X Go / disque").
    $totGb = [math]::Round((($out | Measure-Object gb -Sum).Sum), 2)
    return [pscustomobject]@{ models = @($out); totalGb = $totGb; updatedAt = (Get-Date -Format 'HH:mm:ss') }
}

# SUPPRIME un fichier (pool actif ou archive). Refuse le champion en cours (sinon
# la prod n'a plus de cerveau). Retourne un message pour l'interface.
function Remove-DiskModel {
    param([Parameter(Mandatory)][string]$File, $Config = (Get-DownHereConfig))
    if (-not (Test-ModelName $File)) { return 'nom de fichier invalide' }
    $champ = ''; try { $champ = (Get-Content $Config.Llm.ChampionFile -Raw -ErrorAction Stop).Trim() } catch {}
    if ($File -eq $champ) { return "refuse: $File est le champion servi en prod (choisis-en un autre d'abord)" }
    wsl -d Ubuntu -u root -- bash -c "rm -f '$script:ModelsDir/$File' '$script:ArchiveDir/$File'" | Out-Null
    # Retire aussi de la liste de protection (plus de raison de la garder).
    Set-ModelProtected -File $File -On $false -Config $Config | Out-Null
    return "supprime: $File"
}

# ARCHIVE / DESARCHIVE: deplace entre le pool actif et /archive. Un modele archive
# n'est plus charge/benche/purge par l'arene, mais reste sur le disque.
function Set-ModelArchived {
    param([Parameter(Mandatory)][string]$File, [Parameter(Mandatory)][bool]$On, $Config = (Get-DownHereConfig))
    if (-not (Test-ModelName $File)) { return 'nom de fichier invalide' }
    if ($On) {
        wsl -d Ubuntu -u root -- bash -c "mkdir -p '$script:ArchiveDir' && mv -f '$script:ModelsDir/$File' '$script:ArchiveDir/$File' 2>/dev/null" | Out-Null
        return "archive: $File"
    } else {
        wsl -d Ubuntu -u root -- bash -c "mv -f '$script:ArchiveDir/$File' '$script:ModelsDir/$File' 2>/dev/null" | Out-Null
        return "restaure: $File"
    }
}

# PROTEGE / LIBERE: ajoute/retire le fichier de logs/models_keep.txt. L'arene ne
# purge JAMAIS un fichier protege (voir model_arena.ps1, etape de purge).
function Set-ModelProtected {
    param([Parameter(Mandatory)][string]$File, [Parameter(Mandatory)][bool]$On, $Config = (Get-DownHereConfig))
    if (-not (Test-ModelName $File)) { return 'nom de fichier invalide' }
    $f = Join-Path $Config.Paths.Logs 'models_keep.txt'
    $list = @(); try { $list = @(Get-Content $f -ErrorAction Stop | Where-Object { $_.Trim() }) } catch {}
    if ($On) { if ($list -notcontains $File) { $list += $File } } else { $list = @($list | Where-Object { $_ -ne $File }) }
    Set-Content $f -Value $list -Encoding ascii
    return $(if ($On) { "protege: $File" } else { "liberé: $File" })
}
