default rel
%include "defs.inc"
extern emit_cstr, be_target
global cg_emit_header, cg_emit_runtime, cg_emit_entry, cg_emit_footer

section .data
hdr_lnx:
 db "default rel",10,"bits 64",10,10,"global _start",10,10,0
hdr_win:
 db "default rel",10,"bits 64",10,10
 db "extern GetStdHandle",10,"extern WriteFile",10,"extern ExitProcess",10
 db "extern VirtualAlloc",10,"extern VirtualFree",10,10
 db "global _start",10,10,0

rt_data:
 db "section .data",10
 db "__rt_sv_current: dq 0",10
 db "__rt_pbuf: times 24 db 0",10,0
rt_data_w:
 db "__ely_stdout: dq 0",10,"__ely_written: dd 0",10,0

rt_text:
 db 10,"section .text",10,10,0

;Linux runtime
rt_prt_l:
 db "__rt_print_int:",10
 db "    push rbx",10,"    push r12",10,"    mov r12, rdi",10
 db "    lea rbx, [__rt_pbuf + 22]",10,"    mov byte [rbx], 10",10
 db "    mov rax, r12",10,"    test rax, rax",10,"    jns .pp",10,"    neg rax",10
 db ".pp:",10,"    xor ecx, ecx",10,"    inc ecx",10,"    mov rdi, 10",10
 db ".pl:",10,"    xor edx, edx",10,"    div rdi",10,"    add dl, 48",10
 db "    dec rbx",10,"    mov [rbx], dl",10,"    inc ecx",10
 db "    test rax, rax",10,"    jnz .pl",10
 db "    test r12, r12",10,"    jns .pw",10
 db "    dec rbx",10,"    mov byte [rbx], 45",10,"    inc ecx",10
 db ".pw:",10,"    mov eax, 1",10,"    mov edi, 1",10,"    mov rsi, rbx",10
 db "    mov edx, ecx",10,"    syscall",10
 db "    pop r12",10,"    pop rbx",10,"    ret",10,10,0
rt_pstr_l:
 db "__rt_print_str:",10
 db "    mov rax, 1",10,"    mov rdx, rsi",10,"    mov rsi, rdi",10
 db "    mov edi, 1",10,"    syscall",10,"    ret",10,10,0
rt_claim_l:
 db "__rt_claim:",10
 db "    push rbx",10
 db "    add rdi, 8",10
 db "    mov rsi, rdi",10
 db "    xor edi, edi",10
 db "    mov rdx, 3",10
 db "    mov r10, 0x22",10
 db "    mov r8, -1",10
 db "    xor r9d, r9d",10
 db "    mov rax, 9",10
 db "    syscall",10
 db "    test rax, rax",10
 db "    js .cf",10
 db "    mov [rax], rsi",10
 db "    add rax, 8",10
 db "    pop rbx",10
 db "    ret",10
 db ".cf:",10
 db "    xor eax, eax",10
 db "    pop rbx",10
 db "    ret",10,10,0
rt_release_l:
 db "__rt_release:",10
 db "    sub rdi, 8",10
 db "    mov rsi, [rdi]",10
 db "    mov rax, 11",10
 db "    syscall",10
 db "    ret",10,10,0
rt_pool_l:
 db "__rt_pool_create:",10
 db "    push rbx",10
 db "    mov rbx, rdi",10
 db "    add rbx, 16",10
 db "    mov rsi, rbx",10
 db "    xor edi, edi",10
 db "    mov rdx, 3",10
 db "    mov r10, 0x22",10
 db "    mov r8, -1",10
 db "    xor r9d, r9d",10
 db "    mov rax, 9",10
 db "    syscall",10
 db "    test rax, rax",10
 db "    js .pf",10
 db "    sub rbx, 16",10
 db "    mov [rax], rbx",10
 db "    mov qword [rax+8], 0",10
 db "    pop rbx",10
 db "    ret",10
 db ".pf:",10
 db "    xor eax, eax",10
 db "    pop rbx",10
 db "    ret",10,10
 db "__rt_pool_claim:",10
 db "    mov rax, [rdi+8]",10
 db "    mov rcx, rax",10
 db "    add rcx, rsi",10
 db "    cmp rcx, [rdi]",10
 db "    ja .pcf",10
 db "    mov [rdi+8], rcx",10
 db "    lea rax, [rdi+16+rax]",10
 db "    ret",10
 db ".pcf:",10
 db "    xor eax, eax",10
 db "    ret",10,10
 db "__rt_pool_drain:",10
 db "    mov rsi, [rdi]",10
 db "    add rsi, 16",10
 db "    mov rax, 11",10
 db "    syscall",10
 db "    ret",10,10,0

