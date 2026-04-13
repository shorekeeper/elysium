; Each instruction: [opcode:8][op1:8][op2:8] = 24 bytes
; Buffer starts at INIT_MIR entries, doubles via vmem_realloc when full.
default rel
%include "defs.inc"
extern vmem_alloc, vmem_realloc
global mir_init, mir_emit, mir_emit2, mir_count
global mir_buf, mir_pos, mir_new_label

section .bss
mir_buf: resq 1              ; pointer to instruction array
mir_pos: resq 1              ; number of instructions emitted
mir_cap: resq 1              ; current capacity (in instructions)
mir_label_counter: resq 1    ; monotonic label id counter

section .text

; mir_init: allocate initial buffer
mir_init:
    mov qword[mir_pos], 0
    mov qword[mir_label_counter], 0
    mov qword[mir_cap], INIT_MIR
    mov rdi, INIT_MIR * MIR_SIZE
    call vmem_alloc
    mov [mir_buf], rax
    ret

; mir_ensure: grow buffer if at capacity
mir_ensure:
    mov rax, [mir_pos]
    cmp rax, [mir_cap]
    jl .ok
    push rdi
    push rsi
    push rdx
    mov rdi, [mir_buf]
    mov rsi, [mir_cap]
    imul rsi, rsi, MIR_SIZE       ; old byte count
    mov rdx, [mir_cap]
    shl rdx, 1                    ; double capacity
    mov [mir_cap], rdx
    imul rdx, rdx, MIR_SIZE       ; new byte count
    call vmem_realloc
    mov [mir_buf], rax
    pop rdx
    pop rsi
    pop rdi
.ok:ret

; mir_emit: rdi=opcode, rsi=op1, rdx=op2 -> append instruction
mir_emit:
    call mir_ensure
    push rax
    push rcx
    push rbx
    mov rax, [mir_pos]
    imul rcx, rax, MIR_SIZE
    mov rbx, [mir_buf]
    mov [rbx+rcx], rdi
    mov [rbx+rcx+8], rsi
    mov [rbx+rcx+16], rdx
    pop rbx
    inc qword[mir_pos]
    pop rcx
    pop rax
    ret

; mir_emit2: rdi=opcode, rsi=op1 (op2 defaults to 0)
mir_emit2:
    xor rdx, rdx
    jmp mir_emit

; mir_new_label: -> rax=unique label id
mir_new_label:
    mov rax, [mir_label_counter]
    inc qword[mir_label_counter]
    ret

; mir_count: -> rax=number of emitted instructions
mir_count:
    mov rax, [mir_pos]
    ret