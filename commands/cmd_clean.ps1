#Requires -Version 7.0
# cmd_clean.ps1 [all|obj|exe|tests]
param([string]$What = "all")

Get-ChildItem (Join-Path $PSScriptRoot "_*.ps1") | ForEach-Object { . $_.FullName }

Write-CmdHeader "clean" "[$What]"

function Clean-Obj {
    $count = (Get-ChildItem "*.obj" -ErrorAction SilentlyContinue).Count
    Get-ChildItem "*.obj" -ErrorAction SilentlyContinue | Remove-Item -Force
    Write-Host "    removed $count .obj file(s)" -ForegroundColor Green
}

function Clean-TestArtifacts {
    $testDir = Join-Path $global:ProjectRoot "tests\e2e"
    $count = 0
    if (Test-Path $testDir) {
        $exes = Get-ChildItem $testDir -Filter "*.exe" -ErrorAction SilentlyContinue
        $gots = Get-ChildItem $testDir -Filter "*.got" -ErrorAction SilentlyContinue
        $count = $exes.Count + $gots.Count
        $exes | Remove-Item -Force
        $gots | Remove-Item -Force
    }
    $intExe = Join-Path $global:ProjectRoot "tests\test_internals.exe"
    if (Test-Path $intExe) { Remove-Item $intExe -Force; $count++ }
    Write-Host "    removed $count test artifact(s)" -ForegroundColor Green
}

function Clean-Exe {
    $removed = 0
    foreach ($f in @("elysiumc.exe", "elydump.exe")) {
        if (Test-Path $f) { Remove-Item $f -Force; $removed++ }
    }
    Write-Host "    removed $removed compiler exe(s)" -ForegroundColor Green
}

switch ($What) {
    "obj"   { Clean-Obj }
    "exe"   { Clean-Exe }
    "tests" { Clean-TestArtifacts }
    "all"   { Clean-Obj; Clean-Exe; Clean-TestArtifacts }
    default { Write-Host "    unknown: $What (use all, obj, exe, tests)" -ForegroundColor Red }
}