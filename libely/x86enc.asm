; All arrays (code, labels, patches, iat/data patches) are heap-allocated.
; code_buf, lbl_off, patch_off, patch_lbl, x86_iat_patches, x86_data_patches
; are all pointers to VirtualAlloc'd memory.
default rel
%include "defs.inc"
extern mir_buf, mir_pos
extern vmem_alloc, vmem_realloc
global x86_init, x86_encode, x86_get_code
global x86_iat_patches, x86_iat_patch_count
global x86_data_patches, x86_data_patch_count
global x86_get_label_offset

section .bss
code_buf:   resq 1            ; -> x86 byte output
code_pos:   resq 1            ; bytes emitted
code_cap:   resq 1            ; capacity in bytes

lbl_off:    resq 1            ; -> label offset table (qword per label)
lbl_cap:    resq 1            ; label table capacity

patch_off:  resq 1            ; -> patch source offsets (qword array)
patch_lbl:  resq 1            ; -> patch target labels (qword array)
patch_cnt:  resq 1            ; number of patches
patch_cap:  resq 1            ; patch array capacity

; IAT patches: each entry is [code_offset:8][iat_slot:8] = 16 bytes
x86_iat_patches: resq 1       ; -> array of 16-byte entries
x86_iat_patch_count: resq 1
x86_iat_cap: resq 1

; data patches: each entry is [code_offset:8][data_offset:8] = 16 bytes
x86_data_patches: resq 1      ; -> array of 16-byte entries
x86_data_patch_count: resq 1
x86_data_cap: resq 1

section .text

; x86_init: allocate all buffers at initial sizes
x86_init:
    mov qword[code_pos], 0
    mov qword[patch_cnt], 0
    mov qword[x86_iat_patch_count], 0
    mov qword[x86_data_patch_count], 0
    ; code buffer
    mov qword[code_cap], INIT_CODE
    mov rdi, INIT_CODE
    call vmem_alloc
    mov [code_buf], rax
    ; label offset table (filled with -1 = unknown)
    mov qword[lbl_cap], INIT_LABELS
    mov rdi, INIT_LABELS * 8
    call vmem_alloc
    mov [lbl_off], rax
    mov rdi, rax
    mov rcx, INIT_LABELS
    mov rax, 0xFFFFFFFFFFFFFFFF
    rep stosq
    ; patch arrays
    mov qword[patch_cap], INIT_PATCHES
    mov rdi, INIT_PATCHES * 8
    call vmem_alloc
    mov [patch_off], rax
    mov rdi, INIT_PATCHES * 8
    call vmem_alloc
    mov [patch_lbl], rax
    ; IAT patch array
    mov qword[x86_iat_cap], INIT_PATCHES
    mov rdi, INIT_PATCHES * 16
    call vmem_alloc
    mov [x86_iat_patches], rax
    ; data patch array
    mov qword[x86_data_cap], INIT_PATCHES
    mov rdi, INIT_PATCHES * 16
    call vmem_alloc
    mov [x86_data_patches], rax
    ret

; x86_get_label_offset: rdi=label_id -> rax=code offset for that label
x86_get_label_offset:
    mov rax, [lbl_off]
    mov rax, [rax+rdi*8]
    ret

; x86_get_code: -> rsi=code buffer pointer, rdx=code byte count
x86_get_code:
    mov rsi, [code_buf]
    mov rdx, [code_pos]
    ret

; eb1: emit 1 byte from al
eb1:
    push rbx
    push r11
    mov rbx, [code_pos]
    mov r11, [code_buf]
    mov [r11+rbx], al
    inc qword[code_pos]
    pop r11
    pop rbx
    ret

; eb4: emit 4 bytes (dword) from eax
eb4:
    push rbx
    push r11
    mov rbx, [code_pos]
    mov r11, [code_buf]
    mov [r11+rbx], eax
    add qword[code_pos], 4
    pop r11
    pop rbx
    ret

; eb8: emit 8 bytes (qword) from rax
eb8:
    push rbx
    push r11
    mov rbx, [code_pos]
    mov r11, [code_buf]
    mov [r11+rbx], rax
    add qword[code_pos], 8
    pop r11
    pop rbx
    ret

; add_patch: record a rel32 patch site
; rdi=target label, code_pos=where the rel32 placeholder starts
add_patch:
    push rax
    push r11
    push rbx
    mov rax, [patch_cnt]
    mov r11, [patch_off]
    mov rbx, [code_pos]
    mov [r11+rax*8], rbx
    mov r11, [patch_lbl]
    mov [r11+rax*8], rdi
    inc qword[patch_cnt]
    pop rbx
    pop r11
    pop rax
    ret

; emit_rel32: emit 4 zero bytes as placeholder for rel32 displacement
emit_rel32:
    xor eax, eax
    jmp eb4

; add_iat_patch: record an IAT relocation
; r15=IAT slot index, code_pos=where the disp32 placeholder starts
add_iat_patch:
    push rax
    push rbx
    push rcx
    push r11
    mov rax, [x86_iat_patch_count]
    mov rcx, rax
    shl rcx, 4                    ; each entry = 16 bytes
    mov r11, [x86_iat_patches]
    mov rbx, [code_pos]
    mov [r11+rcx], rbx             ; code offset where disp32 lives
    mov [r11+rcx+8], r15           ; which IAT slot
    inc qword[x86_iat_patch_count]
    pop r11
    pop rcx
    pop rbx
    pop rax
    ret

; add_data_patch: record a data section relocation
; r15=data offset within section, code_pos=where the disp32 placeholder starts
add_data_patch:
    push rax
    push rbx
    push rcx
    push r11
    mov rax, [x86_data_patch_count]
    mov rcx, rax
    shl rcx, 4
    mov r11, [x86_data_patches]
    mov rbx, [code_pos]
    mov [r11+rcx], rbx
    mov [r11+rcx+8], r15
    inc qword[x86_data_patch_count]
    pop r11
    pop rcx
    pop rbx
    pop rax
    ret

; emit ModRM+disp for [rbp - offset]
; al=reg field (0-7), rsi=positive offset (negated internally)
emit_rbp_disp:
    push rbx
    push rcx
    cmp rsi, 128
    jge .d32
    mov cl, al
    shl cl, 3
    or cl, 0x45
    push rax
    movzx eax, cl
    call eb1
    pop rax
    push rax
    mov rax, rsi
    neg rax
    call eb1
    pop rax
    pop rcx
    pop rbx
    ret
.d32:
    mov cl, al
    shl cl, 3
    or cl, 0x85
    push rax
    movzx eax, cl
    call eb1
    pop rax
    push rax
    mov rax, rsi
    neg rax
    call eb4
    pop rax
    pop rcx
    pop rbx
    ret

; cmp rbx, rax (48 39 C3)
emit_cmp_rbx_rax:
    mov al, 0x48
    call eb1
    mov al, 0x39
    call eb1
    mov al, 0xC3
    call eb1
    ret

; SETcc al + movzx rax, al (for comparison results)
emit_setcc:
    push rax
    mov al, 0x0F
    call eb1
    pop rax
    call eb1
    mov al, 0xC0
    call eb1
    mov al, 0x48
    call eb1
    mov al, 0x0F
    call eb1
    mov al, 0xB6
    call eb1
    mov al, 0xC0
    call eb1
    ret