;Windows runtime
rt_init_w:
 db "__rt_init:",10
 db "    sub rsp, 40",10,"    mov ecx, -11",10,"    call GetStdHandle",10
 db "    add rsp, 40",10,"    mov [__ely_stdout], rax",10,"    ret",10,10,0
rt_prt_w:
 db "__rt_print_int:",10
 db "    push rbx",10,"    push r12",10,"    mov r12, rdi",10
 db "    lea rbx, [__rt_pbuf + 22]",10,"    mov byte [rbx], 10",10
 db "    mov rax, r12",10,"    test rax, rax",10,"    jns .pp",10,"    neg rax",10
 db ".pp:",10,"    xor ecx, ecx",10,"    inc ecx",10,"    mov r8, 10",10
 db ".pl:",10,"    xor edx, edx",10,"    div r8",10,"    add dl, 48",10
 db "    dec rbx",10,"    mov [rbx], dl",10,"    inc ecx",10
 db "    test rax, rax",10,"    jnz .pl",10
 db "    test r12, r12",10,"    jns .pw",10
 db "    dec rbx",10,"    mov byte [rbx], 45",10,"    inc ecx",10
 db ".pw:",10,"    mov r8d, ecx",10,"    sub rsp, 40",10
 db "    mov rcx, [__ely_stdout]",10,"    mov rdx, rbx",10
 db "    lea r9, [__ely_written]",10,"    mov qword [rsp+32], 0",10
 db "    call WriteFile",10,"    add rsp, 40",10
 db "    pop r12",10,"    pop rbx",10,"    ret",10,10,0
rt_pstr_w:
 db "__rt_print_str:",10
 db "    sub rsp, 40",10
 db "    mov rcx, [__ely_stdout]",10,"    mov rdx, rdi",10
 db "    mov r8, rsi",10,"    lea r9, [__ely_written]",10
 db "    mov qword [rsp+32], 0",10,"    call WriteFile",10
 db "    add rsp, 40",10,"    ret",10,10,0
rt_claim_w:
 db "__rt_claim:",10
 db "    push rbx",10
 db "    add rdi, 8",10
 db "    mov rbx, rdi",10
 db "    sub rsp, 40",10
 db "    xor ecx, ecx",10
 db "    mov rdx, rbx",10
 db "    mov r8d, 0x3000",10
 db "    mov r9d, 4",10
 db "    call VirtualAlloc",10
 db "    add rsp, 40",10
 db "    test rax, rax",10
 db "    jz .cf",10
 db "    mov [rax], rbx",10
 db "    add rax, 8",10
 db "    pop rbx",10
 db "    ret",10
 db ".cf:",10
 db "    xor eax, eax",10
 db "    pop rbx",10
 db "    ret",10,10,0
rt_release_w:
 db "__rt_release:",10
 db "    sub rdi, 8",10
 db "    sub rsp, 40",10
 db "    mov rcx, rdi",10
 db "    xor edx, edx",10
 db "    mov r8d, 0x8000",10
 db "    call VirtualFree",10
 db "    add rsp, 40",10
 db "    ret",10,10,0
