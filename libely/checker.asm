; checker.asm -- pre-lowering validation pass
; Walks AST, collects function signatures, checks:
;   E001: undefined variables
;   E002: wrong argument count
;   E003: undefined functions
; Uses diagnostic.asm for formatted error output.
default rel
%include "defs.inc"
extern ely_memcmp
extern treg_init, treg_define, treg_define_union, treg_lookup_variant
extern diag_err_undef_var, diag_err_undef_fn, diag_err_wrong_argc
extern diag_get_errors
global checker_run

CK_MAX_FN equ 4096
CK_MAX_VAR equ 4096

section .bss
; function signature table
cf_nptr:  resq CK_MAX_FN
cf_nlen:  resq CK_MAX_FN
cf_argc:  resq CK_MAX_FN
cf_count: resq 1
cf_found: resq 1
; variable scope stack
cv_nptr:  resq CK_MAX_VAR
cv_nlen:  resq CK_MAX_VAR
cv_scope: resq CK_MAX_VAR
cv_count: resq 1
cv_depth: resq 1

section .text

; ==================== SCOPE MANAGEMENT ====================

ck_enter:
    inc qword[cv_depth]
    ret

ck_leave:
    push rax
    push rcx
    mov rax, [cv_depth]
.l: mov rcx, [cv_count]
    test rcx, rcx
    jz .d
    dec rcx
    cmp [cv_scope+rcx*8], rax
    jne .d
    dec qword[cv_count]
    jmp .l
.d: dec qword[cv_depth]
    pop rcx
    pop rax
    ret

; ck_add_var: rsi=name, rcx=len
ck_add_var:
    push rax
    push rdx
    mov rax, [cv_count]
    mov [cv_nptr+rax*8], rsi
    mov [cv_nlen+rax*8], rcx
    mov rdx, [cv_depth]
    mov [cv_scope+rax*8], rdx
    inc qword[cv_count]
    pop rdx
    pop rax
    ret

; ck_find_var: rsi=name, rcx=len -> rax=1 found, 0 not
ck_find_var:
    push rbx
    push rdi
    push rsi
    push rcx
    push r8
    push r9
    mov r8, rsi
    mov r9, rcx
    mov rbx, [cv_count]
.l: test rbx, rbx
    jz .nf
    dec rbx
    cmp r9, [cv_nlen+rbx*8]
    jne .l
    mov rsi, r8
    mov rdi, [cv_nptr+rbx*8]
    mov rcx, r9
    call ely_memcmp
    test rax, rax
    jnz .l
    mov rax, 1
    jmp .d
.nf:xor rax, rax
.d: pop r9
    pop r8
    pop rcx
    pop rsi
    pop rdi
    pop rbx
    ret

; ==================== FUNCTION TABLE ====================

; ck_add_fn: rsi=name, rcx=len, rdi=argc
ck_add_fn:
    push rax
    push rbx
    push r8
    push r9
    push rdi
    mov r8, rsi
    mov r9, rcx
    mov rbx, [cf_count]
.l: test rbx, rbx
    jz .add
    dec rbx
    cmp r9, [cf_nlen+rbx*8]
    jne .l
    push rsi
    push rcx
    mov rsi, r8
    mov rdi, [cf_nptr+rbx*8]
    mov rcx, r9
    call ely_memcmp
    pop rcx
    pop rsi
    test rax, rax
    jnz .l
    jmp .done
.add:
    mov rax, [cf_count]
    mov [cf_nptr+rax*8], r8
    mov [cf_nlen+rax*8], r9
    pop rdi
    push rdi
    mov [cf_argc+rax*8], rdi
    inc qword[cf_count]
.done:
    pop rdi
    pop r9
    pop r8
    pop rbx
    pop rax
    ret

; ck_find_fn: rsi=name, rcx=len -> rax=argc or -1, sets cf_found
ck_find_fn:
    push rbx
    push rdi
    push rsi
    push rcx
    push r8
    push r9
    mov r8, rsi
    mov r9, rcx
    mov qword[cf_found], 0xFFFFFFFFFFFFFFFF
    mov rbx, [cf_count]
.l: test rbx, rbx
    jz .nf
    dec rbx
    cmp r9, [cf_nlen+rbx*8]
    jne .l
    mov rsi, r8
    mov rdi, [cf_nptr+rbx*8]
    mov rcx, r9
    call ely_memcmp
    test rax, rax
    jnz .l
    mov [cf_found], rbx
    mov rax, [cf_argc+rbx*8]
    jmp .d
.nf:mov rax, 0xFFFFFFFFFFFFFFFF
.d: pop r9
    pop r8
    pop rcx
    pop rsi
    pop rdi
    pop rbx
    ret

; ==================== MAIN ENTRY ====================

; checker_run: rdi=AST module root -> rax=error count
checker_run:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov qword[cf_count], 0
    mov qword[cv_count], 0
    mov qword[cv_depth], 0
    call treg_init
    mov r12, rdi
    test r12, r12
    jz .done
    ; pass 1: collect signatures + types
    mov r13, [r12+16]
.p1:test r13, r13
    jz .p2
    cmp qword[r13], NODE_FUNC
    je .p1_fn
    cmp qword[r13], NODE_TYPE_DEF
    je .p1_ty
    cmp qword[r13], NODE_UNION_DEF
    je .p1_un
    jmp .p1_nx
.p1_fn:
    xor r14, r14
    mov r15, [r13+24]
.p1c:test r15, r15
    jz .p1r
    inc r14
    mov r15, [r15+32]
    jmp .p1c
.p1r:
    mov rsi, [r13+48]
    mov rcx, [r13+56]
    mov rdi, r14
    call ck_add_fn
    jmp .p1_nx
.p1_ty:
    mov rdi, r13
    call treg_define
    jmp .p1_nx
.p1_un:
    mov rdi, r13
    call treg_define_union
.p1_nx:
    mov r13, [r13+32]
    jmp .p1
    ; pass 2: check bodies
.p2:
    mov r13, [r12+16]
.p2l:test r13, r13
    jz .done
    cmp qword[r13], NODE_FUNC
    jne .p2n
    call ck_func
.p2n:
    mov r13, [r13+32]
    jmp .p2l
.done:
    call diag_get_errors
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ==================== FUNCTION CHECK ====================

ck_func:
    push rbx
    push r14
    push r15
    mov qword[cv_count], 0
    mov qword[cv_depth], 0
    call ck_enter
    mov rbx, [r13+24]
.fp:test rbx, rbx
    jz .fb
    cmp qword[rbx], NODE_PARAM
    jne .fn
    mov rsi, [rbx+48]
    mov rcx, [rbx+56]
    call ck_add_var
.fn:mov rbx, [rbx+32]
    jmp .fp
.fb:
    mov rdi, [r13+16]
    call ck_slist
    mov rdi, [r13+8]
    test rdi, rdi
    jz .fd
    call ck_expr
.fd:call ck_leave
    pop r15
    pop r14
    pop rbx
    ret

; ==================== STATEMENT CHECK ====================

ck_slist:
    push r12
    mov r12, rdi
.l: test r12, r12
    jz .d
    mov rdi, r12
    call ck_stmt
    mov r12, [r12+32]
    jmp .l
.d: pop r12
    ret

ck_stmt:
    push rbx
    push r12
    push r13
    mov r12, rdi
    test r12, r12
    jz .done
    mov rax, [r12]
    cmp rax, NODE_LET
    je .let
    cmp rax, NODE_RETURN
    je .e1
    cmp rax, NODE_PRINT
    je .e1
    cmp rax, NODE_PRINT_STR
    je .e1
    cmp rax, NODE_IF
    je .if_
    cmp rax, NODE_WHILE
    je .while_
    cmp rax, NODE_FOR
    je .for_
    cmp rax, NODE_MATCH
    je .match_
    cmp rax, NODE_ANCHOR
    je .scope1
    cmp rax, NODE_SUPERVISE
    je .scope1
    cmp rax, NODE_RAW
    je .scope1
    cmp rax, NODE_STORE
    je .store_
    cmp rax, NODE_RELEASE
    je .e1
    cmp rax, NODE_RELEASE_G
    je .e1
    cmp rax, NODE_POOL_DRAIN
    je .e1
    cmp rax, NODE_INDEX_SET
    je .idx_set
    cmp rax, NODE_FIELD_SET
    je .fld_set
    cmp rax, NODE_ASSIGN
    je .assign
    cmp rax, NODE_CALL
    je .ck_call_stmt
    jmp .done

.let:
    mov rdi, [r12+16]
    test rdi, rdi
    jz .let_add
    call ck_expr
.let_add:
    mov rsi, [r12+48]
    mov rcx, [r12+56]
    test rsi, rsi
    jz .done
    call ck_add_var
    jmp .done

.e1:
    mov rdi, [r12+16]
    test rdi, rdi
    jz .done
    call ck_expr
    jmp .done

.if_:
    mov rdi, [r12+16]
    call ck_expr
    call ck_enter
    mov rdi, [r12+24]
    call ck_slist
    call ck_leave
    cmp qword[r12+8], 0
    je .done
    call ck_enter
    mov rdi, [r12+8]
    call ck_slist
    call ck_leave
    jmp .done

.while_:
    mov rdi, [r12+16]
    call ck_expr
    call ck_enter
    mov rdi, [r12+24]
    call ck_slist
    call ck_leave
    jmp .done

.for_:
    call ck_enter
    mov rsi, [r12+48]
    mov rcx, [r12+56]
    call ck_add_var
    mov rdi, [r12+24]
    test rdi, rdi
    jz .for_b
    call ck_expr
.for_b:
    mov rdi, [r12+8]
    test rdi, rdi
    jz .for_c
    call ck_expr
.for_c:
    mov rdi, [r12+16]
    call ck_slist
    call ck_leave
    jmp .done

.match_:
    mov rdi, [r12+16]
    call ck_expr
    mov rbx, [r12+24]
.ma_l:
    test rbx, rbx
    jz .done
    mov rax, [rbx+40]
    cmp rax, 2
    je .ma_bind
    cmp rax, 3
    je .ma_var
    push rbx
    mov rdi, [rbx+16]
    test rdi, rdi
    jz .ma_sk
    call ck_stmt
.ma_sk:pop rbx
    jmp .ma_nx
.ma_bind:
    call ck_enter
    mov rsi, [rbx+48]
    mov rcx, [rbx+56]
    call ck_add_var
    mov rdi, [rbx+24]
    test rdi, rdi
    jz .ma_bb
    call ck_expr
.ma_bb:
    push rbx
    mov rdi, [rbx+16]
    test rdi, rdi
    jz .ma_bs
    call ck_stmt
.ma_bs:pop rbx
    call ck_leave
    jmp .ma_nx
.ma_var:
    call ck_enter
    mov rax, [rbx+24]
    test rax, rax
    jz .ma_vb
    mov rsi, [rax+48]
    mov rcx, [rax+56]
    call ck_add_var
.ma_vb:
    push rbx
    mov rdi, [rbx+16]
    test rdi, rdi
    jz .ma_vs
    call ck_stmt
.ma_vs:pop rbx
    call ck_leave
.ma_nx:
    mov rbx, [rbx+32]
    jmp .ma_l

.scope1:
    call ck_enter
    mov rdi, [r12+16]
    call ck_slist
    call ck_leave
    jmp .done

.store_:
    mov rdi, [r12+16]
    test rdi, rdi
    jz .st2
    call ck_expr
.st2:
    mov rdi, [r12+24]
    test rdi, rdi
    jz .st3
    call ck_expr
.st3:
    mov rdi, [r12+8]
    test rdi, rdi
    jz .done
    call ck_expr
    jmp .done

.idx_set:
    mov rdi, [r12+16]
    test rdi, rdi
    jz .is2
    call ck_expr
.is2:
    mov rdi, [r12+24]
    test rdi, rdi
    jz .is3
    call ck_expr
.is3:
    mov rsi, [r12+48]
    mov rcx, [r12+56]
    test rsi, rsi
    jz .done
    call ck_find_var
    test rax, rax
    jnz .done
    mov rdi, [r12+48]
    mov rsi, [r12+56]
    call diag_err_undef_var
    jmp .done

.fld_set:
    mov rdi, [r12+24]
    test rdi, rdi
    jz .fs2
    call ck_expr
.fs2:
    mov rdi, [r12+16]
    test rdi, rdi
    jz .done
    cmp qword[rdi], NODE_IDENT
    jne .done
    mov rsi, [rdi+48]
    mov rcx, [rdi+56]
    call ck_find_var
    test rax, rax
    jnz .done
    mov rdi, [r12+16]
    mov rdi, [rdi+48]
    mov rsi, [r12+16]
    mov rsi, [rsi+56]
    call diag_err_undef_var
    jmp .done

.assign:
    mov rdi, [r12+16]
    test rdi, rdi
    jz .as_v
    call ck_expr
.as_v:
    mov rsi, [r12+48]
    mov rcx, [r12+56]
    test rsi, rsi
    jz .done
    call ck_find_var
    test rax, rax
    jnz .done
    mov rdi, [r12+48]
    mov rsi, [r12+56]
    call diag_err_undef_var

.ck_call_stmt:
    mov rdi, r12
    call ck_expr
    jmp .done
.done:
    pop r13
    pop r12
    pop rbx
    ret

; ==================== EXPRESSION CHECK ====================

