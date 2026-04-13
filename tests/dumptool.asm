; dumptool.asm -- standalone debug tool
; Usage: elydump <input.ely> [--mir] [--x86] [--sym] [--map]
; Compiles and dumps internal state without writing PE
default rel
%include "defs.inc"
extern GetStdHandle, WriteFile, ExitProcess, GetCommandLineA
extern CreateFileA, ReadFile, CloseHandle
extern frontend_init, frontend_run
extern backend_init
extern mir_init, mir_count, mir_buf, mir_pos
extern x86_init, x86_encode, x86_get_code, x86_get_label_offset
extern lower_module, lower_emit_runtime_win, lower_emit_entry_win
extern lower_entry_label
extern sym_init, sym_count, sym_off, sym_nptr, sym_nlen, sym_type, sym_arrlen
extern be_target, be_mod_root
extern str_pool_pos
global platform_write

STD_OUTPUT_HANDLE equ -11
GENERIC_READ equ 0x80000000
FILE_SHARE_READ equ 1
OPEN_EXISTING equ 3
FILE_ATTR_NORMAL equ 0x80

section .data
msg_ban: db 13,10,"  elydump",13,10,13,10,0
msg_use: db "  Usage: elydump <input.ely> [--mir] [--x86] [--sym] [--all]",13,10,0
msg_mir_hdr: db 13,10,"=== MIR Dump ===",13,10,0
msg_x86_hdr: db 13,10,"=== x86 Hex Dump ===",13,10,0
msg_sym_hdr: db 13,10,"=== Symbol Table ===",13,10,0
msg_map_hdr: db 13,10,"=== Label Map ===",13,10,0
msg_nl: db 13,10,0
msg_sp: db " ",0
msg_colon: db ": ",0
msg_at: db " @ off=",0
msg_ty: db " type=",0
msg_arr: db " arrlen=",0
msg_pipe: db " | ",0
msg_mir_i: db "  MIR[",0
msg_mir_c: db "] op=",0
msg_mir_a: db " a=",0
msg_mir_b: db " b=",0
msg_lbl: db "  L",0
msg_eq: db " = 0x",0
msg_code_sz: db "  code bytes: ",0
msg_str_sz: db "  string pool: ",0
msg_mir_cnt: db "  MIR count: ",0

opt_mir: db "--mir",0
opt_x86: db "--x86",0
opt_sym: db "--sym",0
opt_all: db "--all",0

; MIR opcode names
mir_names:
    dq mn_unk        ; 0
    dq mn_iconst     ; 1
    dq mn_sload      ; 2
    dq mn_sstore     ; 3
    dq mn_slea       ; 4
    dq mn_push       ; 5
    dq mn_pop_rbx    ; 6
    dq mn_pop_rcx    ; 7
    dq mn_pop_rdi    ; 8
    dq mn_pop_rsi    ; 9
    dq mn_pop_rdx    ; 10
    dq mn_pop_r8     ; 11
    dq mn_pop_r9     ; 12
    times 7 dq mn_unk ; 13-19
    dq mn_add        ; 20
    dq mn_sub        ; 21
    dq mn_mul        ; 22
    dq mn_xchg       ; 23
    dq mn_cqo        ; 24
    dq mn_idiv       ; 25
    times 4 dq mn_unk ; 26-29
    dq mn_cmp_eq     ; 30
    dq mn_cmp_ne     ; 31
    dq mn_cmp_lt     ; 32
    dq mn_cmp_gt     ; 33
    dq mn_cmp_le     ; 34
    dq mn_cmp_ge     ; 35
    times 4 dq mn_unk ; 36-39
    dq mn_test       ; 40
    dq mn_jz         ; 41
    dq mn_jnz        ; 42
    dq mn_jne        ; 43
    dq mn_jmp        ; 44
    dq mn_label      ; 45
    times 4 dq mn_unk ; 46-49
    dq mn_call       ; 50
    dq mn_ret        ; 51
    dq mn_enter      ; 52
    dq mn_leave      ; 53
    dq mn_leave_nr   ; 54
    times 5 dq mn_unk ; 55-59
    dq mn_mov_rdi    ; 60
    dq mn_mov_rsi    ; 61
    dq mn_mov_rbx    ; 62
    dq mn_mov_rax_rdi ; 63
    dq mn_mov_rax_rsi ; 64
    dq mn_xor_eax    ; 65
    times 4 dq mn_unk ; 66-69
    dq mn_deref      ; 70
    dq mn_idx_ld     ; 71
    dq mn_idx_st     ; 72
mir_names_count equ 73

