; test_internals.asm -- unit tests for compiler subsystems
default rel
%include "defs.inc"
extern GetStdHandle, WriteFile, ExitProcess
extern arena_init, arena_alloc, ely_memcmp
extern vmem_alloc, vmem_free, vmem_realloc
extern lexer_init, lexer_run
extern lex_source_buf, lex_source_len, lex_token_count, lex_tokens
extern lex_ensure_source
extern sym_init, sym_push, sym_lookup, sym_get_index, sym_alloc_bytes
extern sym_off, sym_type, sym_count
extern type_size, resolve_type_token
extern treg_init, treg_define, treg_lookup, treg_field_index
global platform_write

section .data
msg_pass: db "  [PASS] ",0
msg_fail: db "  [FAIL] ",0
msg_nl:   db 13,10,0
msg_done: db 13,10,"done",13,10,0
msg_banner: db "tests",13,10,0

t1_name: db "vmem_alloc basic",0
t2_name: db "vmem_realloc",0
t3_name: db "arena_alloc",0
t4_name: db "arena_alloc 1000 nodes",0
t5_name: db "ely_memcmp equal",0
t6_name: db "ely_memcmp differ",0
t7_name: db "sym_push + lookup",0
t8_name: db "sym_push 500 syms",0
t9_name: db "type_size i8=1",0
t10_name: db "type_size i64=8",0
t11_name: db "type_size u16=2",0
t12_name: db "lexer basic",0
t13_name: db "lexer token count",0

t7_sym: db "test_var"
t7_sym_len equ 8

t12_src: db "let x = 42;",0
t12_src_len equ 11

section .bss
stdout_h: resq 1
wr_tmp: resd 1
pass_cnt: resq 1
fail_cnt: resq 1

section .text
global _start
_start:
    and rsp, -16
    sub rsp, 32
    mov ecx, -11
    call GetStdHandle
    add rsp, 32
    mov [stdout_h], rax
    mov qword[pass_cnt], 0
    mov qword[fail_cnt], 0
    lea rdi, [msg_banner]
    call pw

    ; init subsystems
    call arena_init
    call sym_init
    call treg_init

    ; test 1: vmem_alloc
    mov rdi, 4096
    call vmem_alloc
    test rax, rax
    jz .t1f
    mov byte[rax], 0xAA
    cmp byte[rax], 0xAA
    jne .t1f
    push rax
    lea rdi, [t1_name]
    call report_pass
    pop rax
    mov rdi, rax
    call vmem_free
    jmp .t2
.t1f:
    lea rdi, [t1_name]
    call report_fail

    ; test 2: vmem_realloc
.t2:
    mov rdi, 64
    call vmem_alloc
    mov byte[rax], 0xBB
    mov rdi, rax
    mov rsi, 64
    mov rdx, 256
    call vmem_realloc
    test rax, rax
    jz .t2f
    cmp byte[rax], 0xBB
    jne .t2f
    push rax
    lea rdi, [t2_name]
    call report_pass
    pop rax
    mov rdi, rax
    call vmem_free
    jmp .t3
.t2f:
    lea rdi, [t2_name]
    call report_fail

    ; test 3: arena_alloc
.t3:
    mov rdi, 128
    call arena_alloc
    test rax, rax
    jz .t3f
    cmp byte[rax], 0
    jne .t3f
    lea rdi, [t3_name]
    call report_pass
    jmp .t4
.t3f:
    lea rdi, [t3_name]
    call report_fail

    ; test 4: arena 1000 nodes
.t4:
    xor rbx, rbx
.t4l:
    cmp rbx, 1000
    jge .t4ok
    mov rdi, NODE_SIZE
    call arena_alloc
    test rax, rax
    jz .t4f
    inc rbx
    jmp .t4l
.t4ok:
    lea rdi, [t4_name]
    call report_pass
    jmp .t5
.t4f:
    lea rdi, [t4_name]
    call report_fail

    ; test 5: memcmp equal
.t5:
    lea rsi, [t7_sym]
    lea rdi, [t7_sym]
    mov rcx, t7_sym_len
    call ely_memcmp
    test rax, rax
    jnz .t5f
    lea rdi, [t5_name]
    call report_pass
    jmp .t6
.t5f:
    lea rdi, [t5_name]
    call report_fail

    ; test 6: memcmp differ
.t6:
    lea rsi, [t7_sym]
    lea rdi, [t12_src]
    mov rcx, 4
    call ely_memcmp
    test rax, rax
    jz .t6f
    lea rdi, [t6_name]
    call report_pass
    jmp .t7
