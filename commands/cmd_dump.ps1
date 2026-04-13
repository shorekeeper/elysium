#Requires -Version 7.0
# cmd_dump.ps1 <file.ely> [--mir] [--x86] [--sym] [--all]
# dump MIR, x86 hex, or symbol table for a .ely file
param([Parameter(ValueFromRemainingArguments)][string[]]$RawArgs)

Get-ChildItem (Join-Path $PSScriptRoot "_*.ps1") | ForEach-Object { . $_.FullName }

$inputFile = ""
$flags = @()

foreach ($a in $RawArgs) {
    if ($a -match "^--") { $flags += $a }
    elseif (-not $inputFile) { $inputFile = $a }
}

if (-not $inputFile) { $inputFile = "demo.ely" }
if ($flags.Count -eq 0) { $flags = @("--all") }

if (-not (Test-Path $inputFile)) {
    Write-Host "  file not found: $inputFile" -ForegroundColor Red
    return
}

Write-CmdHeader "dump" "$inputFile $($flags -join ' ')"

$dumper = Find-DumpTool
if (-not $dumper) {
    Write-Host "    elydump.exe not found" -ForegroundColor Yellow
    Write-Host "    building dump tool..." -ForegroundColor DarkGray

    # build it using the same sources as the compiler + dumptool.asm
    $srcs = @(
        "libely\vmem", "libely\arena", "libely\lexer", "libely\parser",
        "libely\frontend", "libely\types", "libely\symtab", "libely\emit",
        "libely\codegen_rt", "libely\codegen_expr", "libely\codegen_stmt",
        "libely\codegen_func", "libely\backend", "libely\ir", "libely\lower",
        "libely\x86enc", "libely\pe64", "libely\typetab"
    )
    $objs = @()
    foreach ($src in $srcs) {
        $name = Split-Path $src -Leaf
        $r = Invoke-Nasm "$src.asm" "$name.obj"
        if (-not $r.Success) {
            Write-Host "    build failed at $src" -ForegroundColor Red
            return
        }
        $objs += "$name.obj"
    }
    $r = Invoke-Nasm "tests\dumptool.asm" "dumptool.obj"
    if (-not $r.Success) {
        Write-Host "    build failed at dumptool.asm" -ForegroundColor Red
        return
    }
    $objs += "dumptool.obj"

    $linkArgs = @("/nologo", "/subsystem:console", "/entry:_start", "/LARGEADDRESSAWARE:NO") +
        $objs + @("kernel32.lib", "/OUT:elydump.exe")
    & link @linkArgs 2>&1 | Out-Null
    Get-ChildItem "*.obj" -ErrorAction SilentlyContinue | Remove-Item -Force

    $dumper = Find-DumpTool
    if (-not $dumper) {
        Write-Host "    failed to build elydump.exe" -ForegroundColor Red
        return
    }
    Write-Host "    built elydump.exe" -ForegroundColor Green
    Write-Host ""
}

# run dumper
$args_ = @($inputFile) + $flags
$output = & $dumper @args_ 2>&1
foreach ($line in $output) {
    $str = "$line"
    if ($str -match "MIR\[") { Write-Host "  $str" -ForegroundColor Cyan }
    elseif ($str -match "^===") { Write-Host "  $str" -ForegroundColor White }
    elseif ($str -match "0x|[0-9A-F]{2} ") { Write-Host "  $str" -ForegroundColor DarkGray }
    elseif ($str -match "@|type=|arrlen=") { Write-Host "  $str" -ForegroundColor Yellow }
    else { Write-Host "  $str" }
}