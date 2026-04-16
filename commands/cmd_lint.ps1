#Requires -Version 7.0
# cmd_lint.ps1 [file.asm|all] [--strict] [--perf] [--style] [--all]
param([Parameter(ValueFromRemainingArguments)][string[]]$RawArgs)

Get-ChildItem (Join-Path $PSScriptRoot "_*.ps1") | ForEach-Object { . $_.FullName }

$target = "all"; $strict = $false; $showPerf = $false; $showStyle = $false
foreach ($a in $RawArgs) {
    if ([string]::IsNullOrWhiteSpace($a)) { continue }
    switch ($a) {
        "--strict" { $strict = $true }
        "--perf"   { $showPerf = $true }
        "--style"  { $showStyle = $true }
        "--all"    { $strict = $true; $showPerf = $true; $showStyle = $true }
        default    { $target = $a }
    }
}

Write-CmdHeader "lint" "[$target]$(if($strict){' --strict'})$(if($showPerf){' --perf'})$(if($showStyle){' --style'})"

# [unicode glyphs]
$H = [string]::new([char]0x2501, 76)
$L = [string]::new([char]0x2500, 68)
$P = [char]0x2502
$Blk = [char]0x2588
$Dim = [char]0x2591

# [constants]
$CalleeSaved = @('rbx','rbp','r12','r13','r14','r15')
$WriteOps = @(
    'mov','lea','xor','add','sub','inc','dec','shl','shr','sar',
    'and','or','not','neg','imul','movzx','movsx','movsxd',
    'sete','setne','setl','setg','setle','setge','seta','setb','setae','setbe',
    'cmove','cmovne','cmovl','cmovg','bsr','bsf','popcnt','pop'
)
$WriteOpsRx = ($WriteOps | ForEach-Object { [regex]::Escape($_) }) -join '|'
$EntryPoints = @('_start')
$PerExeSymbols = @('_start','platform_write')
$WinApis = @(
    'GetStdHandle','WriteFile','ReadFile','CreateFileA','CloseHandle',
    'ExitProcess','GetCommandLineA','VirtualAlloc','VirtualFree',
    'GetConsoleMode','SetConsoleMode','SetConsoleOutputCP'
)
$script:FileLines = @{}
$script:TotalInstructions = 0
$script:TotalFunctions = 0

# [check metadata]
$script:CM = @{
    L001=@{Lv="ERR";Ic="🔴";Sp="System V AMD64 ABI 3.2.1 / Microsoft x64 2.2"}
    L002=@{Lv="ERR";Ic="🔴";Sp="x86-64 calling convention: push/pop symmetry"}
    L003=@{Lv="WARN";Ic="🟡";Sp="x86-64 calling convention: LIFO register save"}
    L004=@{Lv="WARN";Ic="🟡";Sp="x86-64 calling convention: stack balance"}
    L005=@{Lv="INFO";Ic="🔵";Sp=""}
    L006=@{Lv="ERR";Ic="🔴";Sp="NASM manual 3.9 Local Labels"}
    L007=@{Lv="WARN";Ic="🟡";Sp=""}
    L008=@{Lv="WARN";Ic="🟡";Sp="x86-64 ABI: stack pointer must be restored"}
    L009=@{Lv="ERR";Ic="🔴";Sp="Intel SDM Vol.2 DIV/IDIV: dividend is rdx:rax"}
    L010=@{Lv="ERR";Ic="🔴";Sp="NASM manual 7.6 GLOBAL directive"}
    L011=@{Lv="WARN";Ic="🟡";Sp="Linker symbol resolution"}
    L012=@{Lv="PERF";Ic="⚡";Sp="Intel Optimization Manual 3.5.1.8 Zeroing Idioms"}
    L013=@{Lv="PERF";Ic="⚡";Sp="Intel Optimization Manual 3.5.2.6 TEST vs CMP"}
    L014=@{Lv="WARN";Ic="🟡";Sp=""}
    L015=@{Lv="WARN";Ic="🟡";Sp=""}
    L016=@{Lv="ERR";Ic="🔴";Sp=""}
    L017=@{Lv="WARN";Ic="🟡";Sp=""}
    L018=@{Lv="INFO";Ic="🔵";Sp=""}
    L019=@{Lv="WARN";Ic="🟡";Sp="Linker: unused extern wastes symbol resolution"}
    L020=@{Lv="WARN";Ic="🟡";Sp="Linker: global without definition"}
    L021=@{Lv="WARN";Ic="🟡";Sp="NASM manual 3.3 Effective Addresses: default rel"}
    L022=@{Lv="WARN";Ic="🟡";Sp="Linker symbol resolution"}
    L023=@{Lv="WARN";Ic="🟡";Sp="C/Win32 string convention: null terminator"}
    L024=@{Lv="STYLE";Ic="💎";Sp=""}
    L025=@{Lv="WARN";Ic="🟡";Sp=""}
    L026=@{Lv="PERF";Ic="⚡";Sp="Intel SDM: 32-bit ops zero-extend to 64"}
    L027=@{Lv="WARN";Ic="🟡";Sp=""}
    L028=@{Lv="WARN";Ic="🟡";Sp="Microsoft x64 ABI 4.3: 32-byte shadow space"}
    L029=@{Lv="WARN";Ic="🟡";Sp="NASM: data in .text is unusual"}
    L030=@{Lv="PERF";Ic="⚡";Sp="Intel Optimization Manual: LOOP is slow"}
    L031=@{Lv="WARN";Ic="🟡";Sp="Intel SDM Vol.2 REP: rcx is count register"}
    L032=@{Lv="STYLE";Ic="💎";Sp=""}
    L033=@{Lv="STYLE";Ic="💎";Sp=""}
    L034=@{Lv="WARN";Ic="🟡";Sp="PE/ELF section attributes: W^X"}
    L035=@{Lv="WARN";Ic="🟡";Sp="x86-64: 32-bit regs truncate addresses"}
    L036=@{Lv="STYLE";Ic="💎";Sp=""}
    L037=@{Lv="INFO";Ic="🔵";Sp=""}
    L038=@{Lv="WARN";Ic="🟡";Sp="Win64 does not use syscall; Linux does not use WinAPI"}
    L039=@{Lv="WARN";Ic="🟡";Sp="Microsoft x64 ABI: RSP must be 16-aligned at CALL"}
    L040=@{Lv="ERR";Ic="🔴";Sp="Intel SDM: POP RSP has undefined behavior"}
    L041=@{Lv="PERF";Ic="⚡";Sp=""}
    L042=@{Lv="WARN";Ic="🟡";Sp=""}
    L100=@{Lv="AUDIT";Ic="🔍";Sp=""}
    L101=@{Lv="WARN";Ic="🟡";Sp=""}
}

# [rendering]

function Get-LevelWord { param($Lv)
    switch ($Lv) {
        "ERR"   { "error" }
        "WARN"  { "warning" }
        "PERF"  { "perf" }
        "STYLE" { "style" }
        "INFO"  { "info" }
        "AUDIT" { "audit" }
        default { "note" }
    }
}

function Get-LevelColors { param($Lv)
    switch ($Lv) {
        "ERR"   { @{ Head="Red"; Rule="DarkRed"; Ann="Red" } }
        "WARN"  { @{ Head="Yellow"; Rule="DarkYellow"; Ann="Yellow" } }
        "PERF"  { @{ Head="Magenta"; Rule="DarkMagenta"; Ann="Magenta" } }
        "STYLE" { @{ Head="Cyan"; Rule="DarkCyan"; Ann="Cyan" } }
        "INFO"  { @{ Head="DarkGray"; Rule="DarkGray"; Ann="DarkGray" } }
        "AUDIT" { @{ Head="Magenta"; Rule="DarkMagenta"; Ann="Magenta" } }
        default { @{ Head="Gray"; Rule="Gray"; Ann="Gray" } }
    }
}

