; handles: unary neg/not/bnot, short-circuit && and ||
default rel
%include "defs.inc"
extern lower_expr, mir_emit, mir_emit2, mir_new_label

global lower_expr_ext

section .text

; lower_expr_ext: rdi=AST node pointer
; returns rax=1 if handled, 0 if not
; emits MIR instructions (result left in accumulator)
lower_expr_ext:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov rax, [r12]
    cmp rax, NODE_UNARY_NEG
    je .neg
    cmp rax, NODE_UNARY_NOT
    je .lnot
    cmp rax, NODE_UNARY_BNOT
    je .bnot
    cmp rax, NODE_LOGIC_AND
    je .land
    cmp rax, NODE_LOGIC_OR
    je .lor
    ; not handled
    xor rax, rax
    jmp .ret
.neg:
    mov rdi, [r12+16]
    call lower_expr
    mov rdi, MIR_NEG
    xor rsi, rsi
    call mir_emit2
    mov rax, 1
    jmp .ret
.lnot:
    mov rdi, [r12+16]
    call lower_expr
    mov rdi, MIR_LNOT
    xor rsi, rsi
    call mir_emit2
    mov rax, 1
    jmp .ret
.bnot:
    mov rdi, [r12+16]
    call lower_expr
    mov rdi, MIR_BNOT
    xor rsi, rsi
    call mir_emit2
    mov rax, 1
    jmp .ret

; a && b: short-circuit AND
; eval a; if false skip b; eval b; normalize to 0/1
.land:
    call mir_new_label
    mov r13, rax               ; false_label
    call mir_new_label
    mov r14, rax               ; end_label
    ; eval left
    mov rdi, [r12+16]
    call lower_expr
    mov rdi, MIR_TEST
    xor rsi, rsi
    call mir_emit2
    mov rdi, MIR_JZ
    mov rsi, r13
    call mir_emit2
    ; left was truthy, eval right
    mov rdi, [r12+24]
    call lower_expr
    mov rdi, MIR_TEST
    xor rsi, rsi
    call mir_emit2
    mov rdi, MIR_JZ
    mov rsi, r13
    call mir_emit2
    ; both truthy: result = 1
    mov rdi, MIR_ICONST
    mov rsi, 1
    call mir_emit2
    mov rdi, MIR_JMP
    mov rsi, r14
    call mir_emit2
    ; false path: result = 0
    mov rdi, MIR_LABEL
    mov rsi, r13
    call mir_emit2
    mov rdi, MIR_XOR_EAX
    xor rsi, rsi
    call mir_emit2
    ; end
    mov rdi, MIR_LABEL
    mov rsi, r14
    call mir_emit2
    mov rax, 1
    jmp .ret

; a || b: short-circuit OR
.lor:
    call mir_new_label
    mov r13, rax               ; true_label
    call mir_new_label
    mov r14, rax               ; end_label
    ; eval left
    mov rdi, [r12+16]
    call lower_expr
    mov rdi, MIR_TEST
    xor rsi, rsi
    call mir_emit2
    mov rdi, MIR_JNZ
    mov rsi, r13
    call mir_emit2
    ; left was falsy, eval right
    mov rdi, [r12+24]
    call lower_expr
    mov rdi, MIR_TEST
    xor rsi, rsi
    call mir_emit2
    mov rdi, MIR_JNZ
    mov rsi, r13
    call mir_emit2
    ; both falsy: result = 0
    mov rdi, MIR_XOR_EAX
    xor rsi, rsi
    call mir_emit2
    mov rdi, MIR_JMP
    mov rsi, r14
    call mir_emit2
    ; true path: result = 1
    mov rdi, MIR_LABEL
    mov rsi, r13
    call mir_emit2
    mov rdi, MIR_ICONST
    mov rsi, 1
    call mir_emit2
    ; end
    mov rdi, MIR_LABEL
    mov rsi, r14
    call mir_emit2
    mov rax, 1
    jmp .ret

.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret