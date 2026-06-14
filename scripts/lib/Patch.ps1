<#
DOWN HERE - APPLICATION DE PATCHS (Phase 5).

Le dev IA rend des blocs SEARCH/REPLACE. L'ancien matcher exigeait des lignes
contigues identiques (apres normalisation des espaces) -> beaucoup de
"SKIPPED (no SEARCH match)" des qu'une ligne vide differait.

Ici, deux passes :
  1. STRICTE   : match contigu, insensible aux espaces (comportement d'origine).
  2. TOLERANTE : ignore les lignes vides des deux cotes, MAIS seulement si le
                 motif non-vide matche a UN SEUL endroit (sinon on refuse, pour
                 ne jamais editer au mauvais endroit).

Extrait de dev_loop.ps1 pour etre TESTABLE en isolation (voir scripts/tests/).
#>

function Get-NormalizedLine { param([string]$Line) return ($Line.Trim() -replace '\s+', ' ') }

function Parse-SearchReplaceBlocks {
    param([string]$Text)
    $results = @()
    $pattern = '(?ms)FILE:\s*(?<path>\S+)\s*<{5,}\s*SEARCH\s*\r?\n(?<search>.*?)\r?\n={5,}\s*\r?\n(?<replace>.*?)\r?\n>{5,}\s*REPLACE'
    foreach ($m in [regex]::Matches($Text, $pattern)) {
        $results += [pscustomobject]@{
            Path    = $m.Groups['path'].Value.Trim()
            Search  = $m.Groups['search'].Value -replace "`r", ""
            Replace = $m.Groups['replace'].Value -replace "`r", ""
        }
    }
    return $results
}

function Rebuild-WithSpan {
    param($ContentLines, [int]$Start, [int]$End, [string]$Replace)
    $before = if ($Start -gt 0) { (@($ContentLines[0..($Start - 1)]) -join "`n") + "`n" } else { "" }
    $after = if ($End -lt $ContentLines.Count - 1) { "`n" + (@($ContentLines[($End + 1)..($ContentLines.Count - 1)]) -join "`n") } else { "" }
    return $before + $Replace.Trim("`n") + $after
}

function Try-ApplyEdit {
    param([string]$Content, [string]$Search, [string]$Replace)
    $contentLines = $Content -split "`n"
    $searchLines = @($Search -split "`n")
    # enleve les lignes vides en tete/queue du SEARCH
    while ($searchLines.Count -gt 0 -and (Get-NormalizedLine $searchLines[0]) -eq '') { $searchLines = @($searchLines[1..($searchLines.Count - 1)]) }
    while ($searchLines.Count -gt 0 -and (Get-NormalizedLine $searchLines[-1]) -eq '') { $searchLines = @($searchLines[0..($searchLines.Count - 2)]) }
    if ($searchLines.Count -eq 0) { return $null }
    $normSearch = @($searchLines | ForEach-Object { Get-NormalizedLine $_ })

    # PASSE 1 - stricte : contigu, insensible aux espaces.
    for ($start = 0; $start -le $contentLines.Count - $searchLines.Count; $start++) {
        $isMatch = $true
        for ($k = 0; $k -lt $searchLines.Count; $k++) {
            if ((Get-NormalizedLine $contentLines[$start + $k]) -ne $normSearch[$k]) { $isMatch = $false; break }
        }
        if ($isMatch) { return Rebuild-WithSpan $contentLines $start ($start + $searchLines.Count - 1) $Replace }
    }

    # PASSE 2 - tolerante : ignore les lignes vides, UNIQUEMENT si match unique.
    $sNB = @($normSearch | Where-Object { $_ -ne '' })
    if ($sNB.Count -eq 0) { return $null }
    $spans = New-Object System.Collections.Generic.List[object]
    for ($start = 0; $start -lt $contentLines.Count; $start++) {
        $ci = $start; $si = 0; $first = -1; $last = -1
        while ($si -lt $sNB.Count -and $ci -lt $contentLines.Count) {
            $cn = Get-NormalizedLine $contentLines[$ci]
            if ($cn -eq '') { $ci++; continue }            # saute les lignes vides du contenu
            if ($cn -eq $sNB[$si]) { if ($first -lt 0) { $first = $ci }; $last = $ci; $si++; $ci++ }
            else { break }
        }
        if ($si -eq $sNB.Count) { $spans.Add(@{ Start = $first; End = $last }) }
    }
    if ($spans.Count -eq 1) { return Rebuild-WithSpan $contentLines $spans[0].Start $spans[0].End $Replace }
    return $null   # 0 match, ou plusieurs (ambigu) -> on refuse
}