; x86_encode: walk MIR buffer, emit x86 bytes, then patch all rel32 sites
x86_encode:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    xor r12, r12               ; r12 = MIR instruction index
.loop:
    cmp r12, [mir_pos]
    jge .done
    ; load current MIR instruction fields
    imul r13, r12, MIR_SIZE
    push r11
    mov r11, [mir_buf]
    mov r14, [r11+r13]         ; opcode
    mov r15, [r11+r13+8]      ; op1
    mov rbp, [r11+r13+16]     ; op2
    pop r11

    ; dispatch on opcode
    cmp r14, MIR_ICONST
    je .iconst
    cmp r14, MIR_SLOAD
    je .sload
    cmp r14, MIR_SSTORE
    je .sstore
    cmp r14, MIR_SLEA
    je .slea
    cmp r14, MIR_PUSH
    je .push_
    cmp r14, MIR_POP_RBX
    je .pop_rbx
    cmp r14, MIR_POP_RCX
    je .pop_rcx
    cmp r14, MIR_POP_RDI
    je .pop_rdi
    cmp r14, MIR_POP_RSI
    je .pop_rsi
    cmp r14, MIR_POP_RDX
    je .pop_rdx
    cmp r14, MIR_POP_R8
    je .pop_r8
    cmp r14, MIR_POP_R9
    je .pop_r9
    cmp r14, MIR_ADD
    je .add_
    cmp r14, MIR_SUB
    je .sub_
    cmp r14, MIR_MUL
    je .mul_
    cmp r14, MIR_XCHG_RBX
    je .xchg_
    cmp r14, MIR_CQO
    je .cqo_
    cmp r14, MIR_IDIV_RBX
    je .idiv_
    cmp r14, MIR_CMP_EQ
    je .eq_
    cmp r14, MIR_CMP_NE
    je .ne_
    cmp r14, MIR_CMP_LT
    je .lt_
    cmp r14, MIR_CMP_GT
    je .gt_
    cmp r14, MIR_CMP_LE
    je .le_
    cmp r14, MIR_CMP_GE
    je .ge_
    cmp r14, MIR_TEST
    je .test_
    cmp r14, MIR_JZ
    je .jz_
    cmp r14, MIR_JNZ
    je .jnz_
    cmp r14, MIR_JNE
    je .jne_
    cmp r14, MIR_JMP
    je .jmp_
    cmp r14, MIR_LABEL
    je .label_
    cmp r14, MIR_CALL
    je .call_
    cmp r14, MIR_RET
    je .ret_
    cmp r14, MIR_ENTER
    je .enter_
    cmp r14, MIR_LEAVE
    je .leave_
    cmp r14, MIR_LEAVE_NRET
    je .leave_nr
    cmp r14, MIR_MOV_RDI_RAX
    je .m_rdi_rax
    cmp r14, MIR_MOV_RSI_RAX
    je .m_rsi_rax
    cmp r14, MIR_MOV_RBX_RAX
    je .m_rbx_rax
    cmp r14, MIR_MOV_RAX_RDI
    je .m_rax_rdi
    cmp r14, MIR_MOV_RAX_RSI
    je .m_rax_rsi
    cmp r14, MIR_XOR_EAX
    je .xor_eax
    cmp r14, MIR_DEREF
    je .deref_
    cmp r14, MIR_IDX_LOAD
    je .idx_ld
    cmp r14, MIR_IDX_STORE
    je .idx_st
    cmp r14, MIR_CMP_MEM_IMM
    je .cmp_mi
    cmp r14, MIR_SYSCALL
    je .syscall_
    cmp r14, MIR_FUNC_LABEL
    je .flabel
    cmp r14, MIR_RAW_BYTES
    je .raw_
    cmp r14, MIR_CALL_IAT
    je .call_iat
    cmp r14, MIR_STORE_DATA
    je .store_data
    cmp r14, MIR_LOAD_DATA
    je .load_data
    cmp r14, MIR_LEA_DATA
    je .lea_data
    cmp r14, MIR_SUB_RSP
    je .sub_rsp
    cmp r14, MIR_ADD_RSP
    je .add_rsp
    cmp r14, MIR_MOV_RCX_RDI
    je .m_rcx_rdi
    cmp r14, MIR_MOV_RCX_IMM
    je .m_rcx_imm
    cmp r14, MIR_MOV_RDX_RBX
    je .m_rdx_rbx
    cmp r14, MIR_MOV_R8D_ECX
    je .m_r8d_ecx
    cmp r14, MIR_MOV_R9_RAX
    je .m_r9_rax
    jmp .next

