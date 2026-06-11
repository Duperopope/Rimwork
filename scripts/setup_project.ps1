#!/usr/bin/env powershell
# Script: setup_project.ps1
# Automated setup: clone repos, create project, run test

param(
    [switch]$QuickTest = $false
)

$ErrorActionPreference = "Stop"

Write-Host "RimWorld Lab - Automated Setup" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

$workDir = Split-Path $MyInvocation.MyCommand.Path

# Step 1: Clone decompiled repo
Write-Host "[1/5] Cloning RimWorldDecompiled..." -ForegroundColor Yellow
if (Test-Path "$workDir/reference/rimworld-decompiled/.git") {
    Write-Host "  ✓ Already cloned" -ForegroundColor Green
} else {
    try {
        git clone https://github.com/Chillu1/RimWorldDecompiled.git "$workDir/reference/rimworld-decompiled" | Out-Null
        Write-Host "  ✓ Cloned successfully" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠ Failed: $_" -ForegroundColor Yellow
        Write-Host "    (You can clone manually later)" -ForegroundColor Gray
    }
}

Write-Host ""

# Step 2: Create C# project
Write-Host "[2/5] Creating C# project..." -ForegroundColor Yellow
if (Test-Path "$workDir/src/RimWorldLab/RimWorldLab.csproj") {
    Write-Host "  ✓ Project already exists" -ForegroundColor Green
} else {
    try {
        mkdir -p "$workDir/src/RimWorldLab" -ErrorAction SilentlyContinue | Out-Null
        Push-Location "$workDir/src/RimWorldLab"
        
        # Create project
        dotnet new console -f net8.0 | Out-Null
        
        # Add git stuff
        dotnet new gitignore | Out-Null
        
        Pop-Location
        Write-Host "  ✓ Project created" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Failed: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# Step 3: Create minimal Program.cs
Write-Host "[3/5] Creating test Program.cs..." -ForegroundColor Yellow
$programCs = @"
using System;
using System.Diagnostics;

class Program
{
    static void Main()
    {
        Console.WriteLine("╔════════════════════════════════════╗");
        Console.WriteLine("║  RimWorld Lab - Tick Loop Test     ║");
        Console.WriteLine("╚════════════════════════════════════╝");
        Console.WriteLine("");

        const int TARGET_TICKS_PER_SEC = 60;
        const int TARGET_TICK_MS = 1000 / TARGET_TICKS_PER_SEC;

        var sw = Stopwatch.StartNew();
        int ticks = 0;
        int targetMs = 5000; // 5 second test

        Console.WriteLine($"Target: {TARGET_TICKS_PER_SEC} ticks/sec");
        Console.WriteLine($"Running for {targetMs}ms...");
        Console.WriteLine("");

        while (sw.ElapsedMilliseconds < targetMs)
        {
            OnTick(ticks);
            ticks++;

            // Maintain tick rate
            int elapsed = (int)(sw.ElapsedMilliseconds % TARGET_TICK_MS);
            int sleep = TARGET_TICK_MS - elapsed;
            if (sleep > 0)
                System.Threading.Thread.Sleep(sleep);

            if (ticks % 100 == 0)
                Console.WriteLine($"  Tick {ticks} @ {sw.ElapsedMilliseconds}ms");
        }

        sw.Stop();

        Console.WriteLine("");
        Console.WriteLine("Results:");
        Console.WriteLine($"  Total ticks: {ticks}");
        Console.WriteLine($"  Time: {sw.ElapsedMilliseconds}ms");
        Console.WriteLine($"  Rate: {(double)ticks / (sw.ElapsedMilliseconds / 1000.0):F1} ticks/sec");
        Console.WriteLine($"  Memory: {GC.GetTotalMemory(false) / 1024 / 1024} MB");
        Console.WriteLine("");
        
        if ((double)ticks / (sw.ElapsedMilliseconds / 1000.0) >= 55)
            Console.WriteLine("✓ Tick loop is stable!" );
        else
            Console.WriteLine("⚠ Tick loop may be unstable");
    }

    static void OnTick(int tick)
    {
        // Placeholder for game logic
    }
}
"@

$programPath = "$workDir/src/RimWorldLab/Program.cs"
$programCs | Set-Content $programPath
Write-Host "  ✓ Created Program.cs" -ForegroundColor Green

Write-Host ""

# Step 4: Build
Write-Host "[4/5] Building project..." -ForegroundColor Yellow
try {
    Push-Location "$workDir/src/RimWorldLab"
    dotnet build -c Release 2>&1 | Out-Null
    Pop-Location
    Write-Host "  ✓ Build succeeded" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Build failed: $_" -ForegroundColor Yellow
    Write-Host "    (You can build manually: cd src/RimWorldLab && dotnet build)" -ForegroundColor Gray
}

Write-Host ""

# Step 5: Test
Write-Host "[5/5] Running test..." -ForegroundColor Yellow
try {
    Push-Location "$workDir/src/RimWorldLab"
    dotnet run -c Release 2>&1
    Pop-Location
} catch {
    Write-Host "  ⚠ Run failed: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "✓ Setup complete!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Test LM Studio:"
Write-Host "     & .\scripts\test_lm_api.ps1"
Write-Host ""
Write-Host "  2. Ask LLM to expand:"
Write-Host "     & .\scripts\llm_call.ps1 -UserMessage 'Add Map and Pawn classes'"
Write-Host ""
Write-Host "  3. Or read START_HERE.md for instructions"
Write-Host ""
