; lex_source_buf and lex_tokens are heap-allocated pointers.
; r14 caches lex_source_buf throughout lexer_run to avoid repeated loads.
default rel
%include "defs.inc"
extern ely_memcmp, platform_write, arena_alloc
extern vmem_alloc, vmem_realloc
global lexer_init, lexer_run, lex_ensure_source
global lex_tokens, lex_token_count, lex_source_buf, lex_source_len

section .data
kw_module:db "module",0
kw_fn:db "fn",0
kw_let:db "let",0
kw_return:db "return",0
kw_if:db "if",0
kw_else:db "else",0
kw_print:db "print",0
kw_match:db "match",0
kw_anchor:db "anchor",0
kw_unwind:db "unwind",0
kw_supervise:db "supervise",0
kw_mut:db "mut",0
kw_guard:db "guard",0
kw_public:db "public",0
kw_private:db "private",0
kw_protected:db "protected",0
kw_sealed:db "sealed",0
kw_true:db "true",0
kw_false:db "false",0
kw_bool:db "bool",0
kw_i8:db "i8",0
kw_i16:db "i16",0
kw_i32:db "i32",0
kw_i64:db "i64",0
kw_ptr:db "ptr",0
kw_void:db "void",0
kw_raw:db "raw",0
kw_addr:db "addr",0
kw_import:db "import",0
kw_type:db "type",0
kw_pstr:db "print_str",0
kw_len:db "len",0
kw_store:db "store",0
kw_load:db "load",0
kw_claim:db "claim",0
kw_release:db "release",0
kw_claim_g:db "claim_guarded",0
kw_release_g:db "release_guarded",0
kw_pool_new:db "pool_create",0
kw_pool_claim:db "pool_claim",0
kw_pool_drain:db "pool_drain",0
kw_arrlen:db "arrlen",0
kw_u8:db "u8",0
kw_u16:db "u16",0
kw_u32:db "u32",0
kw_u64:db "u64",0
kw_while:db "while",0
kw_for:db "for",0
kw_in:db "in",0
kw_break:db "break",0
kw_continue:db "continue",0
align 8
kw_table:
    dq kw_module,TOK_MODULE,6, kw_fn,TOK_FN,2, kw_let,TOK_LET,3
    dq kw_return,TOK_RETURN,6, kw_if,TOK_IF,2, kw_else,TOK_ELSE,4
    dq kw_print,TOK_PRINT,5, kw_match,TOK_MATCH,5, kw_anchor,TOK_ANCHOR,6
    dq kw_unwind,TOK_UNWIND,6, kw_supervise,TOK_SUPERVISE,9, kw_mut,TOK_MUT,3
    dq kw_guard,TOK_GUARD,5, kw_public,TOK_PUBLIC,6, kw_private,TOK_PRIVATE,7
    dq kw_protected,TOK_PROTECTED,9, kw_sealed,TOK_SEALED,6
    dq kw_true,TOK_TRUE,4, kw_false,TOK_FALSE,5
    dq kw_bool,TOK_BOOL_KW,4, kw_i8,TOK_I8_KW,2
    dq kw_i16,TOK_I16_KW,3, kw_i32,TOK_I32_KW,3
    dq kw_i64,TOK_I64_KW,3, kw_ptr,TOK_PTR_KW,3
    dq kw_void,TOK_VOID_KW,4, kw_raw,TOK_RAW,3
    dq kw_addr,TOK_ADDR,4, kw_import,TOK_IMPORT,6
    dq kw_type,TOK_TYPE_KW,4, kw_pstr,TOK_PRINT_STR,9
    dq kw_len,TOK_LEN,3, kw_store,TOK_STORE,5
    dq kw_load,TOK_LOAD,4, kw_claim,TOK_CLAIM,5
    dq kw_release,TOK_RELEASE,7, kw_claim_g,TOK_CLAIM_G,13
    dq kw_release_g,TOK_RELEASE_G,16, kw_pool_new,TOK_POOL_NEW,11
    dq kw_pool_claim,TOK_POOL_CLAIM,10, kw_pool_drain,TOK_POOL_DRAIN,10
    dq kw_arrlen,TOK_ARRLEN,6
    dq kw_u8,TOK_U8_KW,2, kw_u16,TOK_U16_KW,3
    dq kw_u32,TOK_U32_KW,3, kw_u64,TOK_U64_KW,3
    dq kw_while,TOK_WHILE,5, kw_for,TOK_FOR,3
    dq kw_in,TOK_IN,2, kw_break,TOK_BREAK,5
    dq kw_continue,TOK_CONTINUE,8