; mov rax, imm64
.iconst:
    mov al, 0x48
    call eb1
    mov al, 0xB8
    call eb1
    mov rax, r15
    call eb8
    jmp .next

; mov rax, [rbp - r15]  (8-byte load, default)
; op2 (rbp) can carry TYPE_* for sized loads
.sload:
    mov rsi, r15
    ; check op2 for sub-64-bit types
    cmp rbp, TYPE_I8
    je .sl_i8
    cmp rbp, TYPE_U8
    je .sl_u8
    cmp rbp, TYPE_BOOL
    je .sl_u8
    cmp rbp, TYPE_I16
    je .sl_i16
    cmp rbp, TYPE_U16
    je .sl_u16
    cmp rbp, TYPE_I32
    je .sl_i32
    cmp rbp, TYPE_U32
    je .sl_u32
    ; default: 64-bit mov rax, [rbp-off]
    mov al, 0x48
    call eb1
    mov al, 0x8B
    call eb1
    xor al, al
    call emit_rbp_disp
    jmp .next
.sl_i8:  ; movsx rax, byte [rbp-off]  (48 0F BE 45 xx)
    mov al, 0x48
    call eb1
    mov al, 0x0F
    call eb1
    mov al, 0xBE
    call eb1
    xor al, al
    call emit_rbp_disp
    jmp .next
.sl_u8:  ; movzx eax, byte [rbp-off]  (0F B6 45 xx)
    mov al, 0x0F
    call eb1
    mov al, 0xB6
    call eb1
    xor al, al
    call emit_rbp_disp
    jmp .next
.sl_i16: ; movsx rax, word [rbp-off]  (48 0F BF 45 xx)
    mov al, 0x48
    call eb1
    mov al, 0x0F
    call eb1
    mov al, 0xBF
    call eb1
    xor al, al
    call emit_rbp_disp
    jmp .next
.sl_u16: ; movzx eax, word [rbp-off]  (0F B7 45 xx)
    mov al, 0x0F
    call eb1
    mov al, 0xB7
    call eb1
    xor al, al
    call emit_rbp_disp
    jmp .next
.sl_i32: ; movsxd rax, dword [rbp-off]  (48 63 45 xx)
    mov al, 0x48
    call eb1
    mov al, 0x63
    call eb1
    xor al, al
    call emit_rbp_disp
    jmp .next
.sl_u32: ; mov eax, [rbp-off]  (8B 45 xx)  -- zero-extends to rax
    mov al, 0x8B
    call eb1
    xor al, al
    call emit_rbp_disp
    jmp .next

; mov [rbp - r15], rax  (8-byte store, default)
; op2 (rbp) can carry TYPE_* for sized stores
.sstore:
    mov rsi, r15
    cmp rbp, TYPE_I8
    je .ss_b
    cmp rbp, TYPE_U8
    je .ss_b
    cmp rbp, TYPE_BOOL
    je .ss_b
    cmp rbp, TYPE_I16
    je .ss_w
    cmp rbp, TYPE_U16
    je .ss_w
    cmp rbp, TYPE_I32
    je .ss_d
    cmp rbp, TYPE_U32
    je .ss_d
    ; default: 64-bit store
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    xor al, al
    call emit_rbp_disp
    jmp .next
.ss_b:   ; mov byte [rbp-off], al  (88 45 xx)
    mov al, 0x88
    call eb1
    xor al, al
    call emit_rbp_disp
    jmp .next
.ss_w:   ; mov word [rbp-off], ax  (66 89 45 xx)
    mov al, 0x66
    call eb1
    mov al, 0x89
    call eb1
    xor al, al
    call emit_rbp_disp
    jmp .next
