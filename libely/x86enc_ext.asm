; called from x86enc when opcode is not in the base set
default rel
%include "defs.inc"
extern eb1

global x86_encode_ext

section .text

; x86_encode_ext: rdi=opcode, rsi=op1, rdx=op2
; emits x86 bytes via eb1. always returns (caller jumps to .next)
x86_encode_ext:
    cmp rdi, MIR_NEG
    je .neg
    cmp rdi, MIR_LNOT
    je .lnot
    cmp rdi, MIR_BNOT
    je .bnot
    cmp rdi, MIR_IMOD_RBX
    je .imod
    cmp rdi, MIR_BAND
    je .band
    cmp rdi, MIR_BOR
    je .bor
    cmp rdi, MIR_BXOR
    je .bxor
    cmp rdi, MIR_SHL
    je .shl_
    cmp rdi, MIR_SHR
    je .shr_
    ret

; neg rax (48 F7 D8)
.neg:
    mov al, 0x48
    call eb1
    mov al, 0xF7
    call eb1
    mov al, 0xD8
    call eb1
    ret

; logical not: test rax,rax; sete al; movzx rax,al
.lnot:
    ; test rax, rax (48 85 C0)
    mov al, 0x48
    call eb1
    mov al, 0x85
    call eb1
    mov al, 0xC0
    call eb1
    ; sete al (0F 94 C0)
    mov al, 0x0F
    call eb1
    mov al, 0x94
    call eb1
    mov al, 0xC0
    call eb1
    ; movzx rax, al (48 0F B6 C0)
    mov al, 0x48
    call eb1
    mov al, 0x0F
    call eb1
    mov al, 0xB6
    call eb1
    mov al, 0xC0
    call eb1
    ret

; bitwise not rax (48 F7 D0)
.bnot:
    mov al, 0x48
    call eb1
    mov al, 0xF7
    call eb1
    mov al, 0xD0
    call eb1
    ret

; idiv rbx then mov rax, rdx (remainder)
.imod:
    ; idiv rbx (48 F7 FB)
    mov al, 0x48
    call eb1
    mov al, 0xF7
    call eb1
    mov al, 0xFB
    call eb1
    ; mov rax, rdx (48 89 D0)
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0xD0
    call eb1
    ret

; and rax, rbx (48 21 D8)
.band:
    mov al, 0x48
    call eb1
    mov al, 0x21
    call eb1
    mov al, 0xD8
    call eb1
    ret

; or rax, rbx (48 09 D8)
.bor:
    mov al, 0x48
    call eb1
    mov al, 0x09
    call eb1
    mov al, 0xD8
    call eb1
    ret

; xor rax, rbx (48 31 D8)
.bxor:
    mov al, 0x48
    call eb1
    mov al, 0x31
    call eb1
    mov al, 0xD8
    call eb1
    ret

; shl: rbx=value, rax=count -> rax = rbx << count
; mov rcx, rax (48 89 C1)
; mov rax, rbx (48 89 D8)
; shl rax, cl  (48 D3 E0)
.shl_:
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0xC1
    call eb1
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0xD8
    call eb1
    mov al, 0x48
    call eb1
    mov al, 0xD3
    call eb1
    mov al, 0xE0
    call eb1
    ret

; shr: rbx=value, rax=count -> rax = rbx >> count
; mov rcx, rax; mov rax, rbx; shr rax, cl (48 D3 E8)
.shr_:
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0xC1
    call eb1
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0xD8
    call eb1
    mov al, 0x48
    call eb1
    mov al, 0xD3
    call eb1
    mov al, 0xE8
    call eb1
    ret