ck_expr:
    push rbx
    push r12
    push r13
    test rdi, rdi
    jz .done
    mov r12, rdi
    mov rax, [r12]
    cmp rax, NODE_NUMBER
    je .done
    cmp rax, NODE_BOOL
    je .done
    cmp rax, NODE_ATOM
    je .done
    cmp rax, NODE_STRING
    je .done
    cmp rax, NODE_IDENT
    je .ident
    cmp rax, NODE_BINOP
    je .binop
    cmp rax, NODE_CALL
    je .call
    cmp rax, NODE_INDEX
    je .index
    cmp rax, NODE_ARRLEN
    je .child1
    cmp rax, NODE_FIELD_ACCESS
    je .child1
    cmp rax, NODE_DEREF
    je .child1
    cmp rax, NODE_LEN
    je .child1
    cmp rax, NODE_CLAIM
    je .child1
    cmp rax, NODE_CLAIM_G
    je .child1
    cmp rax, NODE_POOL_NEW
    je .child1
    cmp rax, NODE_ADDR
    je .addr
    cmp rax, NODE_BORROW
    je .borrow
    cmp rax, NODE_LOAD
    je .two
    cmp rax, NODE_POOL_CLAIM
    je .two
    cmp rax, NODE_RECORD_LIT
    je .rec_lit
    cmp rax, NODE_ARRAY
    je .arr_lit
    jmp .done

.ident:
    mov rsi, [r12+48]
    mov rcx, [r12+56]
    test rsi, rsi
    jz .done
    call ck_find_var
    test rax, rax
    jnz .done
    mov rsi, [r12+48]
    mov rcx, [r12+56]
    call treg_lookup_variant
    cmp rax, 0xFFFFFFFFFFFFFFFF
    jne .done
    mov rdi, [r12+48]
    mov rsi, [r12+56]
    call diag_err_undef_var
    jmp .done

.binop:
    mov rdi, [r12+16]
    call ck_expr
    mov rdi, [r12+24]
    call ck_expr
    jmp .done

.call:
    mov rbx, [r12+16]
    xor r13, r13
.ca_l:
    test rbx, rbx
    jz .ca_chk
    push rbx
    push r13
    mov rdi, rbx
    call ck_expr
    pop r13
    pop rbx
    inc r13
    mov rbx, [rbx+32]
    jmp .ca_l
.ca_chk:
    mov rsi, [r12+48]
    mov rcx, [r12+56]
    test rsi, rsi
    jz .done
    ; variant constructor? skip check
    call treg_lookup_variant
    cmp rax, 0xFFFFFFFFFFFFFFFF
    jne .done
    ; look up function
    mov rsi, [r12+48]
    mov rcx, [r12+56]
    call ck_find_fn
    cmp rax, 0xFFFFFFFFFFFFFFFF
    je .ca_undef
    ; check arg count
    cmp rax, r13
    je .done
    ; wrong count: rax=expected, r13=got
    mov rdx, rax
    mov rcx, r13
    mov rdi, [r12+48]
    mov rsi, [r12+56]
    ; get definition pointer
    mov rbx, [cf_found]
    mov r8, [cf_nptr+rbx*8]
    mov r9, [cf_nlen+rbx*8]
    call diag_err_wrong_argc
    jmp .done
.ca_undef:
    mov rdi, [r12+48]
    mov rsi, [r12+56]
    call diag_err_undef_fn
    jmp .done

.index:
    mov rdi, [r12+16]
    test rdi, rdi
    jz .ix_v
    call ck_expr
.ix_v:
    mov rsi, [r12+48]
    mov rcx, [r12+56]
    test rsi, rsi
    jz .done
    call ck_find_var
    test rax, rax
    jnz .done
    mov rdi, [r12+48]
    mov rsi, [r12+56]
    call diag_err_undef_var
    jmp .done

.child1:
    mov rdi, [r12+16]
    test rdi, rdi
    jz .done
    call ck_expr
    jmp .done

.addr:
    mov rsi, [r12+48]
    mov rcx, [r12+56]
    test rsi, rsi
    jz .done
    call ck_find_var
    test rax, rax
    jnz .done
    mov rdi, [r12+48]
    mov rsi, [r12+56]
    call diag_err_undef_var
    jmp .done

.borrow:
    mov rsi, [r12+48]
    mov rcx, [r12+56]
    test rsi, rsi
    jz .done
    call ck_find_var
    test rax, rax
    jnz .done
    mov rdi, [r12+48]
    mov rsi, [r12+56]
    call diag_err_undef_var
    jmp .done

.two:
    mov rdi, [r12+16]
    test rdi, rdi
    jz .tw2
    call ck_expr
.tw2:
    mov rdi, [r12+24]
    test rdi, rdi
    jz .done
    call ck_expr
    jmp .done

.rec_lit:
    mov rbx, [r12+16]
.rl_l:
    test rbx, rbx
    jz .done
    mov rdi, [rbx+16]
    test rdi, rdi
    jz .rl_n
    call ck_expr
.rl_n:
    mov rbx, [rbx+32]
    jmp .rl_l

.arr_lit:
    mov rbx, [r12+16]
.al_l:
    test rbx, rbx
    jz .done
    push rbx
    mov rdi, rbx
    call ck_expr
    pop rbx
    mov rbx, [rbx+32]
    jmp .al_l

.done:
    pop r13
    pop r12
    pop rbx
    ret