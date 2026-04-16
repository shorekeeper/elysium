; ssa_ir.asm - SSA data structures and allocation APIs
default rel
%include "defs.inc"
extern vmem_alloc, vmem_realloc

; API
global ssa_ir_init, ssa_ir_reset
global ssa_bb_create
global ssa_inst_emit, ssa_inst_set_flags
global ssa_phi_create, ssa_phi_add_src
global ssa_vreg_new, ssa_vreg_set_type
global ssa_slot_register, ssa_slot_find

global ssa_bb_cnt, ssa_inst_cnt, ssa_phi_cnt, ssa_vreg_cnt, ssa_slot_cnt

global bb_first_inst, bb_inst_count, bb_mir_start, bb_mir_end
global bb_succ0, bb_succ1, bb_pred_start, bb_pred_count
global bb_idom, bb_df_start, bb_df_count
global bb_dead, bb_label_id, bb_stack_depth_in

global ssa_inst_buf

global phi_bb, phi_dest, phi_var, phi_src_start, phi_src_count

global vreg_type, vreg_orig_slot, vreg_def_bb, vreg_def_inst

global slot_offset, slot_type, slot_escaped
global slot_current_vreg, slot_vreg_sp, slot_vreg_stk

global pred_pool, pred_pool_pos, pred_pool_cap
global df_pool, df_pool_pos, df_pool_cap
global phi_src_pool, phi_src_pool_pos, phi_src_pool_cap

global dfs_stack, dfs_visited, rpo_buf, rpo_index, rpo_count
global ssa_abort_flag, dom_changed

section .data
align 8
; *** FIX: rpo_index REMOVED from bb_arr_ptrs, BB_ARR_COUNT = 14 ***
bb_arr_ptrs:
    dq bb_first_inst, bb_inst_count, bb_mir_start, bb_mir_end
    dq bb_succ0, bb_succ1, bb_pred_start, bb_pred_count
    dq bb_idom, bb_df_start, bb_df_count
    dq bb_dead, bb_label_id, bb_stack_depth_in
BB_ARR_COUNT equ 14

vreg_arr_ptrs:
    dq vreg_type, vreg_orig_slot, vreg_def_bb, vreg_def_inst
VREG_ARR_COUNT equ 4

phi_arr_ptrs:
    dq phi_bb, phi_dest, phi_var, phi_src_start, phi_src_count
PHI_ARR_COUNT equ 5

slot_arr_ptrs:
    dq slot_offset, slot_type, slot_escaped, slot_current_vreg, slot_vreg_sp
SLOT_ARR_COUNT equ 5

section .bss
ssa_bb_cnt:        resq 1
bb_cap:            resq 1
bb_first_inst:     resq 1
bb_inst_count:     resq 1
bb_mir_start:      resq 1
bb_mir_end:        resq 1
bb_succ0:          resq 1
bb_succ1:          resq 1
bb_pred_start:     resq 1
bb_pred_count:     resq 1
bb_idom:           resq 1
bb_df_start:       resq 1
bb_df_count:       resq 1
bb_dead:           resq 1
bb_label_id:       resq 1
bb_stack_depth_in: resq 1
ssa_inst_cnt:      resq 1
inst_cap:          resq 1
ssa_inst_buf:      resq 1
ssa_phi_cnt:       resq 1
phi_cap:           resq 1
phi_bb:            resq 1
phi_dest:          resq 1
phi_var:           resq 1
phi_src_start:     resq 1
phi_src_count:     resq 1
ssa_vreg_cnt:      resq 1
vreg_cap:          resq 1
vreg_type:         resq 1
vreg_orig_slot:    resq 1
vreg_def_bb:       resq 1
vreg_def_inst:     resq 1
ssa_slot_cnt:      resq 1
slot_cap:          resq 1
slot_offset:       resq 1
slot_type:         resq 1
slot_escaped:      resq 1
slot_current_vreg: resq 1
slot_vreg_sp:      resq 1
slot_vreg_stk:     resq 1
pred_pool:         resq 1
pred_pool_pos:     resq 1
pred_pool_cap:     resq 1
df_pool:           resq 1
df_pool_pos:       resq 1
df_pool_cap:       resq 1
phi_src_pool:      resq 1
phi_src_pool_pos:  resq 1
phi_src_pool_cap:  resq 1
dfs_stack:         resq 1
rpo_buf:           resq 1
rpo_index:         resq 1
rpo_count:         resq 1
dfs_visited:       resq 1
ssa_abort_flag:    resb 1
dom_changed:       resb 1