dq 0,0,0

section .bss
lex_source_buf: resq 1       ; pointer to source text buffer
lex_source_len: resq 1
lex_source_cap: resq 1
lex_pos: resq 1
lex_line: resq 1
lex_tokens: resq 1           ; pointer to token array
lex_token_count: resq 1
lex_tokens_cap: resq 1
str_stage: resb STR_STAGE_SIZE

section .text

; lexer_init: allocate source and token buffers
lexer_init:
    xor rax, rax
    mov [lex_pos], rax
    mov [lex_token_count], rax
    mov [lex_source_len], rax
    mov qword[lex_line], 1
    ; allocate source buffer
    mov qword[lex_source_cap], INIT_SOURCE
    mov rdi, INIT_SOURCE
    call vmem_alloc
    mov [lex_source_buf], rax
    ; allocate token array
    mov qword[lex_tokens_cap], INIT_TOKENS
    mov rdi, INIT_TOKENS * TOKEN_SIZE
    call vmem_alloc
    mov [lex_tokens], rax
    ret

; lex_ensure_source: rdi=needed_bytes -> grow source buffer if too small
lex_ensure_source:
    cmp rdi, [lex_source_cap]
    jl .ok
    push rdi
    mov rdi, [lex_source_buf]
    mov rsi, [lex_source_cap]
    mov rdx, rsi
    shl rdx, 1
    cmp rdx, [rsp]
    jge .sz
    mov rdx, [rsp]
    add rdx, 4096
.sz:mov [lex_source_cap], rdx
    call vmem_realloc
    mov [lex_source_buf], rax
    pop rdi
.ok:ret

; lex_grow_tokens: double the token array
lex_grow_tokens:
    push rdi
    push rsi
    push rdx
    mov rdi, [lex_tokens]
    mov rsi, [lex_tokens_cap]
    imul rsi, rsi, TOKEN_SIZE
    mov rdx, [lex_tokens_cap]
    shl rdx, 1
    mov [lex_tokens_cap], rdx
    imul rdx, rdx, TOKEN_SIZE
    call vmem_realloc
    mov [lex_tokens], rax
    pop rdx
    pop rsi
    pop rdi
    ret

; add_tok: rax=type, rsi=value, rdx=length -> append token
add_tok:
    push rbx
    push rcx
    push r11
    mov rbx, [lex_token_count]
    cmp rbx, [lex_tokens_cap]
    jl .store
    call lex_grow_tokens
.store:
    imul rcx, rbx, TOKEN_SIZE
    mov r11, [lex_tokens]
    mov [r11+rcx], rax
    mov [r11+rcx+8], rsi
    mov [r11+rcx+16], rdx
    push rax
    mov rax, [lex_line]
    mov [r11+rcx+24], rax
    pop rax
    inc qword[lex_token_count]
    pop r11
    pop rcx
    pop rbx
    ret

is_id_start:
    cmp r8b,'_'
    je .y
    cmp r8b,'a'
    jb .u
    cmp r8b,'z'
    jbe .y
.u: cmp r8b,'A'
    jb .n
    cmp r8b,'Z'
    jbe .y
.n: xor eax,eax
    ret
.y: mov al,1
    ret

; lexer_run: tokenize entire source buffer
; r14 = cached pointer to source bytes (avoids reloading [lex_source_buf] every access)
lexer_run:
    push rbx
    push r12
    push r13
    push r14
    mov r14, [lex_source_buf]
.loop:
    mov rsi,[lex_pos]
    cmp rsi,[lex_source_len]
    jge .eof
    movzx r8d,byte[r14+rsi]
    ; track newlines
    cmp r8b,10
    jne .no_nl
    inc qword[lex_line]
.no_nl:
    cmp r8b,' '
    je .ws
    cmp r8b,9
    je .ws
    cmp r8b,10
    je .ws
    cmp r8b,13
    je .ws
    ; // comment
    cmp r8b,'/'
    jne .nc
    lea rax,[rsi+1]
    cmp rax,[lex_source_len]
    jge .nc
    cmp byte[r14+rsi+1],'/'
    jne .nc
.cmt:inc rsi
    cmp rsi,[lex_source_len]
    jge .ce
    cmp byte[r14+rsi],10
    jne .cmt
.ce:mov [lex_pos],rsi
    jmp .loop
.nc:
    call is_id_start
    test al,al
    jnz .ident
    cmp r8b,'0'
    jb .nd
    cmp r8b,'9'
    jbe .num
.nd:cmp r8b,'{'
    je .t_lb
    cmp r8b,'}'
    je .t_rb
    cmp r8b,'('
    je .t_lp
    cmp r8b,')'
    je .t_rp
    cmp r8b,';'
    je .t_se
    cmp r8b,','
    je .t_co
    cmp r8b,'+'
    je .t_pl
    cmp r8b,'*'
    je .t_st
    cmp r8b,'&'
    je .t_am
    cmp r8b,'_'
    je .t_us
    cmp r8b,'@'
    je .t_at
    cmp r8b,'['
    je .t_lbk
    cmp r8b,']'
    je .t_rbk
    cmp r8b,'-'
    je .m_mi
    cmp r8b,'='
    je .m_eq
    cmp r8b,'!'
    je .m_ba
    cmp r8b,'<'
    je .m_lt
    cmp r8b,'>'
    je .m_gt
    cmp r8b,'|'
    je .m_pi
    cmp r8b,'/'
    je .t_sl
    cmp r8b,':'
    je .m_cl
    cmp r8b,'.'
    je .m_dot
    cmp r8b,'"'
    je .str
.ws:inc qword[lex_pos]
    jmp .loop

; identifier
.ident:
    mov r9,rsi
.id_l:inc rsi
    cmp rsi,[lex_source_len]
    jge .id_e
    movzx eax,byte[r14+rsi]
    cmp al,'_'
    je .id_l
    cmp al,'a'
    jb .id_u
    cmp al,'z'
    jbe .id_l
.id_u:cmp al,'A'
    jb .id_d
    cmp al,'Z'
    jbe .id_l
.id_d:cmp al,'0'
    jb .id_e
    cmp al,'9'
    jbe .id_l
.id_e:mov [lex_pos],rsi
    mov r10,rsi
    sub r10,r9
    lea r11,[r14+r9]
    ; check keyword table
    mov r12,kw_table
.kw:mov rdi,[r12]
    test rdi,rdi
    jz .kw_nf
    cmp r10,[r12+16]
    jne .kw_nx
    mov rsi,r11
    mov rcx,r10
    call ely_memcmp
    test rax,rax
    jz .kw_h
.kw_nx:add r12,24
    jmp .kw
.kw_h:mov rax,[r12+8]
    xor rsi,rsi
    xor rdx,rdx
    call add_tok
    jmp .loop
.kw_nf:mov rax,TOK_IDENT
    mov rsi,r11
    mov rdx,r10
    call add_tok
    jmp .loop

; number literal
.num:xor r10,r10
.nu_l:movzx eax,byte[r14+rsi]
    cmp al,'0'
    jb .nu_e
    cmp al,'9'
    ja .nu_e
    sub al,'0'
    imul r10,10
    movzx rax,al
    add r10,rax
    inc rsi
    cmp rsi,[lex_source_len]
    jl .nu_l
.nu_e:mov [lex_pos],rsi
    mov rax,TOK_NUMBER
    mov rsi,r10
    xor rdx,rdx
    call add_tok
    jmp .loop

; single-char tokens
.t_lb:mov rax,TOK_LBRACE
    jmp .sng
.t_rb:mov rax,TOK_RBRACE
    jmp .sng
.t_lp:mov rax,TOK_LPAREN
    jmp .sng
.t_rp:mov rax,TOK_RPAREN
    jmp .sng
.t_se:mov rax,TOK_SEMICOLON
    jmp .sng
.t_co:mov rax,TOK_COMMA
    jmp .sng
.t_pl:mov rax,TOK_PLUS
    jmp .sng
.t_st:mov rax,TOK_STAR
    jmp .sng
.t_sl:mov rax,TOK_SLASH
    jmp .sng
.t_am:mov rax,TOK_AMP
    jmp .sng
.t_us:mov rax,TOK_UNDERSCORE
    jmp .sng
.t_at:mov rax,TOK_AT
    jmp .sng
.t_lbk:mov rax,TOK_LBRACKET
    jmp .sng
.t_rbk:mov rax,TOK_RBRACKET
    jmp .sng
.sng:inc qword[lex_pos]
    xor rsi,rsi
    xor rdx,rdx
    call add_tok
    jmp .loop

; dot / dotdot
.m_dot:
    lea rax,[rsi+1]
    cmp rax,[lex_source_len]
    jge .dot1
    cmp byte[r14+rsi+1],'.'
    je .dotdot
.dot1:mov rax,TOK_DOT
    jmp .sng
.dotdot:
    add qword[lex_pos],2
    mov rax,TOK_DOTDOT
    xor rsi,rsi
    xor rdx,rdx
    call add_tok
    jmp .loop

; colon / dcolon / atom
.m_cl:lea rax,[rsi+1]
    cmp rax,[lex_source_len]
    jge .cl_s
    movzx eax,byte[r14+rsi+1]
    cmp al,':'
    je .dcl
    cmp al,'_'
    je .at_s
    cmp al,'a'
    jb .cl_u
    cmp al,'z'
    jbe .at_s
.cl_u:cmp al,'A'
    jb .cl_s
    cmp al,'Z'
    jbe .at_s
.cl_s:mov rax,TOK_COLON
    jmp .sng
.dcl:add qword[lex_pos],2
    mov rax,TOK_DCOLON
    xor rsi,rsi
    xor rdx,rdx
    call add_tok
    jmp .loop

; atom literal :name
.at_s:inc rsi
    mov r9,rsi
.at_l:inc rsi
    cmp rsi,[lex_source_len]
    jge .at_e
    movzx eax,byte[r14+rsi]
    cmp al,'_'
    je .at_l
    cmp al,'a'
    jb .at_u2
    cmp al,'z'
    jbe .at_l
.at_u2:cmp al,'A'
    jb .at_d2
    cmp al,'Z'
    jbe .at_l
.at_d2:cmp al,'0'
    jb .at_e
    cmp al,'9'
    jbe .at_l
.at_e:mov [lex_pos],rsi
    mov r10,rsi
    sub r10,r9
    lea r11,[r14+r9]
    mov rax,TOK_ATOM
    mov rsi,r11
    mov rdx,r10
    call add_tok
    jmp .loop

; string literal "..."
.str:inc rsi
    xor r10,r10
.str_l:cmp rsi,[lex_source_len]
    jge .str_e
    movzx eax,byte[r14+rsi]
    cmp al,'"'
    je .str_e
    cmp al,'\'
    je .str_esc
    mov [str_stage+r10],al
    inc r10
    inc rsi
    jmp .str_l
.str_esc:inc rsi
    cmp rsi,[lex_source_len]
    jge .str_e
    movzx eax,byte[r14+rsi]
    cmp al,'n'
    je .esc_n
    cmp al,'t'
    je .esc_t
    cmp al,'r'
    je .esc_r
    cmp al,'\'
    je .esc_bs
    cmp al,'"'
    je .esc_q
    cmp al,'0'
    je .esc_0
    mov [str_stage+r10],al
    inc r10
    inc rsi
    jmp .str_l
.esc_n:mov byte[str_stage+r10],10
    inc r10
    inc rsi
    jmp .str_l