function Render-Diag {
    param([PSCustomObject]$D)
    $meta = $script:CM[$D.Code]
    if (-not $meta) { $meta = @{Lv=$D.Level;Ic="?";Sp=""} }
    $c = Get-LevelColors $D.Level
    $word = Get-LevelWord $D.Level
    $rawLines = $script:FileLines[$D.File]

    # top rule
    Write-Host "        $H" -ForegroundColor $c.Rule

    # header
    Write-Host -NoNewline "        $($meta.Ic) " -ForegroundColor $c.Head
    Write-Host -NoNewline "$word" -ForegroundColor $c.Head
    Write-Host -NoNewline "[" -ForegroundColor DarkGray
    Write-Host -NoNewline $D.Code -ForegroundColor $c.Head
    Write-Host -NoNewline "]: " -ForegroundColor DarkGray
    Write-Host $D.Message -ForegroundColor White

    # location
    $loc = "        at $($D.File)"
    if ($D.Line -gt 0) { $loc += ":$($D.Line)" }
    if ($D.Func) { $loc += " $P $($D.Func)()" }
    Write-Host $loc -ForegroundColor DarkGray

    # spec
    $sp = if ($D.Spec) { $D.Spec } elseif ($meta.Sp) { $meta.Sp } else { $null }
    if ($sp) { Write-Host "        ref: $sp" -ForegroundColor DarkGray }

    # light rule
    Write-Host -NoNewline "          $P" -ForegroundColor Blue
    Write-Host "  $L" -ForegroundColor DarkGray

    # empty pipe
    Write-Host "          $P" -ForegroundColor Blue

    # source context
    if ($rawLines -and $D.Line -gt 0) {
        $sLine = [Math]::Max(0, $D.Line - 4)
        $eLine = [Math]::Min($rawLines.Count - 1, $D.Line + 1)
        for ($i = $sLine; $i -le $eLine; $i++) {
            $num = $i + 1
            $isTgt = ($num -eq $D.Line)
            $ns = "$num".PadLeft(8)
            Write-Host -NoNewline " $ns " -ForegroundColor $(if($isTgt){"White"}else{"DarkGray"})
            Write-Host -NoNewline "$P" -ForegroundColor Blue
            $txt = if ($i -lt $rawLines.Count) { $rawLines[$i] } else { "" }
            $baseCol = if ($isTgt) { "White" } else { "DarkGray" }
            Write-Host -NoNewline " " -ForegroundColor $baseCol
            Write-AsmHighlighted $txt $baseCol
            Write-Host ""

            if ($isTgt -and $D.Annotation) {
                $lead = if ($txt -match '^(\s*)') { $Matches[1].Length } else { 0 }
                $tLen = if ($D.AnnLen -gt 0) { $D.AnnLen } else { [Math]::Max(3, [Math]::Min(30, $txt.TrimStart().Length)) }
                $col = if ($D.AnnCol -ge 0) { $D.AnnCol } else { $lead }
                $pad = [string]::new(' ', $col)
                $tildes = [string]::new('~', $tLen)
                Write-Host -NoNewline "          $P " -ForegroundColor Blue
                Write-Host -NoNewline "$pad"
                Write-Host -NoNewline $tildes -ForegroundColor $c.Ann
                Write-Host " $($D.Annotation)" -ForegroundColor $c.Ann
            }
        }
    }

    # empty pipe
    Write-Host "          $P" -ForegroundColor Blue

    # notes
    if ($D.Notes -and $D.Notes.Count -gt 0) {
        Write-Host -NoNewline "          = note: " -ForegroundColor Cyan
        Write-Host $D.Notes[0] -ForegroundColor DarkGray
        for ($j = 1; $j -lt $D.Notes.Count; $j++) {
            Write-Host "                  $($D.Notes[$j])" -ForegroundColor DarkGray
        }
    }
    # helps
    if ($D.Helps -and $D.Helps.Count -gt 0) {
        Write-Host -NoNewline "          = help: " -ForegroundColor Green
        Write-Host $D.Helps[0] -ForegroundColor Green
        for ($j = 1; $j -lt $D.Helps.Count; $j++) {
            Write-Host "                  $($D.Helps[$j])" -ForegroundColor Green
        }
    }

    # bottom rule
    Write-Host "        $H" -ForegroundColor $c.Rule
    Write-Host ""
}

function Render-Compact {
    param([PSCustomObject]$D)
    $meta = $script:CM[$D.Code]
    $icon = switch($D.Level){"ERR"{"x"}"AUDIT"{"@"}"WARN"{"!"}"PERF"{"~"}"STYLE"{"."} default{"i"}}
    $color = switch($D.Level){"ERR"{"Red"}"AUDIT"{"Magenta"}"WARN"{"Yellow"}"PERF"{"Magenta"}"STYLE"{"Cyan"} default{"DarkGray"}}
    $loc = if ($D.Line -gt 0) { ":$($D.Line)" } else { "" }
    $fn = if ($D.Func) { " $($D.Func)" } else { "" }
    Write-Host -NoNewline "      [$icon] " -ForegroundColor $color
    Write-Host -NoNewline "$($D.Code)" -ForegroundColor $color
    Write-Host -NoNewline " $($D.File)${fn}${loc}" -ForegroundColor Gray
    Write-Host "  $($D.Message)" -ForegroundColor $color
    if ($D.Detail) { Write-Host "           $($D.Detail)" -ForegroundColor DarkGray }
}

function Write-AsmHighlighted {
    param([string]$Text, [string]$Base = "White")
    if (-not $Text) { return }
    $bright = $Base -eq "White"
    $cReg = if ($bright) { "Cyan" } else { "DarkCyan" }
    $cNum = if ($bright) { "Magenta" } else { "DarkMagenta" }
    $cStr = if ($bright) { "DarkYellow" } else { "DarkGray" }
    $cCom = "DarkGreen"

    # find ; outside quotes
    $comIdx = $Text.Length
    $inDQ = $false; $inSQ = $false
    for ($ci = 0; $ci -lt $Text.Length; $ci++) {
        $ch = $Text[$ci]
        if ($ch -eq '"' -and -not $inSQ) { $inDQ = !$inDQ }
        if ($ch -eq "'" -and -not $inDQ) { $inSQ = !$inSQ }
        if (!$inDQ -and !$inSQ -and $ch -eq ';') { $comIdx = $ci; break }
    }
    $code = $Text.Substring(0, $comIdx)

    $spans = [System.Collections.Generic.List[object]]::new()

    $strPat = '"[^"]*"' + "|'[^']*'"
    foreach ($m in [regex]::Matches($code, $strPat)) {
        $spans.Add(@([int]$m.Index, [int]$m.Length, $cStr, 0))
    }
    $regPat = '\b([re]?(ax|bx|cx|dx|si|di|bp|sp)|(al|bl|cl|dl|ah|bh|ch|dh|sil|dil|bpl|spl)|r([89]|1[0-5])[dwb]?)\b'
    foreach ($m in [regex]::Matches($code, $regPat, 'IgnoreCase')) {
        $spans.Add(@([int]$m.Index, [int]$m.Length, $cReg, 1))
    }
    foreach ($m in [regex]::Matches($code, '\b(0x[0-9a-fA-F]+|\d+)\b')) {
        $spans.Add(@([int]$m.Index, [int]$m.Length, $cNum, 2))
    }

    $sorted = @($spans | Sort-Object { $_[0] }, { $_[3] })
    $pos = 0
    foreach ($s in $sorted) {
        if ($s[0] -lt $pos) { continue }
        if ($s[0] -gt $pos) {
            Write-Host -NoNewline $code.Substring($pos, $s[0] - $pos) -ForegroundColor $Base
        }
        Write-Host -NoNewline $code.Substring($s[0], $s[1]) -ForegroundColor $s[2]
        $pos = $s[0] + $s[1]
    }
    if ($pos -lt $code.Length) {
        Write-Host -NoNewline $code.Substring($pos) -ForegroundColor $Base
    }
    if ($comIdx -lt $Text.Length) {
        Write-Host -NoNewline $Text.Substring($comIdx) -ForegroundColor $cCom
    }
}

