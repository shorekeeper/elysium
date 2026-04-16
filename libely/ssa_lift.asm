; ssa_lift.asm - convert flat MIR into basic blocks
default rel
%include "defs.inc"
extern vmem_alloc, vmem_free
extern mir_buf
extern ssa_bb_create, ssa_slot_register, ssa_slot_find
extern ssa_bb_cnt, ssa_slot_cnt
extern bb_mir_start, bb_mir_end, bb_succ0, bb_succ1, bb_label_id
extern slot_escaped

global ssa_collect_slots, ssa_mark_escaped, ssa_build_bbs
global ssa_find_bb_for_label

section .text

ssa_collect_slots:
    push rbx
    push r12
    push r13
    push r11
    mov r12, rdi
    mov r13, rsi
    mov rbx, r12
.lp:cmp rbx, r13
    jge .dn
    imul rax, rbx, MIR_SIZE
    mov r11, [mir_buf]
    mov rdi, [r11+rax]
    mov rsi, [r11+rax+8]
    mov rdx, [r11+rax+16]
    cmp rdi, MIR_SLOAD
    je .reg
    cmp rdi, MIR_SSTORE
    je .reg
    jmp .nx
.reg:
    mov rdi, rsi
    mov rsi, rdx
    cmp rsi, TYPE_INFER
    jne .ty
    mov rsi, TYPE_I64
.ty:test rsi, rsi
    jnz .ok
    mov rsi, TYPE_I64
.ok:call ssa_slot_register
.nx:inc rbx
    jmp .lp
.dn:pop r11
    pop r13
    pop r12
    pop rbx
    ret

ssa_mark_escaped:
    push rbx
    push r12
    push r13
    push r11
    mov r12, rdi
    mov r13, rsi
    xor rbx, rbx
.zl:cmp rbx, [ssa_slot_cnt]
    jge .sc
    mov r11, [slot_escaped]
    mov qword[r11+rbx*8], 0
    inc rbx
    jmp .zl
.sc:mov rbx, r12
.sl:cmp rbx, r13
    jge .sd
    imul rax, rbx, MIR_SIZE
    mov r11, [mir_buf]
    mov rdi, [r11+rax]
    cmp rdi, MIR_SLEA
    jne .sn
    mov rdi, [r11+rax+8]
    call ssa_slot_find
    cmp rax, -1
    je .sn
    push r11
    mov r11, [slot_escaped]
    mov qword[r11+rax*8], 1
    pop r11
.sn:inc rbx
    jmp .sl
.sd:pop r11
    pop r13
    pop r12
    pop rbx
    ret

ssa_build_bbs:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r12, rdi
    mov r13, rsi
    mov r14, rsi
    sub r14, rdi
    ; allocate is_bb_start byte array
    mov rdi, r14
    add rdi, 16
    call vmem_alloc
    mov r15, rax
    ; mark function entry
    mov byte[r15], 1
    ; pass 1: scan, mark BB boundaries
    xor rbx, rbx
.p1:cmp rbx, r14
    jge .p2
    lea rax, [r12+rbx]
    imul rax, rax, MIR_SIZE
    push r11
    mov r11, [mir_buf]
    mov rdi, [r11+rax]
    pop r11
    cmp rdi, MIR_LABEL
    je .p1_mark
    ; *** FIX: terminators include LEAVE_NRET ***
    cmp rdi, MIR_JMP
    je .p1_term
    cmp rdi, MIR_JZ
    je .p1_term
    cmp rdi, MIR_JNZ
    je .p1_term
    cmp rdi, MIR_JNE
    je .p1_term
    cmp rdi, MIR_LEAVE
    je .p1_term
    cmp rdi, MIR_RET
    je .p1_term
    cmp rdi, MIR_LEAVE_NRET
    je .p1_term
    jmp .p1_nx
.p1_mark:
    mov byte[r15+rbx], 1
    jmp .p1_nx
.p1_term:
    lea rax, [rbx+1]
    cmp rax, r14
    jge .p1_nx
    mov byte[r15+rax], 1
.p1_nx:
    inc rbx
    jmp .p1

    ; pass 2: create BBs
.p2:mov qword[ssa_bb_cnt], 0
    mov rbp, -1
    xor rbx, rbx
