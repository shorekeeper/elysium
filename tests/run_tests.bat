@echo off
setlocal enabledelayedexpansion
cd /d %~dp0\..
set PASS=0
set FAIL=0
set TOTAL=0
set EXE=elysiumc.exe

if not exist %EXE% (
    echo [error] %EXE% not found, run build_compiler.bat first
    exit /b 1
)

echo.
echo test
echo.

for %%f in (tests\e2e\*.ely) do (
    set /a TOTAL+=1
    set "NAME=%%~nf"
    set "ELY=%%f"
    set "EXP=tests\e2e\%%~nf.expected"
    set "OUT=tests\e2e\%%~nf.exe"
    set "GOT=tests\e2e\%%~nf.got"

    if not exist !EXP! (
        echo  [SKIP] !NAME! -- no .expected file
    ) else (
        %EXE% !ELY! -o !OUT! >nul 2>&1
        if errorlevel 1 (
            echo  [FAIL] !NAME! -- compile error
            set /a FAIL+=1
        ) else (
            !OUT! > !GOT! 2>&1
            fc /w !GOT! !EXP! >nul 2>&1
            if errorlevel 1 (
                echo  [FAIL] !NAME!
                set /a FAIL+=1
            ) else (
                echo  [PASS] !NAME!
                set /a PASS+=1
                del !OUT! !GOT! 2>nul
            )
        )
    )
)

echo.
echo Results: !PASS! passed, !FAIL! failed, !TOTAL! total
echo.
if !FAIL! gtr 0 exit /b 1
exit /b 0