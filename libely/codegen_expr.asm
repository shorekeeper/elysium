default rel
%include "defs.inc"
extern emit_cstr,emit_num,emit_nl,emit_name,emit_label,emit_jmp_label
extern new_label,sym_lookup,sym_get_index,sym_off,sym_arrlen
extern be_target,platform_write,emit_str_data
global compile_expr

section .data
s_mov_rax:     db "    mov rax, ",0
s_load:        db "    mov rax, [rbp - ",0
s_close_brk:   db "]",10,0
s_push_rax:    db "    push rax",10,0
s_pop_rbx:     db "    pop rbx",10,0
s_xor_eax:     db "    xor eax, eax",10,0
s_add:         db "    add rax, rbx",10,0
s_sub_op:      db "    sub rbx, rax",10,"    mov rax, rbx",10,0
s_mul:         db "    imul rax, rbx",10,0
s_cmp:         db "    cmp rbx, rax",10,0
s_sete:        db "    sete al",10,"    movzx rax, al",10,0
s_setne:       db "    setne al",10,"    movzx rax, al",10,0
s_setl:        db "    setl al",10,"    movzx rax, al",10,0
s_setg:        db "    setg al",10,"    movzx rax, al",10,0
s_setle:       db "    setle al",10,"    movzx rax, al",10,0
s_setge:       db "    setge al",10,"    movzx rax, al",10,0
s_call:        db "    call ",0
s_fnpre:       db "__ely_fn_",0
s_dotL:        db ".L",0
s_jmp:         db "    jmp ",0
s_div_test:    db "    test rax, rax",10,"    jnz ",0
s_div_sv:      db "    mov rdi, [__rt_sv_current]",10
               db "    test rdi, rdi",10,"    jz ",0
s_div_body:    db "    xchg rax, rbx",10,"    cqo",10,"    idiv rbx",10,0
s_mov_rsi1:    db "    mov rsi, 1",10,0
s_call_crst:   db "    call __rt_ckpt_restore",10,0
s_lea_rax:     db "    lea rax, [rbp - ",0
s_deref:       db "    mov rax, [rax]",10,0
s_mov_rdi_str: db "    mov rdi, __ely_str_",0
s_mov_rsi_str: db "    mov rsi, __ely_str_",0
s_len_suf:     db "_len",10,0
s_mov_rax_rdi: db "    mov rax, rdi",10,0
s_mov_rax_rsi: db "    mov rax, rsi",10,0
s_pop_rdi:     db "    pop rdi",10,0
s_pop_rsi:     db "    pop rsi",10,0
s_pop_rdx:     db "    pop rdx",10,0
s_pop_rcx:     db "    pop rcx",10,0
s_pop_r8:      db "    pop r8",10,0
s_pop_r9:      db "    pop r9",10,0
s_mov_rdi_rax: db "    mov rdi, rax",10,0
s_mov_rsi_rax: db "    mov rsi, rax",10,0
s_call_claim:  db "    call __rt_claim",10,0
s_call_pnew:   db "    call __rt_pool_create",10,0
s_call_pclaim: db "    call __rt_pool_claim",10,0
s_load_mem:    db "    mov rax, [rax + rbx*8]",10,0
s_mov_rbx_rax: db "    mov rbx, rax",10,0
s_idx_load:    db "    mov rax, [rax + rbx*8]",10,0
align 8
popregs: dq s_pop_rdi,s_pop_rsi,s_pop_rdx,s_pop_rcx,s_pop_r8,s_pop_r9
err_undef:  db "  [error] undefined: '",0
err_undef2: db "'",10,0

section .text
ce_print:
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

compile_expr:
    push rbx
    push rcx
    push r12
    push r13
    test rdi,rdi
    jz .zero
    mov r12,rdi
    mov rax,[r12]
    cmp rax,NODE_NUMBER
    je .num
    cmp rax,NODE_BOOL
    je .bool
    cmp rax,NODE_IDENT
    je .id
    cmp rax,NODE_BINOP
    je .bin
    cmp rax,NODE_CALL
    je .call
    cmp rax,NODE_BORROW
    je .brw
    cmp rax,NODE_ATOM
    je .atom
    cmp rax,NODE_ADDR
    je .addr
    cmp rax,NODE_DEREF
    je .deref
    cmp rax,NODE_STRING
    je .string
    cmp rax,NODE_LEN
    je .len
    cmp rax,NODE_LOAD
    je .memload
    cmp rax,NODE_CLAIM
    je .claim
    cmp rax,NODE_CLAIM_G
    je .claim_g
    cmp rax,NODE_POOL_NEW
    je .pool_new
    cmp rax,NODE_POOL_CLAIM
    je .pool_claim
    cmp rax,NODE_INDEX
    je .idx
    cmp rax,NODE_ARRLEN
    je .arrlen

.zero:
    mov rdi,s_xor_eax
    call emit_cstr
    jmp .d

.num:
    mov rdi,s_mov_rax
    call emit_cstr
    mov rax,[r12+8]
    call emit_num
    call emit_nl
    jmp .d

.bool:
    mov rdi,s_mov_rax
    call emit_cstr
    mov rax,[r12+8]
    call emit_num
    call emit_nl
    jmp .d

; identifier: check if array (emit lea) or scalar (emit mov)
.id:
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call sym_get_index
    cmp rax,-1
    je .id_undef
    push rax
    mov rbx,[sym_arrlen+rax*8]
    test rbx,rbx
    pop rax
    jnz .id_arr
    ; scalar: mov rax, [rbp - offset]
    mov rax,[sym_off+rax*8]
    push rax
    mov rdi,s_load
    call emit_cstr
    pop rax
    call emit_num
    mov rdi,s_close_brk
    call emit_cstr
    jmp .d
; array: lea rax, [rbp - offset] (return base pointer)
.id_arr:
    mov rax,[sym_off+rax*8]
    push rax
    mov rdi,s_lea_rax
    call emit_cstr
    pop rax
    call emit_num
    mov rdi,s_close_brk
    call emit_cstr
    jmp .d

.id_undef:
    mov rdi,err_undef
    call ce_print
    mov rsi,[r12+48]
    mov rdx,[r12+56]
    call platform_write
    mov rdi,err_undef2
    call ce_print
    mov rdi,s_xor_eax
    call emit_cstr
    jmp .d

.brw:
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call sym_lookup
    test rax,rax
    jz .zero
    push rax
    mov rdi,s_load
    call emit_cstr
    pop rax
    call emit_num
    mov rdi,s_close_brk
    call emit_cstr
    jmp .d

.atom:
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    mov rax,5381
.atom_h:test rcx,rcx
    jz .atom_e
    movzx rdx,byte[rsi]
    imul rax,rax,33
    add rax,rdx
    inc rsi
    dec rcx
    jmp .atom_h
.atom_e:push rax
    mov rdi,s_mov_rax
    call emit_cstr
    pop rax
    call emit_num
    call emit_nl
    jmp .d

.addr:
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call sym_lookup
    test rax,rax
    jz .zero
    push rax
    mov rdi,s_lea_rax
    call emit_cstr
    pop rax
    call emit_num
    mov rdi,s_close_brk
    call emit_cstr
    jmp .d

.deref:
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_deref
    call emit_cstr
    jmp .d

.string:
    mov rsi,[r12+48]
    mov rdx,[r12+56]
    call emit_str_data
    push rax
    mov rdi,s_mov_rdi_str
    call emit_cstr
    pop rax
    push rax
    call emit_num
    call emit_nl
    mov rdi,s_mov_rsi_str
    call emit_cstr
    pop rax
    push rax
    call emit_num
    mov rdi,s_len_suf
    call emit_cstr
    mov rdi,s_mov_rax_rdi
    call emit_cstr
    pop rax
    jmp .d

.len:
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_mov_rax_rsi
    call emit_cstr
    jmp .d

.memload:
    mov rdi,[r12+24]
    call compile_expr
    mov rdi,s_push_rax
    call emit_cstr
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_pop_rbx
    call emit_cstr
    mov rdi,s_load_mem
    call emit_cstr
    jmp .d

.claim:
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_mov_rdi_rax
    call emit_cstr
    mov rdi,s_call_claim
    call emit_cstr
    jmp .d
.claim_g:
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_mov_rdi_rax
    call emit_cstr
    mov rdi,s_call_claim
    call emit_cstr
    jmp .d
.pool_new:
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_mov_rdi_rax
    call emit_cstr
    mov rdi,s_call_pnew
    call emit_cstr
    jmp .d
.pool_claim:
    mov rdi,[r12+24]
    call compile_expr
    mov rdi,s_push_rax
    call emit_cstr
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_mov_rdi_rax
    call emit_cstr
    mov rdi,s_pop_rsi
    call emit_cstr
    mov rdi,s_call_pclaim
    call emit_cstr
    jmp .d

