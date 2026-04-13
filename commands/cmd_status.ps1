#Requires -Version 7.0
# cmd_status.ps1 - git and build status
param()

Get-ChildItem (Join-Path $PSScriptRoot "_*.ps1") | ForEach-Object { . $_.FullName }

Write-CmdHeader "status" ""

# git
$hasGit = $false
try { git rev-parse --git-dir 2>$null | Out-Null; $hasGit = ($LASTEXITCODE -eq 0) } catch {}

if ($hasGit) {
    $branch = (git branch --show-current 2>&1) -join ""
    $dirty = @(git status --porcelain 2>&1).Count
    $lastCommit = git log -1 --format="%h %s (%cr)" 2>&1

    Write-Host "    Git" -ForegroundColor White
    Write-Host "      branch:  $branch" -ForegroundColor Gray
    Write-Host "      dirty:   $dirty file(s)" -ForegroundColor $(if ($dirty -gt 0) { "Yellow" } else { "Green" })
    Write-Host "      last:    $lastCommit" -ForegroundColor DarkGray
    Write-Host ""
}

# build status
Write-Host "    Build" -ForegroundColor White
$comp = Find-Compiler
if ($comp) {
    $age = [math]::Round(((Get-Date) - (Get-Item $comp).LastWriteTime).TotalMinutes)
    Write-Host "      elysiumc.exe:  built (${age}m ago)" -ForegroundColor Green
} else {
    Write-Host "      elysiumc.exe:  not built" -ForegroundColor Yellow
}