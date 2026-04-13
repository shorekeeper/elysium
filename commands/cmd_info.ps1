#Requires -Version 7.0
# cmd_info.ps1 - project statistics
param()

Get-ChildItem (Join-Path $PSScriptRoot "_*.ps1") | ForEach-Object { . $_.FullName }

Write-CmdHeader "info" "project"

# source stats
$stats = Get-AsmFileStats
Write-Host "    Source Files" -ForegroundColor White
Write-Host "      .asm + .inc files: $($stats.Files)" -ForegroundColor Gray
Write-Host "      total lines:       $($stats.Total)" -ForegroundColor Gray
Write-Host "      code lines:        $($stats.Code)" -ForegroundColor Gray
Write-Host "      comment lines:     $($stats.Comments)" -ForegroundColor Gray
Write-Host ""

# test stats
$testDir = Join-Path $global:ProjectRoot "tests\e2e"
$testCount = 0
if (Test-Path $testDir) {
    $testCount = (Get-ChildItem $testDir -Filter "*.ely").Count
}
Write-Host "    Tests" -ForegroundColor White
Write-Host "      E2E test files:    $testCount" -ForegroundColor Gray
Write-Host ""

# compiler binary
Write-Host "    Build" -ForegroundColor White
$comp = Find-Compiler
if ($comp) {
    $size = [math]::Round((Get-Item $comp).Length / 1024, 1)
    Write-Host "      elysiumc.exe:      ${size} KB" -ForegroundColor Gray
} else {
    Write-Host "      elysiumc.exe:      not built" -ForegroundColor Yellow
}

$dump = Find-DumpTool
if ($dump) {
    $size = [math]::Round((Get-Item $dump).Length / 1024, 1)
    Write-Host "      elydump.exe:       ${size} KB" -ForegroundColor Gray
} else {
    Write-Host "      elydump.exe:       not built" -ForegroundColor DarkGray
}
Write-Host ""

# toolchain
Write-Host "    Toolchain" -ForegroundColor White
$nasmVer = (nasm -v 2>&1) -join ""
Write-Host "      NASM:              $nasmVer" -ForegroundColor Gray
try {
    $linkVer = (link 2>&1 | Select-Object -First 1) -replace "Microsoft.*Linker Version ", "link "
    Write-Host "      Linker:            $linkVer" -ForegroundColor Gray
} catch {
    Write-Host "      Linker:            not found" -ForegroundColor Yellow
}