.ss_d:   ; mov dword [rbp-off], eax  (89 45 xx)
    mov al, 0x89
    call eb1
    xor al, al
    call emit_rbp_disp
    jmp .next

; lea rax, [rbp - r15]
.slea:
    mov al, 0x48
    call eb1
    mov al, 0x8D
    call eb1
    xor al, al
    mov rsi, r15
    call emit_rbp_disp
    jmp .next

; push rax
.push_:
    mov al, 0x50
    call eb1
    jmp .next

; pop register
.pop_rbx:
    mov al, 0x5B
    call eb1
    jmp .next
.pop_rcx:
    mov al, 0x59
    call eb1
    jmp .next
.pop_rdi:
    mov al, 0x5F
    call eb1
    jmp .next
.pop_rsi:
    mov al, 0x5E
    call eb1
    jmp .next
.pop_rdx:
    mov al, 0x5A
    call eb1
    jmp .next
.pop_r8:
    mov al, 0x41
    call eb1
    mov al, 0x58
    call eb1
    jmp .next
.pop_r9:
    mov al, 0x41
    call eb1
    mov al, 0x59
    call eb1
    jmp .next

; add rax, rbx
.add_:
    mov al, 0x48
    call eb1
    mov al, 0x01
    call eb1
    mov al, 0xD8
    call eb1
    jmp .next

; sub rbx, rax; mov rax, rbx  (left - right, operands were swapped by push/pop)
.sub_:
    mov al, 0x48
    call eb1
    mov al, 0x29
    call eb1
    mov al, 0xC3
    call eb1
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0xD8
    call eb1
    jmp .next

; imul rax, rbx
.mul_:
    mov al, 0x48
    call eb1
    mov al, 0x0F
    call eb1
    mov al, 0xAF
    call eb1
    mov al, 0xC3
    call eb1
    jmp .next

; xchg rax, rbx
.xchg_:
    mov al, 0x48
    call eb1
    mov al, 0x93
    call eb1
    jmp .next

; cqo (sign-extend rax -> rdx:rax for idiv)
.cqo_:
    mov al, 0x48
    call eb1
    mov al, 0x99
    call eb1
    jmp .next

; idiv rbx
.idiv_:
    mov al, 0x48
    call eb1
    mov al, 0xF7
    call eb1
    mov al, 0xFB
    call eb1
    jmp .next

; comparison operators: cmp rbx, rax + SETcc + movzx
.eq_:
    call emit_cmp_rbx_rax
    mov al, 0x94
    call emit_setcc
    jmp .next
.ne_:
    call emit_cmp_rbx_rax
    mov al, 0x95
    call emit_setcc
    jmp .next
.lt_:
    call emit_cmp_rbx_rax
    mov al, 0x9C
    call emit_setcc
    jmp .next
.gt_:
    call emit_cmp_rbx_rax
    mov al, 0x9F
    call emit_setcc
    jmp .next
.le_:
    call emit_cmp_rbx_rax
    mov al, 0x9E
    call emit_setcc
    jmp .next
.ge_:
    call emit_cmp_rbx_rax
    mov al, 0x9D
    call emit_setcc
    jmp .next

; test rax, rax
.test_:
    mov al, 0x48
    call eb1
    mov al, 0x85
    call eb1
    mov al, 0xC0
    call eb1
    jmp .next

; conditional jumps: emit 0F 8x + rel32 placeholder
.jz_:
    mov al, 0x0F
    call eb1
    mov al, 0x84
    call eb1
    mov rdi, r15
    call add_patch
    call emit_rel32
    jmp .next
.jnz_:
    mov al, 0x0F
    call eb1
    mov al, 0x85
    call eb1
    mov rdi, r15
    call add_patch
    call emit_rel32
    jmp .next
