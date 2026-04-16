; parser_ext.asm - extended expression precedence levels
; precedence (low->high): || -> && -> cmp -> | -> ^ -> & -> << >> -> + - -> * / %
default rel
%include "defs.inc"
extern ct, ea, p_cmp, p_add, p_primary, p_postfix, new_node, pk

global p_or, p_and, p_bitor, p_bitxor, p_bitand, p_shift

section .text

; p_or: handles || (lowest new precedence)
p_or:
    push rbx
    push rcx
    push r12
    call p_and
    mov r12, rax
.l: call ct
    cmp rax, TOK_OR_OR
    jne .d
    call ea
    call p_and
    push rax
    call new_node
    mov qword[rax], NODE_LOGIC_OR
    mov [rax+16], r12
    pop rbx
    mov [rax+24], rbx
    mov r12, rax
    jmp .l
.d: mov rax, r12
    pop r12
    pop rcx
    pop rbx
    ret

; p_and: handles &&
p_and:
    push rbx
    push rcx
    push r12
    call p_cmp
    mov r12, rax
.l: call ct
    cmp rax, TOK_AND_AND
    jne .d
    call ea
    call p_cmp
    push rax
    call new_node
    mov qword[rax], NODE_LOGIC_AND
    mov [rax+16], r12
    pop rbx
    mov [rax+24], rbx
    mov r12, rax
    jmp .l
.d: mov rax, r12
    pop r12
    pop rcx
    pop rbx
    ret

; p_bitor: handles | (bitwise OR via TOK_BAR)
p_bitor:
    push rbx
    push rcx
    push r12
    call p_bitxor
    mov r12, rax
.l: call ct
    cmp rax, TOK_BAR
    jne .d
    push rax
    call ea
    call p_bitxor
    mov rbx, rax
    pop rcx
    push rbx
    call new_node
    mov qword[rax], NODE_BINOP
    mov [rax+8], rcx
    mov [rax+16], r12
    pop rbx
    mov [rax+24], rbx
    mov r12, rax
    jmp .l
.d: mov rax, r12
    pop r12
    pop rcx
    pop rbx
    ret

; p_bitxor: handles ^
p_bitxor:
    push rbx
    push rcx
    push r12
    call p_bitand
    mov r12, rax
.l: call ct
    cmp rax, TOK_CARET
    jne .d
    push rax
    call ea
    call p_bitand
    mov rbx, rax
    pop rcx
    push rbx
    call new_node
    mov qword[rax], NODE_BINOP
    mov [rax+8], rcx
    mov [rax+16], r12
    pop rbx
    mov [rax+24], rbx
    mov r12, rax
    jmp .l
.d: mov rax, r12
    pop r12
    pop rcx
    pop rbx
    ret

; p_bitand: handles & as binary (infix) operator
p_bitand:
    push rbx
    push rcx
    push r12
    call p_shift
    mov r12, rax
.l: call ct
    cmp rax, TOK_AMP
    jne .d
    push rax
    call ea
    call p_shift
    mov rbx, rax
    pop rcx
    push rbx
    call new_node
    mov qword[rax], NODE_BINOP
    mov [rax+8], rcx
    mov [rax+16], r12
    pop rbx
    mov [rax+24], rbx
    mov r12, rax
    jmp .l
.d: mov rax, r12
    pop r12
    pop rcx
    pop rbx
    ret

; p_shift: handles << and >>
p_shift:
    push rbx
    push rcx
    push r12
    call p_add
    mov r12, rax
.l: call ct
    cmp rax, TOK_SHL
    je .op
    cmp rax, TOK_SHR
    je .op
    mov rax, r12
    pop r12
    pop rcx
    pop rbx
    ret
.op:push rax
    call ea
    call p_primary
    call p_postfix
    mov rbx, rax
    pop rcx
    push rbx
    call new_node
    mov qword[rax], NODE_BINOP
    mov [rax+8], rcx
    mov [rax+16], r12
    pop rbx
    mov [rax+24], rbx
    mov r12, rax
    jmp .l