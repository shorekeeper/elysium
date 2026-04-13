# _common.ps1 - shared helpers for all commands

$script:AnsiE = [char]0x1b

function Format-Duration {
    param([double]$Ms)
    if ($Ms -lt 1000) { return "$([math]::Round($Ms))ms" }
    if ($Ms -lt 60000) { return "$([math]::Round($Ms / 1000, 1))s" }
    $m = [math]::Floor($Ms / 60000)
    $s = [math]::Round(($Ms % 60000) / 1000, 1)
    return "${m}m ${s}s"
}

function Write-CmdHeader {
    param([string]$Name, [string]$Desc)
    Write-Host ""
    Write-Host "  $Name" -ForegroundColor Cyan -NoNewline
    Write-Host " $Desc" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-SubStep {
    param([string]$Label, [string]$Status, [string]$Detail = "")
    $color = switch ($Status) {
        "OK"   { "Green" }
        "FAIL" { "Red" }
        "SKIP" { "Yellow" }
        "WARN" { "Yellow" }
        default { "Gray" }
    }
    Write-Host -NoNewline "    $Label " -ForegroundColor White
    Write-Host -NoNewline $Status -ForegroundColor $color
    if ($Detail) { Write-Host " $Detail" -ForegroundColor DarkGray }
    else { Write-Host "" }
}

function Hide-Cursor { Write-Host -NoNewline "$script:AnsiE[?25l" }
function Show-Cursor { Write-Host -NoNewline "$script:AnsiE[?25h" }

# progress bar: renders inline, overwrites itself
function Write-Progress-Inline {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Label,
        [string]$Status = "",
        [int]$BarWidth = 25
    )
    $e = $script:AnsiE
    $pct = if ($Total -gt 0) { [math]::Min(100, [math]::Round($Current / $Total * 100)) } else { 0 }
    $filled = if ($Total -gt 0) { [int][math]::Round($Current / $Total * $BarWidth) } else { 0 }
    $filled = [int][math]::Min($filled, $BarWidth)
    $empty = [int]($BarWidth - $filled)

    $barColor = if ($pct -ge 100) { "32" } elseif ($pct -ge 50) { "33" } else { "36" }
    $filledStr = if ($filled -gt 0) { [string]::new([char]0x2501, $filled) } else { "" }
    $emptyStr = if ($empty -gt 0) { [string]::new([char]0x2500, $empty) } else { "" }
    $bar = "$e[${barColor}m$filledStr$e[2m$emptyStr$e[0m"

    $line = "    [$bar] $Current/$Total $Status"
    Write-Host -NoNewline "`r$e[2K$line"
}

# finish progress bar with final message
function Complete-Progress {
    param([string]$Message, [string]$Color = "Green")
    $e = $script:AnsiE
    Write-Host -NoNewline "`r$e[2K"
    Write-Host "    $Message" -ForegroundColor $Color
}

function Get-AsmFileStats {
    $files = @()
    $dirs = @("libely", "compiler")
    foreach ($d in $dirs) {
        $p = Join-Path $global:ProjectRoot $d
        if (Test-Path $p) {
            $files += Get-ChildItem -Path $p -Filter "*.asm" -ErrorAction SilentlyContinue
        }
    }
    $incFiles = Get-ChildItem -Path $global:ProjectRoot -Filter "*.inc" -ErrorAction SilentlyContinue
    if ($incFiles) { $files += $incFiles }
    $totalLines = 0; $codeLines = 0; $commentLines = 0
    foreach ($f in $files) {
        $content = Get-Content $f.FullName -ErrorAction SilentlyContinue
        if (-not $content) { continue }
        $totalLines += $content.Count
        foreach ($l in $content) {
            $trimmed = $l.Trim()
            if ($trimmed -match "^\s*;") { $commentLines++ }
            elseif ($trimmed) { $codeLines++ }
        }
    }
    return [PSCustomObject]@{
        Files    = $files.Count
        Total    = $totalLines
        Code     = $codeLines
        Comments = $commentLines
    }
}

function Invoke-Nasm {
    param([string]$Source, [string]$Output)
    $srcFull = Join-Path $global:ProjectRoot $Source
    $outFull = Join-Path $global:ProjectRoot $Output
    $incPath = "$global:ProjectRoot\"
    $result = & nasm -f win64 "-I$incPath" $srcFull -o $outFull 2>&1
    $exitCode = $LASTEXITCODE
    $lines = @($result | ForEach-Object { "$_" })
    $warnings = @($lines | Where-Object { $_ -match "warning" })
    $errors = @($lines | Where-Object { $_ -match "error" })
    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output   = $lines
        Warnings = $warnings
        Errors   = $errors
        Success  = ($exitCode -eq 0)
    }
}

function Ensure-VCEnv {
    $testLink = Get-Command link.exe -ErrorAction SilentlyContinue
    if ($testLink) {
        $ver = & link.exe 2>&1 | Select-Object -First 1
        if ("$ver" -match "Microsoft") { return $true }
    }
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vsWhere)) {
        Write-Host "    Visual Studio not found" -ForegroundColor Red
        return $false
    }
    $vsPath = & $vsWhere -latest -property installationPath 2>$null
    if (-not $vsPath) {
        Write-Host "    vswhere returned nothing" -ForegroundColor Red
        return $false
    }
    $vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvarsall.bat"
    if (-not (Test-Path $vcvars)) {
        Write-Host "    vcvarsall.bat not found" -ForegroundColor Red
        return $false
    }
    $envLines = cmd.exe /c "`"$vcvars`" x64 >nul 2>&1 && set" 2>&1
    foreach ($line in $envLines) {
        if ("$line" -match "^([^=]+)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], "Process")
        }
    }
    $testLink = Get-Command link.exe -ErrorAction SilentlyContinue
    if ($testLink) {
        $ver = & link.exe 2>&1 | Select-Object -First 1
        if ("$ver" -match "Microsoft") {
            Write-Host "    VC environment loaded (x64)" -ForegroundColor DarkGray
            return $true
        }
    }
    Write-Host "    link.exe still not working after vcvars" -ForegroundColor Red
    return $false
}

function Ensure-Nasm {
    $nasm = Get-Command nasm -ErrorAction SilentlyContinue
    if ($nasm) { return $true }
    $paths = @(
        "$env:ProgramFiles\NASM",
        "${env:ProgramFiles(x86)}\NASM",
        "$env:LOCALAPPDATA\bin\NASM"
    )
    foreach ($p in $paths) {
        $exe = Join-Path $p "nasm.exe"
        if (Test-Path $exe) {
            $env:PATH = "$p;$env:PATH"
            Write-Host "    found NASM at $p" -ForegroundColor DarkGray
            return $true
        }
    }
    Write-Host "    NASM not found, install from https://nasm.us" -ForegroundColor Red
    return $false
}

function Find-Compiler {
    $exe = Join-Path $global:ProjectRoot "elysiumc.exe"
    if (Test-Path $exe) { return $exe }
    return $null
}

function Find-DumpTool {
    $exe = Join-Path $global:ProjectRoot "elydump.exe"
    if (Test-Path $exe) { return $exe }
    return $null
}