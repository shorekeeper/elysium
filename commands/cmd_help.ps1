#Requires -Version 7.0
# cmd_help.ps1 [command]
param([string]$Topic = "")

Get-ChildItem (Join-Path $PSScriptRoot "_*.ps1") | ForEach-Object { . $_.FullName }

$commands = @(
    @{ Cmd = "build";  Alias = "b"; Desc = "Build targets (compiler, tests, dump tool)" ;
       Usage = "build [all|compiler|internals|dump]" },
    @{ Cmd = "test";   Alias = "t"; Desc = "Run test suites" ;
       Usage = "test [all|e2e|internal|<name>]" },
    @{ Cmd = "run";    Alias = "r"; Desc = "Compile and run a .ely file" ;
       Usage = "run [file.ely] [-o out.exe] [--keep]" },
    @{ Cmd = "dump";   Alias = "d"; Desc = "Dump MIR, x86, symbols for a .ely file" ;
       Usage = "dump [file.ely] [--mir] [--x86] [--sym] [--all]" },
    @{ Cmd = "clean";  Alias = "c"; Desc = "Remove build artifacts" ;
       Usage = "clean [all|obj|exe|tests]" },
    @{ Cmd = "info";   Alias = "i"; Desc = "Project statistics and toolchain" ;
       Usage = "info" },
    @{ Cmd = "status"; Alias = "s"; Desc = "Git and build status" ;
       Usage = "status" },
    @{ Cmd = "help";   Alias = "h"; Desc = "This help" ;
       Usage = "help [command]" }
)

if ($Topic) {
    $found = $commands | Where-Object { $_.Cmd -eq $Topic -or $_.Alias -eq $Topic }
    if ($found) {
        Write-Host ""
        Write-Host "  $($found.Cmd) ($($found.Alias)) - $($found.Desc)" -ForegroundColor Cyan
        Write-Host "  usage: $($found.Usage)" -ForegroundColor Gray
        Write-Host ""
    } else {
        Write-Host "  unknown command: $Topic" -ForegroundColor Red
    }
    return
}

Write-Host ""
Write-Host "  Commands:" -ForegroundColor White
Write-Host ""
foreach ($c in $commands) {
    $alias = "($($c.Alias))".PadRight(4)
    Write-Host -NoNewline "    $($c.Cmd.PadRight(8))" -ForegroundColor Cyan
    Write-Host -NoNewline " $alias " -ForegroundColor DarkGray
    Write-Host "$($c.Desc)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  Shortcuts:" -ForegroundColor White
Write-Host "    !!    repeat last command" -ForegroundColor Gray
Write-Host "    q     quit" -ForegroundColor Gray
Write-Host ""
Write-Host "  Examples:" -ForegroundColor White
Write-Host "    build                 build everything" -ForegroundColor DarkGray
Write-Host "    build compiler        build only compiler" -ForegroundColor DarkGray
Write-Host "    run demo.ely          compile and run" -ForegroundColor DarkGray
Write-Host "    test e2e              run E2E tests" -ForegroundColor DarkGray
Write-Host "    test t_hello          run single test" -ForegroundColor DarkGray
Write-Host "    dump demo.ely --mir   show MIR output" -ForegroundColor DarkGray
Write-Host ""