.jne_:
    mov al, 0x0F
    call eb1
    mov al, 0x85
    call eb1
    mov rdi, r15
    call add_patch
    call emit_rel32
    jmp .next

; unconditional jump: E9 + rel32
.jmp_:
    mov al, 0xE9
    call eb1
    mov rdi, r15
    call add_patch
    call emit_rel32
    jmp .next

; label: record current code position
.label_:
    push r11
    mov r11, [lbl_off]
    mov rax, [code_pos]
    mov [r11+r15*8], rax
    pop r11
    jmp .next

; call rel32
.call_:
    mov al, 0xE8
    call eb1
    mov rdi, r15
    call add_patch
    call emit_rel32
    jmp .next

; ret
.ret_:
    mov al, 0xC3
    call eb1
    jmp .next

; function prologue: push rbx; push r12; push rbp; mov rbp,rsp; sub rsp,imm32
.enter_:
    mov al, 0x53
    call eb1
    mov al, 0x41
    call eb1
    mov al, 0x54
    call eb1
    mov al, 0x55
    call eb1
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0xE5
    call eb1
    mov al, 0x48
    call eb1
    mov al, 0x81
    call eb1
    mov al, 0xEC
    call eb1
    mov eax, r15d
    call eb4
    jmp .next

; function epilogue with ret: leave; pop r12; pop rbx; ret
.leave_:
    mov al, 0xC9
    call eb1
    mov al, 0x41
    call eb1
    mov al, 0x5C
    call eb1
    mov al, 0x5B
    call eb1
    mov al, 0xC3
    call eb1
    jmp .next

; epilogue without ret (for failed clause fallthrough)
.leave_nr:
    mov al, 0xC9
    call eb1
    mov al, 0x41
    call eb1
    mov al, 0x5C
    call eb1
    mov al, 0x5B
    call eb1
    jmp .next

; register moves
.m_rdi_rax:                    ; mov rdi, rax  (48 89 C7)
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0xC7
    call eb1
    jmp .next
.m_rsi_rax:                    ; mov rsi, rax  (48 89 C6)
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0xC6
    call eb1
    jmp .next
.m_rbx_rax:                    ; mov rbx, rax  (48 89 C3)
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0xC3
    call eb1
    jmp .next
.m_rax_rdi:                    ; mov rax, rdi  (48 89 F8)
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0xF8
    call eb1
    jmp .next
.m_rax_rsi:                    ; mov rax, rsi  (48 89 F0)
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0xF0
    call eb1
    jmp .next

; xor eax, eax (31 C0)
.xor_eax:
    mov al, 0x31
    call eb1
    mov al, 0xC0
    call eb1
    jmp .next

; deref: mov rax, [rax]  (48 8B 00)
.deref_:
    mov al, 0x48
    call eb1
    mov al, 0x8B
    call eb1
    mov al, 0x00
    call eb1
    jmp .next

; indexed load: mov rax, [rax + rbx*scale]
; r15 (op1) carries TYPE_* for element size
.idx_ld:
    cmp r15, TYPE_I8
    je .il_i8
    cmp r15, TYPE_U8
    je .il_u8
    cmp r15, TYPE_BOOL
    je .il_u8
    cmp r15, TYPE_I16
    je .il_i16
    cmp r15, TYPE_U16
    je .il_u16
    cmp r15, TYPE_I32
    je .il_i32
    cmp r15, TYPE_U32
    je .il_u32
    ; default: 64-bit, scale=8  mov rax,[rax+rbx*8]  (48 8B 04 D8)
    mov al, 0x48
    call eb1
    mov al, 0x8B
    call eb1
    mov al, 0x04
    call eb1
    mov al, 0xD8
    call eb1
    jmp .next
.il_i8:  ; movsx rax, byte [rax+rbx*1]  (48 0F BE 04 18)
    mov al, 0x48
    call eb1
    mov al, 0x0F
    call eb1
    mov al, 0xBE
    call eb1
    mov al, 0x04
    call eb1
    mov al, 0x18
    call eb1
    jmp .next
