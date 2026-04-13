; frontend.asm - public facade
; exports: frontend_init, frontend_run(rsi=src,rdx=len)->rax=AST
default rel
%include "defs.inc"
extern arena_init, lexer_init, parser_init
extern lex_source_buf, lex_source_len, lex_ensure_source, lexer_run, parser_run
global frontend_init, frontend_run

section .text
frontend_init:
    call arena_init
    call lexer_init
    call parser_init
    ret

frontend_run:
    push rbx
    push r12
    push rbp
    mov rbp, rsp
    push rdx
    ; ensure source buffer big enough
    lea rdi, [rdx+1]
    call lex_ensure_source
    pop rdx
    push rdx
    mov rdi, [lex_source_buf]
    mov rcx, rdx
    rep movsb
    pop rdx
    mov [lex_source_len], rdx
    mov rdi, [lex_source_buf]
    mov byte[rdi+rdx], 0
    call lexer_run
    call parser_run
    mov rsp, rbp
    pop rbp
    pop r12
    pop rbx
    ret