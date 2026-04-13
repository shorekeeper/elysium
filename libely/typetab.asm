; typetab.asm - record type + variant registry with proper field offsets
default rel
%include "defs.inc"
extern ely_memcmp, type_size
global treg_init, treg_define, treg_lookup, treg_field_index
global treg_field_count, treg_total_size
global treg_define_union, treg_lookup_variant
global treg_foff, treg_ftype

section .bss
treg_nptr:   resq MAX_REC_TYPES
treg_nlen:   resq MAX_REC_TYPES
treg_fcount: resq MAX_REC_TYPES
treg_tsize:  resq MAX_REC_TYPES
treg_fnptr:  resq MAX_REC_TYPES * MAX_REC_FIELDS
treg_fnlen:  resq MAX_REC_TYPES * MAX_REC_FIELDS
treg_ftype:  resq MAX_REC_TYPES * MAX_REC_FIELDS
treg_foff:   resq MAX_REC_TYPES * MAX_REC_FIELDS
treg_count:  resq 1
var_nptr:    resq MAX_VARIANTS
var_nlen:    resq MAX_VARIANTS
var_tag:     resq MAX_VARIANTS
var_count:   resq 1

section .text

treg_init:
    mov qword[treg_count],0
    mov qword[var_count],0
    ret

; treg_define: rdi=NODE_TYPE_DEF -> register with computed field offsets
treg_define:
    push rbx
    push rcx
    push rsi
    push r8
    push r9
    push r10
    push r11
    mov r8,[treg_count]
    mov rax,[rdi+48]
    mov [treg_nptr+r8*8],rax
    mov rax,[rdi+56]
    mov [treg_nlen+r8*8],rax
    mov rbx,[rdi+16]
    xor r9,r9
    xor r10,r10
.fl:test rbx,rbx
    jz .fd
    mov rax,r8
    imul rax,rax,MAX_REC_FIELDS
    add rax,r9
    mov r11,rax
    mov rcx,[rbx+48]
    mov [treg_fnptr+r11*8],rcx
    mov rcx,[rbx+56]
    mov [treg_fnlen+r11*8],rcx
    mov rcx,[rbx+8]
    cmp rcx,TYPE_INFER
    jne .fty
    mov rcx,TYPE_I64
.fty:
    mov [treg_ftype+r11*8],rcx
    mov rax,rcx
    call type_size
    ; align r10 to field size
    lea rcx,[r10+rax-1]
    push rax
    neg rax
    and rcx,rax
    pop rax
    mov r10,rcx
    mov [treg_foff+r11*8],r10
    add r10,rax
    inc r9
    mov rbx,[rbx+32]
    jmp .fl
.fd:mov [treg_fcount+r8*8],r9
    mov [treg_tsize+r8*8],r10
    inc qword[treg_count]
    pop r11
    pop r10
    pop r9
    pop r8
    pop rsi
    pop rcx
    pop rbx
    ret

treg_lookup:
    push rbx
    push rdi
    push rsi
    push rcx
    push r8
    push r9
    mov r8,rsi
    mov r9,rcx
    xor rbx,rbx
.l: cmp rbx,[treg_count]
    jge .nf
    cmp r9,[treg_nlen+rbx*8]
    jne .nx
    mov rsi,r8
    mov rdi,[treg_nptr+rbx*8]
    mov rcx,r9
    call ely_memcmp
    test rax,rax
    jnz .nx
    mov rax,rbx
    jmp .d
.nx:inc rbx
    jmp .l
.nf:mov rax,-1
.d: pop r9
    pop r8
    pop rcx
    pop rsi
    pop rdi
    pop rbx
    ret

treg_field_index:
    push rbx
    push rdi
    push rsi
    push rcx
    push r8
    push r9
    push r10
    mov r8,rsi
    mov r9,rcx
    mov r10,rdi
    imul rax,r10,MAX_REC_FIELDS
    mov rbx,rax
    xor rdi,rdi
.l: cmp rdi,[treg_fcount+r10*8]
    jge .nf
    mov rax,rbx
    add rax,rdi
    cmp r9,[treg_fnlen+rax*8]
    jne .nx
    push rdi
    mov rsi,r8
    mov rdi,[treg_fnptr+rax*8]
    mov rcx,r9
    call ely_memcmp
    pop rdi
    test rax,rax
    jnz .nx
    mov rax,rdi
    jmp .d
.nx:inc rdi
    jmp .l
.nf:mov rax,-1
.d: pop r10
    pop r9
    pop r8
    pop rcx
    pop rsi
    pop rdi
    pop rbx
    ret

treg_field_count:
    mov rax,[treg_fcount+rdi*8]
    ret

treg_total_size:
    mov rax,[treg_tsize+rdi*8]
    ret

treg_define_union:
    push rbx
    push r8
    mov rbx,[rdi+16]
    xor r8,r8
.l: test rbx,rbx
    jz .d
    mov rax,[var_count]
    mov rcx,[rbx+48]
    mov [var_nptr+rax*8],rcx
    mov rcx,[rbx+56]
    mov [var_nlen+rax*8],rcx
    mov [var_tag+rax*8],r8
    inc qword[var_count]
    inc r8
    mov rbx,[rbx+32]
    jmp .l
.d: pop r8
    pop rbx
    ret

treg_lookup_variant:
    push rbx
    push rdi
    push rsi
    push rcx
    push r8
    push r9
    mov r8,rsi
    mov r9,rcx
    xor rbx,rbx
.l: cmp rbx,[var_count]
    jge .nf
    cmp r9,[var_nlen+rbx*8]
    jne .nx
    mov rsi,r8
    mov rdi,[var_nptr+rbx*8]
    mov rcx,r9
    call ely_memcmp
    test rax,rax
    jnz .nx
    mov rax,[var_tag+rbx*8]
    jmp .d
.nx:inc rbx
    jmp .l
.nf:mov rax,-1
.d: pop r9
    pop r8
    pop rcx
    pop rsi
    pop rdi
    pop rbx
    ret