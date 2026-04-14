; checker.asm -- pre-lowering validation pass
; Walks AST, collects function signatures, checks:
;   E001: undefined variables
;   E002: wrong argument count
;   E003: undefined functions
;   E004: type mismatch / value out of range
;   E005: duplicate variable in same scope
;   E007: unreachable code after return (warning)
;   E009: variable shadows outer scope (warning)
; Uses diagnostic.asm for formatted error output.
default rel
%include "defs.inc"
extern ely_memcmp
extern treg_init, treg_define, treg_define_union, treg_lookup_variant
extern diag_err_undef_var, diag_err_undef_fn, diag_err_wrong_argc
extern diag_err_type_range, diag_err_dup_var
extern diag_warn_unreachable, diag_warn_shadow_var
extern diag_err_missing_return, diag_warn_unused_var
extern diag_get_errors
extern diag_err_leak_unwind, diag_warn_div_supervise

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
cv_used:  resq CK_MAX_VAR
cv_param: resq CK_MAX_VAR
; flow analysis: anchor leak tracking
FA_MAX_ALLOC equ 64
fa_anc_depth:  resq 1              ; anchor nesting depth
fa_anc_nptr:   resq 16             ; anchor name ptrs (stack)
fa_anc_nlen:   resq 16
fa_anc_base:   resq 16             ; alloc base index per depth
fa_alloc_nptr: resq FA_MAX_ALLOC   ; claimed variable name ptr
fa_alloc_nlen: resq FA_MAX_ALLOC
fa_alloc_rel:  resq FA_MAX_ALLOC   ; 1=released, 0=pending
fa_alloc_cnt:  resq 1
; flow analysis: supervise tracking
fa_sup_depth:  resq 1
fa_sup_body:   resq 16             ; first body stmt name ptr per depth
fa_sup_blen:   resq 16
ck_cur_stmt:   resq 1              ; current statement for E011

section .text

; scope management

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
; checks E005 (dup same scope), E009 (shadow outer), inits usage tracking
ck_add_var:
    push rax
    push rdx
    push rbx
    push rdi
    push r8
    push r9
    mov r8, rsi
    mov r9, rcx
    ; scan for dup / shadow
    mov rbx, [cv_count]
.chk:test rbx, rbx
    jz .add
    dec rbx
    cmp r9, [cv_nlen+rbx*8]
    jne .chk
    mov rsi, r8
    mov rdi, [cv_nptr+rbx*8]
    mov rcx, r9
    call ely_memcmp
    test rax, rax
    jnz .chk
    ; same name found: same scope = E005, outer = E009
    mov rax, [cv_depth]
    cmp [cv_scope+rbx*8], rax
    jne .shadow
    mov rdi, r8
    mov rsi, r9
    call diag_err_dup_var
    jmp .add
.shadow:
    mov rdi, r8
    mov rsi, r9
    call diag_warn_shadow_var
.add:
    mov rsi, r8
    mov rcx, r9
    mov rax, [cv_count]
    mov [cv_nptr+rax*8], rsi
    mov [cv_nlen+rax*8], rcx
    mov rdx, [cv_depth]
    mov [cv_scope+rax*8], rdx
    mov qword[cv_used+rax*8], 0
    mov qword[cv_param+rax*8], 0
    inc qword[cv_count]
    pop r9
    pop r8
    pop rdi
    pop rbx
    pop rdx
    pop rax
    ret

; ck_find_var: rsi=name, rcx=len -> rax=1 found, 0 not
; marks variable as used for E008 tracking
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
    mov qword[cv_used+rbx*8], 1  ; mark used for E008
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

; function table

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

; main entry

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
    mov qword[fa_anc_depth], 0
    mov qword[fa_alloc_cnt], 0
    mov qword[fa_sup_depth], 0
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
    ; count parameters
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

; ck_has_return: rdi=stmt_list -> rax=1 if contains return, 0 if not
; simple linear scan, does not analyze branches
ck_has_return:
    push rbx
    mov rbx, rdi
.l: test rbx, rbx
    jz .no
    cmp qword[rbx], NODE_RETURN
    je .yes
    ; check inside if/else bodies (one level deep)
    cmp qword[rbx], NODE_IF
    jne .nx
    push rbx
    mov rdi, [rbx+24]    ; then branch
    call ck_has_return
    test rax, rax
    pop rbx
    jnz .yes
    push rbx
    mov rdi, [rbx+8]     ; else branch (may be null)
    call ck_has_return
    test rax, rax
    pop rbx
    jnz .yes
.nx:mov rbx, [rbx+32]
    jmp .l
.yes:
    mov rax, 1
    pop rbx
    ret
.no:
    xor rax, rax
    pop rbx
    ret

; function check
ck_func:
    push rbx
    push r14
    push r15
    mov qword[cv_count], 0
    mov qword[cv_depth], 0
    call ck_enter
    ; add params, mark as param for E008
    mov rbx, [r13+24]
.fp:test rbx, rbx
    jz .fb
    cmp qword[rbx], NODE_PARAM
    jne .fn
    mov rsi, [rbx+48]
    mov rcx, [rbx+56]
    call ck_add_var
    mov rax, [cv_count]
    dec rax
    mov qword[cv_param+rax*8], 1
.fn:mov rbx, [rbx+32]
    jmp .fp
.fb:
    ; check body
    mov rdi, [r13+16]
    call ck_slist
    ; check guard
    mov rdi, [r13+8]
    test rdi, rdi
    jz .post_guard
    call ck_expr
.post_guard:
    ; E006: missing return for typed functions
    mov rax, [r13+40]
    shr rax, 8            ; extract return type from packed field
    cmp rax, TYPE_VOID
    je .no_e006
    cmp rax, TYPE_INFER
    je .no_e006
    test rax, rax
    jz .no_e006
    mov rdi, [r13+16]    ; body stmt list
    call ck_has_return
    test rax, rax
    jnz .no_e006
    mov rdi, [r13+48]
    mov rsi, [r13+56]
    call diag_err_missing_return
.no_e006:
    ; E008: unused variables (skip params, skip _ prefix)
    xor rbx, rbx
.e008_l:
    cmp rbx, [cv_count]
    jge .e008_d
    cmp qword[cv_param+rbx*8], 1
    je .e008_nx
    cmp qword[cv_used+rbx*8], 1
    je .e008_nx
    mov rsi, [cv_nptr+rbx*8]
    test rsi, rsi
    jz .e008_nx
    cmp byte[rsi], '_'
    je .e008_nx
    mov rdi, rsi
    mov rsi, [cv_nlen+rbx*8]
    push rbx
    call diag_warn_unused_var
    pop rbx
.e008_nx:
    inc rbx
    jmp .e008_l
.e008_d:
    call ck_leave
    pop r15
    pop r14
    pop rbx
    ret
.fd:call ck_leave
    pop r15
    pop r14
    pop rbx
    ret

; statement check

; ck_slist: walk statement list, check each, detect E007 unreachable after return
ck_slist:
    push r12
    push r13
    mov r12, rdi
    xor r13, r13        ; 0 = no return seen yet
.l: test r12, r12
    jz .d
    ; E007: if we already saw a return and this node has a source position, warn
    test r13, r13
    jz .no_warn
    mov rdi, [r12+48]   ; try name_ptr of unreachable statement
    mov rsi, [r12+56]
    test rdi, rdi
    jz .try_child
    call diag_warn_unreachable
    jmp .no_warn
.try_child:
    ; some nodes (print, return) store expr at [16], try its name
    mov rax, [r12+16]
    test rax, rax
    jz .no_warn
    mov rdi, [rax+48]
    mov rsi, [rax+56]
    test rdi, rdi
    jz .no_warn
    call diag_warn_unreachable
.no_warn:
    mov rdi, r12
    call ck_stmt
    ; track whether this was a return
    cmp qword[r12], NODE_RETURN
    jne .not_ret
    mov r13, 1
.not_ret:
    mov r12, [r12+32]
    jmp .l
.d: pop r13
    pop r12
    ret

ck_stmt:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov [ck_cur_stmt], rdi
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
    je .anchor
    cmp rax, NODE_SUPERVISE
    je .supervise
    cmp rax, NODE_RAW
    je .scope1
    cmp rax, NODE_UNWIND
    je .unwind_
    cmp rax, NODE_STORE
    je .store_
    cmp rax, NODE_RELEASE
    je .release_
    cmp rax, NODE_RELEASE_G
    je .release_
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
    jz .let_fin
    call ck_expr
    ; E004: type range
    mov rax, [r12+8]
    cmp rax, TYPE_INFER
    je .let_track
    cmp rax, TYPE_I64
    je .let_track
    cmp rax, TYPE_U64
    je .let_track
    mov rdi, [r12+16]
    cmp qword[rdi], NODE_NUMBER
    jne .let_track
    mov rsi, [rdi+8]
    mov rdi, rax
    push rdi
    push rsi
    call ck_type_range
    test rax, rax
    pop rsi
    pop rdi
    jz .let_track
    mov rcx, rdi
    mov rdx, rsi
    mov rdi, [r12+48]
    mov rsi, [r12+56]
    call diag_err_type_range
    ; E010 flow: track claim() inside anchor
.let_track:
    cmp qword[fa_anc_depth], 0
    je .let_fin
    mov rdi, [r12+16]
    test rdi, rdi
    jz .let_fin
    cmp qword[rdi], NODE_CLAIM
    je .let_do_track
    cmp qword[rdi], NODE_CLAIM_G
    je .let_do_track
    jmp .let_fin
.let_do_track:
    mov rax, [fa_alloc_cnt]
    mov rsi, [r12+48]
    mov [fa_alloc_nptr+rax*8], rsi
    mov rcx, [r12+56]
    mov [fa_alloc_nlen+rax*8], rcx
    mov qword[fa_alloc_rel+rax*8], 0
    inc qword[fa_alloc_cnt]
.let_fin:
    mov rsi, [r12+48]
    mov rcx, [r12+56]
    test rsi, rsi
    jz .done
    call ck_add_var
    jmp .done
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
; anchor: track allocations for E010
.anchor:
    call ck_enter
    mov rax, [fa_anc_depth]
    mov rsi, [r12+48]
    mov [fa_anc_nptr+rax*8], rsi
    mov rcx, [r12+56]
    mov [fa_anc_nlen+rax*8], rcx
    mov rsi, [fa_alloc_cnt]
    mov [fa_anc_base+rax*8], rsi
    inc qword[fa_anc_depth]
    mov rdi, [r12+16]
    call ck_slist
    dec qword[fa_anc_depth]
    mov rax, [fa_anc_depth]
    mov rsi, [fa_anc_base+rax*8]
    mov [fa_alloc_cnt], rsi
    call ck_leave
    jmp .done

; supervise: track for E011
.supervise:
    call ck_enter
    mov rax, [fa_sup_depth]
    mov rdi, [r12+16]
    test rdi, rdi
    jz .sup_nop
    mov rsi, [rdi+48]
    mov [fa_sup_body+rax*8], rsi
    mov rcx, [rdi+56]
    mov [fa_sup_blen+rax*8], rcx
    jmp .sup_go
.sup_nop:
    mov qword[fa_sup_body+rax*8], 0
    mov qword[fa_sup_blen+rax*8], 0
.sup_go:
    inc qword[fa_sup_depth]
    mov rdi, [r12+16]
    call ck_slist
    dec qword[fa_sup_depth]
    call ck_leave
    jmp .done

; unwind: check for unreleased allocs (E010)
.unwind_:
    cmp qword[fa_anc_depth], 0
    je .done
    mov rax, [fa_anc_depth]
    dec rax
    mov rbx, [fa_anc_base+rax*8]
.unw_chk:
    cmp rbx, [fa_alloc_cnt]
    jge .done
    cmp qword[fa_alloc_rel+rbx*8], 1
    je .unw_nx
    ; unreleased: emit E010
    push rbx
    mov rax, [fa_anc_depth]
    dec rax
    mov rdi, [fa_anc_nptr+rax*8]
    mov rsi, [fa_anc_nlen+rax*8]
    mov rdx, [fa_alloc_nptr+rbx*8]
    mov rcx, [fa_alloc_nlen+rbx*8]
    mov r8, [r12+48]
    mov r9, [r12+56]
    call diag_err_leak_unwind
    pop rbx
.unw_nx:
    inc rbx
    jmp .unw_chk

; release: mark alloc as freed for E010 tracking
.release_:
    mov rdi, [r12+16]
    test rdi, rdi
    jz .done
    call ck_expr
    cmp qword[fa_anc_depth], 0
    je .done
    mov rdi, [r12+16]
    test rdi, rdi
    jz .done
    cmp qword[rdi], NODE_IDENT
    jne .done
    mov rsi, [rdi+48]
    mov rcx, [rdi+56]
    test rsi, rsi
    jz .done
    mov rbx, [fa_alloc_cnt]
.rel_chk:
    test rbx, rbx
    jz .done
    dec rbx
    cmp rcx, [fa_alloc_nlen+rbx*8]
    jne .rel_chk
    push rbx
    push rsi
    push rcx
    mov rdi, [fa_alloc_nptr+rbx*8]
    call ely_memcmp
    pop rcx
    pop rsi
    pop rbx
    test rax, rax
    jnz .rel_chk
    mov qword[fa_alloc_rel+rbx*8], 1
    jmp .done
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
    jmp .done

.ck_call_stmt:
    mov rdi, r12
    call ck_expr
    jmp .done

.done:
    pop r13
    pop r12
    pop rbx
    ret

; expression check

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
    ; might be a variant constructor name, not an error
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
    ; E011: division inside supervise
    cmp qword[fa_sup_depth], 0
    je .done
    mov rax, [r12+8]
    cmp rax, TOK_SLASH
    jne .done
    ; find source position: try current stmt name, then left operand
    mov rdi, [ck_cur_stmt]
    test rdi, rdi
    jz .done
    mov rdi, [rdi+48]
    test rdi, rdi
    jnz .e011_emit
    ; try left operand of binop
    mov rdi, [r12+16]
    test rdi, rdi
    jz .done
    mov rdi, [rdi+48]
    test rdi, rdi
    jz .done
.e011_emit:
    push rdi
    mov rax, [ck_cur_stmt]
    test rax, rax
    jz .e011_no_len
    mov rsi, [rax+56]
    jmp .e011_call
.e011_no_len:
    mov rsi, [r12+16]
    mov rsi, [rsi+56]
.e011_call:
    mov rax, [fa_sup_depth]
    dec rax
    mov rdx, [fa_sup_body+rax*8]
    mov rcx, [fa_sup_blen+rax*8]
    pop rdi
    call diag_warn_div_supervise
    jmp .done

.call:
    ; check all argument expressions
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
    ; variant constructor? skip function check
    push rsi
    push rcx
    call treg_lookup_variant
    cmp rax, 0xFFFFFFFFFFFFFFFF
    pop rcx
    pop rsi
    jne .done
    ; look up function
    push rsi
    push rcx
    call ck_find_fn
    pop rcx
    pop rsi
    cmp rax, 0xFFFFFFFFFFFFFFFF
    je .ca_undef
    ; check argument count
    cmp rax, r13
    je .done
    ; wrong count: rax=expected, r13=got
    mov rdx, rax
    mov rcx, r13
    mov rdi, [r12+48]
    mov rsi, [r12+56]
    ; get definition name pointer for location display
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

; ck_type_range: check if literal value fits in declared type
; rdi=TYPE_*, rsi=value (unsigned from parser) -> rax=0 fits, 1 out of range
ck_type_range:
    cmp rdi, TYPE_I8
    je .i8
    cmp rdi, TYPE_U8
    je .u8
    cmp rdi, TYPE_I16
    je .i16
    cmp rdi, TYPE_U16
    je .u16
    cmp rdi, TYPE_I32
    je .i32
    cmp rdi, TYPE_U32
    je .u32
    ; i64/u64/ptr/void/infer: always ok
    xor rax, rax
    ret
.i8:  cmp rsi, 127
    ja .bad
    xor rax, rax
    ret
.u8:  cmp rsi, 255
    ja .bad
    xor rax, rax
    ret
.i16: cmp rsi, 32767
    ja .bad
    xor rax, rax
    ret
.u16: cmp rsi, 65535
    ja .bad
    xor rax, rax
    ret
.i32: cmp rsi, 2147483647
    ja .bad
    xor rax, rax
    ret
.u32: mov rax, 4294967295
    cmp rsi, rax
    ja .bad
    xor rax, rax
    ret
.bad: mov rax, 1
    ret