rt_pool_w:
 db "__rt_pool_create:",10
 db "    push rbx",10
 db "    mov rbx, rdi",10
 db "    add rbx, 16",10
 db "    sub rsp, 40",10
 db "    xor ecx, ecx",10
 db "    mov rdx, rbx",10
 db "    mov r8d, 0x3000",10
 db "    mov r9d, 4",10
 db "    call VirtualAlloc",10
 db "    add rsp, 40",10
 db "    test rax, rax",10
 db "    jz .pf",10
 db "    sub rbx, 16",10
 db "    mov [rax], rbx",10
 db "    mov qword [rax+8], 0",10
 db "    pop rbx",10
 db "    ret",10
 db ".pf:",10
 db "    xor eax, eax",10
 db "    pop rbx",10
 db "    ret",10,10
 db "__rt_pool_claim:",10
 db "    mov rax, [rdi+8]",10
 db "    mov rcx, rax",10
 db "    add rcx, rsi",10
 db "    cmp rcx, [rdi]",10
 db "    ja .pcf",10
 db "    mov [rdi+8], rcx",10
 db "    lea rax, [rdi+16+rax]",10
 db "    ret",10
 db ".pcf:",10
 db "    xor eax, eax",10
 db "    ret",10,10
 db "__rt_pool_drain:",10
 db "    sub rsp, 40",10
 db "    mov rcx, rdi",10
 db "    xor edx, edx",10
 db "    mov r8d, 0x8000",10
 db "    call VirtualFree",10
 db "    add rsp, 40",10
 db "    ret",10,10,0

; checkpoint
rt_ckpt:
 db "__rt_ckpt_save:",10
 db "    mov [rdi], rbx",10,"    mov [rdi+8], rbp",10
 db "    mov [rdi+16], r12",10,"    mov [rdi+24], r13",10
 db "    mov [rdi+32], r14",10,"    mov [rdi+40], r15",10
 db "    lea rax, [rsp+8]",10,"    mov [rdi+48], rax",10
 db "    mov rax, [rsp]",10,"    mov [rdi+56], rax",10
 db "    xor eax, eax",10,"    ret",10,10
 db "__rt_ckpt_restore:",10
 db "    mov rbx, [rdi]",10,"    mov rbp, [rdi+8]",10
 db "    mov r12, [rdi+16]",10,"    mov r13, [rdi+24]",10
 db "    mov r14, [rdi+32]",10,"    mov r15, [rdi+40]",10
 db "    mov rsp, [rdi+48]",10,"    mov rax, rsi",10
 db "    test rax, rax",10,"    jnz .crok",10,"    inc rax",10
 db ".crok:",10,"    jmp qword [rdi+56]",10,10,0

; entry points
ent_l:
 db 10,"_start:",10,"    call __ely_fn_main",10
 db "    mov rdi, rax",10,"    mov rax, 60",10,"    syscall",10,0
ent_w:
 db 10,"_start:",10,"    and rsp, -16",10,"    sub rsp, 32",10
 db "    call __rt_init",10,"    call __ely_fn_main",10
 db "    mov ecx, eax",10,"    call ExitProcess",10,0
ftr_l:
 db 10,"section .note.GNU-stack noalloc noexec nowrite progbits",10,0

section .text
cg_emit_header:
    cmp qword[be_target],TARGET_WIN64
    je .w
    mov rdi,hdr_lnx
    jmp emit_cstr
.w: mov rdi,hdr_win
    jmp emit_cstr

cg_emit_runtime:
    mov rdi,rt_data
    call emit_cstr
    cmp qword[be_target],TARGET_WIN64
    jne .t
    mov rdi,rt_data_w
    call emit_cstr
.t: mov rdi,rt_text
    call emit_cstr
    cmp qword[be_target],TARGET_WIN64
    je .w
    ; Linux runtime
    mov rdi,rt_prt_l
    call emit_cstr
    mov rdi,rt_pstr_l
    call emit_cstr
    mov rdi,rt_claim_l
    call emit_cstr
    mov rdi,rt_release_l
    call emit_cstr
    mov rdi,rt_pool_l
    call emit_cstr
    jmp .c
.w: ; Windows runtime
    mov rdi,rt_init_w
    call emit_cstr
    mov rdi,rt_prt_w
    call emit_cstr
    mov rdi,rt_pstr_w
    call emit_cstr
    mov rdi,rt_claim_w
    call emit_cstr
    mov rdi,rt_release_w
    call emit_cstr
    mov rdi,rt_pool_w
    call emit_cstr
.c: mov rdi,rt_ckpt
    jmp emit_cstr

cg_emit_entry:
    cmp qword[be_target],TARGET_WIN64
    je .w
    mov rdi,ent_l
    jmp emit_cstr
.w: mov rdi,ent_w
    jmp emit_cstr

cg_emit_footer:
    cmp qword[be_target],TARGET_WIN64
    je .w
    mov rdi,ftr_l
    jmp emit_cstr
.w: ret