function Render-Summary {
    param($AllWarnings, $FileCount)
    $c = Get-LevelColors "WARN"
    $errs   = @($AllWarnings | Where-Object { $_.Level -eq "ERR" })
    $warns  = @($AllWarnings | Where-Object { $_.Level -eq "WARN" })
    $perfs  = @($AllWarnings | Where-Object { $_.Level -eq "PERF" })
    $styles = @($AllWarnings | Where-Object { $_.Level -eq "STYLE" })
    $infos  = @($AllWarnings | Where-Object { $_.Level -eq "INFO" })
    $audits = @($AllWarnings | Where-Object { $_.Level -eq "AUDIT" })
    $total = $AllWarnings.Count
    if ($total -eq 0) { $total = 1 }

    Write-Host ""
    Write-Host "        $H" -ForegroundColor DarkCyan

    Write-Host -NoNewline "        " -ForegroundColor White
    Write-Host "ELYSIUM LINT REPORT" -ForegroundColor Cyan
    Write-Host -NoNewline "          $P" -ForegroundColor Blue
    Write-Host "  $L" -ForegroundColor DarkGray
    Write-Host "          $P" -ForegroundColor Blue

    # stats line
    Write-Host -NoNewline "          $P  " -ForegroundColor Blue
    Write-Host "$FileCount files scanned $P $($script:TotalFunctions) functions $P $($script:TotalInstructions) instructions" -ForegroundColor DarkGray
    Write-Host "          $P" -ForegroundColor Blue

    # bar chart
    foreach ($entry in @(
        @("ERR",  $errs.Count,   "Red"),
        @("WARN", $warns.Count,  "Yellow"),
        @("PERF", $perfs.Count,  "Magenta"),
        @("STYLE",$styles.Count, "Cyan"),
        @("INFO", $infos.Count,  "DarkGray"),
        @("AUDIT",$audits.Count, "Magenta")
    )) {
        if ($entry[1] -eq 0) { continue }
        $pct = [Math]::Round($entry[1] / $total * 100)
        $filled = [Math]::Max(1, [Math]::Round($entry[1] / $total * 20))
        $empty = 20 - $filled
        $bar = ([string]::new($Blk, $filled)) + ([string]::new($Dim, $empty))
        Write-Host -NoNewline "          $P  " -ForegroundColor Blue
        $tag = "$($entry[1])".PadLeft(4)
        Write-Host -NoNewline "  $tag $($entry[0].PadRight(6))" -ForegroundColor $entry[2]
        Write-Host -NoNewline " $bar" -ForegroundColor $entry[2]
        Write-Host "  ${pct}%" -ForegroundColor DarkGray
    }

    Write-Host "          $P" -ForegroundColor Blue

    # breakdown
    $grouped = $AllWarnings | Group-Object Code | Sort-Object {
        $lv = ($_.Group[0]).Level
        switch($lv){"ERR"{0}"WARN"{1}"PERF"{2}"STYLE"{3}"AUDIT"{4}default{5}}
    }, Count -Descending
    if ($grouped) {
        Write-Host -NoNewline "          $P  " -ForegroundColor Blue
        $tb = [string]::new([char]0x2500, 16)
        Write-Host " Top Issues $tb" -ForegroundColor White
        $shown = 0
        foreach ($g in $grouped) {
            if ($shown -ge 12) { break }
            $sample = $g.Group[0]
            $icon = switch($sample.Level){"ERR"{"x"}"WARN"{"!"}"PERF"{"~"}"STYLE"{"."}"AUDIT"{"@"}default{"i"}}
            $color = switch($sample.Level){"ERR"{"Red"}"WARN"{"Yellow"}"PERF"{"Magenta"}"STYLE"{"Cyan"}"AUDIT"{"Magenta"}default{"DarkGray"}}
            Write-Host -NoNewline "          $P  " -ForegroundColor Blue
            Write-Host -NoNewline "  [$icon] " -ForegroundColor $color
            Write-Host -NoNewline "$($g.Name)" -ForegroundColor $color
            Write-Host -NoNewline "  x$($g.Count)".PadRight(6) -ForegroundColor White
            Write-Host "$($sample.Message.Substring(0, [Math]::Min(50, $sample.Message.Length)))" -ForegroundColor DarkGray
            $shown++
        }
    }

    Write-Host "          $P" -ForegroundColor Blue

    # final verdict
    if ($errs.Count -gt 0) {
        Write-Host -NoNewline "          = " -ForegroundColor Red
        Write-Host "fix $($errs.Count) error(s) before compilation can proceed" -ForegroundColor Red
    } elseif ($warns.Count + $perfs.Count + $styles.Count + $audits.Count -gt 0) {
        $total = $warns.Count + $perfs.Count + $styles.Count + $audits.Count
        Write-Host -NoNewline "          = " -ForegroundColor Yellow
        Write-Host "$total diagnostic(s) to review (no blocking errors)" -ForegroundColor Yellow
    } else {
        Write-Host -NoNewline "          = " -ForegroundColor Green
        Write-Host "all checks passed" -ForegroundColor Green
    }

    Write-Host "        $H" -ForegroundColor DarkCyan
    Write-Host ""
}

# [parsing]

function Find-AsmFiles {
    param([string]$Target)
    if ($Target -eq "all") {
        $files = @()
        foreach ($d in @("libely","compiler","tests")) {
            $p = Join-Path $global:ProjectRoot $d
            if (Test-Path $p) { $files += Get-ChildItem $p -Filter "*.asm" -ErrorAction SilentlyContinue }
        }
        return $files
    }
    $f = Get-Item $Target -ErrorAction SilentlyContinue
    if ($f) { return @($f) }
    return @()
}

function Parse-Functions {
    param([string[]]$RawLines)
    $functions = @(); $curName = $null; $curLines = @(); $curStart = 0
    for ($i = 0; $i -lt $RawLines.Count; $i++) {
        $line = $RawLines[$i]
        if ($line -match '^([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.*)$' -and
            $line -notmatch '^\s*section\b' -and $line -notmatch '^\s*%' -and
            $line -notmatch '^\s*;' -and $line -notmatch '^\s*times\b') {
            if ($curName -and $curLines.Count -gt 0) {
                $functions += [PSCustomObject]@{ Name=$curName; StartLine=$curStart; Lines=$curLines }
            }
            $curName = $Matches[1]; $curStart = $i + 1; $curLines = @()
            $tail = $Matches[2].Trim()
            $semi = $tail.IndexOf(';')
            if ($semi -ge 0) { $tail = $tail.Substring(0,$semi).Trim() }
            if ($tail) {
                $curLines += [PSCustomObject]@{ Num=($i+1); Raw=$line; Instr=$tail; IsLabel=$false; LabelName="" }
            }
        } elseif ($curName) {
            $t = $line.Trim()
            $semi = $t.IndexOf(';')
            if ($semi -ge 0) { $t = $t.Substring(0,$semi).Trim() }
            $isLbl = $false; $lblName = ""
            if ($t -match '^\.([\w]+)\s*:\s*(.*)$') { $isLbl = $true; $lblName = ".$($Matches[1])"; $t = $Matches[2].Trim() }
            $curLines += [PSCustomObject]@{ Num=$i+1; Raw=$line; Instr=$t; IsLabel=$isLbl; LabelName=$lblName }
        }
    }
    if ($curName -and $curLines.Count -gt 0) {
        $functions += [PSCustomObject]@{ Name=$curName; StartLine=$curStart; Lines=$curLines }
    }
    return $functions
}

