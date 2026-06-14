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
. (Join-Path $lib 'WorldModel.ps1')
. (Join-Path $lib 'Policy.ps1')
. (Join-Path $lib 'Chat.ps1')
. (Join-Path $PSScriptRoot '..\site_gen.ps1')     # pour Get-ChatPageHtml
. (Join-Path $PSScriptRoot '..\self_evolve.ps1')  # moteur d'auto-modification
$cfg = Get-DownHereConfig

Write-Host "== Config ==" -ForegroundColor Cyan
Assert (Test-Path $cfg.Root) "Root existe"
Assert (Test-Path $cfg.Paths.ActiveGame) "ActiveGame existe"
Assert ($cfg.Llm.BaseUrl -like 'http*1234') "Llm.BaseUrl = port 1234"
AssertEq $cfg.Modes.Count 5 "5 modes (IDLE/DEV/PLAY/ARENA/EVOLVE)"

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

Write-Host "== World model + Policy (RSI) ==" -ForegroundColor Cyan
$pol = Get-Policy -Config $cfg
Assert ($pol.arms.Count -ge 2) "policy: au moins 2 bras"
$sel = Select-PolicyArm -Policy $pol -Config $cfg
Assert ($sel.Index -ge 0 -and $sel.Index -lt $pol.arms.Count) "policy: bras valide selectionne"
$before = [int]$pol.n[$sel.Index]
$pol = Update-PolicyReward -Index $sel.Index -Reward 1.0 -Policy $pol -Config $cfg
AssertEq ([int]$pol.n[$sel.Index]) ($before + 1) "policy: compteur incremente"
if (Test-WorldModelReady -Config $cfg) {
    $pSafe = Get-PatchSuccessProbability -Search '"v": 1.0' -Replace '"v": 1.5' -Ext json -Config $cfg
    $pRisk = Get-PatchSuccessProbability -Search 'void F(){}' -Replace 'void F(){ _x.NewCall(); if(a){' -Ext cs -Config $cfg
    if ($null -ne $pSafe -and $null -ne $pRisk) {
        Assert ($pSafe -ge 0 -and $pSafe -le 1) "WM: proba dans [0,1]"
        Assert ($pSafe -gt $pRisk) "WM: patch sur > patch risque (ranking)"
    } else {
        Write-Host "  (predict.py a renvoye NA, tolere comme le fait le systeme)" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "  (world model non entraine -> tests WM ignores, OK sur clone frais)" -ForegroundColor DarkYellow
}

Write-Host "== Conversation (memoire persistante) ==" -ForegroundColor Cyan
Assert ((Get-ChatPageHtml) -match 'Conversation' -and (Get-ChatPageHtml) -match '/chat/send') "chat: page rendue"
# Config temporaire -> ne pollue pas la vraie memoire de l'agent.
$tmp = Join-Path $env:TEMP "dh_chat_test_$PID"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$tcfg = Get-DownHereConfig; $tcfg.Paths.Logs = $tmp
Add-ChatMemory -Fact "fait-test-unitaire" -Config $tcfg
Assert ((Get-ChatMemories -Config $tcfg) -contains "fait-test-unitaire") "chat: memoire persistee + relue"
Add-ChatTurn -Role 'user' -Content 'ping-test' -Config $tcfg
Assert (@(Get-ChatHistory -Last 5 -Config $tcfg | Where-Object { $_.content -eq 'ping-test' }).Count -ge 1) "chat: historique persiste + relu"
Assert ((Build-ChatSystemPrompt -Config $tcfg) -match 'fait-test-unitaire') "chat: la memoire est injectee dans le prompt (se souvient)"
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "== Auto-modification (self_evolve, garde-fous) ==" -ForegroundColor Cyan
Assert (Test-SelfEditAllowed -FileName 'site_gen.ps1') "self: site_gen editable (allowlist)"
Assert (-not (Test-SelfEditAllowed -FileName 'Config.ps1')) "self: Config PROTEGE (frein)"
Assert (-not (Test-SelfEditAllowed -FileName 'run-tests.ps1')) "self: harnais PROTEGE (frein)"
Assert (-not (Test-SelfEditAllowed -FileName 'self_evolve.ps1')) "self: le moteur ne s'edite pas lui-meme"
Assert (Test-Path (Update-SelfIndex -Config $cfg)) "self: INDEX.md auto-genere"
$sgPath = Join-Path $cfg.Paths.Scripts 'site_gen.ps1'
$preEdit = Get-Content $sgPath -Raw
$g = Invoke-SelfEdit -Target 'site_gen.ps1' -Search 'function Get-ChatPageHtml {' -Replace 'function Get-ChatPageHtml {  # (auto-test)' -Why 'test-harnais' -SkipHarness -Config $cfg
Assert ($g.ok) "self: edition SAINE acceptee (patch produit)"
Assert ((Get-Content $sgPath -Raw) -eq $preEdit) "self: fichier restaure a l'identique apres edition"
$b = Invoke-SelfEdit -Target 'site_gen.ps1' -Search 'function Get-ChatPageHtml {' -Replace 'function Get-ChatPageHtml ({{ casse' -Why 'test-harnais' -SkipHarness -Config $cfg
Assert (-not $b.ok) "self: edition CASSEE rejetee (revert auto)"
Assert ((Invoke-ModeReconcile -Mode EVOLVE -DryRun -Config $cfg) -contains 'START evolve') "self: mode EVOLVE lance l'auto-modif"

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
