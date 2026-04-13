#Requires -Version 7.0
# cmd_run.ps1 <file.ely> [-o output.exe] [--keep]
# compile a .ely file and run the resulting exe
param([Parameter(ValueFromRemainingArguments)][string[]]$RawArgs)

Get-ChildItem (Join-Path $PSScriptRoot "_*.ps1") | ForEach-Object { . $_.FullName }

$inputFile = ""
$outputFile = ""
$keep = $false

for ($i = 0; $i -lt $RawArgs.Count; $i++) {
    switch ($RawArgs[$i]) {
        "-o"     { $i++; if ($i -lt $RawArgs.Count) { $outputFile = $RawArgs[$i] } }
        "--keep" { $keep = $true }
        default  { if (-not $inputFile) { $inputFile = $RawArgs[$i] } }
    }
}

if (-not $inputFile) {
    # default to demo.ely
    $inputFile = "demo.ely"
}

if (-not (Test-Path $inputFile)) {
    Write-Host "  file not found: $inputFile" -ForegroundColor Red
    return
}

if (-not $outputFile) {
    $outputFile = [System.IO.Path]::ChangeExtension($inputFile, ".exe")
}

Write-CmdHeader "run" "$inputFile -> $outputFile"

$compiler = Find-Compiler
if (-not $compiler) {
    Write-Host "    elysiumc.exe not found, run 'build' first" -ForegroundColor Red
    return
}

# compile
Write-Host -NoNewline "    compiling ... " -ForegroundColor White
$compOut = & $compiler $inputFile -o $outputFile 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "FAIL" -ForegroundColor Red
    $compOut | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkRed }
    return
}
Write-Host "OK" -ForegroundColor Green

# run
Write-Host "    running $outputFile" -ForegroundColor DarkGray
Write-Host ""
& ".\$outputFile" 2>&1 | ForEach-Object { Write-Host "  $_" }
$exitCode = $LASTEXITCODE
Write-Host ""
Write-Host "    exit code: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Red" })

# cleanup unless --keep
if (-not $keep -and (Test-Path $outputFile)) {
    Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
}