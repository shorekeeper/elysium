@echo off
echo building
cd /d %~dp0\..
for %%f in (libely\vmem libely\arena libely\lexer libely\types ^
    libely\symtab libely\typetab) do (
    nasm -f win64 -I. %%f.asm -o %%~nf.obj
    if errorlevel 1 exit /b 1
)
nasm -f win64 -I. tests\test_internals.asm -o test_internals.obj
if errorlevel 1 exit /b 1
link /nologo /subsystem:console /entry:_start /LARGEADDRESSAWARE:NO ^
  test_internals.obj vmem.obj arena.obj lexer.obj types.obj ^
  symtab.obj typetab.obj ^
  kernel32.lib /OUT:tests\test_internals.exe
if errorlevel 1 exit /b 1
del *.obj 2>nul
echo.
tests\test_internals.exe