; ssa_cfg.asm - control flow graph analysis
; predecessor lists (CSR format), reverse postorder, unreachable pruning
default rel
%include "defs.inc"
extern ssa_bb_cnt
extern bb_succ0, bb_succ1, bb_pred_start, bb_pred_count
extern bb_dead, bb_inst_count
extern pred_pool, pred_pool_pos, pred_pool_cap
extern dfs_stack, dfs_visited, rpo_buf, rpo_index, rpo_count
extern ssa_pred_pool_grow

global ssa_cfg_build_preds, ssa_cfg_compute_rpo, ssa_cfg_prune_unreachable

section .text

; =========================================================================
; ssa_cfg_prune_unreachable: simple DFS from BB 0, mark unvisited as dead
; Must be called before build_preds so dead BBs have -1 successors.
; =========================================================================
ssa_cfg_prune_unreachable:
    push rbx
    push r12
    ; clear visited
    xor rbx, rbx
    mov r11, [dfs_visited]
.cv:cmp rbx, [ssa_bb_cnt]
    jge .dfs
    mov byte[r11+rbx], 0
    inc rbx
    jmp .cv

.dfs:
    ; guard: if no BBs, nothing to do
    cmp qword[ssa_bb_cnt], 0
    je .done
    ; push BB 0
    mov r11, [dfs_stack]
    mov qword[r11], 0
    mov r12, 1                     ; stack_pos = 1
    mov r11, [dfs_visited]
    mov byte[r11], 1               ; visited[0] = 1

.dl:test r12, r12
    jz .mark
    ; pop
    dec r12
    mov r11, [dfs_stack]
    mov rax, [r11+r12*8]
    ; try succ0
    mov r11, [bb_succ0]
    mov rcx, [r11+rax*8]
    cmp rcx, -1
    je .d1
    mov r11, [dfs_visited]
    cmp byte[r11+rcx], 0
    jne .d1
    mov byte[r11+rcx], 1
    mov r11, [dfs_stack]
    mov [r11+r12*8], rcx
    inc r12
.d1:
    ; try succ1
    mov r11, [bb_succ1]
    mov rcx, [r11+rax*8]
    cmp rcx, -1
    je .dl
    mov r11, [dfs_visited]
    cmp byte[r11+rcx], 0
    jne .dl
    mov byte[r11+rcx], 1
    mov r11, [dfs_stack]
    mov [r11+r12*8], rcx
    inc r12
    jmp .dl

.mark:
    ; mark unreachable BBs as dead
    xor rbx, rbx
.ml:cmp rbx, [ssa_bb_cnt]
    jge .done
    mov r11, [dfs_visited]
    cmp byte[r11+rbx], 1
    je .mnx
    ; dead: zero successors, inst count, set dead flag
    mov r11, [bb_succ0]
    mov qword[r11+rbx*8], -1
    mov r11, [bb_succ1]
    mov qword[r11+rbx*8], -1
    mov r11, [bb_inst_count]
    mov qword[r11+rbx*8], 0
    mov r11, [bb_dead]
    mov qword[r11+rbx*8], 1
.mnx:
    inc rbx
    jmp .ml
.done:
    pop r12
    pop rbx
    ret

; =========================================================================
; ssa_cfg_build_preds: build predecessor lists in CSR format
; Three passes: count, prefix-sum, fill. Uses pred_count as fill index.
; Dead BBs have -1 successors so they contribute no edges.
; =========================================================================
ssa_cfg_build_preds:
    push rbx
    push r12
    push r14

    ; Phase 1: zero pred_counts
    xor rbx, rbx
.z: cmp rbx, [ssa_bb_cnt]
    jge .count
    mov r11, [bb_pred_count]
    mov qword[r11+rbx*8], 0
    inc rbx
    jmp .z

    ; Phase 2: count predecessors
.count:
    xor rbx, rbx
.cl:cmp rbx, [ssa_bb_cnt]
    jge .prefix
    mov r11, [bb_succ0]
    mov rax, [r11+rbx*8]
    cmp rax, -1
    je .cs1
    mov r11, [bb_pred_count]
    inc qword[r11+rax*8]
.cs1:
    mov r11, [bb_succ1]
    mov rax, [r11+rbx*8]
    cmp rax, -1
    je .cnx
    mov r11, [bb_pred_count]
    inc qword[r11+rax*8]
.cnx:
    inc rbx
    jmp .cl

    ; Phase 3: prefix sum -> pred_start, total in r12
.prefix:
    xor r12, r12
    xor rbx, rbx
.pl:cmp rbx, [ssa_bb_cnt]
    jge .ensure
    mov r11, [bb_pred_count]
    mov rax, [r11+rbx*8]
    mov r11, [bb_pred_start]
    mov [r11+rbx*8], r12
    add r12, rax
    inc rbx
    jmp .pl

    ; ensure pool capacity
.ensure:
    mov [pred_pool_pos], r12
.eg:mov rax, [pred_pool_pos]
    cmp rax, [pred_pool_cap]
    jl .fill_prep
    push r12
    call ssa_pred_pool_grow
    pop r12
    jmp .eg

    ; Phase 4: zero counts (reuse as fill index), then fill
.fill_prep:
    xor rbx, rbx
.fz:cmp rbx, [ssa_bb_cnt]
    jge .fill
    mov r11, [bb_pred_count]
    mov qword[r11+rbx*8], 0
    inc rbx
    jmp .fz

.fill:
    xor rbx, rbx
.fl:cmp rbx, [ssa_bb_cnt]
    jge .fd
    ; process succ0
    mov r11, [bb_succ0]
    mov r14, [r11+rbx*8]
    cmp r14, -1
    je .fs1
    mov r11, [bb_pred_start]
    mov rcx, [r11+r14*8]
    mov r11, [bb_pred_count]
    mov rdx, [r11+r14*8]
    add rcx, rdx
    mov r11, [pred_pool]
    mov [r11+rcx*8], rbx
    mov r11, [bb_pred_count]
    inc qword[r11+r14*8]
.fs1:
    ; process succ1
    mov r11, [bb_succ1]
    mov r14, [r11+rbx*8]
    cmp r14, -1
    je .fnx
    mov r11, [bb_pred_start]
    mov rcx, [r11+r14*8]
    mov r11, [bb_pred_count]
    mov rdx, [r11+r14*8]
    add rcx, rdx
    mov r11, [pred_pool]
    mov [r11+rcx*8], rbx
    mov r11, [bb_pred_count]
    inc qword[r11+r14*8]
.fnx:
    inc rbx
    jmp .fl

.fd:
    pop r14
    pop r12
    pop rbx
    ret

; =========================================================================
; ssa_cfg_compute_rpo: reverse postorder via explicit DFS stack
; Entry BB is always 0. Result in rpo_buf[], rpo_index[], rpo_count.
; =========================================================================
ssa_cfg_compute_rpo:
    push rbx
    push r12
    push r13
    push r14

    ; clear visited
    xor rbx, rbx
.cv:cmp rbx, [ssa_bb_cnt]
    jge .init
    mov r11, [dfs_visited]
    mov byte[r11+rbx], 0
    inc rbx
    jmp .cv

.init:
    cmp qword[ssa_bb_cnt], 0
    je .ix_done
    ; push BB 0
    mov r11, [dfs_stack]
    mov qword[r11], 0
    mov r12, 1                     ; stack_pos
    mov r11, [dfs_visited]
    mov byte[r11], 1
    xor r13, r13                   ; po_count (postorder index)

.loop:
    test r12, r12
    jz .reverse
    ; peek top of stack
    mov r11, [dfs_stack]
    mov r14, [r11+r12*8-8]

    ; try succ0
    mov r11, [bb_succ0]
    mov rax, [r11+r14*8]
    cmp rax, -1
    je .try1
    mov r11, [dfs_visited]
    cmp byte[r11+rax], 0
    jne .try1
    ; push succ0
    mov byte[r11+rax], 1
    mov r11, [dfs_stack]
    mov [r11+r12*8], rax
    inc r12
    jmp .loop

.try1:
    ; try succ1
    mov r11, [bb_succ1]
    mov rax, [r11+r14*8]
    cmp rax, -1
    je .pop_
    mov r11, [dfs_visited]
    cmp byte[r11+rax], 0
    jne .pop_
    ; push succ1
    mov byte[r11+rax], 1
    mov r11, [dfs_stack]
    mov [r11+r12*8], rax
    inc r12
    jmp .loop

.pop_:
    ; no unvisited successor -> record in postorder
    dec r12
    mov r11, [rpo_buf]
    mov [r11+r13*8], r14
    inc r13
    jmp .loop

.reverse:
    mov [rpo_count], r13
    ; reverse rpo_buf in-place for RPO
    xor rbx, rbx
    lea r14, [r13-1]
.rev:
    cmp rbx, r14
    jge .index
    mov r11, [rpo_buf]
    mov rax, [r11+rbx*8]
    mov rcx, [r11+r14*8]
    mov [r11+rbx*8], rcx
    mov [r11+r14*8], rax
    inc rbx
    dec r14
    jmp .rev

.index:
    ; init rpo_index to -1 for all BBs
    xor rbx, rbx
.ix_init:
    cmp rbx, [ssa_bb_cnt]
    jge .ix_fill
    mov r11, [rpo_index]
    mov qword[r11+rbx*8], -1
    inc rbx
    jmp .ix_init

.ix_fill:
    ; rpo_index[bb] = position in RPO
    xor rbx, rbx
.ix:cmp rbx, [rpo_count]
    jge .ix_done
    mov r11, [rpo_buf]
    mov rax, [r11+rbx*8]
    mov r11, [rpo_index]
    mov [r11+rax*8], rbx
    inc rbx
    jmp .ix

.ix_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret