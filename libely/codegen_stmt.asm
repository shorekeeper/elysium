default rel
%include "defs.inc"
extern compile_expr
extern emit_cstr,emit_num,emit_nl,emit_label,emit_jmp_label,new_label,emit_name
extern sym_push,sym_push_arr,sym_lookup,sym_get_index,sym_leave_scope
extern sym_alloc_bytes,sym_depth
extern sym_bstate,sym_bcnt,sym_alias,sym_off,sym_count,sym_type,sym_set_last_type
extern sym_arrlen
extern anc_push,anc_lookup,anc_pop
extern be_target,platform_write
global compile_stmt, compile_stmt_list

section .data
s_store:    db "    mov [rbp - ",0
s_close_rax:db "], rax",10,0
s_close_brk:db "]",10,0
s_load:     db "    mov rax, [rbp - ",0
s_epilogue: db "    leave",10,"    pop r12",10,"    pop rbx",10,"    ret",10,10,0
s_mov_rdi:  db "    mov rdi, rax",10,0
s_call_prt: db "    call __rt_print_int",10,0
s_call_pstr:db "    call __rt_print_str",10,0
s_test_rax: db "    test rax, rax",10,0
s_jz:       db "    jz ",0
s_jmp:      db "    jmp ",0
s_jne:      db "    jne ",0
s_jnz:      db "    jnz ",0
s_xor_eax:  db "    xor eax, eax",10,0
s_cmp_q:    db "    cmp qword [rbp - ",0
s_close_cma:db "], ",0
s_lea_rdi:  db "    lea rdi, [rbp - ",0
s_call_csav:db "    call __rt_ckpt_save",10,0
s_call_crst:db "    call __rt_ckpt_restore",10,0
s_mov_rsi1: db "    mov rsi, 1",10,0
s_push_sv:  db "    push qword [__rt_sv_current]",10,0
s_pop_sv:   db "    pop qword [__rt_sv_current]",10,0
s_lea_sv:   db "    lea rax, [rbp - ",0
s_set_sv:   db "    mov [__rt_sv_current], rax",10,0
s_push_rax: db "    push rax",10,0
s_pop_rbx:  db "    pop rbx",10,0
s_pop_rcx:  db "    pop rcx",10,0
s_store_mem:db "    mov [rax + rbx*8], rcx",10,0
s_mov_rdi_rax:db "    mov rdi, rax",10,0
s_call_release:db "    call __rt_release",10,0
s_call_pdrain:db "    call __rt_pool_drain",10,0
s_lea_rax:  db "    lea rax, [rbp - ",0
s_mov_rbx_rax:db "    mov rbx, rax",10,0
s_idx_store:db "    mov [rax + rbx*8], rcx",10,0
err_brw_im: db "  [error] cannot borrow: mut-locked",10,0
err_brw_mu: db "  [error] cannot mut-borrow: borrowed",10,0
err_undef:  db "  [error] undefined variable",10,0

section .text
bepr:push rsi
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

compile_stmt_list:
    push rbx
    push r12
    mov r12,rdi
.l: test r12,r12
    jz .d
    mov rdi,r12
    call compile_stmt
    mov r12,[r12+32]
    jmp .l
.d: pop r12
    pop rbx
    ret

compile_stmt:
    push rbx
    push rcx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov rax,[r12]
    cmp rax,NODE_LET
    je .let
    cmp rax,NODE_RETURN
    je .ret
    cmp rax,NODE_PRINT
    je .prn
    cmp rax,NODE_PRINT_STR
    je .pstr
    cmp rax,NODE_IF
    je .if_
    cmp rax,NODE_MATCH
    je .match
    cmp rax,NODE_ANCHOR
    je .anchor
    cmp rax,NODE_SUPERVISE
    je .super
    cmp rax,NODE_UNWIND
    je .unwind
    cmp rax,NODE_RAW
    je .raw
    cmp rax,NODE_STORE
    je .memstore
    cmp rax,NODE_RELEASE
    je .memrel
    cmp rax,NODE_RELEASE_G
    je .memrelg
    cmp rax,NODE_POOL_DRAIN
    je .mpdrain
    cmp rax,NODE_INDEX_SET
    je .idx_set
    jmp .done