.il_u8:  ; movzx eax, byte [rax+rbx*1]  (0F B6 04 18)
    mov al, 0x0F
    call eb1
    mov al, 0xB6
    call eb1
    mov al, 0x04
    call eb1
    mov al, 0x18
    call eb1
    jmp .next
.il_i16: ; movsx rax, word [rax+rbx*2]  (48 0F BF 04 58)
    mov al, 0x48
    call eb1
    mov al, 0x0F
    call eb1
    mov al, 0xBF
    call eb1
    mov al, 0x04
    call eb1
    mov al, 0x58
    call eb1
    jmp .next
.il_u16: ; movzx eax, word [rax+rbx*2]  (0F B7 04 58)
    mov al, 0x0F
    call eb1
    mov al, 0xB7
    call eb1
    mov al, 0x04
    call eb1
    mov al, 0x58
    call eb1
    jmp .next
.il_i32: ; movsxd rax, dword [rax+rbx*4]  (48 63 04 98)
    mov al, 0x48
    call eb1
    mov al, 0x63
    call eb1
    mov al, 0x04
    call eb1
    mov al, 0x98
    call eb1
    jmp .next
.il_u32: ; mov eax, [rax+rbx*4]  (8B 04 98)
    mov al, 0x8B
    call eb1
    mov al, 0x04
    call eb1
    mov al, 0x98
    call eb1
    jmp .next

; indexed store: mov [rax + rbx*scale], rcx
; r15 (op1) carries TYPE_*
.idx_st:
    cmp r15, TYPE_I8
    je .is_b
    cmp r15, TYPE_U8
    je .is_b
    cmp r15, TYPE_BOOL
    je .is_b
    cmp r15, TYPE_I16
    je .is_w
    cmp r15, TYPE_U16
    je .is_w
    cmp r15, TYPE_I32
    je .is_d
    cmp r15, TYPE_U32
    je .is_d
    ; default: 64-bit  mov [rax+rbx*8], rcx  (48 89 0C D8)
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0x0C
    call eb1
    mov al, 0xD8
    call eb1
    jmp .next
.is_b:   ; mov [rax+rbx*1], cl  (88 0C 18)
    mov al, 0x88
    call eb1
    mov al, 0x0C
    call eb1
    mov al, 0x18
    call eb1
    jmp .next
.is_w:   ; mov [rax+rbx*2], cx  (66 89 0C 58)
    mov al, 0x66
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0x0C
    call eb1
    mov al, 0x58
    call eb1
    jmp .next
.is_d:   ; mov [rax+rbx*4], ecx  (89 0C 98)
    mov al, 0x89
    call eb1
    mov al, 0x0C
    call eb1
    mov al, 0x98
    call eb1
    jmp .next

; cmp qword [rbp - r15], imm32(rbp)
.cmp_mi:
    mov al, 0x48
    call eb1
    mov al, 0x81
    call eb1
    mov al, 7
    mov rsi, r15
    call emit_rbp_disp
    mov eax, ebp
    call eb4
    jmp .next

; syscall
.syscall_:
    mov al, 0x0F
    call eb1
    mov al, 0x05
    call eb1
    jmp .next

; function label (same as .label_ but semantically a function entry)
.flabel:
    push r11
    mov r11, [lbl_off]
    mov rax, [code_pos]
    mov [r11+r15*8], rax
    pop r11
    jmp .next

; raw bytes: copy r15=src ptr, rbp=byte count into code buffer
.raw_:
    push rsi
    push rcx
    push rdi
    mov rsi, r15
    mov rdi, [code_buf]
    add rdi, [code_pos]
    mov rcx, rbp
    rep movsb
    add [code_pos], rbp
    pop rdi
    pop rcx
    pop rsi
    jmp .next

