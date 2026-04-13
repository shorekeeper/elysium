; All parallel arrays (name, offset, type, etc.) are heap-allocated
; and double in size when sym_count reaches sym_cap.
; Hash table also grows and rehashes on overflow.

default rel
%include "defs.inc"
%pragma warning disable number-overflow ; NASM IDI HANUI
extern ely_memcmp, vmem_alloc, vmem_free, vmem_realloc
global sym_init, sym_push, sym_lookup, sym_get_index
global sym_leave_scope, sym_alloc_bytes, sym_depth
global sym_bstate, sym_bcnt, sym_alias, sym_off, sym_count
global sym_type, sym_set_last_type, sym_arrlen, sym_push_arr
global sym_rec_type, sym_set_rec_type
global anc_push, anc_lookup, anc_pop

section .data
align 8
; pointers to all parallel arrays (used by sym_grow to resize them all)
sym_arr_ptrs:
    dq sym_nptr, sym_nlen, sym_off, sym_scope, sym_bstate
    dq sym_bcnt, sym_alias, sym_type, sym_arrlen, sym_rec_type
SYM_ARR_COUNT equ 10

section .bss
; each of these holds a pointer to a heap-allocated qword array
sym_nptr:    resq 1           ; -> name pointer per symbol
sym_nlen:    resq 1           ; -> name length per symbol
sym_off:     resq 1           ; -> stack frame offset per symbol
sym_scope:   resq 1           ; -> scope depth per symbol
sym_bstate:  resq 1           ; -> borrow state (0=none, 1=shared, 2=exclusive)
sym_bcnt:    resq 1           ; -> active shared borrow count
sym_alias:   resq 1           ; -> aliased source index (for borrows), -1 if none
sym_type:    resq 1           ; -> TYPE_* per symbol
sym_arrlen:  resq 1           ; -> array length (0 for scalars)
sym_rec_type:resq 1           ; -> record type index (-1 if not a record)
sym_count:   resq 1           ; current number of symbols
sym_depth:   resq 1           ; current scope nesting depth
sym_next:    resq 1           ; next stack frame byte offset to allocate
sym_cap:     resq 1           ; current array capacity
hash_table:  resq 1           ; -> hash table (qword array, -1 = empty slot)
hash_cap:    resq 1           ; hash table slot count
hash_mask:   resq 1           ; hash_cap - 1

; anchor stack (fixed size, deeply nested anchors are rare)
anc_nptr:    resq MAX_ANC
anc_nlen:    resq MAX_ANC
anc_off:     resq MAX_ANC
anc_cnt:     resq 1

section .text

; fnv1a: rsi=name, rcx=len -> rax=hash
fnv1a:
    push rsi
    push rcx
    push rdx
    mov rax, 14695981039346656037
.fl:test rcx, rcx
    jz .fd
    movzx rdx, byte[rsi]
    xor rax, rdx
    imul rax, rax, 0x100000001b3
    inc rsi
    dec rcx
    jmp .fl
.fd:pop rdx
    pop rcx
    pop rsi
    ret

; hash_clear: fill hash table with -1 (empty sentinel)
hash_clear:
    push rcx
    push rdi
    push rax
    mov rdi, [hash_table]
    mov rcx, [hash_cap]
    mov rax, 0xFFFFFFFFFFFFFFFF
    rep stosq
    pop rax
    pop rdi
    pop rcx
    ret

; hash_insert: rbx=sym_index -> probe and insert into hash table
hash_insert:
    push rsi
    push rcx
    push rax
    push rdx
    push r11
    mov r11, [sym_nptr]
    mov rsi, [r11+rbx*8]
    mov r11, [sym_nlen]
    mov rcx, [r11+rbx*8]
    call fnv1a
    and rax, [hash_mask]
    mov r11, [hash_table]
.probe:
    cmp qword[r11+rax*8], 0xFFFFFFFFFFFFFFFF
    je .empty
    inc rax
    and rax, [hash_mask]
    jmp .probe