section .text

alloc_arrays:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor rbx, rbx
.l: cmp rbx, r13
    jge .d
    imul rdi, r14, 8
    call vmem_alloc
    mov rcx, [r12+rbx*8]
    mov [rcx], rax
    inc rbx
    jmp .l
.d: pop r14
    pop r13
    pop r12
    pop rbx
    ret

grow_arrays:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    xor rbx, rbx
.l: cmp rbx, r13
    jge .d
    mov rcx, [r12+rbx*8]
    mov rdi, [rcx]
    imul rsi, r14, 8
    imul rdx, r15, 8
    call vmem_realloc
    mov rcx, [r12+rbx*8]
    mov [rcx], rax
    inc rbx
    jmp .l
.d: pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

ssa_ir_init:
    mov qword[bb_cap], INIT_SSA_BB
    mov qword[inst_cap], INIT_SSA_INST
    mov qword[phi_cap], INIT_SSA_PHI
    mov qword[vreg_cap], INIT_SSA_VREG
    mov qword[slot_cap], INIT_SSA_SLOTS
    mov qword[pred_pool_cap], INIT_SSA_POOL
    mov qword[df_pool_cap], INIT_SSA_POOL
    mov qword[phi_src_pool_cap], INIT_SSA_POOL
    ; BB arrays (14 qword arrays, rpo_index handled separately)
    lea rdi, [bb_arr_ptrs]
    mov rsi, BB_ARR_COUNT
    mov rdx, INIT_SSA_BB
    call alloc_arrays
    ; BB temps: dfs_stack, rpo_buf, rpo_index (separate), dfs_visited
    mov rdi, INIT_SSA_BB * 8
    call vmem_alloc
    mov [dfs_stack], rax
    mov rdi, INIT_SSA_BB * 8
    call vmem_alloc
    mov [rpo_buf], rax
    mov rdi, INIT_SSA_BB * 8
    call vmem_alloc
    mov [rpo_index], rax
    mov rdi, INIT_SSA_BB
    call vmem_alloc
    mov [dfs_visited], rax
    ; instruction buffer
    mov rdi, INIT_SSA_INST
    imul rdi, rdi, SSA_INST_SIZE
    call vmem_alloc
    mov [ssa_inst_buf], rax
    ; phi arrays
    lea rdi, [phi_arr_ptrs]
    mov rsi, PHI_ARR_COUNT
    mov rdx, INIT_SSA_PHI
    call alloc_arrays
    ; vreg arrays
    lea rdi, [vreg_arr_ptrs]
    mov rsi, VREG_ARR_COUNT
    mov rdx, INIT_SSA_VREG
    call alloc_arrays
    ; slot base arrays
    lea rdi, [slot_arr_ptrs]
    mov rsi, SLOT_ARR_COUNT
    mov rdx, INIT_SSA_SLOTS
    call alloc_arrays
    ; slot vreg stack (2D)
    mov rdi, INIT_SSA_SLOTS
    imul rdi, rdi, SSA_VREG_STACK_DEPTH * 8
    call vmem_alloc
    mov [slot_vreg_stk], rax
    ; pools
    mov rdi, INIT_SSA_POOL * 8
    call vmem_alloc
    mov [pred_pool], rax
    mov rdi, INIT_SSA_POOL * 8
    call vmem_alloc
    mov [df_pool], rax
    mov rdi, INIT_SSA_POOL * 8
    call vmem_alloc
    mov [phi_src_pool], rax
    jmp ssa_ir_reset

ssa_ir_reset:
    mov qword[ssa_bb_cnt], 0
    mov qword[ssa_inst_cnt], 0
    mov qword[ssa_phi_cnt], 0
    mov qword[ssa_vreg_cnt], 0
    mov qword[ssa_slot_cnt], 0
    mov qword[pred_pool_pos], 0
    mov qword[df_pool_pos], 0
    mov qword[phi_src_pool_pos], 0
    mov qword[rpo_count], 0
    mov byte[ssa_abort_flag], 0
    mov byte[dom_changed], 0
    ret

; *** FIX: ssa_bb_grow no longer double-grows rpo_index ***
ssa_bb_grow:
    push rbx
    mov rbx, [bb_cap]
    mov rcx, rbx
    shl rcx, 1
    mov [bb_cap], rcx
    lea rdi, [bb_arr_ptrs]
    mov rsi, BB_ARR_COUNT
    mov rdx, rbx
    call grow_arrays
    ; temps: dfs_stack, rpo_buf, rpo_index (all qword), dfs_visited (byte)
    mov rdi, [dfs_stack]
    imul rsi, rbx, 8
    mov rdx, [bb_cap]
    imul rdx, rdx, 8
    call vmem_realloc
    mov [dfs_stack], rax
    mov rdi, [rpo_buf]
    imul rsi, rbx, 8
    mov rdx, [bb_cap]
    imul rdx, rdx, 8
    call vmem_realloc
    mov [rpo_buf], rax
    mov rdi, [rpo_index]
    imul rsi, rbx, 8
    mov rdx, [bb_cap]
    imul rdx, rdx, 8
    call vmem_realloc
    mov [rpo_index], rax
    mov rdi, [dfs_visited]
    mov rsi, rbx
    mov rdx, [bb_cap]
    call vmem_realloc
    mov [dfs_visited], rax
    pop rbx
    ret

ssa_inst_grow:
    mov rdi, [ssa_inst_buf]
    mov rsi, [inst_cap]
    imul rsi, rsi, SSA_INST_SIZE
    mov rdx, [inst_cap]
    shl rdx, 1
    mov [inst_cap], rdx
    imul rdx, rdx, SSA_INST_SIZE
    call vmem_realloc
    mov [ssa_inst_buf], rax
    ret

ssa_phi_grow:
    push rbx
    mov rbx, [phi_cap]
    mov rcx, rbx
    shl rcx, 1
    mov [phi_cap], rcx
    lea rdi, [phi_arr_ptrs]
    mov rsi, PHI_ARR_COUNT
    mov rdx, rbx
    call grow_arrays
    pop rbx
    ret

ssa_vreg_grow:
    push rbx
    mov rbx, [vreg_cap]
    mov rcx, rbx
    shl rcx, 1
    mov [vreg_cap], rcx
    lea rdi, [vreg_arr_ptrs]
    mov rsi, VREG_ARR_COUNT
    mov rdx, rbx
    call grow_arrays
    pop rbx
    ret

ssa_slot_grow:
    push rbx
    mov rbx, [slot_cap]
    mov rcx, rbx
    shl rcx, 1
    mov [slot_cap], rcx
    lea rdi, [slot_arr_ptrs]
    mov rsi, SLOT_ARR_COUNT
    mov rdx, rbx
    call grow_arrays
    mov rdi, [slot_vreg_stk]
    imul rsi, rbx, SSA_VREG_STACK_DEPTH * 8
    mov rdx, [slot_cap]
    imul rdx, rdx, SSA_VREG_STACK_DEPTH * 8
    call vmem_realloc
    mov [slot_vreg_stk], rax
    pop rbx
    ret

