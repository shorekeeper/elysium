default rel
%include "defs.inc"
extern GetStdHandle,WriteFile,ReadFile,CreateFileA,CloseHandle
extern GetConsoleMode, SetConsoleMode
extern ExitProcess,GetCommandLineA
extern frontend_init,frontend_run
extern backend_init,backend_compile_binary_win
extern checker_run, diag_init, diag_summary, diag_get_errors
extern lex_source_buf, lex_source_len

global platform_write

STD_OUTPUT_HANDLE equ -11
GENERIC_READ equ 0x80000000
FILE_SHARE_READ equ 1
OPEN_EXISTING equ 3
FILE_ATTR_NORMAL equ 0x80
INVALID_HANDLE equ -1

section .data
msg_ban:db 13,10,"  elysiumc 'the mighty compiler'",13,10,13,10,0
msg_use:db "  Usage: elysiumc <input.ely> [-o output]",13,10,0
msg_p1:db "  [1/4] parsing",13,10,0
msg_p2:db "  [2/4] lowering to MIR",13,10,0
msg_p3:db "  [3/4] encoding x86",13,10,0
msg_p4:db "  [4/4] writing PE",13,10,0
msg_ok:db 13,10,"  Done: ",0
msg_chk: db "  [1.5/4] Checking...",13,10,0
msg_chk_fail: db 13,10,"  Compilation aborted.",13,10,0
msg_nl:db 13,10,0
msg_eo:db "  [error] cannot open file",13,10,0
msg_ast:db "  [debug] AST root: ",0
msg_mir:db "  [debug] MIR count: ",0
msg_code:db "  [debug] code bytes: ",0
def_out:db "output.exe",0
flag_dump_mir: dq 0
flag_dump_x86: dq 0  
flag_dump_sym: dq 0
flag_dump_map: dq 0
opt_dump_mir: db "--dump-mir",0
opt_dump_x86: db "--dump-x86",0
opt_dump_sym: db "--dump-sym",0
opt_dump_map: db "--dump-map",0

section .bss
stdout_h:resq 1
wr_tmp:resd 1
rd_tmp:resd 1
file_buf:resb INIT_SOURCE
in_name:resb 260
out_name:resb 260
dbg_buf:resb 32
console_mode: resd 1

section .text
global _start
_start:
    and rsp,-16
    sub rsp,32
    mov ecx,STD_OUTPUT_HANDLE
    call GetStdHandle
    add rsp,32
    mov [stdout_h],rax
    
    lea rdi,[msg_ban]
    call pw
    call frontend_init
    call backend_init
    sub rsp,32
    call GetCommandLineA
    add rsp,32
    mov rsi,rax
    call parse_args
    test eax,eax
    jz .usage

    ; [1/4] Parse
    lea rdi,[msg_p1]
    call pw
    sub rsp,64
    lea rcx,[in_name]
    mov rdx,GENERIC_READ
    mov r8d,FILE_SHARE_READ
    xor r9d,r9d
    mov dword[rsp+32],OPEN_EXISTING
    mov dword[rsp+40],FILE_ATTR_NORMAL
    mov qword[rsp+48],0
    call CreateFileA
    add rsp,64
    cmp rax,INVALID_HANDLE
    je .eo
    mov r12,rax
    sub rsp,48
    mov rcx,r12
    lea rdx,[file_buf]
    mov r8d,INIT_SOURCE-1
    lea r9,[rd_tmp]
    mov qword[rsp+32],0
    call ReadFile
    add rsp,48
    mov r13d,dword[rd_tmp]
    mov byte[file_buf+r13],0
    sub rsp,32
    mov rcx,r12
    call CloseHandle
    add rsp,32
    lea rsi,[file_buf]
    mov rdx,r13
    call frontend_run
    mov r14,rax

    ; debug: print AST root address
    lea rdi,[msg_ast]
    call pw
    mov rax,r14
    call print_num
    lea rdi,[msg_nl]
    call pw

; [1.5/4] Check
    lea rdi,[msg_chk]
    call pw
    ; init diagnostics with source and filename
    mov rdi,[lex_source_buf]
    mov rsi,[lex_source_len]
    lea rdx,[in_name]
    xor rcx,rcx
.fnl:cmp byte[rdx+rcx],0
    je .fnd
    inc rcx
    jmp .fnl
.fnd:
    call diag_init
    mov rdi,r14
    call checker_run
    test rax,rax
    jnz .chk_fail

    ; [2/4] Compile to binary
    lea rdi,[msg_p2]
    call pw

    mov rdi,r14
    lea rsi,[out_name]
    call backend_compile_binary_win

    ; [done]
    lea rdi,[msg_ok]
    call pw
    lea rdi,[out_name]
    call pw
    lea rdi,[msg_nl]
    call pw
    xor ecx,ecx
    call ExitProcess

.chk_fail:
    call diag_summary
    lea rdi,[msg_chk_fail]
    call pw
    mov ecx,1
    call ExitProcess