; - LET: check if RHS is array -
.let:
    mov rdi,[r12+16]
    test rdi,rdi
    jz .done
    cmp qword[rdi],NODE_BORROW
    je .let_brw
    cmp qword[rdi],NODE_ARRAY
    je .let_arr
    ; normal scalar let
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call sym_push
    mov r13,rax
    mov rdi,[r12+8]
    call sym_set_last_type
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_store
    call emit_cstr
    mov rax,r13
    call emit_num
    mov rdi,s_close_rax
    call emit_cstr
    jmp .done

; let name = [expr, expr, ...]
.let_arr:
    mov rdi,[r12+16]       ; NODE_ARRAY
    mov r13,[rdi+8]        ; element count
    mov r14,rdi            ; save array node
    ; allocate count*8 bytes
    push r13
    push r14
    imul rdi,r13,8
    call sym_alloc_bytes   ; rax = base_offset
    mov r15,rax
    pop r14
    pop r13
    ; register in symtab
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    mov rdi,r13            ; arrlen
    mov rdx,r15            ; base offset
    call sym_push_arr
    ; compile each element and store at consecutive offsets
    mov rbx,[r14+16]       ; first element expr node
    xor r14,r14            ; element index
.arr_st:
    test rbx,rbx
    jz .done
    push rbx
    push r14
    push r15
    mov rdi,rbx
    call compile_expr
    pop r15
    pop r14
    ; emit: mov [rbp - (base - index*8)], rax
    mov rdi,s_store
    call emit_cstr
    mov rax,r15
    imul rcx,r14,8
    sub rax,rcx
    call emit_num
    mov rdi,s_close_rax
    call emit_cstr
    pop rbx
    inc r14
    mov rbx,[rbx+32]
    jmp .arr_st

; borrow handling (unchanged)
.let_brw:
    mov rdi,[r12+16]
    mov r13,[rdi+8]
    mov rsi,[rdi+48]
    mov rcx,[rdi+56]
    push rdi
    call sym_get_index
    pop rdi
    cmp rax,-1
    je .brw_undef
    mov r14,rax
    test r13,r13
    jnz .brw_mut
    cmp qword[sym_bstate+r14*8],2
    je .brw_ei
    inc qword[sym_bcnt+r14*8]
    jmp .brw_cr
.brw_mut:
    cmp qword[sym_bcnt+r14*8],0
    jne .brw_em
    cmp qword[sym_bstate+r14*8],2
    je .brw_em
    mov qword[sym_bstate+r14*8],2
.brw_cr:
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call sym_push
    mov rdi,TYPE_PTR
    call sym_set_last_type
    mov rbx,[sym_count]
    dec rbx
    mov rax,[sym_off+r14*8]
    mov [sym_off+rbx*8],rax
    test r13,r13
    jz .brw_im
    mov qword[sym_bstate+rbx*8],2
    jmp .brw_al
.brw_im:
    mov qword[sym_bstate+rbx*8],1
.brw_al:
    mov [sym_alias+rbx*8],r14
    jmp .done
.brw_undef:
    mov rdi,err_undef
    call bepr
    jmp .done
.brw_ei:
    mov rdi,err_brw_im
    call bepr
    jmp .done
.brw_em:
    mov rdi,err_brw_mu
    call bepr
    jmp .done

.ret:
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_epilogue
    call emit_cstr
    jmp .done
.prn:
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_mov_rdi
    call emit_cstr
    mov rdi,s_call_prt
    call emit_cstr
    jmp .done
.pstr:
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_call_pstr
    call emit_cstr
    jmp .done

.if_:
    call new_label
    mov r13,rax
    call new_label
    mov r14,rax
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_test_rax
    call emit_cstr
    mov rax,r13
    mov rdi,s_jz
    call emit_jmp_label
    inc qword[sym_depth]
    mov rdi,[r12+24]
    call compile_stmt_list
    call sym_leave_scope
    dec qword[sym_depth]
    mov rax,r14
    mov rdi,s_jmp
    call emit_jmp_label
    mov rax,r13
    call emit_label
    cmp qword[r12+8],0
    je .if_e
    inc qword[sym_depth]
    mov rdi,[r12+8]
    call compile_stmt_list
    call sym_leave_scope
    dec qword[sym_depth]
.if_e:mov rax,r14
    call emit_label
    jmp .done

.match:
    mov rdi,8
    call sym_alloc_bytes
    mov r13,rax
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_store
    call emit_cstr
    mov rax,r13
    call emit_num
    mov rdi,s_close_rax
    call emit_cstr
    call new_label
    mov r14,rax
    push r14
    mov rbx,[r12+24]
.ma_l:test rbx,rbx
    jz .ma_e
    mov rax,[rbx+40]
    cmp rax,0
    je .ma_lit
    cmp rax,1
    je .ma_w
    cmp rax,2
    je .ma_b
    mov rbx,[rbx+32]
    jmp .ma_l
.ma_lit:
    call new_label
    push rax
    mov rdi,s_cmp_q
    call emit_cstr
    mov rax,r13
    call emit_num
    mov rdi,s_close_cma
    call emit_cstr
    mov rax,[rbx+8]
    call emit_num
    call emit_nl
    pop rax
    push rax
    mov rdi,s_jne
    call emit_jmp_label
    push rbx
    mov rdi,[rbx+16]
    call compile_stmt
    pop rbx
    mov rax,[rsp+8]
    mov rdi,s_jmp
    call emit_jmp_label
    pop rax
    call emit_label
    mov rbx,[rbx+32]
    jmp .ma_l
.ma_b:
    call new_label
    push rax
    inc qword[sym_depth]
    mov rdi,s_load
    call emit_cstr
    mov rax,r13
    call emit_num
    mov rdi,s_close_brk
    call emit_cstr
    push rbx
    mov rsi,[rbx+48]
    mov rcx,[rbx+56]
    call sym_push
    mov rdi,s_store
    call emit_cstr
    call emit_num
    mov rdi,s_close_rax
    call emit_cstr
    pop rbx
    mov rax,[rbx+24]
    test rax,rax
    jz .mbe
    push rbx
    mov rdi,rax
    call compile_expr
    pop rbx
    mov rdi,s_test_rax
    call emit_cstr
    mov rax,[rsp]
    mov rdi,s_jz
    call emit_jmp_label
.mbe:push rbx
    mov rdi,[rbx+16]
    call compile_stmt
    pop rbx
    call sym_leave_scope
    dec qword[sym_depth]
    mov rax,[rsp+8]
    mov rdi,s_jmp
    call emit_jmp_label
    pop rax
    call emit_label
    mov rbx,[rbx+32]
    jmp .ma_l
.ma_w:push rbx
    mov rdi,[rbx+16]
    call compile_stmt
    pop rbx
    mov rax,[rsp]
    mov rdi,s_jmp
    call emit_jmp_label
    mov rbx,[rbx+32]
    jmp .ma_l
.ma_e:pop r14
    mov rax,r14
    call emit_label
    jmp .done

.anchor:
    mov rdi,CKPT_BYTES
    call sym_alloc_bytes
    mov r13,rax
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    mov rdx,r13
    call anc_push
    call new_label
    mov r14,rax
    call new_label
    push rax
    mov rdi,s_lea_rdi
    call emit_cstr
    mov rax,r13
    call emit_num
    mov rdi,s_close_brk
    call emit_cstr
    mov rdi,s_call_csav
    call emit_cstr
    mov rdi,s_test_rax
    call emit_cstr
    mov rax,r14
    mov rdi,s_jnz
    call emit_jmp_label
    inc qword[sym_depth]
    mov rdi,[r12+16]
    call compile_stmt_list
    call sym_leave_scope
    dec qword[sym_depth]
    pop rax
    push rax
    mov rdi,s_jmp
    call emit_jmp_label
    mov rax,r14
    call emit_label
    pop rax
    call emit_label
    call anc_pop
    jmp .done

