#Requires -Version 7.0
# cmd_build.ps1 [all|compiler|internals|dump] - build targets
param([Parameter(ValueFromRemainingArguments)][string[]]$RawArgs)

Get-ChildItem (Join-Path $PSScriptRoot "_*.ps1") | ForEach-Object { . $_.FullName }

$target = if ($RawArgs.Count -gt 0) { ([string]$RawArgs[0]).ToLower() } else { "all" }

Write-CmdHeader "build" "[$target]"

if (-not (Ensure-Nasm)) { return }
if (-not (Ensure-VCEnv)) { return }

# source file lists
$compilerSrcs = @(
    "libely\vmem", "libely\arena", "libely\lexer", "libely\parser",
    "libely\frontend", "libely\types", "libely\symtab", "libely\emit",
    "libely\codegen_rt", "libely\codegen_expr", "libely\codegen_stmt",
    "libely\codegen_func", "libely\backend", "libely\ir", "libely\lower",
    "libely\x86enc", "libely\pe64", "libely\typetab", "libely\checker",
    "libely\diagnostic",
    "libely\parser_ext", "libely\lower_ext", "libely\x86enc_ext", "libely\ssa_ir",
    "libely\ssa_lift", "libely\ssa_cfg"
)

$internalSrcs = @(
    "libely\vmem", "libely\arena", "libely\lexer", "libely\types",
    "libely\symtab", "libely\typetab"
)

$dumpSrcs = $compilerSrcs  # dump tool uses all libely modules

# assemble a list of .asm files, show progress bar, return obj paths or $null on failure
function Build-AsmFiles {
    param([string[]]$Sources, [string]$Label)
    $objs = @()
    $total = $Sources.Count
    $errors = @()
    $warnCount = 0

    Hide-Cursor
    for ($i = 0; $i -lt $total; $i++) {
        $src = $Sources[$i]
        $name = Split-Path $src -Leaf
        $objPath = Join-Path $global:ProjectRoot "$name.obj"

        Write-Progress-Inline -Current ($i + 1) -Total $total -Label $Label -Status $name

        $r = Invoke-Nasm "$src.asm" "$name.obj"
        if ($r.Success) {
            $warnCount += $r.Warnings.Count
            $objs += $objPath
        } else {
            $errors += [PSCustomObject]@{ File = "$src.asm"; Messages = $r.Output }
        }
    }
    Show-Cursor

    if ($errors.Count -gt 0) {
        Complete-Progress "$($errors.Count)/$total failed" "Red"
        foreach ($err in $errors) {
            Write-Host "      $($err.File):" -ForegroundColor Red
            $err.Messages | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkRed }
        }
        return $null
    }

    $warnStr = if ($warnCount -gt 0) { " ($warnCount warnings)" } else { "" }
    Complete-Progress "$total/$total assembled$warnStr" "Green"
    return $objs
}

# link obj files into an exe
function Link-Exe {
    param([string[]]$ObjFiles, [string]$Output, [string]$Entry = "_start")
    Write-Host -NoNewline "    linking ... " -ForegroundColor White

    $outPath = Join-Path $global:ProjectRoot $Output
    $linkArgs = @(
        "/nologo", "/subsystem:console", "/entry:$Entry", "/LARGEADDRESSAWARE:NO"
    ) + $ObjFiles + @("kernel32.lib", "/OUT:$outPath")

    Push-Location $global:ProjectRoot
    $linkOutput = & link @linkArgs 2>&1
    $linkExit = $LASTEXITCODE
    Pop-Location

    if ($linkExit -eq 0) {
        $size = [math]::Round((Get-Item $outPath).Length / 1024, 1)
        Write-Host "OK (${size} KB)" -ForegroundColor Green
        return $true
    } else {
        Write-Host "FAIL" -ForegroundColor Red
        $linkOutput | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkRed }
        return $false
    }
}

# cleanup all .obj in project root
function Cleanup-Obj {
    Get-ChildItem (Join-Path $global:ProjectRoot "*.obj") -ErrorAction SilentlyContinue | Remove-Item -Force
}

# build compiler
function Build-Compiler {
    Write-Host "  compiler" -ForegroundColor White

    # lint before build
    Write-Host -NoNewline "    lint ... " -ForegroundColor White
    $lintScript = Join-Path $PSScriptRoot "cmd_lint.ps1"
    if (Test-Path $lintScript) {
        $lintOut = & $lintScript "all" 2>&1 | Out-String
        $hasErrors = $lintOut -match '\[x\] L001'
        if ($hasErrors) {
            Write-Host "FAIL" -ForegroundColor Red
            Write-Host $lintOut
            return $false
        }
        Write-Host "OK" -ForegroundColor Green
    } else {
        Write-Host "SKIP" -ForegroundColor Yellow
    }

    $objs = Build-AsmFiles $compilerSrcs "compiler"
    if (-not $objs) { Cleanup-Obj; return $false }

    # driver
    Write-Host -NoNewline "    driver ... " -ForegroundColor White
    $r = Invoke-Nasm "compiler\elysiumc_win64.asm" "driver.obj"
    if ($r.Success) {
        Write-Host "OK" -ForegroundColor Green
        $objs += (Join-Path $global:ProjectRoot "driver.obj")
    } else {
        Write-Host "FAIL" -ForegroundColor Red
        $r.Output | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkRed }
        Cleanup-Obj; return $false
    }

    $ok = Link-Exe $objs "elysiumc.exe"
    Cleanup-Obj
    return $ok
}

