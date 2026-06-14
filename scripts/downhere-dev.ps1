# DOWN HERE — Chat dev local (Godot/C#)
# Chat interactif avec le LLM local pour poser des questions de dev.
#
# Architecture (voir docs/DOWN_HERE_DESIGN.md §5): le cerveau LLM est
# `llama-server` (llama.cpp ROCm) DANS WSL, sur http://localhost:1234.
# PAS LM Studio (qui squatte ce port + la VRAM). Ce script NE lance RIEN :
# il parle au serveur deja debout. Si le serveur est absent, lance la pile :
#     powershell -File scripts/startup_all.ps1

$ErrorActionPreference = 'Stop'
$api = 'http://localhost:1234'

$Host.UI.RawUI.WindowTitle = 'DOWN HERE — Dev'
Write-Host ''
Write-Host '  ===  DOWN HERE — Chat dev local  ===' -ForegroundColor Cyan
Write-Host ''

# Decouvre le modele servi par llama-server (le champion couronne par l'arene).
# On n'impose aucun modele : on utilise celui que le serveur expose deja.
function Get-ServedModel {
    try {
        $r = Invoke-RestMethod -Uri "$api/v1/models" -TimeoutSec 4
        $id = $r.data[0].id
        if ($id) { return $id }
    } catch {}
    return $null
}

$model = Get-ServedModel
if (-not $model) {
    Write-Host '  [!] Aucun serveur LLM sur http://localhost:1234.' -ForegroundColor Red
    Write-Host '      Lance la pile (llama-server WSL) :' -ForegroundColor Yellow
    Write-Host '          powershell -File scripts/startup_all.ps1' -ForegroundColor Yellow
    Write-Host '      (Surtout PAS LM Studio : il squatte le port 1234.)' -ForegroundColor DarkYellow
    Read-Host '  (Entree pour quitter)'
    exit 1
}

Write-Host "  [OK] Modele servi : $model" -ForegroundColor Green
Write-Host '  Tape ta demande (Godot/C#). "exit" pour quitter.' -ForegroundColor Green
Write-Host ''

$system = @{
    role    = 'system'
    content = "Tu es le dev Godot du projet DOWN HERE (base Thrive, Godot 4.6 mono, C#). Tu reponds en francais, concis, code pret a coller. Tu connais l'ECS Arch, les autoloads Thrive, et les conventions du repo."
}
$history = [System.Collections.ArrayList]@($system)

while ($true) {
    Write-Host 'toi> ' -ForegroundColor Cyan -NoNewline
    $q = Read-Host
    if ([string]::IsNullOrWhiteSpace($q)) { continue }
    if ($q -in @('exit', 'quit', 'q')) { break }

    [void]$history.Add(@{ role = 'user'; content = $q })
    $body = @{ model = $model; messages = $history; temperature = 0.3; stream = $false } | ConvertTo-Json -Depth 8

    try {
        $resp = Invoke-RestMethod -Uri "$api/v1/chat/completions" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 300
        $answer = $resp.choices[0].message.content
        [void]$history.Add(@{ role = 'assistant'; content = $answer })
        Write-Host ''
        Write-Host 'dev> ' -ForegroundColor Green -NoNewline
        Write-Host $answer
        Write-Host ''
    } catch {
        Write-Host "  [!] Erreur API: $_" -ForegroundColor Red
    }
}

Write-Host '  A bientot.' -ForegroundColor Cyan
