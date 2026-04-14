#Requires -Version 7.0
# cmd_lint.ps1 [file.asm|all] [--strict]
param([Parameter(ValueFromRemainingArguments)][string[]]$RawArgs)

Get-ChildItem (Join-Path $PSScriptRoot "_*.ps1") | ForEach-Object { . $_.FullName }

$target = "all"
$strict = $false
foreach ($a in $RawArgs) {
    if ([string]::IsNullOrWhiteSpace($a)) { continue }
    if ($a -eq "--strict") { $strict = $true }
    else { $target = $a }
}

Write-CmdHeader "lint" "[$target]$(if($strict){' --strict'})"


# Constants


$CalleeSaved = @('rbx','rbp','r12','r13','r14','r15')

$WriteOps = @(
    'mov','lea','xor','add','sub','inc','dec','shl','shr','sar',
    'and','or','not','neg','imul','movzx','movsx','movsxd',
    'sete','setne','setl','setg','setle','setge','seta','setb','setae','setbe',
    'cmove','cmovne','cmovl','cmovg','bsr','bsf','popcnt'
)
$WriteOpsRx = ($WriteOps | ForEach-Object { [regex]::Escape($_) }) -join '|'

# Entry points that don't follow calling convention (no caller to return to)
$EntryPoints = @('_start')

# Symbols expected to exist in multiple link units
$PerExeSymbols = @('_start','platform_write')


# File discovery


function Find-AsmFiles {
    param([string]$Target)
    if ($Target -eq "all") {
        $files = @()
        foreach ($d in @("libely","compiler","tests")) {
            $p = Join-Path $global:ProjectRoot $d
            if (Test-Path $p) {
                $files += Get-ChildItem $p -Filter "*.asm" -ErrorAction SilentlyContinue
            }
        }
        return $files
    }
    $f = Get-Item $Target -ErrorAction SilentlyContinue
    if ($f) { return @($f) }
    return @()
}


# Parsing


