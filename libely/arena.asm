; Old blocks are never freed so all pointers remain valid forever.
; When current block is full, allocates a new one (doubling size).
default rel
%include "defs.inc"
extern vmem_alloc
global arena_init, arena_alloc, new_node, ely_memcmp
global arena_mark, arena_reset

section .bss
ar_base: resq 1              ; current block base
ar_pos:  resq 1              ; next free byte in current block
ar_end:  resq 1              ; end of current block
ar_blksz: resq 1             ; current block size (doubles on grow)

section .text

; arena_init: allocate first block
arena_init:
    mov rdi, INIT_ARENA
    call vmem_alloc
    mov [ar_base], rax
    mov [ar_pos], rax
    lea rcx, [rax + INIT_ARENA]
    mov [ar_end], rcx
    mov qword[ar_blksz], INIT_ARENA
    ret

; arena_alloc: rdi=size -> rax=zeroed pointer
; If request doesn't fit, allocate new block (old block stays alive)
arena_alloc:
    push rbx
    push rcx
    mov rbx, rdi
.retry:
    mov rax, [ar_pos]
    lea rcx, [rax + rbx]
    cmp rcx, [ar_end]
    ja .grow
    mov [ar_pos], rcx
    ; zero the allocated region
    push rax
    push rdi
    mov rdi, rax
    mov rcx, rbx
    xor al, al
    rep stosb
    pop rdi
    pop rax
    pop rcx
    pop rbx
    ret
.grow:
    ; double block size, ensure it fits the request
    mov rcx, [ar_blksz]
    shl rcx, 1
    lea rax, [rbx + 64]
    cmp rcx, rax
    jge .ok
    mov rcx, rax
.ok:
    mov [ar_blksz], rcx
    mov rdi, rcx
    call vmem_alloc
    mov [ar_base], rax
    mov [ar_pos], rax
    mov rcx, [ar_blksz]
    lea rcx, [rax + rcx]
    mov [ar_end], rcx
    jmp .retry

; new_node: allocate NODE_SIZE bytes, zeroed
new_node:
    push rdi
    mov rdi, NODE_SIZE
    call arena_alloc
    pop rdi
    ret

; arena_mark / arena_reset: save/restore position within current block
arena_mark:
    mov rax, [ar_pos]
    ret

arena_reset:
    mov [ar_pos], rdi
    ret

; ely_memcmp: rsi=a, rdi=b, rcx=len -> rax=0 if equal, 1 if not
ely_memcmp:
    push rsi
    push rdi
    push rcx
.l: test rcx, rcx
    jz .e
    mov al, [rsi]
    cmp al, [rdi]
    jne .n
    inc rsi
    inc rdi
    dec rcx
    jmp .l
.e: xor rax, rax
    jmp .r
.n: mov rax, 1
.r: pop rcx
    pop rdi
    pop rsi
    ret