function Get-Declarations {
    param([string[]]$RawLines)
    $globals = @(); $externs = @()
    foreach ($line in $RawLines) {
        if ($line -match '^\s*global\s+(.+)') {
            $globals += ($Matches[1] -split '\s*,\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
        if ($line -match '^\s*extern\s+(.+)') {
            $externs += ($Matches[1] -split '\s*,\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
    }
    return @{ Globals=$globals; Externs=$externs }
}

# [per-function helpers]

function Get-EntryPushes {
    param($Lines)
    $pushes = @()
    foreach ($l in $Lines) {
        if (-not $l.Instr) { continue }
        if ($l.Instr -match '^push\s+(\w+)$') { $pushes += $Matches[1].ToLower() }
        else { break }
    }
    return $pushes
}

function Get-AllPopsBeforeLastRet {
    param($Lines)
    $lastRet = -1
    for ($i = $Lines.Count - 1; $i -ge 0; $i--) {
        if ($Lines[$i].Instr -match '^ret\b') { $lastRet = $i; break }
    }
    if ($lastRet -lt 0) { return @() }
    $pops = @(); $j = $lastRet - 1
    while ($j -ge 0) {
        $t = $Lines[$j].Instr
        if (-not $t) { $j--; continue }
        if ($t -match '^pop\s+(\w+)$') { $pops = @($Matches[1].ToLower()) + $pops; $j-- }
        else { break }
    }
    return $pops
}

function Get-ModifiedCalleeSaved {
    param($Lines)
    $modified = @{}
    foreach ($l in $Lines) {
        $t = $l.Instr
        if (-not $t -or $t -match '^push\s' -or $t -match '^pop\s') { continue }
        foreach ($reg in $CalleeSaved) {
            if ($t -match "^(?:${WriteOpsRx})\s+${reg}\b") {
                if (-not $modified.ContainsKey($reg)) { $modified[$reg] = @{ Line=$l.Num; Text=$t } }
            }
        }
    }
    return $modified
}

function Get-BodyPushPopRegs {
    param($Lines)
    $pushed = @{}; $popped = @{}
    foreach ($l in $Lines) {
        if ($l.Instr -match '^push\s+(\w+)$') { $pushed[$Matches[1].ToLower()] = $true }
        if ($l.Instr -match '^pop\s+(\w+)$')  { $popped[$Matches[1].ToLower()] = $true }
    }
    $saved = @()
    foreach ($r in $pushed.Keys) { if ($popped.ContainsKey($r)) { $saved += $r } }
    return $saved
}

function MkDiag {
    param(
        [Parameter(Position=0)][string]$File,
        [Parameter(Position=1)][string]$Func,
        [Parameter(Position=2)][int]$Line,
        [Parameter(Position=3)][string]$Level,
        [Parameter(Position=4)][string]$Code,
        [Parameter(Position=5)][string]$Message,
        [Parameter(Position=6)][string]$Detail = "",
        [Parameter(Position=7)][string]$Ann = "",
        [int]$AnnCol = -1,
        [int]$AnnLen = 0,
        [string[]]$Notes = @(),
        [string[]]$Helps = @(),
        [string]$Spec = ""
    )
    $fn = [System.Collections.Generic.List[string]]::new()
    foreach ($n in $Notes) { foreach ($s in ($n -split "`n")) { if ($s.Trim()) { $fn.Add($s) } } }
    $fh = [System.Collections.Generic.List[string]]::new()
    foreach ($h in $Helps) { foreach ($s in ($h -split "`n")) { if ($s.Trim()) { $fh.Add($s) } } }
    [PSCustomObject]@{
        File=$File; Func=$Func; Line=$Line; Level=$Level; Code=$Code
        Message=$Message; Detail=$Detail; Annotation=$Ann
        AnnCol=$AnnCol; AnnLen=$AnnLen
        Notes=[string[]]$fn.ToArray(); Helps=[string[]]$fh.ToArray(); Spec=$Spec
    }
}

# [per-function checks]

function Check-Function {
    param($Func, [string]$RelPath, [string[]]$RawLines, [string[]]$FileExterns, [string[]]$FileGlobals, [string[]]$AllLabels)
    $warnings = @()
    $lines = $Func.Lines
    $isEntry = $Func.Name -in $EntryPoints

    # parse annotations
    $suppressed = @(); $isUnsafe = $false; $audits = @(); $expects = @()
    foreach ($l in $lines) {
        $raw = $l.Raw
        if ($raw -match '@ely:lint\s+(\w[\w-]*)\s*(.*)') {
            $dir = $Matches[1].ToLower(); $rest = $Matches[2].Trim()
            $dashIdx = $rest.IndexOf('--')
            if ($dashIdx -ge 0) { $rest = $rest.Substring(0, $dashIdx).Trim() }
            switch ($dir) {
                "suppress" { $suppressed += ($rest -split '[,\s]+' | Where-Object { $_ -match '^L\d+$' }) }
                "unsafe"   { $isUnsafe = $true }
                "audit"    { $audits += [PSCustomObject]@{ Line=$l.Num; Message=$rest } }
                "expect"   { $expects += ($rest -split '[,\s]+' | Where-Object { $_ -match '^L\d+$' }) }
            }
        }
        if ($raw -match '@lint:allow\s+(L\d+)') { $suppressed += $Matches[1] }
    }

    if ($isUnsafe) {
        foreach ($a in $audits) {
            $warnings += (MkDiag $RelPath $Func.Name $a.Line "AUDIT" "L100" `
                "AUDIT: $($a.Message)" "marked for review" "flagged for human review")
        }
        return $warnings
    }

    $instrLines = @($lines | Where-Object {
        $_.Instr -and
        $_.Instr -notmatch '^(db|dw|dd|dq|times|section|extern|global)\b' -and
        $_.Instr -notmatch '^%(macro|endmacro|define|undef|ifdef|ifndef|if|elif|else|endif|include|pragma|assign|rep|endrep)\b'
    })
    $script:TotalInstructions += $instrLines.Count
    $script:TotalFunctions++

    if ($instrLines.Count -lt 2) { return $warnings }

    $hasRet = $instrLines | Where-Object { $_.Instr -match '^ret\b' }
    $entryPushes = @(Get-EntryPushes $lines)
    $allPops     = @(Get-AllPopsBeforeLastRet $lines)
    $modified    = Get-ModifiedCalleeSaved $lines
    $bodySaved   = @(Get-BodyPushPopRegs $lines)

    # L001
    if (-not $isEntry) {
        foreach ($reg in $modified.Keys) {
            if ($reg -in $entryPushes -or $reg -in $bodySaved) { continue }
            $info = $modified[$reg]
            $warnings += (MkDiag $RelPath $Func.Name $info.Line "ERR" "L001" `
                "callee-saved '$reg' modified without push/pop preservation" `
                $info.Text "writes '$reg' without saving it first" `
                -Notes @("$reg is callee-saved in both System V AMD64 and Win64 ABIs.`nany function that modifies it must save/restore or the caller's value is corrupted.") `
                -Helps @("add 'push $reg' at function entry and 'pop $reg' before ret`nor use a volatile register (rax, rcx, rdx, r8-r11) instead"))
        }
    }

    if ($hasRet -and -not $isEntry) {
        # L002
        foreach ($reg in $allPops) {
            if ($reg -in $CalleeSaved -and $reg -notin $entryPushes) {
                $warnings += (MkDiag $RelPath $Func.Name $Func.StartLine "ERR" "L002" `
                    "epilogue pops '$reg' but entry never pushed it" `
                    "push: [$($entryPushes -join ', ')]  pop: [$($allPops -join ', ')]" `
                    "popping a register that was never pushed corrupts the stack" `
                    -Notes @("the epilogue pops '$reg' which was never saved at entry.`nthis shifts the entire return stack and will crash or corrupt data.") `
                    -Helps @("either add 'push $reg' at entry or remove 'pop $reg' from epilogue"))
            }
        }

        $N = $entryPushes.Count
        if ($N -gt 0 -and $allPops.Count -eq $N) {
            # L003
            $expected = @($entryPushes); [array]::Reverse($expected)
            if (($allPops -join ',') -ne ($expected -join ',')) {
                $warnings += (MkDiag $RelPath $Func.Name $Func.StartLine "WARN" "L003" `
                    "push/pop order mismatch (LIFO violation)" `
                    "push: [$($entryPushes -join ', ')]  pop: [$($allPops -join ', ')]  expected: [$($expected -join ', ')]" `
                    "registers must be popped in reverse push order (LIFO)" `
                    -Notes @("push order: [$($entryPushes -join ', ')], pop order: [$($allPops -join ', ')]`nexpected pop order: [$($expected -join ', ')] (reverse of push)") `
                    -Helps @("reorder the pop sequence to match reverse push order"))
            }
        } elseif ($N -gt 0 -and $allPops.Count -lt $N) {
            # L004
            $calleePushed = @($entryPushes | Where-Object { $_ -in $CalleeSaved })
            if ($calleePushed.Count -gt 0) {
                $warnings += (MkDiag $RelPath $Func.Name $Func.StartLine "WARN" "L004" `
                    "fewer pops ($($allPops.Count)) than pushes ($N) at primary ret" `
                    "push: [$($entryPushes -join ', ')]  pop: [$($allPops -join ', ')]" `
                    "stack leak: some pushed values are never restored")
            }
        }
    }

    # L005
    $afterTerminal = $false; $terminalLine = 0
    foreach ($l in $lines) {
        if ($l.IsLabel -or ($l.Raw -match '^\s*\.[\w]+\s*:')) { $afterTerminal = $false }
        $t = $l.Instr
        if (-not $t -or $t -match '^(db|dw|dd|dq|times|section|extern|global|%)\b') { continue }
        if ($afterTerminal) {
            $warnings += (MkDiag $RelPath $Func.Name $l.Num "INFO" "L005" `
                "unreachable code after line $terminalLine" $t `
                "this instruction can never execute" `
                -Notes @("the previous ret/jmp at line $terminalLine is unconditional`ncode after it will never be reached unless jumped to by a label") `
                -Helps @("remove dead code or add a label if this is a jump target"))
            $afterTerminal = $false
        }
        if ($t -match '^ret\b') { $afterTerminal = $true; $terminalLine = $l.Num }
        elseif ($t -match '^jmp\s+[\.\w]' -and $t -notmatch 'qword|dword|\[') {
            $afterTerminal = $true; $terminalLine = $l.Num
        }
    }

    # L006
    $definedLabels = @{}
    foreach ($l in $lines) {
        if ($l.IsLabel) { $definedLabels[$l.LabelName] = $l.Num }
        if ($l.Raw -match '^\s*(\.[\w]+)\s*:') { $definedLabels[$Matches[1]] = $l.Num }
    }
    foreach ($l in $instrLines) {
        if ($l.Instr -match '^\s*(?:j\w+|call|loop\w*)\s+(\.\w+)\b') {
            $lbl = $Matches[1]
            if (-not $definedLabels.ContainsKey($lbl)) {
                $warnings += (MkDiag $RelPath $Func.Name $l.Num "ERR" "L006" `
                    "jump to undefined local label '$lbl'" $l.Instr `
                    "label '$lbl' does not exist in this function" `
                    -Notes @("local labels (starting with .) are scoped to the enclosing global label.`n'$lbl' is not defined in '$($Func.Name)'.") `
                    -Helps @("check spelling or add '$lbl`:' at the target location"))
            }
        }
    }

    # L007
    if ($instrLines.Count -gt 0) {
        $last = $instrLines[-1].Instr
        $isData = $last -match '^(db|dw|dd|dq|times|resb|resw|resd|resq)\b' -or $last -match '\bequ\b'
        if (-not $isData -and $last -and $last -notmatch '^ret\b' -and $last -notmatch '^jmp\b' -and
            $last -notmatch '^call\s+ExitProcess\b' -and $last -notmatch '^syscall\b') {
            $warnings += (MkDiag $RelPath $Func.Name $instrLines[-1].Num "WARN" "L007" `
                "function falls through (no ret/jmp at end)" $last `
                "execution continues into the next function" `
                -Notes @("without a terminating ret or jmp, execution falls through`ninto whatever code follows, causing unpredictable behavior.") `
                -Helps @("add 'ret' at the end of the function"))
        }
    }

    # L008
    if ($strict) {
        $subs = @($instrLines | Where-Object { $_.Instr -match '^sub\s+rsp\b' })
        $adds = @($instrLines | Where-Object { $_.Instr -match '^add\s+rsp\b' })
        if ($subs.Count -ne $adds.Count) {
            $warnings += (MkDiag $RelPath $Func.Name $Func.StartLine "WARN" "L008" `
                "sub rsp ($($subs.Count)) != add rsp ($($adds.Count)) -- stack may leak" `
                "possible stack pointer imbalance" `
                "mismatched stack adjustment count")
        }
    }

    # L009
    for ($i = 0; $i -lt $instrLines.Count; $i++) {
        $t = $instrLines[$i].Instr
        if ($t -match '^\s*(i?div)\s+') {
            $isDivFound = $true; $isCleared = $false
            $start = [Math]::Max(0, $i - 8)
            for ($j = $i - 1; $j -ge $start; $j--) {
                $prev = $instrLines[$j].Instr
                if ($prev -match 'xor\s+(edx|rdx)\s*,\s*(edx|rdx)') { $isCleared = $true; break }
                if ($prev -match '\bcqo\b|\bcdq\b|\bcwd\b') { $isCleared = $true; break }
                if ($prev -match '\bxor\s+edx\b') { $isCleared = $true; break }
                if ($prev -match 'mov\s+(rdx|edx)\s*,\s*0') { $isCleared = $true; break }
            }
            if (-not $isCleared) {
                $warnings += (MkDiag $RelPath $Func.Name $instrLines[$i].Num "ERR" "L009" `
                    "div/idiv without clearing rdx (dividend is rdx:rax)" $t `
                    "rdx not zeroed/sign-extended before division" `
                    -Notes @("DIV divides rdx:rax by the operand. if rdx contains leftover`ndata, the quotient is wrong or #DE (divide error) is raised.`nIDIV requires CQO (sign-extend rax into rdx:rax).") `
                    -Helps @("add 'xor edx, edx' before DIV (unsigned)`nor 'cqo' before IDIV (signed)"))
            }
        }
    }

    # L012
    if ($showPerf) {
        foreach ($l in $instrLines) {
            if ($l.Instr -match '^\s*mov\s+(r\w+|e\w+),\s*0\s*$') {
                $reg = $Matches[1]
                $r32 = $reg -replace '^r(\w)x$','e$1x' -replace '^r(\w+)$','e$1d'
                $warnings += (MkDiag $RelPath $Func.Name $l.Num "PERF" "L012" `
                    "'mov $reg, 0' is 5-7 bytes; 'xor $r32, $r32' is 2 bytes and breaks dep chains" `
                    $l.Instr "use 'xor $r32, $r32' instead (smaller, faster)" `
                    -Notes @("'xor eXX, eXX' is the canonical zeroing idiom on x86-64.`nit is 2 bytes vs 5-7 for mov, and modern CPUs recognize it`nas a dependency-breaking zeroing operation.") `
                    -Helps @("replace with 'xor $r32, $r32' (zero-extends to 64 bits automatically)"))
            }
        }
    }

    # L013
    if ($showPerf) {
        for ($i = 0; $i -lt $instrLines.Count - 1; $i++) {
            if ($instrLines[$i].Instr -match '^\s*cmp\s+(\w+),\s*0\s*$') {
                $reg = $Matches[1]
                $next = $instrLines[$i+1].Instr
                if ($next -match '^\s*(je|jne|jz|jnz)\b') {
                    $jmp = $Matches[1]
                    $replacement = if ($jmp -eq 'je' -or $jmp -eq 'jz') { 'jz' } else { 'jnz' }
                    $warnings += (MkDiag $RelPath $Func.Name $instrLines[$i].Num "PERF" "L013" `
                        "'cmp $reg, 0' + '$jmp' can be 'test $reg, $reg' + '$replacement'" `
                        $instrLines[$i].Instr "test is shorter (no immediate encoding)" `
                        -Helps @("replace with 'test $reg, $reg' then '$replacement <target>'"))
                }
            }
        }
    }

    # L014
    for ($i = 0; $i -lt $instrLines.Count - 1; $i++) {
        $t1 = $instrLines[$i].Instr; $t2 = $instrLines[$i+1].Instr
        if ($t1 -match '^push\s+(\w+)$' -and $t2 -match '^pop\s+(\w+)$') {
            if ($Matches[1].ToLower() -eq ($t1 -replace '^push\s+','').ToLower()) {
                $reg = ($t1 -replace '^push\s+','').ToLower()
                if ($t2 -match "^pop\s+$reg\s*$") {
                    $warnings += (MkDiag $RelPath $Func.Name $instrLines[$i].Num "WARN" "L014" `
                        "push '$reg' immediately followed by pop '$reg' is a no-op" $t1 `
                        "these two instructions cancel each other out" `
                        -Helps @("remove both instructions; they waste 2 memory operations for no effect"))
                }
            }
        }
    }

    # L015
    foreach ($l in $instrLines) {
        if ($l.Instr -match '^\s*mov\s+(\w+)\s*,\s*(\w+)\s*$') {
            if ($Matches[1].ToLower() -eq $Matches[2].ToLower()) {
                $warnings += (MkDiag $RelPath $Func.Name $l.Num "WARN" "L015" `
                    "redundant 'mov $($Matches[1]), $($Matches[2])' (source == destination)" `
                    $l.Instr "this instruction does nothing")
            }
        }
    }

    # L016
    foreach ($l in $instrLines) {
        if ($l.IsLabel -and $l.Instr -match "^jmp\s+$([regex]::Escape($l.LabelName))\s*$") {
            $warnings += (MkDiag $RelPath $Func.Name $l.Num "ERR" "L016" `
                "unconditional jump to self creates infinite loop" $l.Instr `
                "CPU will spin here forever" `
                -Notes @("this label jumps to itself unconditionally.`nthe CPU will loop here forever, burning 100% of one core.") `
                -Helps @("if intentional, add a comment. otherwise fix the jump target."))
        }
    }

    # L017
    for ($i = 0; $i -lt $instrLines.Count - 1; $i++) {
        if ($instrLines[$i].Instr -match '^ret\b' -and $instrLines[$i+1].Instr -match '^ret\b') {
            if (-not $instrLines[$i+1].IsLabel) {
                $warnings += (MkDiag $RelPath $Func.Name $instrLines[$i+1].Num "WARN" "L017" `
                    "duplicate ret instruction (second ret is unreachable)" `
                    $instrLines[$i+1].Instr "this ret can never execute" `
                    -Helps @("remove the duplicate ret"))
            }
        }
    }

    # L018
    $labelRefs = @{}
    foreach ($l in $instrLines) {
        $t = $l.Instr
        if ($t -match '(?:j\w+|call|loop\w*)\s+(\.\w+)') { $labelRefs[$Matches[1]] = $true }
    }
    foreach ($lbl in $definedLabels.Keys) {
        if (-not $labelRefs.ContainsKey($lbl)) {
            $warnings += (MkDiag $RelPath $Func.Name $definedLabels[$lbl] "INFO" "L018" `
                "local label '$lbl' defined but never referenced" "" `
                "dead label (no jump/call targets it)")
        }
    }

    # L022
    foreach ($l in $instrLines) {
        if ($l.Instr -match '^\s*call\s+([a-zA-Z_]\w*)\s*$') {
            $sym = $Matches[1]
            if ($sym -notin $FileExterns -and $sym -notin $FileGlobals -and $sym -notin $AllLabels -and $sym -notin $WinApis) {
                $warnings += (MkDiag $RelPath $Func.Name $l.Num "WARN" "L022" `
                    "call to '$sym' which is not declared as extern or global" $l.Instr `
                    "'$sym' may be an undefined symbol at link time" `
                    -Notes @("the linker will report an unresolved symbol unless '$sym'`nis declared with 'extern $sym' or defined in this file.") `
                    -Helps @("add 'extern $sym' at the top of the file`nor check for a typo in the function name"))
            }
        }
    }

    # L024
    if ($showStyle -and $instrLines.Count -gt 150) {
        $warnings += (MkDiag $RelPath $Func.Name $Func.StartLine "STYLE" "L024" `
            "function has $($instrLines.Count) instructions (threshold: 150)" "" `
            "complex function: consider splitting" `
            -Notes @("functions over 150 instructions are harder to understand,`ntest, and maintain. cyclomatic complexity is likely high.") `
            -Helps @("extract logical subsections into helper functions"))
    }

    # L025
    for ($i = 0; $i -lt $instrLines.Count - 1; $i++) {
        if ($instrLines[$i].Instr -match '^\s*cmp\b' -and $instrLines[$i+1].Instr -match '^\s*jmp\b') {
            if ($instrLines[$i+1].Instr -notmatch 'jmp\s+\[') {
                $warnings += (MkDiag $RelPath $Func.Name $instrLines[$i].Num "WARN" "L025" `
                    "cmp immediately followed by unconditional jmp (comparison result unused)" `
                    $instrLines[$i].Instr `
                    "the flags set by cmp are ignored by the unconditional jmp")
            }
        }
    }

    # L026
    if ($showPerf) {
        foreach ($l in $instrLines) {
            if ($l.Instr -match '^\s*xor\s+(rax|rbx|rcx|rdx|rsi|rdi|r\d+)\s*,\s*(rax|rbx|rcx|rdx|rsi|rdi|r\d+)\s*$') {
                if ($Matches[1] -eq $Matches[2]) {
                    $r = $Matches[1]
                    $r32 = $r -replace '^r(\w)x$','e$1x' -replace '^r(\w)i$','e$1i' -replace '^r(\d+)$','r${1}d'
                    $warnings += (MkDiag $RelPath $Func.Name $l.Num "PERF" "L026" `
                        "'xor $r, $r' has unnecessary REX prefix; use 'xor $r32, $r32'" `
                        $l.Instr `
                        "32-bit xor is 1 byte smaller and zero-extends to 64 bits")
                }
            }
        }
    }

    # L027
    for ($i = 0; $i -lt $instrLines.Count - 1; $i++) {
        $t1 = $instrLines[$i].Instr; $t2 = $instrLines[$i+1].Instr
        if ($t1 -and $t2 -and $t1 -eq $t2 -and $t1 -notmatch '^(nop|pop|push|call|ret)') {
            $warnings += (MkDiag $RelPath $Func.Name $instrLines[$i+1].Num "WARN" "L027" `
                "consecutive duplicate instruction: '$t1'" $t2 `
                "exact duplicate of the previous instruction")
        }
    }

    # L028
    foreach ($l in $instrLines) {
        if ($l.Instr -match '^\s*call\s+(\w+)' -and $Matches[1] -in $WinApis) {
            $api = $Matches[1]; $hasShadow = $false
            $idx = [array]::IndexOf($instrLines, $l)
            $start = [Math]::Max(0, $idx - 10)
            for ($j = $idx - 1; $j -ge $start; $j--) {
                if ($instrLines[$j].Instr -match 'sub\s+rsp\s*,\s*(\d+)') {
                    if ([int]$Matches[1] -ge 32) { $hasShadow = $true; break }
                }
            }
            if (-not $hasShadow) {
                $warnings += (MkDiag $RelPath $Func.Name $l.Num "WARN" "L028" `
                    "call to '$api' without 'sub rsp, 32' shadow space" $l.Instr `
                    "Win64 ABI requires 32-byte shadow space before API calls" `
                    -Notes @("Microsoft x64 ABI requires the caller to allocate at least`n32 bytes of shadow space before any CALL instruction.`nthe callee uses this to spill the 4 register parameters.") `
                    -Helps @("add 'sub rsp, 32' (or more, aligned to 16) before the call`nand 'add rsp, 32' after it returns"))
            }
        }
    }

    # L030
    if ($showPerf) {
        foreach ($l in $instrLines) {
            if ($l.Instr -match '^\s*loop\b') {
                $warnings += (MkDiag $RelPath $Func.Name $l.Num "PERF" "L030" `
                    "LOOP instruction is microcoded and slow on modern CPUs" $l.Instr `
                    "replace with dec+jnz for better throughput" `
                    -Notes @("LOOP is a legacy instruction that decrements rcx and branches.`non modern CPUs it is 5-11 uops vs 1+1 for dec+jnz.`nall major optimization guides recommend avoiding it.") `
                    -Helps @("replace with 'dec rcx' followed by 'jnz <label>'"))
            }
        }
    }

    # L031
    foreach ($l in $instrLines) {
        if ($l.Instr -match '^\s*rep\s+(movsb|stosb|lodsb)') {
            $idx = [array]::IndexOf($instrLines, $l)
            $rcxSet = $false
            $start = [Math]::Max(0, $idx - 6)
            for ($j = $idx - 1; $j -ge $start; $j--) {
                if ($instrLines[$j].Instr -match '(mov|xor|lea)\s+(rcx|ecx)\b') { $rcxSet = $true; break }
            }
            if (-not $rcxSet -and $idx -le 8) { $rcxSet = $true }
            if (-not $rcxSet) {
                foreach ($pl in $lines) {
                    if ($pl.Instr -match 'push\s+rcx') { $rcxSet = $true; break }
                    if ($pl.Instr -match '^\s*$' -or $pl.IsLabel) { continue }
                    if ($pl.Instr -match '^(push|sub|mov|and)\b') { continue }
                    break
                }
            }
            if (-not $rcxSet) {
                $warnings += (MkDiag $RelPath $Func.Name $l.Num "WARN" "L031" `
                    "REP prefix without visible rcx setup within 6 instructions" $l.Instr `
                    "rcx controls the repeat count; ensure it's set")
            }
        }
    }

    # L033
    if ($showStyle) {
        foreach ($l in $instrLines) {
            if ($l.Instr -match '(?:mov|add|sub|cmp|and|or|xor)\s+\w+\s*,\s*(0x[0-9a-fA-F]{3,}|\d{4,})' -and
                $l.Raw -notmatch ';') {
                $val = $Matches[1]
                $warnings += (MkDiag $RelPath $Func.Name $l.Num "STYLE" "L033" `
                    "magic number '$val' without comment" $l.Instr `
                    "consider adding a comment or using an equ constant")
            }
        }
    }

    # L035
    foreach ($l in $instrLines) {
        if ($l.Instr -match '\[\s*(eax|ebx|ecx|edx|esi|edi|ebp|esp)') {
            $reg = $Matches[1]
            $warnings += (MkDiag $RelPath $Func.Name $l.Num "WARN" "L035" `
                "32-bit register '$reg' used as memory address in 64-bit mode" $l.Instr `
                "address truncated to 32 bits, likely a bug" `
                -Notes @("in 64-bit mode, using a 32-bit register as a base/index`ntruncates the address to 4GB. use the 64-bit variant instead.") `
                -Helps @("replace '$reg' with '$($reg -replace '^e','r')' in the memory operand"))
        }
    }

    # L037
    if ($instrLines.Count -le 2 -and $instrLines.Count -gt 0) {
        $allRet = $true
        foreach ($il in $instrLines) { if ($il.Instr -notmatch '^ret\b') { $allRet = $false } }
        if ($allRet) {
            $warnings += (MkDiag $RelPath $Func.Name $Func.StartLine "INFO" "L037" `
                "function '$($Func.Name)' has no instructions (just ret)" "" `
                "empty function body")
        }
    }

    # L040
    foreach ($l in $instrLines) {
        if ($l.Instr -match '^\s*pop\s+rsp\b') {
            $warnings += (MkDiag $RelPath $Func.Name $l.Num "ERR" "L040" `
                "'pop rsp' is extremely dangerous and has undefined behavior" $l.Instr `
                "pop rsp corrupts the stack pointer mid-operation" `
                -Notes @("POP RSP reads from [RSP], then writes to RSP. the value of RSP`nused for the read is the value BEFORE incrementing. Intel documents`nthis but it almost never does what you want.") `
                -Helps @("if you need to restore RSP, use 'mov rsp, <source>' instead"))
        }
    }

    # L041
    if ($showPerf) {
        foreach ($l in $instrLines) {
            if ($l.Instr -match '^\s*lea\s+\w+\s*,\s*\[\s*\d+\s*\]') {
                $warnings += (MkDiag $RelPath $Func.Name $l.Num "PERF" "L041" `
                    "LEA with constant-only operand is equivalent to MOV" $l.Instr `
                    "LEA [imm] is slower than MOV reg, imm on some uarchs")
            }
        }
    }

    # L042
    for ($i = 0; $i -lt $instrLines.Count - 2; $i++) {
        if ($instrLines[$i].Instr -match '^\s*nop' -and $instrLines[$i+1].Instr -match '^\s*nop' -and $instrLines[$i+2].Instr -match '^\s*nop') {
            $warnings += (MkDiag $RelPath $Func.Name $instrLines[$i].Num "WARN" "L042" `
                "3+ consecutive NOP instructions (suspicious padding)" $instrLines[$i].Instr `
                "use 'align' directive instead of manual nop padding")
        }
    }

    # audit markers
    foreach ($a in $audits) {
        $warnings += (MkDiag $RelPath $Func.Name $a.Line "AUDIT" "L100" `
            "AUDIT: $($a.Message)" "flagged for human review" "flagged for human review")
    }

    # L101
    $firedCodes = @($warnings | ForEach-Object { $_.Code } | Select-Object -Unique)
    foreach ($exp in $expects) {
        if ($exp -notin $firedCodes) {
            $warnings += (MkDiag $RelPath $Func.Name $Func.StartLine "WARN" "L101" `
                "expected $exp but it didn't fire - stale annotation?" `
                "remove @ely:lint expect $exp if no longer needed" `
                "stale @ely:lint expect")
        }
    }

    # suppressions
    if ($suppressed.Count -gt 0) {
        $warnings = @($warnings | Where-Object { $_.Code -notin $suppressed })
    }

    return $warnings
}

# [per-file checks]

function Check-File {
    param([string]$RelPath, [string[]]$RawLines, [hashtable]$Decl)
    $warnings = @()
    $hasDefaultRel = $false; $inText = $false; $inData = $false
    $hasWinExterns = $false; $hasSyscall = $false

    for ($i = 0; $i -lt $RawLines.Count; $i++) {
        $line = $RawLines[$i]; $trimmed = $line.Trim()

        if ($trimmed -match '^default\s+rel') { $hasDefaultRel = $true }
        if ($trimmed -match '^section\s+\.text') { $inText = $true; $inData = $false }
        if ($trimmed -match '^section\s+\.data') { $inText = $false; $inData = $true }
        if ($trimmed -match '^section\s+\.bss')  { $inText = $false; $inData = $false }

        # L023
        if ($inData -and $trimmed -match '^(\w+)\s*:\s*db\s+"[^"]*"\s*$') {
            $lblName = $Matches[1]
            $hasLenEqu = $false
            $searchEnd = [Math]::Min($RawLines.Count - 1, $i + 3)
            for ($si = $i; $si -le $searchEnd; $si++) {
                if ($RawLines[$si] -match "${lblName}_len\s+equ\b") { $hasLenEqu = $true; break }
            }
            $isLookup = ($trimmed -match 'db\s+"[0-9A-Fa-f]+"\s*$')
            if (-not $hasLenEqu -and -not $isLookup) {
                $warnings += (MkDiag $RelPath "" ($i+1) "WARN" "L023" `
                    "string in .data may lack null terminator" $trimmed `
                    "C-style strings need trailing ',0'")
            }
        }

        # L029
        if ($inText -and $trimmed -match '^\w+\s*:\s*d[bwdq]\s' -and $trimmed -notmatch '^\s*;') {
            $warnings += (MkDiag $RelPath "" ($i+1) "WARN" "L029" `
                "data definition in .text section" $trimmed `
                "data should be in .data or .rodata section")
        }

        # L032
        if ($showStyle -and $line.Length -gt 120 -and $trimmed -notmatch '^\s*;' -and $trimmed -notmatch '^\s*db\b') {
            $warnings += (MkDiag $RelPath "" ($i+1) "STYLE" "L032" `
                "line is $($line.Length) characters (threshold: 120)" "" `
                "long line reduces readability")
        }

        # L034
        if ($trimmed -match 'section\s+\.text.*\bwrite\b') {
            $warnings += (MkDiag $RelPath "" ($i+1) "WARN" "L034" `
                "section .text marked writable (W^X violation)" $trimmed `
                "writable code sections are a security risk")
        }

        # L036
        if ($showStyle -and $line.Contains("`t") -and $trimmed -and $trimmed -notmatch '^\s*;') {
            $warnings += (MkDiag $RelPath "" ($i+1) "STYLE" "L036" `
                "tab character in source (inconsistent display widths)" "" `
                "use spaces for consistent formatting")
        }

        if ($trimmed -match '\bsyscall\b') { $hasSyscall = $true }
    }

    foreach ($e in $Decl.Externs) {
        if ($e -in $WinApis) { $hasWinExterns = $true; break }
    }

    # L021
    if (-not $hasDefaultRel -and $RawLines.Count -gt 5) {
        $hasCode = $RawLines | Where-Object { $_ -match '^\s*(mov|lea|call|push|pop)\b' }
        if ($hasCode) {
            $warnings += (MkDiag $RelPath "" 1 "WARN" "L021" `
                "missing 'default rel' directive" "" `
                "without 'default rel', NASM generates absolute addresses" `
                -Notes @("in 64-bit mode, RIP-relative addressing is more compact and`nrequired for position-independent code. without 'default rel',`nNASM uses absolute addressing which wastes bytes and breaks PIC.") `
                -Helps @("add 'default rel' at the top of the file"))
        }
    }

    # L038
    if ($hasSyscall -and $hasWinExterns) {
        $warnings += (MkDiag $RelPath "" 1 "WARN" "L038" `
            "file uses both 'syscall' and Win32 API imports" "" `
            "mixing syscall and WinAPI suggests cross-platform confusion")
    }

    # L019
    $fileText = $RawLines -join "`n"
    foreach ($ext in $Decl.Externs) {
        if ($ext -in $WinApis) { continue }
        $escaped = [regex]::Escape($ext)
        $refs = [regex]::Matches($fileText, "\b$escaped\b")
        $nonDeclRefs = @($refs | Where-Object { $_.Value -eq $ext })
        $declCount = @($RawLines | Where-Object { $_ -match "^\s*extern\b.*\b$escaped\b" }).Count
        if ($nonDeclRefs.Count -le $declCount) {
            $externLine = 1
            for ($ei = 0; $ei -lt $RawLines.Count; $ei++) {
                if ($RawLines[$ei] -match "^\s*extern\b.*\b$escaped\b") { $externLine = $ei + 1; break }
            }
            $warnings += (MkDiag $RelPath "" $externLine "WARN" "L019" `
                "extern '$ext' declared but never used in this file" "" `
                "unused extern import")
        }
    }

    # L020
    $labelDefs = @($RawLines | Where-Object { $_ -match '^([a-zA-Z_]\w*)\s*:' } | ForEach-Object { ($_ -split ':')[0].Trim() })
    foreach ($g in $Decl.Globals) {
        if ($g -notin $labelDefs) {
            $globalLine = 1
            $gEsc = [regex]::Escape($g)
            for ($gi = 0; $gi -lt $RawLines.Count; $gi++) {
                if ($RawLines[$gi] -match "^\s*global\b.*\b$gEsc\b") { $globalLine = $gi + 1; break }
            }
            $warnings += (MkDiag $RelPath "" $globalLine "WARN" "L020" `
                "global '${g}' declared but no label '${g}:' found in file" "" `
                "global without definition")
        }
    }

    return $warnings
}

# [cross-file checks]

function Check-CrossFile {
    param($FileData)
    $warnings = @()
    $globalMap = @{}; $externMap = @{}

    foreach ($fd in $FileData) {
        foreach ($g in $fd.Globals) {
            if (-not $globalMap.ContainsKey($g)) { $globalMap[$g] = @() }
            $globalMap[$g] += $fd.RelPath
        }
        foreach ($e in $fd.Externs) {
            if (-not $externMap.ContainsKey($e)) { $externMap[$e] = @() }
            $externMap[$e] += $fd.RelPath
        }
    }

    # L010
    foreach ($sym in $globalMap.Keys) {
        if ($sym -in $PerExeSymbols) { continue }
        $files = @($globalMap[$sym])
        if ($files.Count -gt 1) {
            $warnings += (MkDiag ($files -join ', ') "" 0 "ERR" "L010" `
                "'$sym' declared global in $($files.Count) files: linker will reject" `
                ($files -join ', ') "duplicate global symbol" `
                -Notes @("each global symbol must be defined exactly once across all`nobject files. the linker will report a multiply-defined error.") `
                -Helps @("remove the duplicate 'global $sym' from all but one file"))
        }
    }

    # L011
    $platformSyms = $WinApis + @('VirtualAlloc','VirtualFree')
    foreach ($sym in $externMap.Keys) {
        if ($sym -in $platformSyms -or $sym -in $PerExeSymbols) { continue }
        if ($sym[0] -cmatch '[A-Z]') { continue }
        if ($globalMap.ContainsKey($sym)) { continue }
        $files = $externMap[$sym] -join ', '
        $warnings += (MkDiag $files "" 0 "WARN" "L011" `
            "'$sym' declared extern but not global anywhere in project" `
            "used in: $files" "unresolved extern" `
            -Notes @("'$sym' is imported but no file exports it with 'global'.`nthe linker will fail with an unresolved symbol error.") `
            -Helps @("add 'global ${sym}' in the file that defines '${sym}:'`nor check for a typo in the extern name"))
    }

    return $warnings
}

# [main]

$files = @(Find-AsmFiles $target)
if ($files.Count -eq 0) {
    Write-Host "    no .asm files found" -ForegroundColor Yellow
    return
}

$allWarnings = @()
$fileData = @()
$fileCount = 0

foreach ($f in $files) {
    $rawLines = @(Get-Content $f.FullName)
    $relPath = $f.FullName.Replace($global:ProjectRoot, "").TrimStart("\","/")
    $script:FileLines[$relPath] = $rawLines

    $decl = Get-Declarations $rawLines
    $fileData += [PSCustomObject]@{ RelPath=$relPath; Globals=$decl.Globals; Externs=$decl.Externs }

    $fw = @(Check-File $relPath $rawLines $decl)
    if ($fw.Count -gt 0) { $allWarnings += $fw }

    $allLabels = @($rawLines | Where-Object { $_ -match '^([a-zA-Z_]\w*)\s*:' } | ForEach-Object { ($_ -split ':')[0].Trim() })

    $functions = Parse-Functions $rawLines
    foreach ($func in $functions) {
        $w = @(Check-Function $func $relPath $rawLines $decl.Externs $decl.Globals $allLabels)
        if ($w.Count -gt 0) { $allWarnings += $w }
    }
    $fileCount++
}

$crossWarnings = @(Check-CrossFile $fileData)
if ($crossWarnings.Count -gt 0) { $allWarnings += $crossWarnings }

# [filter by visibility]
$displayWarnings = $allWarnings | Where-Object {
    $dominated = $false
    if ($_.Level -eq "INFO" -and -not $strict) { $dominated = $true }
    if ($_.Level -eq "PERF" -and -not $showPerf) { $dominated = $true }
    if ($_.Level -eq "STYLE" -and -not $showStyle) { $dominated = $true }
    -not $dominated
}
$displayWarnings = @($displayWarnings)

$errs   = @($displayWarnings | Where-Object { $_.Level -eq "ERR" })
$warns  = @($displayWarnings | Where-Object { $_.Level -eq "WARN" })
$perfs  = @($displayWarnings | Where-Object { $_.Level -eq "PERF" })
$styles = @($displayWarnings | Where-Object { $_.Level -eq "STYLE" })
$audits = @($displayWarnings | Where-Object { $_.Level -eq "AUDIT" })
$infos  = @($allWarnings | Where-Object { $_.Level -eq "INFO" })

if ($displayWarnings.Count -eq 0) {
    $extra = ""
    $hidden = @()
    if ($infos.Count -gt 0 -and -not $strict)    { $hidden += "$($infos.Count) info" }
    $perfH = @($allWarnings | Where-Object { $_.Level -eq "PERF" })
    $styleH = @($allWarnings | Where-Object { $_.Level -eq "STYLE" })
    if ($perfH.Count -gt 0 -and -not $showPerf)  { $hidden += "$($perfH.Count) perf" }
    if ($styleH.Count -gt 0 -and -not $showStyle) { $hidden += "$($styleH.Count) style" }
    if ($hidden.Count -gt 0) { $extra = " ($($hidden -join ', ') hidden, use --all)" }
    Write-Host "    $fileCount files, all clean${extra}" -ForegroundColor Green
    return
}

# [render diagnostics]
$richBudget = @{ ERR=999; WARN=10; PERF=5; STYLE=5; AUDIT=999; INFO=3 }
$richCounts = @{ ERR=0; WARN=0; PERF=0; STYLE=0; AUDIT=0; INFO=0 }

$sorted = $displayWarnings | Sort-Object {
    switch($_.Level){"ERR"{0}"AUDIT"{1}"WARN"{2}"PERF"{3}"STYLE"{4}default{5}}
}, File, Line

$compactQueue = @()

foreach ($d in $sorted) {
    if ($d -isnot [PSCustomObject]) { continue }
    $lv = $d.Level
    if ($richCounts[$lv] -lt $richBudget[$lv]) {
        $null = Render-Diag $d
        $richCounts[$lv]++
    } else {
        $compactQueue += $d
    }
}

if ($compactQueue.Count -gt 0) {
    Write-Host ""
    Write-Host "    ... and $($compactQueue.Count) more:" -ForegroundColor DarkGray
    Write-Host ""
    foreach ($d in $compactQueue) {
        if ($d -isnot [PSCustomObject]) { continue }
        $null = Render-Compact $d
    }
    Write-Host ""
}

Render-Summary $displayWarnings $fileCount

if ($errs.Count -gt 0) { $global:LASTEXITCODE = 1 }