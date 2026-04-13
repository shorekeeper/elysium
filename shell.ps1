#Requires -Version 7.0

param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$DirectArgs
)

$ErrorActionPreference = "Continue"
$global:CommandCount = 0
$global:ErrorCount = 0
$global:LastResult = $null
$global:ProjectRoot = $PSScriptRoot

Set-Location $global:ProjectRoot

# load command helpers
$commandDir = Join-Path $PSScriptRoot "commands"
Get-ChildItem (Join-Path $commandDir "_*.ps1") -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

# aliases
$global:Aliases = @{
    "b"  = "build"
    "t"  = "test"
    "r"  = "run"
    "d"  = "dump"
    "c"  = "clean"
    "s"  = "status"
    "i"  = "info"
    "h"  = "help"
    "q"  = "exit"
    "!!" = "repeat"
}

function Resolve-CmdAlias {
    param([string]$Name)
    $clean = $Name.Trim().Trim([char]0)
    if ($global:Aliases.ContainsKey($clean)) { return $global:Aliases[$clean] }
    return $clean
}

function Parse-Input {
    param([string]$Line)
    $Line = $Line.Trim().Trim([char]0)
    if (-not $Line) { return $null }
    $tokens = @($Line -split '\s+' | Where-Object { $_ })
    if ($tokens.Count -eq 0) { return $null }
    $cmd = Resolve-CmdAlias ([string]$tokens[0]).ToLower()
    $cmdArgs = if ($tokens.Count -gt 1) { @($tokens[1..($tokens.Count - 1)]) } else { @() }
    return @{ Command = $cmd; Args = $cmdArgs; Raw = $Line }
}

function Write-Prompt {
    $errTag = ($global:ErrorCount -gt 0) ? " $($global:ErrorCount)err" : ""
    $baseColor = ($global:ErrorCount -gt 0) ? "Red" : "Cyan"
    Write-Host -NoNewline "ely" -ForegroundColor $baseColor
    if ($errTag) { Write-Host -NoNewline $errTag -ForegroundColor Red }
    Write-Host -NoNewline "> " -ForegroundColor DarkGray
}

function Invoke-ElyCommand {
    param([string]$Command, [string[]]$CmdArgs)
    $Command = $Command.Trim().Trim([char]0)
    if (-not $Command) { return }
    $scriptPath = Join-Path $commandDir "cmd_$Command.ps1"
    if (-not (Test-Path $scriptPath)) {
        Write-Host "  unknown command: $Command" -ForegroundColor Red
        Write-Host "  type 'help' for available commands" -ForegroundColor DarkGray
        return
    }
    $global:CommandCount++
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $scriptPath @CmdArgs
    } catch {
        Write-Host "  command error: $($_.Exception.Message)" -ForegroundColor Red
        $global:ErrorCount++
    }
    $sw.Stop()
    $ms = $sw.Elapsed.TotalMilliseconds
    $elapsed = Format-Duration $ms
    Write-Host "  $elapsed" -ForegroundColor DarkGray
}

function Show-Banner {
    Write-Host ""
    Write-Host "  Elysium Compiler Shell" -ForegroundColor Cyan
    Write-Host "  type 'help' for commands, 'q' to quit" -ForegroundColor DarkGray
    Write-Host ""
}

# single command mode
if ($DirectArgs -and $DirectArgs.Count -gt 0) {
    $parsed = Parse-Input ($DirectArgs -join " ")
    if ($parsed) { Invoke-ElyCommand $parsed.Command $parsed.Args }
    exit $LASTEXITCODE
}

# interactive REPL
Show-Banner
$lastLine = ""

while ($true) {
    Write-Prompt
    $line = $null
    try { $line = Read-Host } catch { Write-Host ""; continue }
    if (-not $line) { continue }
    $line = $line.Trim()
    if (-not $line) { continue }
    $parsed = Parse-Input $line
    if (-not $parsed) { continue }

    switch ($parsed.Command) {
        "exit" {
            Write-Host "  $($global:CommandCount) commands, $($global:ErrorCount) errors" -ForegroundColor DarkGray
            Write-Host ""
            exit 0
        }
        "repeat" {
            if ($lastLine) {
                Write-Host "  repeating: $lastLine" -ForegroundColor DarkGray
                $p = Parse-Input $lastLine
                if ($p) { Invoke-ElyCommand $p.Command $p.Args }
            } else {
                Write-Host "  nothing to repeat" -ForegroundColor Yellow
            }
            continue
        }
        default {
            $lastLine = $line
            Invoke-ElyCommand $parsed.Command $parsed.Args
        }
    }
    Write-Host ""
}