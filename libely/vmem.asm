; vmem.asm -- OS virtual memory primitives (Windows)
default rel
%include "defs.inc"
extern VirtualAlloc, VirtualFree
global vmem_alloc, vmem_free, vmem_realloc

section .text

; vmem_alloc: rdi=size -> rax=zeroed ptr or 0
vmem_alloc:
    push rbx
    sub rsp, 32
    xor ecx, ecx
    mov rdx, rdi
    mov r8d, 0x3000
    mov r9d, 0x04
    call VirtualAlloc
    add rsp, 32
    pop rbx
    ret

; vmem_free: rdi=ptr
vmem_free:
    push rbx
    sub rsp, 32
    mov rcx, rdi
    xor edx, edx
    mov r8d, 0x8000
    call VirtualFree
    add rsp, 32
    pop rbx
    ret

; vmem_realloc: rdi=old_ptr, rsi=old_bytes, rdx=new_bytes -> rax=new_ptr
vmem_realloc:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rdi, r14
    call vmem_alloc
    test rax, rax
    jz .fail
    mov rbx, rax
    mov rdi, rbx
    mov rsi, r12
    mov rcx, r13
    cmp rcx, r14
    jbe .cp
    mov rcx, r14
.cp:rep movsb
    mov rdi, r12
    call vmem_free
    mov rax, rbx
.fail:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret