<#
DOWN HERE - RAPPORT DE JEU -> DEV (ferme la boucle play -> dev).

Apres des sessions de jeu de l'agent, on AGREGE deux sources REELLES :
  1. scripts/logs/real_transitions.jsonl  (le flux d'etat vecu : energie, nourriture,
     TOXINE) -> metriques de friction (meurt-il pres du poison ? affame ?).
  2. le LOG du jeu  user://logs/log.txt  (%APPDATA%\DownHereOrigins\logs\log.txt)
     -> les VRAIS bugs (exceptions, erreurs Godot) avec leur frequence.

On en tire :
  - scripts/logs/play_findings.md   (lisible par l'humain)
  - des entrees dans scripts/logs/feedback.jsonl (file deja lue par le dashboard ET
    exploitable par la boucle de dev) -> le jeu DIT au dev quoi corriger.

Garde-fou : on n'emet QUE si on a assez de donnees (-MinTransitions) -> "apres un
nombre de sessions convaincantes", pas sur une mort isolee. Dedupe les findings
deja remontes (pas de spam).

  pwsh -File scripts\play_report.ps1
  pwsh -File scripts\play_report.ps1 -MinTransitions 500 -Emit
#>
param(
    [int]$MinTransitions = 200,   # seuil "sessions convaincantes"
    [int]$Top = 6,                # nb de bugs distincts remontes
    [switch]$Emit                 # ecrire aussi dans feedback.jsonl (sinon: rapport seul)
)
. "$PSScriptRoot\lib\Config.ps1"
$cfg = Get-DownHereConfig
$logs = $cfg.Paths.Logs
$transFile = Join-Path $logs 'real_transitions.jsonl'
$findFile = Join-Path $logs 'play_findings.md'
$fbFile = Join-Path $logs 'feedback.jsonl'
$gameLog = Join-Path $env:APPDATA 'DownHereOrigins\logs\log.txt'

# ---- 1) Metriques de friction depuis le flux d'etat vecu ----
$rows = @()
if (Test-Path $transFile) {
    foreach ($l in (Get-Content $transFile -ErrorAction SilentlyContinue)) {
        if (-not $l.Trim()) { continue }
        try { $rows += , (($l | ConvertFrom-Json).s) } catch {}
    }
}
$n = $rows.Count
$play = [ordered]@{}
if ($n) {
    $energies = @($rows | ForEach-Object { [double]$_[0] })
    $hasTox = ($rows[0].Count -ge 7)
    $lowE = @($energies | Where-Object { $_ -lt 0.15 }).Count
    $meanE = [math]::Round((($energies | Measure-Object -Average).Average), 3)
    $play['transitions'] = $n
    $play['energie_moyenne'] = $meanE
    $play['pct_en_detresse'] = [math]::Round($lowE * 100 / $n, 1)   # energie quasi nulle
    if ($hasTox) {
        $nearTox = @($rows | Where-Object { [double]$_[6] -lt 0.25 }).Count
        # mort probable PAR la toxine: pas en detresse ET pres du poison
        $dangerTox = @($rows | Where-Object { [double]$_[0] -lt 0.2 -and [double]$_[6] -lt 0.3 }).Count
        $play['pct_pres_toxine'] = [math]::Round($nearTox * 100 / $n, 1)
        $play['pct_detresse_pres_toxine'] = [math]::Round($dangerTox * 100 / $n, 1)
    }
}

# ---- 2) Vrais bugs depuis le log du jeu ----
$bugs = @{}
if (Test-Path $gameLog) {
    foreach ($l in (Get-Content $gameLog -Tail 4000 -ErrorAction SilentlyContinue)) {
        if ($l -notmatch '(?i)error|exception|condition .* is true|failed|cannot|null reference') { continue }
        # signature normalisee: on enleve chiffres/chemins pour regrouper les memes erreurs
        $sig = ($l -replace '0x[0-9a-fA-F]+', '' -replace '\d+', '#' -replace '[A-Za-z]:\\\\[^\s]+', '<path>').Trim()
        if ($sig.Length -gt 160) { $sig = $sig.Substring(0, 160) }
        if ($sig) { if ($bugs.ContainsKey($sig)) { $bugs[$sig]++ } else { $bugs[$sig] = 1 } }
    }
}
$topBugs = @($bugs.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $Top)

# ---- 3) Rapport lisible ----
$md = @()
$md += "# DOWN HERE - Rapport de jeu -> dev"
$md += "_genere $(Get-Date -Format 'yyyy-MM-dd HH:mm') - $n transitions vecues_"
$md += ""
$md += "## Friction de jeu (ce que l'agent VIT)"
if ($n -lt $MinTransitions) {
    $md += "- pas assez de donnees ($n < $MinTransitions) - laisser l'agent jouer davantage."
}
else {
    foreach ($k in $play.Keys) { $md += "- **$k** : $($play[$k])" }
    if ($play['pct_detresse_pres_toxine'] -ge 15) {
        $md += "- :warning: l'agent meurt souvent **pres du sulfure d'hydrogene** -> il lui faut des **proteines chimiosynthetiques** (choix d'organelle dans l'editeur), pas seulement l'eviter."
    }
}
$md += ""
$md += "## Bugs reels du jeu (log.txt, regroupes)"
if (-not (Test-Path $gameLog)) { $md += "- log du jeu introuvable ($gameLog) - lance le jeu une fois." }
elseif (-not $topBugs.Count) { $md += "- aucun bug detecte dans le log recent. :)" }
else { foreach ($b in $topBugs) { $md += "- **x$($b.Value)** $($b.Key)" } }
Set-Content -Path $findFile -Value ($md -join "`n") -Encoding utf8
Write-Host "rapport -> $findFile`n"
$md -join "`n" | Write-Host

# ---- 4) Remonter au dev (feedback.jsonl) si assez de donnees ----
if ($Emit -and $n -ge $MinTransitions) {
    $existing = @(); try { $existing = @(Get-Content $fbFile -ErrorAction Stop | ForEach-Object { try { ($_ | ConvertFrom-Json).text } catch {} }) } catch {}
    $items = @()
    foreach ($b in $topBugs) { if ($b.Value -ge 3) { $items += @{ type = 'bug'; text = "[jeu x$($b.Value)] $($b.Key)" } } }
    if ($play['pct_detresse_pres_toxine'] -ge 15) {
        $items += @{ type = 'feature'; text = "[jeu] l'agent meurt souvent pres du H2S : exposer/automatiser le choix d'organelle chimiosynthetique dans l'editeur" }
    }
    $added = 0
    foreach ($it in $items) {
        if ($existing -contains $it.text) { continue }
        @{ date = (Get-Date -Format 'dd/MM HH:mm'); type = $it.type; text = $it.text; status = 'propose'; src = 'play' } |
            ConvertTo-Json -Compress | Add-Content -Path $fbFile -Encoding utf8
        $added++
    }
    Write-Host "`n$added finding(s) remonte(s) au dev (feedback.jsonl)."
}
elseif ($Emit) { Write-Host "`npas d'emission: $n < $MinTransitions (sessions pas encore convaincantes)." }