.esc_t:mov byte[str_stage+r10],9
    inc r10
    inc rsi
    jmp .str_l
.esc_r:mov byte[str_stage+r10],13
    inc r10
    inc rsi
    jmp .str_l
.esc_bs:mov byte[str_stage+r10],92
    inc r10
    inc rsi
    jmp .str_l
.esc_q:mov byte[str_stage+r10],34
    inc r10
    inc rsi
    jmp .str_l
.esc_0:mov byte[str_stage+r10],0
    inc r10
    inc rsi
    jmp .str_l
.str_e:mov [lex_pos],rsi
    cmp rsi,[lex_source_len]
    jge .str_emit
    cmp byte[r14+rsi],'"'
    jne .str_emit
    inc qword[lex_pos]
.str_emit:
    ; copy processed string into arena
    push r10
    mov rdi,r10
    call arena_alloc
    mov rdi,rax
    lea rsi,[str_stage]
    mov rcx,r10
    push rdi
    rep movsb
    pop rdi
    pop r10
    mov rax,TOK_STRING
    mov rsi,rdi
    mov rdx,r10
    call add_tok
    jmp .loop

; minus / arrow
.m_mi:lea rax,[rsi+1]
    cmp rax,[lex_source_len]
    jge .mi1
    cmp byte[r14+rsi+1],'>'
    je .m_ar
.mi1:mov rax,TOK_MINUS
    jmp .sng
.m_ar:add qword[lex_pos],2
    mov rax,TOK_ARROW
    xor rsi,rsi
    xor rdx,rdx
    call add_tok
    jmp .loop

; equals / == / =>
.m_eq:lea rax,[rsi+1]
    cmp rax,[lex_source_len]
    jge .m_as
    cmp byte[r14+rsi+1],'='
    je .m_ee
    cmp byte[r14+rsi+1],'>'
    je .m_fa
.m_as:mov rax,TOK_EQUALS
    jmp .sng
.m_ee:add qword[lex_pos],2
    mov rax,TOK_EQ
    xor rsi,rsi
    xor rdx,rdx
    call add_tok
    jmp .loop
.m_fa:add qword[lex_pos],2
    mov rax,TOK_FATARROW
    xor rsi,rsi
    xor rdx,rdx
    call add_tok
    jmp .loop

; !=
.m_ba:lea rax,[rsi+1]
    cmp rax,[lex_source_len]
    jge .ws
    cmp byte[r14+rsi+1],'='
    jne .ws
    add qword[lex_pos],2
    mov rax,TOK_NEQ
    xor rsi,rsi
    xor rdx,rdx
    call add_tok
    jmp .loop

; < / <=
.m_lt:lea rax,[rsi+1]
    cmp rax,[lex_source_len]
    jge .lt1
    cmp byte[r14+rsi+1],'='
    je .m_le
.lt1:mov rax,TOK_LT
    jmp .sng
.m_le:add qword[lex_pos],2
    mov rax,TOK_LE
    xor rsi,rsi
    xor rdx,rdx
    call add_tok
    jmp .loop

; > / >=
.m_gt:lea rax,[rsi+1]
    cmp rax,[lex_source_len]
    jge .gt1
    cmp byte[r14+rsi+1],'='
    je .m_ge
.gt1:mov rax,TOK_GT
    jmp .sng
.m_ge:add qword[lex_pos],2
    mov rax,TOK_GE
    xor rsi,rsi
    xor rdx,rdx
    call add_tok
    jmp .loop

; | / |>
.m_pi:lea rax,[rsi+1]
    cmp rax,[lex_source_len]
    jge .bar
    cmp byte[r14+rsi+1],'>'
    jne .bar
    add qword[lex_pos],2
    mov rax,TOK_PIPE
    xor rsi,rsi
    xor rdx,rdx
    call add_tok
    jmp .loop
.bar:mov rax,TOK_BAR
    jmp .sng

; end of file
.eof:mov rax,TOK_EOF
    xor rsi,rsi
    xor rdx,rdx
    call add_tok
    pop r14
    pop r13
    pop r12
    pop rbx
    ret