; name[expr] -> lea base, compute index, load
.idx:
    ; compile index -> rax
    mov rdi,[r12+16]
    call compile_expr
    ; mov rbx, rax (save index)
    mov rdi,s_mov_rbx_rax
    call emit_cstr
    ; lea rax, [rbp - base_offset]
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call sym_lookup
    test rax,rax
    jz .zero
    push rax
    mov rdi,s_lea_rax
    call emit_cstr
    pop rax
    call emit_num
    mov rdi,s_close_brk
    call emit_cstr
    ; mov rax, [rax + rbx*8]
    mov rdi,s_idx_load
    call emit_cstr
    jmp .d

; arrlen(name) -> compile-time constant from symtab
.arrlen:
    mov rdi,[r12+16]
    test rdi,rdi
    jz .zero
    cmp qword[rdi],NODE_IDENT
    jne .zero
    mov rsi,[rdi+48]
    mov rcx,[rdi+56]
    call sym_get_index
    cmp rax,-1
    je .zero
    mov rax,[sym_arrlen+rax*8]
    test rax,rax
    jz .zero
    push rax
    mov rdi,s_mov_rax
    call emit_cstr
    pop rax
    call emit_num
    call emit_nl
    jmp .d

.bin:
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_push_rax
    call emit_cstr
    mov rdi,[r12+24]
    call compile_expr
    mov rdi,s_pop_rbx
    call emit_cstr
    mov rbx,[r12+8]
    cmp rbx,TOK_PLUS
    je .ba
    cmp rbx,TOK_MINUS
    je .bs
    cmp rbx,TOK_STAR
    je .bm
    cmp rbx,TOK_SLASH
    je .bv
    cmp rbx,TOK_EQ
    je .beq
    cmp rbx,TOK_NEQ
    je .bne_
    cmp rbx,TOK_LT
    je .blt
    cmp rbx,TOK_GT
    je .bgt
    cmp rbx,TOK_LE
    je .ble
    cmp rbx,TOK_GE
    je .bge
    jmp .d
.ba:mov rdi,s_add
    call emit_cstr
    jmp .d
.bs:mov rdi,s_sub_op
    call emit_cstr
    jmp .d
.bm:mov rdi,s_mul
    call emit_cstr
    jmp .d
.bv: call new_label
    mov r13,rax
    call new_label
    push rax
    call new_label
    push rax
    mov rdi,s_div_test
    call emit_cstr
    mov rdi,s_dotL
    call emit_cstr
    mov rax,r13
    call emit_num
    call emit_nl
    mov rdi,s_div_sv
    call emit_cstr
    mov rdi,s_dotL
    call emit_cstr
    pop rax
    push rax
    call emit_num
    call emit_nl
    mov rdi,s_mov_rsi1
    call emit_cstr
    mov rdi,s_call_crst
    call emit_cstr
    pop rax
    call emit_label
    mov rdi,s_xor_eax
    call emit_cstr
    pop rax
    push rax
    mov rdi,s_jmp
    call emit_jmp_label
    mov rax,r13
    call emit_label
    mov rdi,s_div_body
    call emit_cstr
    pop rax
    call emit_label
    jmp .d
.beq:mov rdi,s_cmp
    call emit_cstr
    mov rdi,s_sete
    call emit_cstr
    jmp .d
.bne_:mov rdi,s_cmp
    call emit_cstr
    mov rdi,s_setne
    call emit_cstr
    jmp .d
.blt:mov rdi,s_cmp
    call emit_cstr
    mov rdi,s_setl
    call emit_cstr
    jmp .d
.bgt:mov rdi,s_cmp
    call emit_cstr
    mov rdi,s_setg
    call emit_cstr
    jmp .d
.ble:mov rdi,s_cmp
    call emit_cstr
    mov rdi,s_setle
    call emit_cstr
    jmp .d
.bge:mov rdi,s_cmp
    call emit_cstr
    mov rdi,s_setge
    call emit_cstr
    jmp .d

.call:
    xor r13,r13
    mov rbx,[r12+16]
.ca_e:test rbx,rbx
    jz .ca_p
    push rbx
    push r13
    mov rdi,rbx
    call compile_expr
    mov rdi,s_push_rax
    call emit_cstr
    pop r13
    pop rbx
    inc r13
    mov rbx,[rbx+32]
    jmp .ca_e
.ca_p:test r13,r13
    jz .ca_c
    mov rbx,r13
    dec rbx
.ca_pl:cmp rbx,0
    jl .ca_c
    mov rdi,[popregs+rbx*8]
    call emit_cstr
    dec rbx
    jmp .ca_pl
.ca_c:mov rdi,s_call
    call emit_cstr
    mov rdi,s_fnpre
    call emit_cstr
    mov rsi,[r12+48]
    mov rdx,[r12+56]
    call emit_name
    call emit_nl

.d: pop r13
    pop r12
    pop rcx
    pop rbx
    ret