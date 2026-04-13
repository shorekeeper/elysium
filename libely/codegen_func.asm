; codegen_func.asm - function clause compilation
default rel
%include "defs.inc"
extern compile_expr,compile_stmt_list
extern emit_cstr,emit_num,emit_nl,emit_name,emit_label,emit_jmp_label,new_label
extern sym_init,sym_push,sym_alloc_bytes,sym_leave_scope,sym_depth
extern sym_set_last_type
extern be_target,be_mod_root,ely_memcmp
global compile_module

section .data
s_fnpre:    db "__ely_fn_",0
s_colon_nl: db ":",10,0
s_prologue: db "    push rbx",10,"    push r12",10
            db "    push rbp",10,"    mov rbp, rsp",10,0
s_sub_rsp:  db "    sub rsp, ",0
s_epilogue: db "    leave",10,"    pop r12",10,"    pop rbx",10,"    ret",10,10,0
s_epi_nr:   db "    leave",10,"    pop r12",10,"    pop rbx",10,0
s_store2:   db "    mov [rbp - ",0
s_close_cm: db "], ",0
s_cmp_q:    db "    cmp qword [rbp - ",0
s_close_cma:db "], ",0
s_test_rax: db "    test rax, rax",10,0
s_jne:      db "    jne ",0
s_jz:       db "    jz ",0
s_xor_eax:  db "    xor eax, eax",10,0
s_ret:      db "    ret",10,0
s_rdi:db "rdi",0
s_rsi:db "rsi",0
s_rdx:db "rdx",0
s_rcx:db "rcx",0
s_r8: db "r8",0
s_r9: db "r9",0
align 8
argregs: dq s_rdi,s_rsi,s_rdx,s_rcx,s_r8,s_r9

LEGACY_MAX_SYMS equ 1024

section .bss
clause_ptrs: resq MAX_CLAUSES
clause_cnt: resq 1
done_nptr: resq LEGACY_MAX_SYMS
done_nlen: resq LEGACY_MAX_SYMS
done_cnt: resq 1

section .text
is_done:
    push rbx
    push rdi
    push rsi
    push rcx
    push r8
    push r9
    mov r8,rsi
    mov r9,rcx
    mov rbx,[done_cnt]
.l: test rbx,rbx
    jz .nf
    dec rbx
    cmp r9,[done_nlen+rbx*8]
    jne .l
    mov rsi,r8
    mov rdi,[done_nptr+rbx*8]
    mov rcx,r9
    call ely_memcmp
    test rax,rax
    jnz .l
    mov rax,1
    jmp .d
.nf:xor rax,rax
.d: pop r9
    pop r8
    pop rcx
    pop rsi
    pop rdi
    pop rbx
    ret

mark_done:
    push rax
    mov rax,[done_cnt]
    mov [done_nptr+rax*8],rsi
    mov [done_nlen+rax*8],rcx
    inc qword[done_cnt]
    pop rax
    ret

collect:
    push rbx
    push rdi
    push rsi
    push rcx
    push r8
    push r9
    mov r8,rsi
    mov r9,rcx
    mov qword[clause_cnt],0
    mov rdi,[be_mod_root]
    test rdi,rdi
    jz .d
    mov rbx,[rdi+16]
.l: test rbx,rbx
    jz .d
    cmp qword[rbx],NODE_FUNC
    jne .nx
    cmp r9,[rbx+56]
    jne .nx
    mov rsi,r8
    mov rdi,[rbx+48]
    mov rcx,r9
    push rbx
    call ely_memcmp
    pop rbx
    test rax,rax
    jnz .nx
    mov rax,[clause_cnt]
    mov [clause_ptrs+rax*8],rbx
    inc qword[clause_cnt]
.nx:mov rbx,[rbx+32]
    jmp .l
.d: pop r9
    pop r8
    pop rcx
    pop rsi
    pop rdi
    pop rbx
    ret

compile_module:
    push rbx
    push r12
    mov qword[done_cnt],0
    test rdi,rdi
    jz .end
    mov r12,[rdi+16]
.lp:test r12,r12
    jz .end
    cmp qword[r12],NODE_FUNC
    jne .nx
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call is_done
    test rax,rax
    jnz .nx
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call collect
    call compile_func_group
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call mark_done
.nx:mov r12,[r12+32]
    jmp .lp
.end:pop r12
    pop rbx
    ret

compile_func_group:
    push rbx
    push r12
    push r13
    mov rdi,s_fnpre
    call emit_cstr
    mov rax,[clause_ptrs]
    mov rsi,[rax+48]
    mov rdx,[rax+56]
    call emit_name
    mov rdi,s_colon_nl
    call emit_cstr
    xor r12,r12
.lp:cmp r12,[clause_cnt]
    jge .done
    mov r13,[clause_ptrs+r12*8]
    call compile_clause
    inc r12
    jmp .lp
.done:
    mov rdi,s_xor_eax
    call emit_cstr
    mov rdi,s_ret
    call emit_cstr
    call emit_nl
    pop r13
    pop r12
    pop rbx
    ret

compile_clause:
    push rbx
    push rcx
    push r14
    push r15
    call new_label
    mov r14,rax
    call sym_init
    inc qword[sym_depth]
    mov rdi,s_prologue
    call emit_cstr
    mov rdi,s_sub_rsp
    call emit_cstr
    mov rax,FRAME_SIZE
    call emit_num
    call emit_nl
    xor r15,r15
    mov rbx,[r13+24]
.par:test rbx,rbx
    jz .pd
    cmp r15,6
    jge .pd
    cmp qword[rbx],NODE_PARAM
    je .pvar
    cmp qword[rbx],NODE_NUMBER
    je .plit
    jmp .pnx
; variable param
.pvar:
    mov rsi,[rbx+48]
    mov rcx,[rbx+56]
    call sym_push
    push rax
    ; set type from param annotation
    mov rdi,[rbx+8]
    call sym_set_last_type
    pop rax
    push rax
    mov rdi,s_store2
    call emit_cstr
    pop rax
    push rax
    call emit_num
    mov rdi,s_close_cm
    call emit_cstr
    mov rdi,[argregs+r15*8]
    call emit_cstr
    call emit_nl
    pop rax
    jmp .pnx
; literal pattern
.plit:
    push rbx
    push r15
    mov rdi,8
    call sym_alloc_bytes
    pop r15
    pop rbx
    push rax
    mov rdi,s_store2
    call emit_cstr
    pop rax
    push rax
    call emit_num
    mov rdi,s_close_cm
    call emit_cstr
    mov rdi,[argregs+r15*8]
    call emit_cstr
    call emit_nl
    mov rdi,s_cmp_q
    call emit_cstr
    pop rax
    call emit_num
    mov rdi,s_close_cma
    call emit_cstr
    mov rax,[rbx+8]
    call emit_num
    call emit_nl
    mov rax,r14
    mov rdi,s_jne
    call emit_jmp_label
.pnx:inc r15
    mov rbx,[rbx+32]
    jmp .par
.pd:
    mov rax,[r13+8]
    test rax,rax
    jz .ng
    mov rdi,rax
    call compile_expr
    mov rdi,s_test_rax
    call emit_cstr
    mov rax,r14
    mov rdi,s_jz
    call emit_jmp_label
.ng:
    mov rdi,[r13+16]
    call compile_stmt_list
    mov rdi,s_epilogue
    call emit_cstr
    mov rax,r14
    call emit_label
    mov rdi,s_epi_nr
    call emit_cstr
    call sym_leave_scope
    dec qword[sym_depth]
    pop r15
    pop r14
    pop rcx
    pop rbx
    ret