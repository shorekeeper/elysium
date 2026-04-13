@echo off
echo building
cd /d %~dp0\..
for %%f in (libely\vmem libely\arena libely\lexer libely\parser libely\frontend ^
    libely\types libely\symtab libely\emit libely\codegen_rt ^
    libely\codegen_expr libely\codegen_stmt libely\codegen_func ^
    libely\backend libely\ir libely\lower libely\x86enc libely\pe64 ^
    libely\typetab) do (
    nasm -f win64 -I. %%f.asm -o %%~nf.obj
    if errorlevel 1 exit /b 1
)
nasm -f win64 -I. tests\dumptool.asm -o dumptool.obj
if errorlevel 1 exit /b 1
link /nologo /subsystem:console /entry:_start /LARGEADDRESSAWARE:NO ^
  dumptool.obj vmem.obj arena.obj lexer.obj parser.obj frontend.obj types.obj ^
  symtab.obj emit.obj codegen_rt.obj codegen_expr.obj codegen_stmt.obj ^
  codegen_func.obj backend.obj ir.obj lower.obj x86enc.obj pe64.obj ^
  typetab.obj ^
  kernel32.lib /OUT:elydump.exe
if errorlevel 1 exit /b 1
del *.obj 2>nul
echo elydump.exe