# build internal test runner
function Build-Internals {
    Write-Host "  test_internals" -ForegroundColor White
    $testAsm = Join-Path $global:ProjectRoot "tests\test_internals.asm"
    if (-not (Test-Path $testAsm)) {
        Write-Host "    tests\test_internals.asm not found, skipping" -ForegroundColor Yellow
        return $true
    }
    $objs = Build-AsmFiles $internalSrcs "internals"
    if (-not $objs) { Cleanup-Obj; return $false }

    Write-Host -NoNewline "    test_internals.asm ... " -ForegroundColor White
    $r = Invoke-Nasm "tests\test_internals.asm" "test_internals.obj"
    if ($r.Success) {
        Write-Host "OK" -ForegroundColor Green
        $objs += (Join-Path $global:ProjectRoot "test_internals.obj")
    } else {
        Write-Host "FAIL" -ForegroundColor Red
        $r.Output | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkRed }
        Cleanup-Obj; return $false
    }

    $ok = Link-Exe $objs "tests\test_internals.exe"
    Cleanup-Obj
    return $ok
}

# build dump tool
function Build-Dump {
    Write-Host "  elydump" -ForegroundColor White
    $dumpAsm = Join-Path $global:ProjectRoot "tests\dumptool.asm"
    if (-not (Test-Path $dumpAsm)) {
        Write-Host "    tests\dumptool.asm not found, skipping" -ForegroundColor Yellow
        return $true
    }
    $objs = Build-AsmFiles $dumpSrcs "dump"
    if (-not $objs) { Cleanup-Obj; return $false }

    Write-Host -NoNewline "    dumptool.asm ... " -ForegroundColor White
    $r = Invoke-Nasm "tests\dumptool.asm" "dumptool.obj"
    if ($r.Success) {
        Write-Host "OK" -ForegroundColor Green
        $objs += (Join-Path $global:ProjectRoot "dumptool.obj")
    } else {
        Write-Host "FAIL" -ForegroundColor Red
        $r.Output | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkRed }
        Cleanup-Obj; return $false
    }

    $ok = Link-Exe $objs "elydump.exe"
    Cleanup-Obj
    return $ok
}

# verify: quick compile+run of a minimal test to confirm the compiler works
function Build-Verify {
    Write-Host ""
    Write-Host "  verify" -ForegroundColor White
    $compiler = Find-Compiler
    if (-not $compiler) {
        Write-Host "    elysiumc.exe not found, skipping verify" -ForegroundColor Yellow
        return $false
    }

    # write a minimal test program
    $testEly = Join-Path $global:ProjectRoot "_verify.ely"
    $testExe = Join-Path $global:ProjectRoot "_verify.exe"
    @"
module Main {
  public fn main() -> i64 {
    print(42);
    return 0;
  }
}
"@ | Set-Content $testEly -Encoding ASCII

    Write-Host -NoNewline "    compile _verify.ely ... " -ForegroundColor White
    $compOut = & $compiler $testEly -o $testExe 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAIL" -ForegroundColor Red
        $compOut | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkRed }
        Remove-Item $testEly -Force -ErrorAction SilentlyContinue
        return $false
    }
    Write-Host "OK" -ForegroundColor Green

    Write-Host -NoNewline "    run _verify.exe ... " -ForegroundColor White
    $runOut = (& $testExe 2>&1 | Out-String).Trim()
    $runExit = $LASTEXITCODE

    Remove-Item $testEly -Force -ErrorAction SilentlyContinue
    Remove-Item $testExe -Force -ErrorAction SilentlyContinue

    if ($runExit -eq 0 -and $runOut -eq "42") {
        Write-Host "OK (output=42)" -ForegroundColor Green
        return $true
    } else {
        Write-Host "FAIL (exit=$runExit, output='$runOut')" -ForegroundColor Red
        return $false
    }
}

# dispatch
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$results = @{}

switch ($target) {
    "compiler" {
        $results["compiler"] = Build-Compiler
        $results["verify"] = Build-Verify
    }
    "internals" {
        $results["internals"] = Build-Internals
    }
    "dump" {
        $results["dump"] = Build-Dump
    }
    "all" {
        $results["compiler"] = Build-Compiler
        # check for optional targets
        $hasInternals = Test-Path (Join-Path $global:ProjectRoot "tests\test_internals.asm")
        $hasDump = Test-Path (Join-Path $global:ProjectRoot "tests\dumptool.asm")

        if ($hasInternals) {
            Write-Host ""
            $results["internals"] = Build-Internals
        }
        if ($hasDump) {
            Write-Host ""
            $results["dump"] = Build-Dump
        }
        $results["verify"] = Build-Verify
    }
    default {
        Write-Host "    unknown target: $target" -ForegroundColor Red
        Write-Host "    use: all, compiler, internals, dump" -ForegroundColor DarkGray
        return
    }
}

$sw.Stop()

# summary
Write-Host ""
$failCount = @($results.Values | Where-Object { $_ -eq $false }).Count
$passCount = @($results.Values | Where-Object { $_ -eq $true }).Count

foreach ($kv in $results.GetEnumerator()) {
    $icon = if ($kv.Value) { "+" } else { "x" }
    $color = if ($kv.Value) { "Green" } else { "Red" }
    Write-Host "    [$icon] $($kv.Key)" -ForegroundColor $color
}

Write-Host ""
if ($failCount -eq 0) {
    Write-Host "    all targets OK" -ForegroundColor Green
} else {
    Write-Host "    $failCount target(s) failed" -ForegroundColor Red
}