.empty:
    mov [r11+rax*8], rbx
    pop r11
    pop rdx
    pop rax
    pop rcx
    pop rsi
    ret

; hash_rebuild: clear and re-insert all current symbols
hash_rebuild:
    push rbx
    call hash_clear
    xor rbx, rbx
.rl:cmp rbx, [sym_count]
    jge .rd
    call hash_insert
    inc rbx
    jmp .rl
.rd:pop rbx
    ret

; sym_grow: double all parallel arrays + rehash
sym_grow:
    push rbx
    push r12
    push r13
    mov r13, [sym_cap]
    mov rax, r13
    shl rax, 1
    mov [sym_cap], rax
    ; resize each parallel array
    xor r12, r12
.l: cmp r12, SYM_ARR_COUNT
    jge .hash
    mov rbx, [sym_arr_ptrs+r12*8]
    mov rdi, [rbx]                 ; old pointer
    imul rsi, r13, 8               ; old bytes
    mov rdx, [sym_cap]
    imul rdx, rdx, 8               ; new bytes
    call vmem_realloc
    mov rbx, [sym_arr_ptrs+r12*8]
    mov [rbx], rax
    inc r12
    jmp .l
.hash:
    ; grow hash table: free old, alloc double, rehash
    mov rdi, [hash_table]
    call vmem_free
    mov rdi, [hash_cap]
    shl rdi, 1
    mov [hash_cap], rdi
    dec rdi
    mov [hash_mask], rdi
    inc rdi
    shl rdi, 3
    call vmem_alloc
    mov [hash_table], rax
    call hash_rebuild
    pop r13
    pop r12
    pop rbx
    ret

; sym_init: allocate all arrays at initial capacity, clear state
sym_init:
    push rbx
    push r12
    mov qword[sym_count], 0
    mov qword[sym_depth], 0
    mov qword[sym_next], 0
    mov qword[anc_cnt], 0
    mov qword[sym_cap], INIT_SYMS
    ; allocate each parallel array
    xor r12, r12
.l: cmp r12, SYM_ARR_COUNT
    jge .ht
    mov rdi, INIT_SYMS * 8
    call vmem_alloc
    mov rbx, [sym_arr_ptrs+r12*8]
    mov [rbx], rax
    inc r12
    jmp .l
.ht:
    ; allocate hash table
    mov qword[hash_cap], INIT_HASH
    mov qword[hash_mask], INIT_HASH - 1
    mov rdi, INIT_HASH * 8
    call vmem_alloc
    mov [hash_table], rax
    call hash_clear
    pop r12
    pop rbx
    ret

; sym_push: rsi=name, rcx=len -> rax=frame offset
; Grows arrays if at capacity. Allocates 8 bytes of frame space.
sym_push:
    push rbx
    push r11
    mov rax, [sym_count]
    cmp rax, [sym_cap]
    jl .ok
    call sym_grow
.ok:
    add qword[sym_next], 8
    mov rax, [sym_next]
    mov rbx, [sym_count]
    ; store name
    mov r11, [sym_nptr]
    mov [r11+rbx*8], rsi
    mov r11, [sym_nlen]
    mov [r11+rbx*8], rcx
    ; store offset
    mov r11, [sym_off]
    mov [r11+rbx*8], rax
    ; store scope depth
    push rdx
    mov rdx, [sym_depth]
    mov r11, [sym_scope]
    mov [r11+rbx*8], rdx
    pop rdx
    ; zero borrow state
    mov r11, [sym_bstate]
    mov qword[r11+rbx*8], 0
    mov r11, [sym_bcnt]
    mov qword[r11+rbx*8], 0
    mov r11, [sym_alias]
    mov qword[r11+rbx*8], 0xFFFFFFFFFFFFFFFF
    ; default type = infer
    mov r11, [sym_type]
    mov qword[r11+rbx*8], TYPE_INFER
    ; not an array
    mov r11, [sym_arrlen]
    mov qword[r11+rbx*8], 0
    ; not a record
    mov r11, [sym_rec_type]
    mov qword[r11+rbx*8], 0xFFFFFFFFFFFFFFFF
    call hash_insert
    inc qword[sym_count]
    pop r11
    pop rbx
    ret

; sym_push_arr: rsi=name, rcx=namelen, rdi=arrlen, rdx=base_offset
; Register an array variable (pre-allocated frame space).
sym_push_arr:
    push rbx
    push r10
    push r11
    mov rax, [sym_count]
    cmp rax, [sym_cap]
    jl .ok
    push rdi
    push rsi
    push rcx
    push rdx
    call sym_grow
    pop rdx
    pop rcx
    pop rsi
    pop rdi
.ok:
    mov rbx, [sym_count]
    mov r11, [sym_nptr]
    mov [r11+rbx*8], rsi
    mov r11, [sym_nlen]
    mov [r11+rbx*8], rcx
    mov r11, [sym_off]
    mov [r11+rbx*8], rdx
    mov r10, [sym_depth]
    mov r11, [sym_scope]
    mov [r11+rbx*8], r10
    mov r11, [sym_bstate]
    mov qword[r11+rbx*8], 0
    mov r11, [sym_bcnt]
    mov qword[r11+rbx*8], 0
    mov r11, [sym_alias]
    mov qword[r11+rbx*8], 0xFFFFFFFFFFFFFFFF
    mov r11, [sym_type]
    mov qword[r11+rbx*8], TYPE_I64
    mov r11, [sym_arrlen]
    mov [r11+rbx*8], rdi
    mov r11, [sym_rec_type]
    mov qword[r11+rbx*8], 0xFFFFFFFFFFFFFFFF
    call hash_insert
    inc qword[sym_count]
    pop r11
    pop r10
    pop rbx
    ret

; sym_set_last_type: rdi=TYPE_* -> set type of most recently pushed symbol
sym_set_last_type:
    push rax
    push r11
    mov rax, [sym_count]
    dec rax
    mov r11, [sym_type]
    mov [r11+rax*8], rdi
    pop r11
    pop rax
    ret

; sym_set_rec_type: rdi=type_reg_index -> tag last symbol as record instance
sym_set_rec_type:
    push rax
    push r11
    mov rax, [sym_count]
    dec rax
    mov r11, [sym_rec_type]
    mov [r11+rax*8], rdi
    pop r11
    pop rax
    ret

; sym_alloc_bytes: rdi=bytes -> rax=frame offset (bump allocator for stack frame)
sym_alloc_bytes:
    add [sym_next], rdi
    mov rax, [sym_next]
    ret

; sym_lookup: rsi=name, rcx=len -> rax=frame offset, or 0 if not found
; Finds newest (highest index) match via hash table probing.
sym_lookup:
    push rbx
    push rdi
    push rcx
    push rsi
    push r8
    push r9
    push r10
    push r11
    mov r8, rsi
    mov r9, rcx
    call fnv1a
    and rax, [hash_mask]
    mov r10, 0xFFFFFFFFFFFFFFFF      ; best index = none
    mov r11, [hash_table]
.lp:
    mov rbx, [r11+rax*8]
    cmp rbx, 0xFFFFFFFFFFFFFFFF
    je .dp
    ; compare name length
    push r11
    mov r11, [sym_nlen]
    cmp r9, [r11+rbx*8]
    pop r11
    jne .next
    ; compare name bytes
    mov rsi, r8
    push r11
    mov r11, [sym_nptr]
    mov rdi, [r11+rbx*8]
    pop r11
    mov rcx, r9
    call ely_memcmp
    test rax, rax
    jnz .nh
    ; match found: keep newest (highest index)
    cmp rbx, r10
    jle .next
    mov r10, rbx
.next:
    inc rax
    and rax, [hash_mask]
    jmp .lp
.nh:
    inc rax
    and rax, [hash_mask]
    jmp .lp
.dp:
    cmp r10, 0xFFFFFFFFFFFFFFFF
    je .nf
    push r11
    mov r11, [sym_off]
    mov rax, [r11+r10*8]
    pop r11
    jmp .d
.nf:xor rax, rax
.d: pop r11
    pop r10
    pop r9
    pop r8
    pop rsi
    pop rcx
    pop rdi
    pop rbx
    ret

; sym_get_index: rsi=name, rcx=len -> rax=symbol index, or -1
sym_get_index:
    push rbx
    push rdi
    push rcx
    push rsi
    push r8
    push r9
    push r10
    push r11
    mov r8, rsi
    mov r9, rcx
    call fnv1a
    and rax, [hash_mask]
    mov r10, 0xFFFFFFFFFFFFFFFF
    mov r11, [hash_table]
.lp:
    mov rbx, [r11+rax*8]
    cmp rbx, 0xFFFFFFFFFFFFFFFF
    je .done
    push r11
    mov r11, [sym_nlen]
    cmp r9, [r11+rbx*8]
    pop r11
    jne .nx
    mov rsi, r8
    push r11
    mov r11, [sym_nptr]
    mov rdi, [r11+rbx*8]
    pop r11
    mov rcx, r9
    call ely_memcmp
    test rax, rax
    jnz .nx
    cmp rbx, r10
    jle .nx
    mov r10, rbx
.nx:
    inc rax
    and rax, [hash_mask]
    jmp .lp
.done:
    mov rax, r10
    pop r11
    pop r10
    pop r9
    pop r8
    pop rsi
    pop rcx
    pop rdi
    pop rbx
    ret

; sym_leave_scope: pop all symbols at current depth, release borrows, rehash
sym_leave_scope:
    push rax
    push rbx
    push r10
    push r11
    mov rax, [sym_depth]
.l:
    mov rbx, [sym_count]
    test rbx, rbx
    jz .rb
    dec rbx
    mov r11, [sym_scope]
    cmp [r11+rbx*8], rax
    jne .rb
    ; if this symbol is a borrow alias, release it
    mov r11, [sym_alias]
    mov r10, [r11+rbx*8]
    cmp r10, 0xFFFFFFFFFFFFFFFF
    je .rm
    mov r11, [sym_bstate]
    cmp qword[r11+rbx*8], 2
    je .rmu
    mov r11, [sym_bcnt]
    cmp qword[r11+r10*8], 0
    je .rm
    dec qword[r11+r10*8]
    jmp .rm
.rmu:
    mov r11, [sym_bstate]
    mov qword[r11+r10*8], 0
.rm:
    dec qword[sym_count]
    jmp .l
.rb:
    call hash_rebuild
    pop r11
    pop r10
    pop rbx
    pop rax
    ret

; ==================== ANCHOR TABLE ====================

; anc_push: rsi=name, rcx=len, rdx=ckpt_offset -> register anchor
anc_push:
    push rax
    mov rax, [anc_cnt]
    mov [anc_nptr+rax*8], rsi
    mov [anc_nlen+rax*8], rcx
    mov [anc_off+rax*8], rdx
    inc qword[anc_cnt]
    pop rax
    ret

; anc_lookup: rsi=name, rcx=len -> rax=ckpt_offset, or 0
anc_lookup:
    push rbx
    push rdi
    push rsi
    push rcx
    push r8
    push r9
    mov r8, rsi
    mov r9, rcx
    mov rbx, [anc_cnt]
.l: test rbx, rbx
    jz .nf
    dec rbx
    cmp r9, [anc_nlen+rbx*8]
    jne .l
    mov rsi, r8
    mov rdi, [anc_nptr+rbx*8]
    mov rcx, r9
    call ely_memcmp
    test rax, rax
    jnz .l
    mov rax, [anc_off+rbx*8]
    jmp .d
.nf:xor rax, rax
.d: pop r9
    pop r8
    pop rcx
    pop rsi
    pop rdi
    pop rbx
    ret

; anc_pop: remove topmost anchor
anc_pop:
    dec qword[anc_cnt]
    ret