ssa_pred_pool_grow:
    mov rdi, [pred_pool]
    mov rsi, [pred_pool_cap]
    imul rsi, rsi, 8
    mov rdx, [pred_pool_cap]
    shl rdx, 1
    mov [pred_pool_cap], rdx
    imul rdx, rdx, 8
    call vmem_realloc
    mov [pred_pool], rax
    ret

ssa_df_pool_grow:
    mov rdi, [df_pool]
    mov rsi, [df_pool_cap]
    imul rsi, rsi, 8
    mov rdx, [df_pool_cap]
    shl rdx, 1
    mov [df_pool_cap], rdx
    imul rdx, rdx, 8
    call vmem_realloc
    mov [df_pool], rax
    ret

ssa_phisrc_pool_grow:
    mov rdi, [phi_src_pool]
    mov rsi, [phi_src_pool_cap]
    imul rsi, rsi, 8
    mov rdx, [phi_src_pool_cap]
    shl rdx, 1
    mov [phi_src_pool_cap], rdx
    imul rdx, rdx, 8
    call vmem_realloc
    mov [phi_src_pool], rax
    ret

ssa_bb_create:
    push rbx
    push r11
    mov rax, [ssa_bb_cnt]
    cmp rax, [bb_cap]
    jl .ok
    call ssa_bb_grow
.ok:
    mov rbx, [ssa_bb_cnt]
    mov r11, [bb_first_inst]
    mov qword[r11+rbx*8], -1
    mov r11, [bb_inst_count]
    mov qword[r11+rbx*8], 0
    mov r11, [bb_mir_start]
    mov qword[r11+rbx*8], 0
    mov r11, [bb_mir_end]
    mov qword[r11+rbx*8], 0
    mov r11, [bb_succ0]
    mov qword[r11+rbx*8], -1
    mov r11, [bb_succ1]
    mov qword[r11+rbx*8], -1
    mov r11, [bb_pred_start]
    mov qword[r11+rbx*8], 0
    mov r11, [bb_pred_count]
    mov qword[r11+rbx*8], 0
    mov r11, [bb_idom]
    mov qword[r11+rbx*8], -1
    mov r11, [bb_df_start]
    mov qword[r11+rbx*8], 0
    mov r11, [bb_df_count]
    mov qword[r11+rbx*8], 0
    mov r11, [bb_dead]
    mov qword[r11+rbx*8], 0
    mov r11, [bb_label_id]
    mov qword[r11+rbx*8], -1
    mov r11, [bb_stack_depth_in]
    mov qword[r11+rbx*8], -1
    inc qword[ssa_bb_cnt]
    mov rax, rbx
    pop r11
    pop rbx
    ret

ssa_inst_emit:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbp, r8
    push r9
    mov rax, [ssa_inst_cnt]
    cmp rax, [inst_cap]
    jl .ok
    call ssa_inst_grow
.ok:
    pop r9
    mov rbx, [ssa_inst_cnt]
    imul rax, rbx, SSA_INST_SIZE
    push r11
    mov r11, [ssa_inst_buf]
    mov [r11+rax+SSA_F_OP], r13
    mov [r11+rax+SSA_F_DEST], r14
    mov [r11+rax+SSA_F_SRC1], r15
    mov [r11+rax+SSA_F_SRC2], rbp
    mov [r11+rax+SSA_F_IMM], r9
    mov qword[r11+rax+SSA_F_FLAG], 0
    pop r11
    push r11
    mov r11, [bb_inst_count]
    cmp qword[r11+r12*8], 0
    jne .not_first
    mov r11, [bb_first_inst]
    mov [r11+r12*8], rbx
    mov r11, [bb_inst_count]
.not_first:
    inc qword[r11+r12*8]
    pop r11
    inc qword[ssa_inst_cnt]
    mov rax, rbx
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

ssa_inst_set_flags:
    push r11
    imul rax, rdi, SSA_INST_SIZE
    mov r11, [ssa_inst_buf]
    mov [r11+rax+SSA_F_FLAG], rsi
    pop r11
    ret

