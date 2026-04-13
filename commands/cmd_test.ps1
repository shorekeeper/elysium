#Requires -Version 7.0
# cmd_test.ps1 [all|e2e|internal|<testname>]
param([Parameter(ValueFromRemainingArguments)][string[]]$RawArgs)

Get-ChildItem (Join-Path $PSScriptRoot "_*.ps1") | ForEach-Object { . $_.FullName }

$suite = if ($RawArgs.Count -gt 0) { $RawArgs[0] } else { "all" }

Write-CmdHeader "test" "[$suite]"

$compiler = Find-Compiler
if (-not $compiler) {
    Write-Host "    elysiumc.exe not found, run 'build' first" -ForegroundColor Red
    return
}

function Run-E2E {
    param([string]$Filter = "")
    $testDir = Join-Path $global:ProjectRoot "tests\e2e"
    if (-not (Test-Path $testDir)) {
        Write-Host "    tests\e2e\ not found" -ForegroundColor Yellow
        return @{ Passed = 0; Failed = 0; Skipped = 0 }
    }

    $elyFiles = Get-ChildItem $testDir -Filter "*.ely"
    if ($Filter) {
        $elyFiles = $elyFiles | Where-Object { $_.BaseName -match $Filter }
    }

    $pass = 0; $fail = 0; $skip = 0

    foreach ($ely in $elyFiles) {
        $name = $ely.BaseName
        $expected = Join-Path $testDir "$name.expected"
        $outExe = Join-Path $testDir "$name.exe"
        $gotFile = Join-Path $testDir "$name.got"

        if (-not (Test-Path $expected)) {
            Write-Host "    [SKIP] $name (no .expected)" -ForegroundColor Yellow
            $skip++
            continue
        }

        Write-Host -NoNewline "    $name ... " -ForegroundColor White

        # compile
        $compOut = & $compiler $ely.FullName -o $outExe 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "COMPILE FAIL" -ForegroundColor Red
            $fail++
            continue
        }

        # run
        $runOut = & $outExe 2>&1 | Out-String
        $runOut | Set-Content $gotFile -NoNewline

        # compare (whitespace-tolerant)
        $expText = (Get-Content $expected -Raw).Trim()
        $gotText = $runOut.Trim()

        if ($gotText -eq $expText) {
            Write-Host "PASS" -ForegroundColor Green
            $pass++
            Remove-Item $outExe -Force -ErrorAction SilentlyContinue
            Remove-Item $gotFile -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "FAIL" -ForegroundColor Red
            $fail++
            Write-Host "      expected: $($expText.Substring(0, [math]::Min(80, $expText.Length)))" -ForegroundColor DarkGray
            Write-Host "      got:      $($gotText.Substring(0, [math]::Min(80, $gotText.Length)))" -ForegroundColor DarkRed
        }
    }

    return @{ Passed = $pass; Failed = $fail; Skipped = $skip }
}

function Run-Internal {
    $exe = Join-Path $global:ProjectRoot "tests\test_internals.exe"
    if (-not (Test-Path $exe)) {
        Write-Host "    test_internals.exe not found, building..." -ForegroundColor Yellow

        # build it
        $intSrcs = @(
            "libely\vmem", "libely\arena", "libely\lexer", "libely\types",
            "libely\symtab", "libely\typetab"
        )
        $objs = @()
        foreach ($src in $intSrcs) {
            $name = Split-Path $src -Leaf
            $r = Invoke-Nasm "$src.asm" "$name.obj"
            if (-not $r.Success) {
                Write-Host "    failed to build $src.asm" -ForegroundColor Red
                return @{ Passed = 0; Failed = 1; Skipped = 0 }
            }
            $objs += "$name.obj"
        }
        $r = Invoke-Nasm "tests\test_internals.asm" "test_internals.obj"
        if (-not $r.Success) {
            Write-Host "    failed to build test_internals.asm" -ForegroundColor Red
            return @{ Passed = 0; Failed = 1; Skipped = 0 }
        }
        $objs += "test_internals.obj"

        $linkArgs = @("/nologo", "/subsystem:console", "/entry:_start", "/LARGEADDRESSAWARE:NO") +
            $objs + @("kernel32.lib", "/OUT:tests\test_internals.exe")
        & link @linkArgs 2>&1 | Out-Null
        Get-ChildItem "*.obj" -ErrorAction SilentlyContinue | Remove-Item -Force
    }

    Write-Host "    running internal tests..." -ForegroundColor DarkGray
    $output = & $exe 2>&1
    $pass = 0; $fail = 0
    foreach ($line in $output) {
        $str = "$line"
        if ($str -match "\[PASS\]") {
            Write-Host "    $str" -ForegroundColor Green
            $pass++
        } elseif ($str -match "\[FAIL\]") {
            Write-Host "    $str" -ForegroundColor Red
            $fail++
        } else {
            Write-Host "    $str" -ForegroundColor DarkGray
        }
    }
    return @{ Passed = $pass; Failed = $fail; Skipped = 0 }
}

switch ($suite) {
    "e2e" {
        $r = Run-E2E
        Write-Host ""
        Write-Host "    E2E: $($r.Passed) passed, $($r.Failed) failed, $($r.Skipped) skipped" -ForegroundColor $(if ($r.Failed -gt 0) { "Red" } else { "Green" })
    }
    "internal" {
        $r = Run-Internal
        Write-Host ""
        Write-Host "    Internal: $($r.Passed) passed, $($r.Failed) failed" -ForegroundColor $(if ($r.Failed -gt 0) { "Red" } else { "Green" })
    }
    "all" {
        Write-Host "  E2E tests" -ForegroundColor Cyan
        $e2e = Run-E2E
        Write-Host ""
        Write-Host "  Internal tests" -ForegroundColor Cyan
        $int = Run-Internal
        Write-Host ""
        $tp = $e2e.Passed + $int.Passed
        $tf = $e2e.Failed + $int.Failed
        $ts = $e2e.Skipped + $int.Skipped
        Write-Host "    Total: $tp passed, $tf failed, $ts skipped" -ForegroundColor $(if ($tf -gt 0) { "Red" } else { "Green" })
    }
    default {
        # try as individual test name filter
        $r = Run-E2E $suite
        if ($r.Passed + $r.Failed + $r.Skipped -eq 0) {
            Write-Host "    no tests matching '$suite'" -ForegroundColor Yellow
        } else {
            Write-Host ""
            Write-Host "    $($r.Passed) passed, $($r.Failed) failed" -ForegroundColor $(if ($r.Failed -gt 0) { "Red" } else { "Green" })
        }
    }
}