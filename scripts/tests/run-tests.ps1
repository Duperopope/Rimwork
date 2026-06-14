<#
DOWN HERE - Tests d'orchestration (Phase 6).

Harnais autonome (zero dependance : pas besoin de Pester) qui verifie le
socle : Config, Patch (matcher SEARCH/REPLACE), Modes, State, et le parse de
tous les scripts. Code de sortie = nombre d'echecs (0 = tout vert).

  pwsh -File scripts/tests/run-tests.ps1
#>

$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function Assert($cond, $name) {
    if ($cond) { $script:pass++; Write-Host "  PASS $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL $name" -ForegroundColor Red }
}
function AssertEq($got, $want, $name) { Assert ($got -eq $want) "$name (got '$got' want '$want')" }

$lib = Join-Path $PSScriptRoot '..\lib'
. (Join-Path $lib 'Config.ps1')
. (Join-Path $lib 'Patch.ps1')
. (Join-Path $lib 'Modes.ps1')
. (Join-Path $lib 'State.ps1')
$cfg = Get-DownHereConfig

Write-Host "== Config ==" -ForegroundColor Cyan
Assert (Test-Path $cfg.Root) "Root existe"
Assert (Test-Path $cfg.Paths.ActiveGame) "ActiveGame existe"
Assert ($cfg.Llm.BaseUrl -like 'http*1234') "Llm.BaseUrl = port 1234"
AssertEq $cfg.Modes.Count 4 "4 modes"

Write-Host "== Patch (matcher SEARCH/REPLACE) ==" -ForegroundColor Cyan
$c = "line A`nline B`nline C"
AssertEq (Try-ApplyEdit $c "line B" "LINE B!") "line A`nLINE B!`nline C" "match exact"
AssertEq (Try-ApplyEdit $c "line    B" "X") "line A`nX`nline C" "insensible aux espaces"
AssertEq (Try-ApplyEdit "a`n`nb" "a`nb" "X") "X" "tolere une ligne vide (match unique)"
AssertEq (Try-ApplyEdit "a`n`nb`nQ`na`n`nb" "a`nb" "X") $null "ambigu (2 spans) -> refus"
AssertEq (Try-ApplyEdit $c "zzz" "X") $null "aucun match -> null"
$blocks = Parse-SearchReplaceBlocks "FILE: foo.cs`n<<<<<< SEARCH`nold`n======`nnew`n>>>>>> REPLACE"
AssertEq @($blocks).Count 1 "parse 1 bloc SEARCH/REPLACE"
AssertEq $blocks[0].Path "foo.cs" "parse: chemin"

Write-Host "== Modes ==" -ForegroundColor Cyan
$idle = Invoke-ModeReconcile -Mode IDLE -DryRun -Config $cfg
AssertEq (@($idle | Where-Object { $_ -like 'START*' }).Count) 0 "IDLE ne demarre rien"
$dev = Invoke-ModeReconcile -Mode DEV -DryRun -Config $cfg
Assert ($dev -contains 'START dev') "DEV demarre le dev"
Assert (-not ($dev -contains 'START arena')) "DEV ne demarre pas l'arene"
$play = Invoke-ModeReconcile -Mode PLAY -DryRun -Config $cfg
Assert (($play -contains 'START game') -and ($play -contains 'START play')) "PLAY demarre jeu + agent"
$prev = Get-DownHereMode -Config $cfg
AssertEq (Set-DownHereMode -Mode PLAY -Config $cfg) "PLAY" "Set-DownHereMode PLAY"
AssertEq (Get-DownHereMode -Config $cfg) "PLAY" "Get-DownHereMode = PLAY"
Set-DownHereMode -Mode $prev -Config $cfg | Out-Null   # restaure
$threw = $false; try { Set-DownHereMode -Mode 'BOGUS' -Config $cfg } catch { $threw = $true }
Assert $threw "mode invalide rejete"

Write-Host "== State ==" -ForegroundColor Cyan
$st = Get-DownHereState -Config $cfg
Assert ($null -ne $st.mode) "State.mode present"
Assert ($null -ne $st.roadmap) "State.roadmap present"
Assert ($st.agents.Keys -contains 'dev') "State.agents.dev present"

Write-Host "== Parse de tous les scripts ==" -ForegroundColor Cyan
$bad = 0
Get-ChildItem (Join-Path $PSScriptRoot '..') -Filter *.ps1 -Recurse | ForEach-Object {
    $e = $null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e) | Out-Null
    if ($e) { $bad++; Write-Host "    parse FAIL $($_.Name)" -ForegroundColor Red }
}
Assert ($bad -eq 0) "tous les scripts parsent"

Write-Host ""
Write-Host "RESULTAT: $script:pass OK, $script:fail echec(s)" -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $script:fail