mn_unk: db "???",0
mn_iconst: db "ICONST",0
mn_sload: db "SLOAD",0
mn_sstore: db "SSTORE",0
mn_slea: db "SLEA",0
mn_push: db "PUSH",0
mn_pop_rbx: db "POP_RBX",0
mn_pop_rcx: db "POP_RCX",0
mn_pop_rdi: db "POP_RDI",0
mn_pop_rsi: db "POP_RSI",0
mn_pop_rdx: db "POP_RDX",0
mn_pop_r8: db "POP_R8",0
mn_pop_r9: db "POP_R9",0
mn_add: db "ADD",0
mn_sub: db "SUB",0
mn_mul: db "MUL",0
mn_xchg: db "XCHG",0
mn_cqo: db "CQO",0
mn_idiv: db "IDIV",0
mn_cmp_eq: db "CMP_EQ",0
mn_cmp_ne: db "CMP_NE",0
mn_cmp_lt: db "CMP_LT",0
mn_cmp_gt: db "CMP_GT",0
mn_cmp_le: db "CMP_LE",0
mn_cmp_ge: db "CMP_GE",0
mn_test: db "TEST",0
mn_jz: db "JZ",0
mn_jnz: db "JNZ",0
mn_jne: db "JNE",0
mn_jmp: db "JMP",0
mn_label: db "LABEL",0
mn_call: db "CALL",0
mn_ret: db "RET",0
mn_enter: db "ENTER",0
mn_leave: db "LEAVE",0
mn_leave_nr: db "LEAVE_NR",0
mn_mov_rdi: db "MOV_RDI_RAX",0
mn_mov_rsi: db "MOV_RSI_RAX",0
mn_mov_rbx: db "MOV_RBX_RAX",0
mn_mov_rax_rdi: db "MOV_RAX_RDI",0
mn_mov_rax_rsi: db "MOV_RAX_RSI",0
mn_xor_eax: db "XOR_EAX",0
mn_deref: db "DEREF",0
mn_idx_ld: db "IDX_LOAD",0
mn_idx_st: db "IDX_STORE",0

hex_chars: db "0123456789ABCDEF"

section .bss
stdout_h: resq 1
wr_tmp: resd 1
rd_tmp: resd 1
file_buf: resq 1
in_name: resb 260
num_buf: resb 32
hex_buf: resb 4
do_mir: resq 1
do_x86: resq 1
do_sym: resq 1

section .text
global _start
_start:
    and rsp, -16
    sub rsp, 32
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    add rsp, 32
    mov [stdout_h], rax
    mov qword[do_mir], 0
    mov qword[do_x86], 0
    mov qword[do_sym], 0

    lea rdi, [msg_ban]
    call pw

    call frontend_init
    call backend_init

    sub rsp, 32
    call GetCommandLineA
    add rsp, 32
    mov rsi, rax
    call skip_exe
    test rsi, rsi
    jz .usage
    lea rdi, [in_name]
    call copy_arg
    test rsi, rsi
    jz .defaults

    ; parse flags
.flags:
    call skip_ws
    test rsi, rsi
    jz .go
    lea rdi, [opt_mir]
    call cmp_opt
    test rax, rax
    jnz .f_mir
    lea rdi, [opt_x86]
    call cmp_opt
    test rax, rax
    jnz .f_x86
    lea rdi, [opt_sym]
    call cmp_opt
    test rax, rax
    jnz .f_sym
    lea rdi, [opt_all]
    call cmp_opt
    test rax, rax
    jnz .f_all
    jmp .go
.f_mir:
    mov qword[do_mir], 1
    jmp .flags
.f_x86:
    mov qword[do_x86], 1
    jmp .flags
.f_sym:
    mov qword[do_sym], 1
    jmp .flags
.f_all:
    mov qword[do_mir], 1
    mov qword[do_x86], 1
    mov qword[do_sym], 1
    jmp .flags
.defaults:
    mov qword[do_mir], 1
    mov qword[do_x86], 1
    mov qword[do_sym], 1

.go:
    ; read file
    mov rdi, INIT_SOURCE
    call vmem_alloc_local
    mov [file_buf], rax
    sub rsp, 64
    lea rcx, [in_name]
    mov rdx, GENERIC_READ
    mov r8d, FILE_SHARE_READ
    xor r9d, r9d
    mov dword[rsp+32], OPEN_EXISTING
    mov dword[rsp+40], FILE_ATTR_NORMAL
    mov qword[rsp+48], 0
    call CreateFileA
    add rsp, 64
    cmp rax, -1
    je .usage
    mov r12, rax
    sub rsp, 48
    mov rcx, r12
    mov rdx, [file_buf]
    mov r8d, INIT_SOURCE - 1
    lea r9, [rd_tmp]
    mov qword[rsp+32], 0
    call ReadFile
    add rsp, 48
    mov r13d, dword[rd_tmp]
    mov rdi, [file_buf]
    mov byte[rdi+r13], 0
    sub rsp, 32
    mov rcx, r12
    call CloseHandle
    add rsp, 32

    ; parse
    mov rsi, [file_buf]
    mov rdx, r13
    call frontend_run
    mov r14, rax

    ; lower
    mov qword[be_mod_root], r14
    mov qword[be_target], TARGET_WIN64
    call mir_init
    call x86_init
    call sym_init
    call lower_emit_runtime_win
    mov rdi, r14
    call lower_module
    call lower_emit_entry_win

    ; summary
    lea rdi, [msg_mir_cnt]
    call pw
    call mir_count
    call print_dec
    lea rdi, [msg_nl]
    call pw

    ; encode
    call x86_encode
    call x86_get_code
    push rsi
    push rdx
    lea rdi, [msg_code_sz]
    call pw
    pop rdx
    pop rsi
    push rsi
    push rdx
    mov rax, rdx
    call print_dec
    lea rdi, [msg_nl]
    call pw
    pop rdx
    pop rsi

    lea rdi, [msg_str_sz]
    call pw
    mov rax, [str_pool_pos]
    call print_dec
    lea rdi, [msg_nl]
    call pw

    ; dump MIR
    cmp qword[do_mir], 0
    je .no_mir
    call dump_mir
.no_mir:

    ; dump x86
    cmp qword[do_x86], 0
    je .no_x86
    call dump_x86
.no_x86:

    ; dump symbols
    cmp qword[do_sym], 0
    je .no_sym
    call dump_sym
.no_sym:

    xor ecx, ecx
    call ExitProcess

.usage:
    lea rdi, [msg_use]
    call pw
    xor ecx, ecx
    call ExitProcess

; ==================== MIR DUMP ====================

dump_mir:
    push rbx
    push r12
    lea rdi, [msg_mir_hdr]
    call pw
    xor r12, r12
.l: cmp r12, [mir_pos]
    jge .d
    lea rdi, [msg_mir_i]
    call pw
    mov rax, r12
    call print_dec
    lea rdi, [msg_mir_c]
    call pw
    ; get opcode
    imul rbx, r12, MIR_SIZE
    push r11
    mov r11, [mir_buf]
    mov rax, [r11+rbx]
    mov rcx, [r11+rbx+8]
    mov rdx, [r11+rbx+16]
    pop r11
    push rcx
    push rdx
    ; print opcode name
    cmp rax, mir_names_count
    jge .unk
    mov rdi, [mir_names+rax*8]
    jmp .pn
.unk:
    lea rdi, [mn_unk]
.pn:call pw
    ; print operands
    lea rdi, [msg_mir_a]
    call pw
    pop rdx
    pop rcx
    push rdx
    mov rax, rcx
    call print_dec
    lea rdi, [msg_mir_b]
    call pw
    pop rax
    call print_dec
    lea rdi, [msg_nl]
    call pw
    inc r12
    jmp .l
.d: pop r12
    pop rbx
    ret

; ==================== X86 HEX DUMP ====================

dump_x86:
    push rbx
    push r12
    push r13
    lea rdi, [msg_x86_hdr]
    call pw
    call x86_get_code
    mov r12, rsi
    mov r13, rdx
    xor rbx, rbx
.l: cmp rbx, r13
    jge .d
    ; print offset every 16 bytes
    mov rax, rbx
    and rax, 0xF
    test rax, rax
    jnz .nb
    ; newline + offset
    test rbx, rbx
    jz .first
    lea rdi, [msg_nl]
    call pw
.first:
    lea rdi, [msg_sp]
    call pw
    lea rdi, [msg_sp]
    call pw
    mov rax, rbx
    call print_hex16
    lea rdi, [msg_colon]
    call pw
.nb:
    movzx rax, byte[r12+rbx]
    call print_hex8
    lea rdi, [msg_sp]
    call pw
    inc rbx
    jmp .l
.d: lea rdi, [msg_nl]
    call pw
    pop r13
    pop r12
    pop rbx
    ret

; ==================== SYMBOL DUMP ====================

dump_sym:
    push rbx
    push r11
    lea rdi, [msg_sym_hdr]
    call pw
    xor rbx, rbx
.l: cmp rbx, [sym_count]
    jge .d
    lea rdi, [msg_sp]
    call pw
    lea rdi, [msg_sp]
    call pw
    ; print name
    mov r11, [sym_nptr]
    mov rsi, [r11+rbx*8]
    mov r11, [sym_nlen]
    mov rdx, [r11+rbx*8]
    call platform_write
    ; offset
    lea rdi, [msg_at]
    call pw
    mov r11, [sym_off]
    mov rax, [r11+rbx*8]
    call print_dec
    ; type
    lea rdi, [msg_ty]
    call pw
    mov r11, [sym_type]
    mov rax, [r11+rbx*8]
    call print_dec
    ; arrlen
    mov r11, [sym_arrlen]
    mov rax, [r11+rbx*8]
    test rax, rax
    jz .no_arr
    push rax
    lea rdi, [msg_arr]
    call pw
    pop rax
    call print_dec
.no_arr:
    lea rdi, [msg_nl]
    call pw
    inc rbx
    jmp .l
.d: pop r11
    pop rbx
    ret

; ==================== HELPERS ====================

extern vmem_alloc
vmem_alloc_local:
    jmp vmem_alloc

extern x86_init
extern str_pool_pos

print_dec:
    push rbx
    push rcx
    push rdx
    push rsi
    test rax, rax
    jns .pos
    push rax
    mov byte[num_buf], '-'
    mov rsi, num_buf
    mov rdx, 1
    call platform_write
    pop rax
    neg rax
.pos:
    test rax, rax
    jnz .nz
    mov byte[num_buf], '0'
    mov rsi, num_buf
    mov rdx, 1
    call platform_write
    jmp .end
.nz:xor rcx, rcx
    mov rbx, 10
.ext:test rax, rax
    jz .bld
    xor rdx, rdx
    div rbx
    add dl, '0'
    push rdx
    inc rcx
    jmp .ext
.bld:mov rbx, rcx
    xor rdx, rdx
.pop:test rcx, rcx
    jz .wr
    pop rax
    mov [num_buf+rdx], al
    inc rdx
    dec rcx
    jmp .pop
.wr:mov rsi, num_buf
    mov rdx, rbx
    call platform_write
.end:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

print_hex8:
    push rbx
    mov rbx, rax
    shr rax, 4
    and rax, 0xF
    movzx eax, byte[hex_chars+rax]
    mov [hex_buf], al
    mov rax, rbx
    and rax, 0xF
    movzx eax, byte[hex_chars+rax]
    mov [hex_buf+1], al
    mov rsi, hex_buf
    mov rdx, 2
    call platform_write
    pop rbx
    ret

print_hex16:
    push rbx
    mov rbx, rax
    shr rax, 12
    and rax, 0xF
    movzx eax, byte[hex_chars+rax]
    mov [hex_buf], al
    mov rax, rbx
    shr rax, 8
    and rax, 0xF
    movzx eax, byte[hex_chars+rax]
    mov [hex_buf+1], al
    mov rax, rbx
    shr rax, 4
    and rax, 0xF
    movzx eax, byte[hex_chars+rax]
    mov [hex_buf+2], al
    mov rax, rbx
    and rax, 0xF
    movzx eax, byte[hex_chars+rax]
    mov [hex_buf+3], al
    mov rsi, hex_buf
    mov rdx, 4
    call platform_write
    pop rbx
    ret

skip_exe:
    cmp byte[rsi], '"'
    jne .unq
    inc rsi
.sq:cmp byte[rsi], 0
    je .fail
    cmp byte[rsi], '"'
    je .eq
    inc rsi
    jmp .sq
.eq:inc rsi
    jmp skip_ws
.unq:
    cmp byte[rsi], ' '
    je .ws
    cmp byte[rsi], 0
    je .fail
    inc rsi
    jmp .unq
.ws:jmp skip_ws
.fail:
    xor rsi, rsi
    ret

skip_ws:
    cmp byte[rsi], ' '
    jne .d
    inc rsi
    jmp skip_ws
.d: cmp byte[rsi], 0
    jne .ok
    xor rsi, rsi
.ok:ret

copy_arg:
    xor rcx, rcx
.l: mov al, [rsi+rcx]
    cmp al, 0
    je .d
    cmp al, ' '
    je .d
    mov [rdi+rcx], al
    inc rcx
    jmp .l
.d: mov byte[rdi+rcx], 0
    add rsi, rcx
    call skip_ws
    ret

cmp_opt:
    push rbx
    push rcx
    xor rcx, rcx
.l: mov al, [rdi+rcx]
    test al, al
    jz .check
    cmp al, [rsi+rcx]
    jne .no
    inc rcx
    jmp .l
.check:
    mov al, [rsi+rcx]
    cmp al, ' '
    je .yes
    cmp al, 0
    je .yes
.no:xor rax, rax
    pop rcx
    pop rbx
    ret
.yes:
    lea rsi, [rsi+rcx]
    call skip_ws
    mov rax, 1
    pop rcx
    pop rbx
    ret

pw: push rsi
    push rdx
    mov rsi, rdi
    xor rdx, rdx
.l: cmp byte[rsi+rdx], 0
    je .g
    inc rdx
    jmp .l
.g: call platform_write
    pop rdx
    pop rsi
    ret

platform_write:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    sub rsp, 48
    mov rcx, [stdout_h]
    mov rdx, r12
    mov r8, r13
    lea r9, [wr_tmp]
    mov qword[rsp+32], 0
    call WriteFile
    add rsp, 48
    pop r13
    pop r12
    pop rbx
    ret