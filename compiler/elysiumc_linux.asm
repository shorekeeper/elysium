; elysiumc_linux.asm 
; not tested properly yet
; old
; does not handle mir
; does nothing
; old
; bruh
%include "defs.inc"
extern frontend_init,frontend_run,backend_init,backend_compile,backend_get_output
extern backend_compile_binary
global platform_write

SYS_READ equ 0
SYS_WRITE equ 1
SYS_OPEN equ 2
SYS_CLOSE equ 3
SYS_FORK equ 57
SYS_EXECVE equ 59
SYS_EXIT equ 60
SYS_WAIT4 equ 61
SYS_UNLINK equ 87

section .data
msg_ban:db 10,"  elysium 'compiler' bruh",10,10,0
msg_use:db "  Usage: elysiumc <input.ely> [-o output]",10,0
msg_p1:db "  [1/4] Parsing...",10,0
msg_p2:db "  [2/4] Codegen...",10,0
msg_p3:db "  [3/4] Assembling...",10,0
msg_p4:db "  [4/4] Linking...",10,0
msg_ok:db 10,"  Done: ",0
msg_nl:db 10,0
msg_eo:db "  [error] cannot open file",10,0
msg_ew:db "  [error] cannot write temp",10,0
msg_en:db "  [error] nasm failed",10,0
msg_el:db "  [error] ld failed",10,0
sh_path:db "/bin/sh",0
sh_c:db "-c",0
tmp_asm:db "__ely_temp.asm",0
tmp_o:db "__ely_temp.o",0
nasm_cmd:db "nasm -f elf64 __ely_temp.asm -o __ely_temp.o",0
ld_pre:db "ld __ely_temp.o -o ",0

section .bss
saved_envp:resq 1
file_buf:resb SOURCE_MAX
out_name:resb 260
ld_cmd:resb 512
sh_argv:resq 4
wait_st:resd 1

section .text
global _start
_start:
    mov rbp,rsp
    mov rax,[rbp]
    lea r14,[rbp+8]
    lea r14,[r14+rax*8+8]
    mov [saved_envp],r14
    lea rdi,[msg_ban]
    call pw
    call frontend_init
    call backend_init
    cmp qword[rbp],2
    jl .usage
    mov r12,[rbp+16]
    cmp qword[rbp],4
    jl .der
    mov rsi,[rbp+24]
    cmp byte[rsi],'-'
    jne .der
    cmp byte[rsi+1],'o'
    jne .der
    mov rsi,[rbp+32]
    lea rdi,[out_name]
    call scpy
    jmp .have
.der:mov rsi,r12
    lea rdi,[out_name]
    call derive
.have:
    lea rdi,[msg_p1]
    call pw
    mov rdi,r12
    mov rax,SYS_OPEN
    xor rsi,rsi
    xor rdx,rdx
    syscall
    test rax,rax
    js .eo
    mov r13,rax
    mov rdi,r13
    mov rax,SYS_READ
    lea rsi,[file_buf]
    mov rdx,SOURCE_MAX-1
    syscall
    mov r14,rax
    mov byte[file_buf+r14],0
    mov rdi,r13
    mov rax,SYS_CLOSE
    syscall
    lea rsi,[file_buf]
    mov rdx,r14
    call frontend_run
    mov r15,rax
    lea rdi,[msg_p2]
    call pw
    
    ; use binary backend directly
    mov rdi,r15              ; AST root
    lea rsi,[out_name]       ; output filename
    call backend_compile_binary

    ; no need for nasm/ld steps!
    lea rdi,[msg_ok]
    call pw
    lea rdi,[out_name]
    call pw
    lea rdi,[msg_nl]
    call pw
    lea rdi,[msg_nl]
    call pw

    xor rdi,rdi
    mov rax,SYS_EXIT
    syscall
    test rax,rax
    js .ew
    mov r13,rax
    mov rdi,r13
    mov rax,SYS_WRITE
    mov rsi,r14
    mov rdx,r15
    syscall
    mov rdi,r13
    mov rax,SYS_CLOSE
    syscall
    lea rdi,[msg_p3]
    call pw
    lea rdi,[nasm_cmd]
    call run_sh
    test eax,eax
    jnz .en
    lea rdi,[msg_p4]
    call pw
    lea rdi,[ld_cmd]
    lea rsi,[ld_pre]
    call scat
    lea rsi,[out_name]
    call scat
    mov byte[rdi],0
    lea rdi,[ld_cmd]
    call run_sh
    test eax,eax
    jnz .el
    lea rdi,[tmp_asm]
    mov rax,SYS_UNLINK
    syscall
    lea rdi,[tmp_o]
    mov rax,SYS_UNLINK
    syscall
    lea rdi,[out_name]
    mov rax,90
    mov rsi,0o755
    syscall
    lea rdi,[msg_ok]
    call pw
    lea rdi,[out_name]
    call pw
    lea rdi,[msg_nl]
    call pw
    lea rdi,[msg_nl]
    call pw
    xor rdi,rdi
    mov rax,SYS_EXIT
    syscall
.usage:lea rdi,[msg_use]
    call pw
    xor rdi,rdi
    mov rax,SYS_EXIT
    syscall
.eo:lea rdi,[msg_eo]
    call pw
    jmp .die
.ew:lea rdi,[msg_ew]
    call pw
    jmp .die
.en:lea rdi,[msg_en]
    call pw
    jmp .die
.el:lea rdi,[msg_el]
    call pw
.die:mov rdi,1
    mov rax,SYS_EXIT
    syscall

run_sh:
    push rbx
    push r12
    mov r12,rdi
    lea rax,[sh_path]
    mov [sh_argv],rax
    lea rax,[sh_c]
    mov [sh_argv+8],rax
    mov [sh_argv+16],r12
    mov qword[sh_argv+24],0
    mov rax,SYS_FORK
    syscall
    test rax,rax
    jz .child
    js .fe
    mov rdi,rax
    lea rsi,[wait_st]
    xor rdx,rdx
    xor r10,r10
    mov rax,SYS_WAIT4
    syscall
    mov eax,[wait_st]
    shr eax,8
    and eax,0xFF
    pop r12
    pop rbx
    ret
.child:
    lea rdi,[sh_path]
    lea rsi,[sh_argv]
    mov rdx,[saved_envp]
    mov rax,SYS_EXECVE
    syscall
    mov rdi,127
    mov rax,SYS_EXIT
    syscall
.fe:mov eax,1
    pop r12
    pop rbx
    ret

derive:
    push rcx
    mov rcx,rsi
    xor rax,rax
.fs:cmp byte[rcx],0
    je .fd
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
.de:mov byte[rdi],0
    pop rcx
    ret

scpy:
.l: mov al,[rsi]
    mov [rdi],al
    test al,al
    jz .d
    inc rsi
    inc rdi
    jmp .l
.d: ret

scat:
    push rsi
.l: mov al,[rsi]
    test al,al
    jz .d
    mov [rdi],al
    inc rdi
    inc rsi
    jmp .l
.d: pop rsi
    ret

pw:
    push rsi
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
    push rax
    push rdi
    mov rdi,1
    mov rax,SYS_WRITE
    syscall
    pop rdi
    pop rax
    ret
section .note.GNU-stack noalloc noexec nowrite progbits