ssa_phi_create:
    push rbx
    push r11
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    mov rax, [ssa_phi_cnt]
    cmp rax, [phi_cap]
    jl .ok
    push rdi
    call ssa_phi_grow
    pop rdi
.ok:
    mov rbx, [ssa_phi_cnt]
    mov r11, [phi_bb]
    mov [r11+rbx*8], rdi
    mov r11, [phi_dest]
    mov [r11+rbx*8], r12
    mov r11, [phi_var]
    mov [r11+rbx*8], r13
    mov rax, [phi_src_pool_pos]
    mov r11, [phi_src_start]
    mov [r11+rbx*8], rax
    mov r11, [phi_src_count]
    mov qword[r11+rbx*8], 0
    inc qword[ssa_phi_cnt]
    mov rax, rbx
    pop r13
    pop r12
    pop r11
    pop rbx
    ret

ssa_phi_add_src:
    push rbx
    push r11
    mov rax, [phi_src_pool_pos]
    add rax, 2
    cmp rax, [phi_src_pool_cap]
    jl .ok
    push rdi
    push rsi
    push rdx
    call ssa_phisrc_pool_grow
    pop rdx
    pop rsi
    pop rdi
.ok:
    mov rbx, [phi_src_pool_pos]
    mov r11, [phi_src_pool]
    mov [r11+rbx*8], rsi
    mov [r11+rbx*8+8], rdx
    add qword[phi_src_pool_pos], 2
    mov r11, [phi_src_count]
    inc qword[r11+rdi*8]
    pop r11
    pop rbx
    ret

ssa_vreg_new:
    push rbx
    push r11
    mov rax, [ssa_vreg_cnt]
    cmp rax, [vreg_cap]
    jl .ok
    call ssa_vreg_grow
.ok:
    mov rbx, [ssa_vreg_cnt]
    mov r11, [vreg_type]
    mov qword[r11+rbx*8], TYPE_I64
    mov r11, [vreg_orig_slot]
    mov qword[r11+rbx*8], -1
    mov r11, [vreg_def_bb]
    mov qword[r11+rbx*8], -1
    mov r11, [vreg_def_inst]
    mov qword[r11+rbx*8], -1
    inc qword[ssa_vreg_cnt]
    mov rax, rbx
    pop r11
    pop rbx
    ret

ssa_vreg_set_type:
    push r11
    mov r11, [vreg_type]
    mov [r11+rdi*8], rsi
    pop r11
    ret

ssa_slot_register:
    push rbx
    push r11
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    xor rbx, rbx
.sl:cmp rbx, [ssa_slot_cnt]
    jge .new
    mov r11, [slot_offset]
    cmp r12, [r11+rbx*8]
    je .found
    inc rbx
    jmp .sl
.found:
    mov rax, rbx
    jmp .ret
.new:
    mov rax, [ssa_slot_cnt]
    cmp rax, [slot_cap]
    jl .nok
    push r12
    push r13
    call ssa_slot_grow
    pop r13
    pop r12
.nok:
    mov rbx, [ssa_slot_cnt]
    mov r11, [slot_offset]
    mov [r11+rbx*8], r12
    mov r11, [slot_type]
    mov [r11+rbx*8], r13
    mov r11, [slot_escaped]
    mov qword[r11+rbx*8], 0
    mov r11, [slot_current_vreg]
    mov qword[r11+rbx*8], -1
    mov r11, [slot_vreg_sp]
    mov qword[r11+rbx*8], 0
    inc qword[ssa_slot_cnt]
    mov rax, rbx
.ret:
    pop r13
    pop r12
    pop r11
    pop rbx
    ret

ssa_slot_find:
    push rbx
    push r11
    xor rbx, rbx
.l: cmp rbx, [ssa_slot_cnt]
    jge .nf
    mov r11, [slot_offset]
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