function Parse-Functions {
    param([string[]]$RawLines)
    $functions = @()
    $curName = $null
    $curLines = @()
    $curStart = 0

    for ($i = 0; $i -lt $RawLines.Count; $i++) {
        $line = $RawLines[$i]
        # top-level label
        if ($line -match '^([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.*)$' -and
            $line -notmatch '^\s*section\b' -and
            $line -notmatch '^\s*%' -and
            $line -notmatch '^\s*;' -and
            $line -notmatch '^\s*times\b') {

            if ($curName -and $curLines.Count -gt 0) {
                $functions += [PSCustomObject]@{
                    Name=$curName; StartLine=$curStart; Lines=$curLines
                }
            }
            $curName = $Matches[1]
            $curStart = $i + 1
            $curLines = @()

            #capture instruction after colon on same line
            $tail = $Matches[2].Trim()
            $semi = $tail.IndexOf(';')
            if ($semi -ge 0) { $tail = $tail.Substring(0,$semi).Trim() }
            if ($tail) {
                $curLines += [PSCustomObject]@{
                    Num     = ($i + 1)
                    Raw     = $line
                    Instr   = $tail
                    IsLabel = $false
                    LabelName = ""
                }
            }
        } elseif ($curName) {
            $t = $line.Trim()
            $semi = $t.IndexOf(';')
            if ($semi -ge 0) { $t = $t.Substring(0,$semi).Trim() }
            $isLbl = $false; $lblName = ""
            if ($t -match '^\.([\w]+)\s*:\s*(.*)$') {
                $isLbl = $true; $lblName = ".$($Matches[1])"
                $t = $Matches[2].Trim()
            }
            $curLines += [PSCustomObject]@{
                Num=$i+1; Raw=$line; Instr=$t; IsLabel=$isLbl; LabelName=$lblName
            }
        }
    }
    if ($curName -and $curLines.Count -gt 0) {
        $functions += [PSCustomObject]@{
            Name=$curName; StartLine=$curStart; Lines=$curLines
        }
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


# Per-function helpers


function Get-EntryPushes {
    param($Lines)
    $pushes = @()
    foreach ($l in $Lines) {
        if (-not $l.Instr) { continue }
        if ($l.Instr -match '^push\s+(\w+)$') {
            $pushes += $Matches[1].ToLower()
        } else { break }
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
    $pops = @()
    $j = $lastRet - 1
    while ($j -ge 0) {
        $t = $Lines[$j].Instr
        if (-not $t) { $j--; continue }
        if ($t -match '^pop\s+(\w+)$') {
            $pops = @($Matches[1].ToLower()) + $pops
            $j--
        } else { break }
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
                if (-not $modified.ContainsKey($reg)) {
                    $modified[$reg] = @{ Line=$l.Num; Text=$t }
                }
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


# Per-function checks

function Check-Function {
    param($Func, [string]$RelPath)
    $warnings = @()
    $lines = $Func.Lines
    $isEntry = $Func.Name -in $EntryPoints

    # Parse @ely:lint directives
    #   @ely:lint suppress L001         suppress specific code
    #   @ely:lint suppress L001,L003    suppress multiple
    #   @ely:lint suppress L001 -- why  with reason (ignored by tool, for humans)
    #   @ely:lint unsafe                suppress ALL checks for this function
    #   @ely:lint audit -- message      flag for human review (always shown)
    #   @ely:lint expect L001           warn if L001 does NOT fire (stale guard)
    #   @lint:allow L001                backward compat (old syntax)

    $suppressed = @()
    $isUnsafe = $false
    $audits = @()
    $expects = @()

    foreach ($l in $lines) {
        $raw = $l.Raw

        # @ely:lint <directive> [args] [-- reason]
        if ($raw -match '@ely:lint\s+(\w[\w-]*)\s*(.*)') {
            $directive = $Matches[1].ToLower()
            $rest = $Matches[2].Trim()
            # strip reason after --
            $reason = ""
            $dashIdx = $rest.IndexOf('--')
            if ($dashIdx -ge 0) {
                $reason = $rest.Substring($dashIdx + 2).Trim()
                $rest = $rest.Substring(0, $dashIdx).Trim()
            }

            switch ($directive) {
                "suppress" {
                    $codes = $rest -split '[,\s]+' | Where-Object { $_ -match '^L\d+$' }
                    $suppressed += $codes
                }
                "unsafe" {
                    $isUnsafe = $true
                }
                "audit" {
                    $audits += [PSCustomObject]@{
                        Line = $l.Num
                        Message = if ($reason) { $reason } else { $rest }
                    }
                }
                "expect" {
                    $codes = $rest -split '[,\s]+' | Where-Object { $_ -match '^L\d+$' }
                    $expects += $codes
                }
            }
        }

        # backward compat: @lint:allow L001
        if ($raw -match '@lint:allow\s+(L\d+)') {
            $suppressed += $Matches[1]
        }
    }

    # if @ely:lint unsafe - skip everything except audits
    if ($isUnsafe) {
        foreach ($a in $audits) {
            $warnings += [PSCustomObject]@{
                File=$RelPath; Func=$Func.Name; Line=$a.Line; Level="AUDIT"; Code="L100"
                Message="AUDIT: $($a.Message)"
                Detail="marked for review"
            }
        }
        return $warnings
    }

    
    # Actual checks
    
    $instrLines = @($lines | Where-Object { $_.Instr -and $_.Instr -notmatch '^(db|dw|dd|dq|times|section|extern|global)\b' })
    if ($instrLines.Count -lt 3) { return $warnings }

    $hasRet = $instrLines | Where-Object { $_.Instr -match '^ret\b' }
    $entryPushes = @(Get-EntryPushes $lines)
    $allPops     = @(Get-AllPopsBeforeLastRet $lines)
    $modified    = Get-ModifiedCalleeSaved $lines
    $bodySaved   = @(Get-BodyPushPopRegs $lines)

    #L001: callee-saved written without save
    if (-not $isEntry) {
        foreach ($reg in $modified.Keys) {
            if ($reg -in $entryPushes) { continue }
            if ($reg -in $bodySaved)   { continue }
            $info = $modified[$reg]
            $warnings += [PSCustomObject]@{
                File=$RelPath; Func=$Func.Name; Line=$info.Line; Level="ERR"; Code="L001"
                Message="'$reg' written without push/pop"
                Detail=$info.Text
            }
        }
    }

    if ($hasRet -and -not $isEntry) {
        #L002: epilogue pops callee-saved never pushed
        foreach ($reg in $allPops) {
            if ($reg -in $CalleeSaved -and $reg -notin $entryPushes) {
                $warnings += [PSCustomObject]@{
                    File=$RelPath; Func=$Func.Name; Line=$Func.StartLine; Level="ERR"; Code="L002"
                    Message="epilogue pops '$reg' but entry never pushed it"
                    Detail="push: [$($entryPushes -join ', ')]  pop: [$($allPops -join ', ')]"
                }
            }
        }

        $N = $entryPushes.Count
        if ($N -gt 0 -and $allPops.Count -eq $N) {
            #L003: push/pop order mismatch
            $expected = @($entryPushes)
            [array]::Reverse($expected)
            if (($allPops -join ',') -ne ($expected -join ',')) {
                $warnings += [PSCustomObject]@{
                    File=$RelPath; Func=$Func.Name; Line=$Func.StartLine; Level="WARN"; Code="L003"
                    Message="push/pop order mismatch"
                    Detail="push: [$($entryPushes -join ', ')]  pop: [$($allPops -join ', ')]  expected: [$($expected -join ', ')]"
                }
            }
        } elseif ($N -gt 0 -and $allPops.Count -lt $N) {
            #L004: fewer pops than pushes (callee-saved only)
            $calleePushed = @($entryPushes | Where-Object { $_ -in $CalleeSaved })
            if ($calleePushed.Count -gt 0) {
                $warnings += [PSCustomObject]@{
                    File=$RelPath; Func=$Func.Name; Line=$Func.StartLine; Level="WARN"; Code="L004"
                    Message="fewer pops ($($allPops.Count)) than pushes ($N) - callee-saved at risk"
                    Detail="push: [$($entryPushes -join ', ')]  pop: [$($allPops -join ', ')]"
                }
            }
        }
    }

    #L005: dead code (label-aware)
    $afterTerminal = $false
    $terminalLine = 0
    foreach ($l in $lines) {
        if ($l.IsLabel -or ($l.Raw -match '^\s*\.[\w]+\s*:')) {
            $afterTerminal = $false
        }
        $t = $l.Instr
        if (-not $t -or $t -match '^(db|dw|dd|dq|times|section|extern|global|%)\b') { continue }
        if ($afterTerminal) {
            $warnings += [PSCustomObject]@{
                File=$RelPath; Func=$Func.Name; Line=$l.Num; Level="INFO"; Code="L005"
                Message="possibly unreachable after line $terminalLine"
                Detail=$t
            }
            $afterTerminal = $false
        }
        if ($t -match '^ret\b') {
            $afterTerminal = $true; $terminalLine = $l.Num
        } elseif ($t -match '^jmp\s+[\.\w]' -and $t -notmatch 'qword|dword|\[') {
            $afterTerminal = $true; $terminalLine = $l.Num
        }
    }

    #L006: jump to undefined local label
    $definedLabels = @{}
    foreach ($l in $lines) {
        if ($l.IsLabel) { $definedLabels[$l.LabelName] = $l.Num }
        if ($l.Raw -match '^\s*(\.[\w]+)\s*:') { $definedLabels[$Matches[1]] = $l.Num }
    }
    foreach ($l in $instrLines) {
        if ($l.Instr -match '^\s*(?:j\w+|call|loop\w*)\s+(\.\w+)\b') {
            $lbl = $Matches[1]
            if (-not $definedLabels.ContainsKey($lbl)) {
                $warnings += [PSCustomObject]@{
                    File=$RelPath; Func=$Func.Name; Line=$l.Num; Level="ERR"; Code="L006"
                    Message="jump to undefined label '$lbl'"
                    Detail=$l.Instr
                }
            }
        }
    }

    #L007: falls through
    if ($instrLines.Count -gt 0) {
        $last = $instrLines[-1].Instr
        $isData = $last -match '^(db|dw|dd|dq|times|resb|resw|resd|resq)\b' -or
                  $last -match '\bequ\b' -or $last -match '^%' -or $last -match '^section\b'
        if (-not $isData -and $last -and
            $last -notmatch '^ret\b' -and $last -notmatch '^jmp\b' -and
            $last -notmatch '^call\s+ExitProcess\b' -and $last -notmatch '^syscall\b') {
            $warnings += [PSCustomObject]@{
                File=$RelPath; Func=$Func.Name; Line=$instrLines[-1].Num; Level="WARN"; Code="L007"
                Message="falls through (no ret/jmp at end)"
                Detail=$last
            }
        }
    }

    #L008: sub rsp / add rsp mismatch (--strict)
    if ($strict) {
        $subs = @($instrLines | Where-Object { $_.Instr -match '^sub\s+rsp\b' })
        $adds = @($instrLines | Where-Object { $_.Instr -match '^add\s+rsp\b' })
        if ($subs.Count -ne $adds.Count) {
            $warnings += [PSCustomObject]@{
                File=$RelPath; Func=$Func.Name; Line=$Func.StartLine; Level="WARN"; Code="L008"
                Message="sub rsp ($($subs.Count)) != add rsp ($($adds.Count))"
                Detail="possible stack leak"
            }
        }
    }

    # emit audit markers
    foreach ($a in $audits) {
        $warnings += [PSCustomObject]@{
            File=$RelPath; Func=$Func.Name; Line=$a.Line; Level="AUDIT"; Code="L100"
            Message="AUDIT: $($a.Message)"
            Detail="flagged for human review"
        }
    }

    # check expects: warn if expected warning didn't fire
    $firedCodes = @($warnings | ForEach-Object { $_.Code } | Select-Object -Unique)
    foreach ($exp in $expects) {
        if ($exp -notin $firedCodes) {
            $warnings += [PSCustomObject]@{
                File=$RelPath; Func=$Func.Name; Line=$Func.StartLine; Level="WARN"; Code="L101"
                Message="expected $exp but it didn't fire - stale annotation?"
                Detail="remove @ely:lint expect $exp if no longer needed"
            }
        }
    }

    # apply suppressions last
    if ($suppressed.Count -gt 0) {
        $warnings = @($warnings | Where-Object { $_.Code -notin $suppressed })
    }

    return $warnings
}


# Cross-file checks


function Check-CrossFile {
    param($FileData)
    $warnings = @()

    $globalMap = @{}
    $externMap = @{}

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

    #L010: duplicate global (skip per-exe symbols)
    foreach ($sym in $globalMap.Keys) {
        if ($sym -in $PerExeSymbols) { continue }
        $files = @($globalMap[$sym])
        if ($files.Count -gt 1) {
            $warnings += [PSCustomObject]@{
                File=($files -join ', '); Func=""; Line=0; Level="ERR"; Code="L010"
                Message="'$sym' global in $($files.Count) files"
                Detail=$files -join ', '
            }
        }
    }

    #L011: extern not global anywhere (skip platform imports)
    $platformSyms = @(
        'GetStdHandle','WriteFile','ReadFile','CreateFileA','CloseHandle',
        'ExitProcess','GetCommandLineA','VirtualAlloc','VirtualFree'
    )
    # also skip anything starting with uppercase (Win32 API convention)
    foreach ($sym in $externMap.Keys) {
        if ($sym -in $platformSyms) { continue }
        if ($sym -in $PerExeSymbols) { continue }
        if ($sym[0] -cmatch '[A-Z]') { continue }
        if ($globalMap.ContainsKey($sym)) { continue }
        $files = $externMap[$sym] -join ', '
        $warnings += [PSCustomObject]@{
            File=$files; Func=""; Line=0; Level="WARN"; Code="L011"
            Message="'$sym' extern but not global anywhere"
            Detail="used in: $files"
        }
    }

    return $warnings
}


# Main


$files = @(Find-AsmFiles $target)
if ($files.Count -eq 0) {
    Write-Host "    no .asm files found" -ForegroundColor Yellow
    return
}

$allWarnings = @()
$fileData = @()
$fileCount = 0

foreach ($f in $files) {
    $rawLines = Get-Content $f.FullName
    $relPath = $f.FullName.Replace($global:ProjectRoot, "").TrimStart("\","/")

    $decl = Get-Declarations $rawLines
    $fileData += [PSCustomObject]@{ RelPath=$relPath; Globals=$decl.Globals; Externs=$decl.Externs }

    $functions = Parse-Functions $rawLines
    foreach ($func in $functions) {
        $w = @(Check-Function $func $relPath)
        if ($w.Count -gt 0) { $allWarnings += $w }
    }
    $fileCount++
}

$crossWarnings = @(Check-CrossFile $fileData)
if ($crossWarnings.Count -gt 0) { $allWarnings += $crossWarnings }


# Output (skip INFO unless --strict)

$displayWarnings = if ($strict) {
    $allWarnings
} else {
    @($allWarnings | Where-Object { $_.Level -ne "INFO" })
}

$errs   = @($displayWarnings | Where-Object { $_.Level -eq "ERR" })
$warns  = @($displayWarnings | Where-Object { $_.Level -eq "WARN" })
$audits = @($displayWarnings | Where-Object { $_.Level -eq "AUDIT" })
$infos  = @($allWarnings | Where-Object { $_.Level -eq "INFO" })

if ($displayWarnings.Count -eq 0) {
    $extra = if ($infos.Count -gt 0) { " ($($infos.Count) info hidden, use --strict)" } else { "" }
    Write-Host "    $fileCount files, all clean${extra}" -ForegroundColor Green
    return
}

$grouped = $displayWarnings | Group-Object File | Sort-Object Name
foreach ($group in $grouped) {
    Write-Host ""
    Write-Host "    $($group.Name)" -ForegroundColor White
    $sorted = $group.Group | Sort-Object { switch($_.Level){"ERR"{0}"AUDIT"{1}"WARN"{2}default{3}} }, Line
    foreach ($w in $sorted) {
        $icon  = switch ($w.Level) { "ERR"{"x"} "AUDIT"{"@"} "WARN"{"!"} default{"."} }
        $color = switch ($w.Level) { "ERR"{"Red"} "AUDIT"{"Magenta"} "WARN"{"Yellow"} default{"DarkGray"} }
        $loc   = if ($w.Line -gt 0) { ":$($w.Line)" } else { "" }
        $fn    = if ($w.Func) { " $($w.Func)" } else { "" }

        Write-Host -NoNewline "      [$icon] " -ForegroundColor $color
        Write-Host -NoNewline "$($w.Code)" -ForegroundColor $color
        Write-Host -NoNewline "${fn}${loc}" -ForegroundColor Gray
        Write-Host "  $($w.Message)" -ForegroundColor $color
        if ($w.Detail) {
            Write-Host "           $($w.Detail)" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
$auditStr = if ($audits.Count -gt 0) { " | $($audits.Count) audit(s)" } else { "" }
$infoStr = if ($infos.Count -gt 0 -and -not $strict) { " | $($infos.Count) info (--strict)" } else { "" }
$summary = "    $fileCount files | $($errs.Count) error(s) | $($warns.Count) warning(s)${auditStr}${infoStr}"
$sumColor = if ($errs.Count -gt 0) { "Red" } elseif ($audits.Count -gt 0) { "Magenta" } elseif ($warns.Count -gt 0) { "Yellow" } else { "Green" }
Write-Host $summary -ForegroundColor $sumColor

if ($errs.Count -gt 0) { $global:LASTEXITCODE = 1 }