.super:
    mov rdi,CKPT_BYTES
    call sym_alloc_bytes
    mov r13,rax
    call new_label
    mov r14,rax
    call new_label
    push rax
    mov rdi,s_push_sv
    call emit_cstr
    mov rdi,s_lea_rdi
    call emit_cstr
    mov rax,r13
    call emit_num
    mov rdi,s_close_brk
    call emit_cstr
    mov rdi,s_call_csav
    call emit_cstr
    mov rdi,s_test_rax
    call emit_cstr
    mov rax,r14
    mov rdi,s_jnz
    call emit_jmp_label
    mov rdi,s_lea_sv
    call emit_cstr
    mov rax,r13
    call emit_num
    mov rdi,s_close_brk
    call emit_cstr
    mov rdi,s_set_sv
    call emit_cstr
    inc qword[sym_depth]
    mov rdi,[r12+16]
    call compile_stmt_list
    call sym_leave_scope
    dec qword[sym_depth]
    pop rax
    push rax
    mov rdi,s_jmp
    call emit_jmp_label
    mov rax,r14
    call emit_label
    pop rax
    call emit_label
    mov rdi,s_pop_sv
    call emit_cstr
    jmp .done

.unwind:
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call anc_lookup
    test rax,rax
    jz .done
    mov r13,rax
    mov rdi,s_lea_rdi
    call emit_cstr
    mov rax,r13
    call emit_num
    mov rdi,s_close_brk
    call emit_cstr
    mov rdi,s_mov_rsi1
    call emit_cstr
    mov rdi,s_call_crst
    call emit_cstr
    jmp .done

.raw:
    inc qword[sym_depth]
    mov rdi,[r12+16]
    call compile_stmt_list
    call sym_leave_scope
    dec qword[sym_depth]
    jmp .done

; store(ptr, offset, value)
.memstore:
    mov rdi,[r12+8]
    call compile_expr
    mov rdi,s_push_rax
    call emit_cstr
    mov rdi,[r12+24]
    call compile_expr
    mov rdi,s_push_rax
    call emit_cstr
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_pop_rbx
    call emit_cstr
    mov rdi,s_pop_rcx
    call emit_cstr
    mov rdi,s_store_mem
    call emit_cstr
    jmp .done

.memrel:
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_mov_rdi_rax
    call emit_cstr
    mov rdi,s_call_release
    call emit_cstr
    jmp .done
.memrelg:
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_mov_rdi_rax
    call emit_cstr
    mov rdi,s_call_release
    call emit_cstr
    jmp .done
.mpdrain:
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_mov_rdi_rax
    call emit_cstr
    mov rdi,s_call_pdrain
    call emit_cstr
    jmp .done

; name[index] = value;
.idx_set:
    ; compile value -> push
    mov rdi,[r12+24]
    call compile_expr
    mov rdi,s_push_rax
    call emit_cstr
    ; compile index -> push
    mov rdi,[r12+16]
    call compile_expr
    mov rdi,s_push_rax
    call emit_cstr
    ; lea rax, [rbp - base]
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call sym_lookup
    test rax,rax
    jz .done
    push rax
    mov rdi,s_lea_rax
    call emit_cstr
    pop rax
    call emit_num
    mov rdi,s_close_brk
    call emit_cstr
    ; pop rbx (index), pop rcx (value)
    mov rdi,s_pop_rbx
    call emit_cstr
    mov rdi,s_pop_rcx
    call emit_cstr
    ; mov [rax + rbx*8], rcx
    mov rdi,s_idx_store
    call emit_cstr

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rcx
    pop rbx
    ret