.p2l:cmp rbx, r14
    jge .p3
    cmp byte[r15+rbx], 1
    jne .p2s
    push rbx
    call ssa_bb_create
    mov rbp, rax
    pop rbx
    lea rax, [r12+rbx]
    push r11
    mov r11, [bb_mir_start]
    mov [r11+rbp*8], rax
    pop r11
    lea rax, [r12+rbx]
    imul rax, rax, MIR_SIZE
    push r11
    mov r11, [mir_buf]
    mov rdi, [r11+rax]
    mov rsi, [r11+rax+8]
    pop r11
    cmp rdi, MIR_LABEL
    je .p2_lbl
    cmp rdi, MIR_FUNC_LABEL
    je .p2_lbl
    jmp .p2s
.p2_lbl:
    push r11
    mov r11, [bb_label_id]
    mov [r11+rbp*8], rsi
    pop r11
.p2s:
    inc rbx
    jmp .p2l

    ; pass 3: set bb_mir_end
.p3:mov rax, [ssa_bb_cnt]
    test rax, rax
    jz .p4
    xor rbx, rbx
.p3l:lea rax, [rbx+1]
    cmp rax, [ssa_bb_cnt]
    jge .p3e
    push r11
    mov r11, [bb_mir_start]
    mov rax, [r11+rax*8]
    mov r11, [bb_mir_end]
    mov [r11+rbx*8], rax
    pop r11
    inc rbx
    jmp .p3l
.p3e:
    mov rax, [ssa_bb_cnt]
    dec rax
    push r11
    mov r11, [bb_mir_end]
    mov [r11+rax*8], r13
    pop r11

    ; pass 4: set successor edges
.p4:xor rbx, rbx
.p4l:cmp rbx, [ssa_bb_cnt]
    jge .done
    push r11
    mov r11, [bb_mir_end]
    mov rax, [r11+rbx*8]
    pop r11
    dec rax
    imul rcx, rax, MIR_SIZE
    push r11
    mov r11, [mir_buf]
    mov rdi, [r11+rcx]
    mov rsi, [r11+rcx+8]
    pop r11
    cmp rdi, MIR_JMP
    je .s_jmp
    cmp rdi, MIR_JZ
    je .s_cond
    cmp rdi, MIR_JNZ
    je .s_cond
    cmp rdi, MIR_JNE
    je .s_cond
    cmp rdi, MIR_LEAVE
    je .s_ret
    cmp rdi, MIR_RET
    je .s_ret
    ; *** FIX: LEAVE_NRET = no successors ***
    cmp rdi, MIR_LEAVE_NRET
    je .s_ret
    jmp .s_fall

.s_jmp:
    mov rdi, rsi
    push rbx
    call ssa_find_bb_for_label
    pop rbx
    push r11
    mov r11, [bb_succ0]
    mov [r11+rbx*8], rax
    mov r11, [bb_succ1]
    mov qword[r11+rbx*8], -1
    pop r11
    jmp .p4n

.s_cond:
    push rsi
    lea rax, [rbx+1]
    cmp rax, [ssa_bb_cnt]
    jl .s_c1
    mov rax, -1
.s_c1:
    push r11
    mov r11, [bb_succ0]
    mov [r11+rbx*8], rax
    pop r11
    pop rsi
    mov rdi, rsi
    push rbx
    call ssa_find_bb_for_label
    pop rbx
    push r11
    mov r11, [bb_succ1]
    mov [r11+rbx*8], rax
    pop r11
    jmp .p4n

.s_ret:
    push r11
    mov r11, [bb_succ0]
    mov qword[r11+rbx*8], -1
    mov r11, [bb_succ1]
    mov qword[r11+rbx*8], -1
    pop r11
    jmp .p4n

.s_fall:
    lea rax, [rbx+1]
    cmp rax, [ssa_bb_cnt]
    jl .s_f1
    mov rax, -1
.s_f1:
    push r11
    mov r11, [bb_succ0]
    mov [r11+rbx*8], rax
    mov r11, [bb_succ1]
    mov qword[r11+rbx*8], -1
    pop r11

.p4n:
    inc rbx
    jmp .p4l

.done:
    ; *** FIX: free temporary is_bb_start array ***
    mov rdi, r15
    call vmem_free

    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

ssa_find_bb_for_label:
    push rbx
    push r11
    xor rbx, rbx
.l: cmp rbx, [ssa_bb_cnt]
    jge .nf
    mov r11, [bb_label_id]
    cmp rdi, [r11+rbx*8]
    je .f
    inc rbx
    jmp .l
.f: mov rax, rbx
    pop r11
    pop rbx
    ret
.nf:mov rax, -1
    pop r11
    pop rbx
    ret