.t6f:
    lea rdi, [t6_name]
    call report_fail

    ; test 7: sym_push + lookup
.t7:
    call sym_init
    lea rsi, [t7_sym]
    mov rcx, t7_sym_len
    call sym_push
    mov rbx, rax
    lea rsi, [t7_sym]
    mov rcx, t7_sym_len
    call sym_lookup
    cmp rax, rbx
    jne .t7f
    lea rdi, [t7_name]
    call report_pass
    jmp .t8
.t7f:
    lea rdi, [t7_name]
    call report_fail

    ; test 8: 500 syms
.t8:
    call sym_init
    xor rbx, rbx
    sub rsp, 16
.t8l:
    cmp rbx, 500
    jge .t8ok
    ; generate unique name on stack
    mov rax, rbx
    mov byte[rsp], 'v'
    mov rcx, 100
    xor rdx, rdx
    div rcx
    add dl, '0'
    mov [rsp+1], dl
    mov rax, rbx
    mov rcx, 10
    xor rdx, rdx
    div rcx
    mov rax, rdx
    add al, '0'
    mov [rsp+2], al
    mov rax, rbx
    xor rdx, rdx
    mov rcx, 10
    div rcx
    ; ignore, just use 3-char name
    lea rsi, [rsp]
    mov rcx, 3
    call sym_push
    inc rbx
    jmp .t8l
.t8ok:
    add rsp, 16
    cmp qword[sym_count], 500
    jne .t8f
    lea rdi, [t8_name]
    call report_pass
    jmp .t9
.t8f:
    add rsp, 16
    lea rdi, [t8_name]
    call report_fail

    ; test 9: type_size i8 = 1
.t9:
    mov rax, TYPE_I8
    call type_size
    cmp rax, 1
    jne .t9f
    lea rdi, [t9_name]
    call report_pass
    jmp .t10
.t9f:
    lea rdi, [t9_name]
    call report_fail

    ; test 10: type_size i64 = 8
.t10:
    mov rax, TYPE_I64
    call type_size
    cmp rax, 8
    jne .t10f
    lea rdi, [t10_name]
    call report_pass
    jmp .t11
.t10f:
    lea rdi, [t10_name]
    call report_fail

    ; test 11: type_size u16 = 2
.t11:
    mov rax, TYPE_U16
    call type_size
    cmp rax, 2
    jne .t11f
    lea rdi, [t11_name]
    call report_pass
    jmp .t12
.t11f:
    lea rdi, [t11_name]
    call report_fail

    ; test 12: lexer basic
.t12:
    call lexer_init
    lea rdi, [t12_src_len+1]
    call lex_ensure_source
    mov rdi, [lex_source_buf]
    lea rsi, [t12_src]
    mov rcx, t12_src_len
    rep movsb
    mov qword[lex_source_len], t12_src_len
    mov rdi, [lex_source_buf]
    mov byte[rdi+t12_src_len], 0
    call lexer_run
    cmp qword[lex_token_count], 0
    je .t12f
    lea rdi, [t12_name]
    call report_pass
    jmp .t13
.t12f:
    lea rdi, [t12_name]
    call report_fail

    ; test 13: lexer token count for "let x = 42;"
    ; should be: LET IDENT EQUALS NUMBER SEMICOLON EOF = 6
.t13:
    cmp qword[lex_token_count], 6
    jne .t13f
    lea rdi, [t13_name]
    call report_pass
    jmp .end
.t13f:
    lea rdi, [t13_name]
    call report_fail

.end:
    lea rdi, [msg_done]
    call pw
    ; exit with fail count
    mov ecx, [fail_cnt]
    call ExitProcess

report_pass:
    push rdi
    lea rdi, [msg_pass]
    call pw
    pop rdi
    call pw
    lea rdi, [msg_nl]
    call pw
    inc qword[pass_cnt]
    ret

report_fail:
    push rdi
    lea rdi, [msg_fail]
    call pw
    pop rdi
    call pw
    lea rdi, [msg_nl]
    call pw
    inc qword[fail_cnt]
    ret

pw: push rsi
    push rdx
    mov rsi, rdi
    xor rdx, rdx
.l: cmp byte[rsi+rdx], 0
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
    mov r12, rsi
    mov r13, rdx
    sub rsp, 48
    mov rcx, [stdout_h]
    mov rdx, r12
    mov r8, r13
    lea r9, [wr_tmp]
    mov qword[rsp+32], 0
    call WriteFile
    add rsp, 48
    pop r13
    pop r12
    pop rbx
    ret