.usage:
    lea rdi,[msg_use]
    call pw
    xor ecx,ecx
    call ExitProcess
.eo:
    lea rdi,[msg_eo]
    call pw
    mov ecx,1
    call ExitProcess

; print decimal number from rax
print_num:
    push rbx
    push rcx
    push rdx
    push rsi
    test rax,rax
    jnz .nz
    mov byte[dbg_buf],'0'
    mov rsi,dbg_buf
    mov rdx,1
    call platform_write
    jmp .end
.nz:xor rcx,rcx
    mov rbx,10
.ext:test rax,rax
    jz .bld
    xor rdx,rdx
    div rbx
    add dl,'0'
    push rdx
    inc rcx
    jmp .ext
.bld:mov rbx,rcx
    xor rdx,rdx
.pop:test rcx,rcx
    jz .wr
    pop rax
    mov [dbg_buf+rdx],al
    inc rdx
    dec rcx
    jmp .pop
.wr:mov rsi,dbg_buf
    mov rdx,rbx
    call platform_write
.end:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; argument parsing
parse_args:
    cmp byte[rsi],'"'
    jne .unq
    inc rsi
.sq:cmp byte[rsi],0
    je .no
    cmp byte[rsi],'"'
    je .eq
    inc rsi
    jmp .sq
.eq:inc rsi
    jmp .ws
.unq:cmp byte[rsi],0
    je .no
    cmp byte[rsi],' '
    je .ws
    inc rsi
    jmp .unq
.ws:cmp byte[rsi],' '
    jne .ga
    inc rsi
    jmp .ws
.ga:cmp byte[rsi],0
    je .no
    lea rdi,[in_name]
    call carg
    push rsi
    lea rsi,[in_name]
    lea rdi,[out_name]
    call derive
    pop rsi
    call skipw
    test rax,rax
    jz .ok
    mov rsi,rax
    cmp byte[rsi],'-'
    jne .ok
    cmp byte[rsi+1],'o'
    jne .ok
    add rsi,2
    call skipw
    test rax,rax
    jz .ok
    mov rsi,rax
    lea rdi,[out_name]
    call carg
    lea rdi,[out_name]
    call ensexe
.ok:mov eax,1
    ret
.no:xor eax,eax
    ret

derive:push rcx
    mov rcx,rsi
    xor rax,rax
.fs:cmp byte[rcx],0
    je .fd
    cmp byte[rcx],'\'
    je .ff
    cmp byte[rcx],'/'
    je .ff
    inc rcx
    jmp .fs
.ff:lea rax,[rcx+1]
    inc rcx
    jmp .fs
.fd:test rax,rax
    jz .dn
    mov rsi,rax
.dn:
.dc:mov al,[rsi]
    cmp al,0
    je .de
    cmp al,'.'
    je .de
    mov [rdi],al
    inc rsi
    inc rdi
    jmp .dc
.de:mov byte[rdi],'.'
    mov byte[rdi+1],'e'
    mov byte[rdi+2],'x'
    mov byte[rdi+3],'e'
    mov byte[rdi+4],0
    pop rcx
    ret

ensexe:push rsi
    mov rsi,rdi
    xor rcx,rcx
.l: cmp byte[rsi+rcx],0
    je .c
    inc rcx
    jmp .l
.c: cmp rcx,4
    jl .a
    cmp byte[rsi+rcx-4],'.'
    jne .a
    cmp byte[rsi+rcx-3],'e'
    jne .a
    cmp byte[rsi+rcx-2],'x'
    jne .a
    cmp byte[rsi+rcx-1],'e'
    je .d
.a: lea rdi,[rsi+rcx]
    mov byte[rdi],'.'
    mov byte[rdi+1],'e'
    mov byte[rdi+2],'x'
    mov byte[rdi+3],'e'
    mov byte[rdi+4],0
.d: pop rsi
    ret

carg:push rcx
    xor rcx,rcx
.l: mov al,[rsi+rcx]
    cmp al,0
    je .d
    cmp al,' '
    je .d
    mov [rdi+rcx],al
    inc rcx
    jmp .l
.d: mov byte[rdi+rcx],0
    add rsi,rcx
    pop rcx
    ret

skipw:
.l: cmp byte[rsi],' '
    jne .c
    inc rsi
    jmp .l
.c: cmp byte[rsi],0
    je .n
    mov rax,rsi
    ret
.n: xor eax,eax
    ret

pw: push rsi
    push rdx
    mov rsi,rdi
    xor rdx,rdx
.l: cmp byte[rsi+rdx],0
    je .g
    inc rdx
    jmp .l
.g: call platform_write
    pop rdx
    pop rsi
    ret

platform_write:
    push rbx
    push r12
    push r13
    mov r12,rsi
    mov r13,rdx
    sub rsp,48
    mov rcx,[stdout_h]
    mov rdx,r12
    mov r8,r13
    lea r9,[wr_tmp]
    mov qword[rsp+32],0
    call WriteFile
    add rsp,48
    pop r13
    pop r12
    pop rbx
    ret