; call [rip + disp32]  -- indirect call through IAT
; r15=IAT slot index. We emit FF 15 + placeholder, record patch.
.call_iat:
    mov al, 0xFF
    call eb1
    mov al, 0x15
    call eb1
    call add_iat_patch
    call emit_rel32
    jmp .next

; mov [rip + disp32], rax  -- store to data section
; r15=data offset. Emit 48 89 05 + placeholder, record data patch.
.store_data:
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0x05
    call eb1
    call add_data_patch
    call emit_rel32
    jmp .next

; mov rax, [rip + disp32]  -- load from data section
; r15=data offset. Emit 48 8B 05 + placeholder, record data patch.
.load_data:
    mov al, 0x48
    call eb1
    mov al, 0x8B
    call eb1
    mov al, 0x05
    call eb1
    call add_data_patch
    call emit_rel32
    jmp .next

; lea rax, [rip + disp32]  -- address of data section item
; r15=data offset. Emit 48 8D 05 + placeholder, record data patch.
.lea_data:
    mov al, 0x48
    call eb1
    mov al, 0x8D
    call eb1
    mov al, 0x05
    call eb1
    call add_data_patch
    call emit_rel32
    jmp .next

; sub rsp, imm
.sub_rsp:
    mov al, 0x48
    call eb1
    cmp r15, 128
    jge .sub_rsp32
    mov al, 0x83
    call eb1
    mov al, 0xEC
    call eb1
    mov al, r15b
    call eb1
    jmp .next
.sub_rsp32:
    mov al, 0x81
    call eb1
    mov al, 0xEC
    call eb1
    mov eax, r15d
    call eb4
    jmp .next

; add rsp, imm
.add_rsp:
    mov al, 0x48
    call eb1
    cmp r15, 128
    jge .add_rsp32
    mov al, 0x83
    call eb1
    mov al, 0xC4
    call eb1
    mov al, r15b
    call eb1
    jmp .next
.add_rsp32:
    mov al, 0x81
    call eb1
    mov al, 0xC4
    call eb1
    mov eax, r15d
    call eb4
    jmp .next

; mov rcx, rdi  (48 89 F9)
.m_rcx_rdi:
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0xF9
    call eb1
    jmp .next

; mov ecx, imm32  (B9 xx xx xx xx)
.m_rcx_imm:
    mov al, 0xB9
    call eb1
    mov eax, r15d
    call eb4
    jmp .next

; mov rdx, rbx  (48 89 DA)
.m_rdx_rbx:
    mov al, 0x48
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0xDA
    call eb1
    jmp .next

; mov r8d, ecx  (41 89 C8)
.m_r8d_ecx:
    mov al, 0x41
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0xC8
    call eb1
    jmp .next

; mov r9, rax  (49 89 C1)
.m_r9_rax:
    mov al, 0x49
    call eb1
    mov al, 0x89
    call eb1
    mov al, 0xC1
    call eb1
    jmp .next

.next:
    inc r12
    jmp .loop

.done:
    ; Walk all recorded rel32 patch sites.
    ; For each: compute displacement = label_offset - (patch_offset + 4)
    ; and write it into the code buffer at patch_offset.
    xor r12, r12
.plp:
    cmp r12, [patch_cnt]
    jge .pd
    ; load patch source offset
    push r11
    mov r11, [patch_off]
    mov rax, [r11+r12*8]      ; rax = code offset of the rel32 placeholder
    ; load target label
    mov r11, [patch_lbl]
    mov rbx, [r11+r12*8]      ; rbx = label id
    pop r11
    ; look up label's code offset
    push r11
    mov r11, [lbl_off]
    mov rcx, [r11+rbx*8]      ; rcx = label's code offset
    pop r11
    ; displacement = target - (source + 4)
    sub rcx, rax
    sub rcx, 4
    ; write displacement into code buffer
    push r11
    mov r11, [code_buf]
    mov [r11+rax], ecx
    pop r11
    inc r12
    jmp .plp
.pd:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret