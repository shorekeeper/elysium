; Converts parsed AST into flat MIR instructions for x86 encoding.
; Handles: functions, clauses, pattern matching, guards, statements,
; expressions, records, unions, borrows, anchors, pools, strings.
default rel
%include "defs.inc"
extern mir_emit, mir_emit2, mir_new_label
extern sym_init, sym_push, sym_push_arr, sym_lookup, sym_get_index
extern sym_leave_scope, sym_alloc_bytes, sym_depth
extern sym_bstate, sym_bcnt, sym_alias, sym_off, sym_count
extern sym_type, sym_set_last_type, sym_arrlen
extern sym_rec_type, sym_set_rec_type
extern anc_push, anc_lookup, anc_pop
extern be_mod_root, be_target, ely_memcmp
extern treg_init, treg_define, treg_lookup, treg_field_index
extern treg_field_count, treg_total_size
extern treg_define_union, treg_lookup_variant
extern treg_foff, treg_ftype
extern type_size
extern vmem_alloc
global lower_module
global lower_emit_runtime_win, lower_emit_entry_win
global lower_emit_runtime_linux, lower_emit_entry_linux
global lower_entry_label
global str_pool, str_pool_pos

; local limit for done/fn tables (these are compiler-internal,
; not user-facing -- 4096 function names is plenty)
LOWER_MAX equ 4096
LOWER_STR_POOL equ 0x10000

section .bss
clause_ptrs: resq MAX_CLAUSES
clause_cnt:  resq 1
done_nptr:   resq LOWER_MAX
done_nlen:   resq LOWER_MAX
done_cnt:    resq 1
fn_nptr:     resq LOWER_MAX
fn_nlen:     resq LOWER_MAX
fn_label:    resq LOWER_MAX
fn_count:    resq 1
rt_init_label:       resq 1
rt_print_label:      resq 1
rt_pstr_label:       resq 1
rt_ckpt_save_label:  resq 1
rt_ckpt_restore_label: resq 1
rt_claim_label:      resq 1
rt_release_label:    resq 1
rt_pool_create_label: resq 1
rt_pool_claim_label:  resq 1
rt_pool_drain_label:  resq 1
lower_entry_label:   resq 1
str_pool:        resb LOWER_STR_POOL
str_pool_pos:    resq 1
; temporaries for record field lowering
arr_elem_type: resq 1
arr_elem_size: resq 1
rec_fld_off:   resq 1
rec_fld_type:  resq 1

section .data
nm_main: db "main"
nm_main_len equ 4

; checkpoint save/restore raw x86 bytes
rt_ckpt_save_bytes:
    db 0x48,0x89,0x1F
    db 0x48,0x89,0x6F,0x08
    db 0x4C,0x89,0x67,0x10
    db 0x4C,0x89,0x6F,0x18
    db 0x4C,0x89,0x77,0x20
    db 0x4C,0x89,0x7F,0x28
    db 0x48,0x8D,0x44,0x24,0x08
    db 0x48,0x89,0x47,0x30
    db 0x48,0x8B,0x04,0x24
    db 0x48,0x89,0x47,0x38
    db 0x31,0xC0
    db 0xC3
rt_ckpt_save_bytes_len equ $ - rt_ckpt_save_bytes

rt_ckpt_restore_bytes:
    db 0x48,0x8B,0x1F
    db 0x48,0x8B,0x6F,0x08
    db 0x4C,0x8B,0x67,0x10
    db 0x4C,0x8B,0x6F,0x18
    db 0x4C,0x8B,0x77,0x20
    db 0x4C,0x8B,0x7F,0x28
    db 0x48,0x8B,0x67,0x30
    db 0x48,0x89,0xF0
    db 0x48,0x85,0xC0
    db 0x75,0x03
    db 0x48,0xFF,0xC0
    db 0xFF,0x67,0x38
rt_ckpt_restore_bytes_len equ $ - rt_ckpt_restore_bytes

; Windows print_int number conversion block
rt_win_prt_conv:
    db 0x53,0x41,0x54,0x41,0x55
    db 0x49,0x89,0xFC
    db 0x48,0x83,0xEC,0x40
    db 0x48,0x8D,0x5C,0x24,0x37
    db 0xC6,0x03,0x0A
    db 0x4C,0x89,0xE0
    db 0x48,0x85,0xC0,0x79,0x03,0x48,0xF7,0xD8
    db 0x31,0xC9,0xFF,0xC1
    db 0x49,0xC7,0xC5,0x0A,0x00,0x00,0x00
    db 0x31,0xD2,0x49,0xF7,0xF5,0x80,0xC2,0x30
    db 0x48,0xFF,0xCB,0x88,0x13,0xFF,0xC1
    db 0x48,0x85,0xC0,0x75,0xEC
    db 0x4D,0x85,0xE4,0x79,0x08
    db 0x48,0xFF,0xCB,0xC6,0x03,0x2D,0xFF,0xC1
    db 0x41,0x89,0xCD
rt_win_prt_conv_len equ $ - rt_win_prt_conv

rt_win_prt_args1:
    db 0x48,0x89,0xC1,0x48,0x89,0xDA,0x4D,0x89,0xE8
rt_win_prt_args1_len equ $ - rt_win_prt_args1

rt_win_wf_args2:
    db 0x49,0x89,0xC1
    db 0x48,0xC7,0x44,0x24,0x20,0x00,0x00,0x00,0x00
rt_win_wf_args2_len equ $ - rt_win_wf_args2

rt_win_prt_epilog:
    db 0x41,0x5D,0x41,0x5C,0x5B
rt_win_prt_epilog_len equ $ - rt_win_prt_epilog

rt_win_pstr_args1:
    db 0x48,0x89,0xC1,0x48,0x89,0xFA,0x49,0x89,0xF0
rt_win_pstr_args1_len equ $ - rt_win_pstr_args1

rt_win_entry_align:
    db 0x48,0x83,0xE4,0xF0
rt_win_entry_align_len equ $ - rt_win_entry_align

rt_win_mov_ecx_eax:
    db 0x89,0xC1
rt_win_mov_ecx_eax_len equ $ - rt_win_mov_ecx_eax

; Windows claim/release raw bytes
rt_win_claim_pre:
    db 0x53,0x48,0x8D,0x5F,0x08
rt_win_claim_pre_len equ $ - rt_win_claim_pre

rt_win_claim_args:
    db 0x31,0xC9,0x48,0x89,0xDA
    db 0x41,0xB8,0x00,0x30,0x00,0x00
    db 0x41,0xB9,0x04,0x00,0x00,0x00
rt_win_claim_args_len equ $ - rt_win_claim_args

rt_win_claim_ok:
    db 0x48,0x89,0x18,0x48,0x83,0xC0,0x08,0x5B
rt_win_claim_ok_len equ $ - rt_win_claim_ok

rt_win_claim_fail:
    db 0x5B
rt_win_claim_fail_len equ $ - rt_win_claim_fail

rt_win_release_pre:
    db 0x48,0x83,0xEF,0x08
rt_win_release_pre_len equ $ - rt_win_release_pre

rt_win_release_args:
    db 0x31,0xD2,0x41,0xB8,0x00,0x80,0x00,0x00
rt_win_release_args_len equ $ - rt_win_release_args

; Windows pool_create
rt_win_pcreate_pre:
    db 0x53,0x48,0x8D,0x5F,0x10
rt_win_pcreate_pre_len equ $ - rt_win_pcreate_pre

rt_win_pcreate_ok:
    db 0x48,0x83,0xEB,0x10
    db 0x48,0x89,0x18
    db 0x48,0xC7,0x40,0x08,0x00,0x00,0x00,0x00
    db 0x5B
rt_win_pcreate_ok_len equ $ - rt_win_pcreate_ok

; pool_claim (platform-independent)
rt_pool_claim_bytes:
    db 0x48,0x8B,0x47,0x08
    db 0x48,0x89,0xC1
    db 0x48,0x01,0xF1
    db 0x48,0x3B,0x0F
    db 0x77,0x0A
    db 0x48,0x89,0x4F,0x08
    db 0x48,0x8D,0x44,0x07,0x10
    db 0xC3
    db 0x31,0xC0
    db 0xC3
rt_pool_claim_bytes_len equ $ - rt_pool_claim_bytes

; Linux runtime raw bytes
rt_linux_print:
    db 0x53,0x41,0x54,0x49,0x89,0xFC
    db 0x48,0x83,0xEC,0x20
    db 0x48,0x8D,0x5C,0x24,0x1F,0xC6,0x03,0x0A
    db 0x4C,0x89,0xE0,0x48,0x85,0xC0,0x79,0x03,0x48,0xF7,0xD8
    db 0x31,0xC9,0xFF,0xC1
    db 0x41,0x50,0x41,0xB8,0x0A,0x00,0x00,0x00
    db 0x31,0xD2,0x49,0xF7,0xF0,0x80,0xC2,0x30
    db 0x48,0xFF,0xCB,0x88,0x13,0xFF,0xC1
    db 0x48,0x85,0xC0,0x75,0xEC
    db 0x41,0x58,0x4D,0x85,0xE4,0x79,0x07
    db 0x48,0xFF,0xCB,0xC6,0x03,0x2D,0xFF,0xC1
    db 0xB8,0x01,0x00,0x00,0x00,0xBF,0x01,0x00,0x00,0x00
    db 0x48,0x89,0xDE,0x89,0xCA,0x0F,0x05
    db 0x48,0x83,0xC4,0x20,0x41,0x5C,0x5B,0xC3
rt_linux_print_len equ $ - rt_linux_print

rt_linux_pstr:
    db 0x48,0x89,0xF2,0x48,0x89,0xFE
    db 0xBF,0x01,0x00,0x00,0x00,0xB8,0x01,0x00,0x00,0x00
    db 0x0F,0x05,0xC3
rt_linux_pstr_len equ $ - rt_linux_pstr

rt_linux_claim:
    db 0x53,0x48,0x8D,0x5F,0x08
    db 0x31,0xFF,0x48,0x89,0xDE
    db 0xBA,0x03,0x00,0x00,0x00
    db 0x41,0xBA,0x22,0x00,0x00,0x00
    db 0x49,0xC7,0xC0,0xFF,0xFF,0xFF,0xFF
    db 0x45,0x31,0xC9
    db 0xB8,0x09,0x00,0x00,0x00,0x0F,0x05
    db 0x48,0x85,0xC0,0x78,0x09
    db 0x48,0x89,0x18,0x48,0x83,0xC0,0x08,0x5B,0xC3
    db 0x31,0xC0,0x5B,0xC3
rt_linux_claim_len equ $ - rt_linux_claim

rt_linux_release:
    db 0x48,0x83,0xEF,0x08
    db 0x48,0x8B,0x37
    db 0xB8,0x0B,0x00,0x00,0x00,0x0F,0x05,0xC3
rt_linux_release_len equ $ - rt_linux_release

rt_linux_pcreate:
    db 0x53,0x48,0x8D,0x5F,0x10
    db 0x31,0xFF,0x48,0x89,0xDE
    db 0xBA,0x03,0x00,0x00,0x00
    db 0x41,0xBA,0x22,0x00,0x00,0x00
    db 0x49,0xC7,0xC0,0xFF,0xFF,0xFF,0xFF
    db 0x45,0x31,0xC9
    db 0xB8,0x09,0x00,0x00,0x00,0x0F,0x05
    db 0x48,0x85,0xC0,0x78,0x11
    db 0x48,0x83,0xEB,0x10
    db 0x48,0x89,0x18
    db 0x48,0xC7,0x40,0x08,0x00,0x00,0x00,0x00
    db 0x5B,0xC3
    db 0x31,0xC0,0x5B,0xC3
rt_linux_pcreate_len equ $ - rt_linux_pcreate

rt_linux_pdrain:
    db 0x48,0x8B,0x37
    db 0x48,0x83,0xC6,0x10
    db 0xB8,0x0B,0x00,0x00,0x00,0x0F,0x05,0xC3
rt_linux_pdrain_len equ $ - rt_linux_pdrain

section .text

; helpers
str_pool_init:
    mov qword[str_pool_pos], 0
    ret

; str_pool_register: rsi=src, rcx=len -> rax=pool offset
str_pool_register:
    push rdi
    push rcx
    mov rax, [str_pool_pos]
    lea rdi, [str_pool]
    add rdi, rax
    rep movsb
    pop rcx
    add [str_pool_pos], rcx
    pop rdi
    ret

; shorthand: emit MIR with 3 operands
m3:  jmp mir_emit
; shorthand: emit MIR with op2=0
m2:  xor rdx, rdx
     jmp mir_emit

; resolve type annotation from let node, default to i64
resolve_let_type:
    mov rax, [r12+8]
    cmp rax, TYPE_INFER
    jne .ok
    mov rax, TYPE_I64
.ok:ret

; ==================== SYMTAB INDIRECT HELPERS ====================
; sym_off etc. are now pointers to heap arrays.
; These macros load the pointer, index it, and return the value.
; We use r11 as scratch (caller must not be using it).

; load sym field into rax: field_ptr, index_reg
%macro sym_load 2
    push r11
    mov r11, [%1]
    mov rax, [r11+%2*8]
    pop r11
%endmacro

; store rax into sym field: field_ptr, index_reg
%macro sym_store 2
    push r11
    mov r11, [%1]
    mov [r11+%2*8], rax
    pop r11
%endmacro

; ==================== WINDOWS RUNTIME ====================

lower_emit_runtime_win:
    push rbx
    call str_pool_init
    call mir_new_label
    mov [rt_init_label], rax
    call mir_new_label
    mov [rt_print_label], rax
    call mir_new_label
    mov [rt_pstr_label], rax
    call mir_new_label
    mov [rt_ckpt_save_label], rax
    call mir_new_label
    mov [rt_ckpt_restore_label], rax
    call mir_new_label
    mov [rt_claim_label], rax
    call mir_new_label
    mov [rt_release_label], rax
    call mir_new_label
    mov [rt_pool_create_label], rax
    call mir_new_label
    mov [rt_pool_claim_label], rax
    call mir_new_label
    mov [rt_pool_drain_label], rax

    ; __rt_init: GetStdHandle(-11) -> store stdout
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_init_label]
    call m2
    mov rdi,MIR_SUB_RSP
    mov rsi,40
    call m2
    mov rdi,MIR_MOV_RCX_IMM
    mov rsi,0xFFFFFFF5
    call m2
    mov rdi,MIR_CALL_IAT
    mov rsi,IAT_GETSTD
    call m2
    mov rdi,MIR_ADD_RSP
    mov rsi,40
    call m2
    mov rdi,MIR_STORE_DATA
    mov rsi,DATA_STDOUT
    call m2
    mov rdi,MIR_RET
    xor rsi,rsi
    call m2

    ; __rt_print_int: convert rdi to decimal string, call WriteFile
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_print_label]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_prt_conv]
    mov rdx,rt_win_prt_conv_len
    call m3
    mov rdi,MIR_SUB_RSP
    mov rsi,48
    call m2
    mov rdi,MIR_LOAD_DATA
    mov rsi,DATA_STDOUT
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_prt_args1]
    mov rdx,rt_win_prt_args1_len
    call m3
    mov rdi,MIR_LEA_DATA
    mov rsi,DATA_WRITTEN
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_wf_args2]
    mov rdx,rt_win_wf_args2_len
    call m3
    mov rdi,MIR_CALL_IAT
    mov rsi,IAT_WRITE
    call m2
    mov rdi,MIR_ADD_RSP
    mov rsi,48
    call m2
    mov rdi,MIR_ADD_RSP
    mov rsi,64
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_prt_epilog]
    mov rdx,rt_win_prt_epilog_len
    call m3
    mov rdi,MIR_RET
    xor rsi,rsi
    call m2

    ; __rt_print_str: write rdi=buf rsi=len via WriteFile
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_pstr_label]
    call m2
    mov rdi,MIR_SUB_RSP
    mov rsi,40
    call m2
    mov rdi,MIR_LOAD_DATA
    mov rsi,DATA_STDOUT
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_pstr_args1]
    mov rdx,rt_win_pstr_args1_len
    call m3
    mov rdi,MIR_LEA_DATA
    mov rsi,DATA_WRITTEN
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_wf_args2]
    mov rdx,rt_win_wf_args2_len
    call m3
    mov rdi,MIR_CALL_IAT
    mov rsi,IAT_WRITE
    call m2
    mov rdi,MIR_ADD_RSP
    mov rsi,40
    call m2
    mov rdi,MIR_RET
    xor rsi,rsi
    call m2

    ; __rt_ckpt_save / restore
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_ckpt_save_label]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_ckpt_save_bytes]
    mov rdx,rt_ckpt_save_bytes_len
    call m3
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_ckpt_restore_label]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_ckpt_restore_bytes]
    mov rdx,rt_ckpt_restore_bytes_len
    call m3

    ; __rt_claim: VirtualAlloc wrapper
    call mir_new_label
    push rax
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_claim_label]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_claim_pre]
    mov rdx,rt_win_claim_pre_len
    call m3
    mov rdi,MIR_SUB_RSP
    mov rsi,32
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_claim_args]
    mov rdx,rt_win_claim_args_len
    call m3
    mov rdi,MIR_CALL_IAT
    mov rsi,IAT_VALLOC
    call m2
    mov rdi,MIR_ADD_RSP
    mov rsi,32
    call m2
    mov rdi,MIR_TEST
    xor rsi,rsi
    call m2
    mov rdi,MIR_JZ
    mov rsi,[rsp]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_claim_ok]
    mov rdx,rt_win_claim_ok_len
    call m3
    mov rdi,MIR_RET
    xor rsi,rsi
    call m2
    pop rax
    mov rdi,MIR_LABEL
    mov rsi,rax
    call m2
    mov rdi,MIR_XOR_EAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_claim_fail]
    mov rdx,rt_win_claim_fail_len
    call m3
    mov rdi,MIR_RET
    xor rsi,rsi
    call m2

    ; __rt_release: VirtualFree wrapper
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_release_label]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_release_pre]
    mov rdx,rt_win_release_pre_len
    call m3
    mov rdi,MIR_SUB_RSP
    mov rsi,32
    call m2
    mov rdi,MIR_MOV_RCX_RDI
    xor rsi,rsi
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_release_args]
    mov rdx,rt_win_release_args_len
    call m3
    mov rdi,MIR_CALL_IAT
    mov rsi,IAT_VFREE
    call m2
    mov rdi,MIR_ADD_RSP
    mov rsi,32
    call m2
    mov rdi,MIR_RET
    xor rsi,rsi
    call m2

    ; __rt_pool_create
    call mir_new_label
    push rax
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_pool_create_label]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_pcreate_pre]
    mov rdx,rt_win_pcreate_pre_len
    call m3
    mov rdi,MIR_SUB_RSP
    mov rsi,32
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_claim_args]
    mov rdx,rt_win_claim_args_len
    call m3
    mov rdi,MIR_CALL_IAT
    mov rsi,IAT_VALLOC
    call m2
    mov rdi,MIR_ADD_RSP
    mov rsi,32
    call m2
    mov rdi,MIR_TEST
    xor rsi,rsi
    call m2
    mov rdi,MIR_JZ
    mov rsi,[rsp]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_pcreate_ok]
    mov rdx,rt_win_pcreate_ok_len
    call m3
    mov rdi,MIR_RET
    xor rsi,rsi
    call m2
    pop rax
    mov rdi,MIR_LABEL
    mov rsi,rax
    call m2
    mov rdi,MIR_XOR_EAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_claim_fail]
    mov rdx,rt_win_claim_fail_len
    call m3
    mov rdi,MIR_RET
    xor rsi,rsi
    call m2

    ; __rt_pool_claim
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_pool_claim_label]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_pool_claim_bytes]
    mov rdx,rt_pool_claim_bytes_len
    call m3

    ; __rt_pool_drain
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_pool_drain_label]
    call m2
    mov rdi,MIR_SUB_RSP
    mov rsi,32
    call m2
    mov rdi,MIR_MOV_RCX_RDI
    xor rsi,rsi
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_release_args]
    mov rdx,rt_win_release_args_len
    call m3
    mov rdi,MIR_CALL_IAT
    mov rsi,IAT_VFREE
    call m2
    mov rdi,MIR_ADD_RSP
    mov rsi,32
    call m2
    mov rdi,MIR_RET
    xor rsi,rsi
    call m2

    pop rbx
    ret

; ==================== WINDOWS ENTRY ====================

lower_emit_entry_win:
    push rbx
    call mir_new_label
    mov [lower_entry_label],rax
    mov rdi,MIR_LABEL
    mov rsi,rax
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_entry_align]
    mov rdx,rt_win_entry_align_len
    call m3
    mov rdi,MIR_SUB_RSP
    mov rsi,32
    call m2
    mov rdi,MIR_CALL
    mov rsi,[rt_init_label]
    call m2
    lea rsi,[nm_main]
    mov rcx,nm_main_len
    call fn_lookup_label
    mov rdi,MIR_CALL
    mov rsi,rax
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_win_mov_ecx_eax]
    mov rdx,rt_win_mov_ecx_eax_len
    call m3
    mov rdi,MIR_CALL_IAT
    mov rsi,IAT_EXIT
    call m2
    pop rbx
    ret

; ==================== LINUX RUNTIME ====================

lower_emit_runtime_linux:
    push rbx
    call str_pool_init
    call mir_new_label
    mov [rt_print_label],rax
    call mir_new_label
    mov [rt_pstr_label],rax
    call mir_new_label
    mov [rt_ckpt_save_label],rax
    call mir_new_label
    mov [rt_ckpt_restore_label],rax
    call mir_new_label
    mov [rt_claim_label],rax
    call mir_new_label
    mov [rt_release_label],rax
    call mir_new_label
    mov [rt_pool_create_label],rax
    call mir_new_label
    mov [rt_pool_claim_label],rax
    call mir_new_label
    mov [rt_pool_drain_label],rax
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_print_label]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_linux_print]
    mov rdx,rt_linux_print_len
    call m3
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_pstr_label]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_linux_pstr]
    mov rdx,rt_linux_pstr_len
    call m3
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_ckpt_save_label]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_ckpt_save_bytes]
    mov rdx,rt_ckpt_save_bytes_len
    call m3
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_ckpt_restore_label]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_ckpt_restore_bytes]
    mov rdx,rt_ckpt_restore_bytes_len
    call m3
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_claim_label]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_linux_claim]
    mov rdx,rt_linux_claim_len
    call m3
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_release_label]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_linux_release]
    mov rdx,rt_linux_release_len
    call m3
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_pool_create_label]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_linux_pcreate]
    mov rdx,rt_linux_pcreate_len
    call m3
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_pool_claim_label]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_pool_claim_bytes]
    mov rdx,rt_pool_claim_bytes_len
    call m3
    mov rdi,MIR_FUNC_LABEL
    mov rsi,[rt_pool_drain_label]
    call m2
    mov rdi,MIR_RAW_BYTES
    lea rsi,[rt_linux_pdrain]
    mov rdx,rt_linux_pdrain_len
    call m3
    pop rbx
    ret

; ==================== LINUX ENTRY ====================

lower_emit_entry_linux:
    push rbx
    call mir_new_label
    mov [lower_entry_label],rax
    mov rdi,MIR_LABEL
    mov rsi,rax
    call m2
    lea rsi,[nm_main]
    mov rcx,nm_main_len
    call fn_lookup_label
    mov rdi,MIR_CALL
    mov rsi,rax
    call m2
    mov rdi,MIR_MOV_RDI_RAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_ICONST
    mov rsi,60
    call m2
    mov rdi,MIR_SYSCALL
    xor rsi,rsi
    call m2
    pop rbx
    ret

; ==================== FUNCTION TABLE ====================

fn_register:
    push rbx
    call fn_lookup_label
    cmp rax,-1
    jne .found
    call mir_new_label
    mov rbx,[fn_count]
    mov [fn_nptr+rbx*8],rsi
    mov [fn_nlen+rbx*8],rcx
    mov [fn_label+rbx*8],rax
    inc qword[fn_count]
.found:
    pop rbx
    ret

fn_lookup_label:
    push rbx
    push rdi
    push rsi
    push rcx
    push r8
    push r9
    mov r8,rsi
    mov r9,rcx
    mov rbx,[fn_count]
.l: test rbx,rbx
    jz .nf
    dec rbx
    cmp r9,[fn_nlen+rbx*8]
    jne .l
    mov rsi,r8
    mov rdi,[fn_nptr+rbx*8]
    mov rcx,r9
    call ely_memcmp
    test rax,rax
    jnz .l
    mov rax,[fn_label+rbx*8]
    jmp .d
.nf:mov rax,-1
.d: pop r9
    pop r8
    pop rcx
    pop rsi
    pop rdi
    pop rbx
    ret

is_done:
    push rbx
    push rdi
    push rsi
    push rcx
    push r8
    push r9
    mov r8,rsi
    mov r9,rcx
    mov rbx,[done_cnt]
.l: test rbx,rbx
    jz .nf
    dec rbx
    cmp r9,[done_nlen+rbx*8]
    jne .l
    mov rsi,r8
    mov rdi,[done_nptr+rbx*8]
    mov rcx,r9
    call ely_memcmp
    test rax,rax
    jnz .l
    mov rax,1
    jmp .d
.nf:xor rax,rax
.d: pop r9
    pop r8
    pop rcx
    pop rsi
    pop rdi
    pop rbx
    ret

mark_done:
    push rax
    mov rax,[done_cnt]
    mov [done_nptr+rax*8],rsi
    mov [done_nlen+rax*8],rcx
    inc qword[done_cnt]
    pop rax
    ret

collect:
    push rbx
    push rdi
    push rsi
    push rcx
    push r8
    push r9
    mov r8,rsi
    mov r9,rcx
    mov qword[clause_cnt],0
    mov rdi,[be_mod_root]
    test rdi,rdi
    jz .d
    mov rbx,[rdi+16]
.l: test rbx,rbx
    jz .d
    cmp qword[rbx],NODE_FUNC
    jne .nx
    cmp r9,[rbx+56]
    jne .nx
    mov rsi,r8
    mov rdi,[rbx+48]
    mov rcx,r9
    push rbx
    call ely_memcmp
    pop rbx
    test rax,rax
    jnz .nx
    mov rax,[clause_cnt]
    mov [clause_ptrs+rax*8],rbx
    inc qword[clause_cnt]
.nx:mov rbx,[rbx+32]
    jmp .l
.d: pop r9
    pop r8
    pop rcx
    pop rsi
    pop rdi
    pop rbx
    ret

; ==================== MODULE ====================

lower_module:
    push rbx
    push r12
    call treg_init
    mov qword[done_cnt],0
    mov qword[fn_count],0
    test rdi,rdi
    jz .end
    ; first pass: register all function names and type definitions
    mov r12,[rdi+16]
.reg:test r12,r12
    jz .comp
    cmp qword[r12],NODE_FUNC
    je .reg_fn
    cmp qword[r12],NODE_TYPE_DEF
    je .reg_ty
    cmp qword[r12],NODE_UNION_DEF
    je .reg_union
    jmp .rnx
.reg_fn:
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call fn_register
    jmp .rnx
.reg_ty:
    mov rdi,r12
    call treg_define
    jmp .rnx
.reg_union:
    mov rdi,r12
    call treg_define_union
.rnx:mov r12,[r12+32]
    jmp .reg
    ; second pass: compile function groups
.comp:
    mov rdi,[be_mod_root]
    mov r12,[rdi+16]
.lp:test r12,r12
    jz .end
    cmp qword[r12],NODE_FUNC
    jne .nx
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call is_done
    test rax,rax
    jnz .nx
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call collect
    call lower_func_group
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call mark_done
.nx:mov r12,[r12+32]
    jmp .lp
.end:pop r12
    pop rbx
    ret

; ==================== FUNC GROUP ====================

lower_func_group:
    push rbx
    push r12
    push r13
    mov rax,[clause_ptrs]
    mov rsi,[rax+48]
    mov rcx,[rax+56]
    call fn_lookup_label
    mov rdi,MIR_FUNC_LABEL
    mov rsi,rax
    call m2
    xor r12,r12
.lp:cmp r12,[clause_cnt]
    jge .done
    mov r13,[clause_ptrs+r12*8]
    call lower_clause
    inc r12
    jmp .lp
.done:
    ; fallthrough: return 0
    mov rdi,MIR_XOR_EAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_RET
    xor rsi,rsi
    call m2
    pop r13
    pop r12
    pop rbx
    ret

; ==================== CLAUSE ====================
; r13 = function clause AST node

lower_clause:
    push rbx
    push rcx
    push r14
    push r15
    call mir_new_label
    mov r14,rax                ; skip label (jump here if clause doesn't match)
    call sym_init
    inc qword[sym_depth]
    ; emit function prologue
    mov rdi,MIR_ENTER
    mov rsi,FRAME_SIZE
    call m2
    ; bind parameters from registers to stack slots
    xor r15,r15                ; parameter index
    mov rbx,[r13+24]           ; first param node
.par:test rbx,rbx
    jz .pd
    cmp r15,6
    jge .pd
    cmp qword[rbx],NODE_PARAM
    je .pvar
    cmp qword[rbx],NODE_NUMBER
    je .plit
    jmp .pnx
.pvar:
    ; named parameter: allocate slot, move register value to stack
    mov rsi,[rbx+48]
    mov rcx,[rbx+56]
    call sym_push
    push rax
    push rbx
    push r15
    cmp r15,0
    je .a_rdi
    cmp r15,1
    je .a_rsi
    cmp r15,2
    je .a_rdx
    jmp .a_done
.a_rdi:
    mov rdi,MIR_MOV_RAX_RDI
    xor rsi,rsi
    call m2
    jmp .a_done
.a_rsi:
    mov rdi,MIR_MOV_RAX_RSI
    xor rsi,rsi
    call m2
    jmp .a_done
.a_rdx:
    ; no dedicated MIR opcode, emit raw: mov rax, rdx (48 89 D0)
    push rax
    sub rsp,8
    mov byte[rsp],0x48
    mov byte[rsp+1],0x89
    mov byte[rsp+2],0xD0
    mov rdi,MIR_RAW_BYTES
    mov rsi,rsp
    mov rdx,3
    call m3
    add rsp,8
    pop rax
.a_done:
    pop r15
    pop rbx
    pop rax
    mov rdi,MIR_SSTORE
    mov rsi,rax
    call m2
    jmp .pnx
.plit:
    ; literal pattern: store arg, then compare against literal value
    push rbx
    push r15
    mov rdi,8
    call sym_alloc_bytes
    pop r15
    pop rbx
    push rax
    push rbx
    push r15
    cmp r15,0
    je .pl_rdi
    cmp r15,1
    je .pl_rsi
    jmp .pl_done
.pl_rdi:
    mov rdi,MIR_MOV_RAX_RDI
    xor rsi,rsi
    call m2
    jmp .pl_done
.pl_rsi:
    mov rdi,MIR_MOV_RAX_RSI
    xor rsi,rsi
    call m2
.pl_done:
    pop r15
    pop rbx
    pop rax
    push rax
    mov rdi,MIR_SSTORE
    mov rsi,rax
    call m2
    pop rax
    ; cmp [rbp-off], literal_value
    mov rdi,MIR_CMP_MEM_IMM
    mov rsi,rax
    mov rdx,[rbx+8]
    call m3
    ; if not equal, skip to next clause
    mov rdi,MIR_JNE
    mov rsi,r14
    call m2
.pnx:inc r15
    mov rbx,[rbx+32]
    jmp .par
.pd:
    ; guard expression (if present)
    mov rax,[r13+8]
    test rax,rax
    jz .ng
    mov rdi,rax
    call lower_expr
    mov rdi,MIR_TEST
    xor rsi,rsi
    call m2
    mov rdi,MIR_JZ
    mov rsi,r14
    call m2
.ng:
    ; compile function body
    mov rdi,[r13+16]
    call lower_stmt_list
    ; epilogue with return
    mov rdi,MIR_LEAVE
    xor rsi,rsi
    call m2
    ; skip label: fallthrough to next clause attempt
    mov rdi,MIR_LABEL
    mov rsi,r14
    call m2
    ; epilogue without ret (restore frame for next clause)
    mov rdi,MIR_LEAVE_NRET
    xor rsi,rsi
    call m2
    call sym_leave_scope
    dec qword[sym_depth]
    pop r15
    pop r14
    pop rcx
    pop rbx
    ret

; ==================== STATEMENTS ====================

lower_stmt_list:
    push rbx
    push r12
    mov r12,rdi
.l: test r12,r12
    jz .d
    mov rdi,r12
    call lower_stmt
    mov r12,[r12+32]
    jmp .l
.d: pop r12
    pop rbx
    ret

lower_stmt:
    push rbx
    push rcx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov rax,[r12]
    cmp rax,NODE_LET
    je .let
    cmp rax,NODE_RETURN
    je .ret
    cmp rax,NODE_PRINT
    je .prn
    cmp rax,NODE_PRINT_STR
    je .pstr
    cmp rax,NODE_IF
    je .if_
    cmp rax,NODE_INDEX_SET
    je .idx_set
    cmp rax,NODE_MATCH
    je .match
    cmp rax,NODE_ANCHOR
    je .anchor
    cmp rax,NODE_SUPERVISE
    je .super
    cmp rax,NODE_UNWIND
    je .unwind
    cmp rax,NODE_STORE
    je .store_
    cmp rax,NODE_RELEASE
    je .release_
    cmp rax,NODE_RELEASE_G
    je .release_
    cmp rax,NODE_POOL_DRAIN
    je .pdrain
    cmp rax,NODE_FIELD_SET
    je .field_set
    cmp rax,NODE_RAW
    je .raw_blk
    jmp .done

; ---- let ----
.let:
    mov rdi,[r12+16]
    test rdi,rdi
    jz .done
    cmp qword[rdi],NODE_ARRAY
    je .let_arr
    cmp qword[rdi],NODE_RECORD_LIT
    je .let_rec
    cmp qword[rdi],NODE_BORROW
    je .let_brw
    ; check if RHS is a variant constructor call
    cmp qword[rdi],NODE_CALL
    jne .let_scalar
    push rdi
    mov rsi,[rdi+48]
    mov rcx,[rdi+56]
    call treg_lookup_variant
    pop rdi
    cmp rax,-1
    je .let_scalar
    jmp .let_variant

; plain scalar: let name [:: type] = expr;
.let_scalar:
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call sym_push
    mov r13,rax
    ; set type annotation
    call resolve_let_type
    mov rdi,rax
    call sym_set_last_type
    ; compile initializer expression
    mov rdi,[r12+16]
    call lower_expr
    ; store with type info in op2
    call resolve_let_type
    mov rdx,rax
    mov rdi,MIR_SSTORE
    mov rsi,r13
    call mir_emit
    jmp .done

; borrow: let name = &var or &mut var
.let_brw:
    mov rdi,[r12+16]
    mov r13,[rdi+8]            ; mut flag
    mov rsi,[rdi+48]
    mov rcx,[rdi+56]
    call sym_get_index
    cmp rax,-1
    je .done
    mov r14,rax
    ; check borrow rules
    test r13,r13
    jnz .brw_mut
    push r11
    mov r11,[sym_bstate]
    cmp qword[r11+r14*8],2
    pop r11
    je .done
    push r11
    mov r11,[sym_bcnt]
    inc qword[r11+r14*8]
    pop r11
    jmp .brw_create
.brw_mut:
    push r11
    mov r11,[sym_bcnt]
    cmp qword[r11+r14*8],0
    pop r11
    jne .done
    push r11
    mov r11,[sym_bstate]
    cmp qword[r11+r14*8],2
    pop r11
    je .done
    push r11
    mov r11,[sym_bstate]
    mov qword[r11+r14*8],2
    pop r11
.brw_create:
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call sym_push
    ; copy source offset to alias
    mov rbx,[sym_count]
    dec rbx
    push r11
    mov r11,[sym_off]
    sym_load sym_off, r14
    mov [r11+rbx*8],rax
    pop r11
    push r11
    mov r11,[sym_alias]
    mov [r11+rbx*8],r14
    pop r11
    test r13,r13
    jz .brw_im
    push r11
    mov r11,[sym_bstate]
    mov qword[r11+rbx*8],2
    pop r11
    jmp .done
.brw_im:
    push r11
    mov r11,[sym_bstate]
    mov qword[r11+rbx*8],1
    pop r11
    jmp .done

; variant: let name = Variant(expr)
.let_variant:
    mov r13,rax                ; tag
    mov r14,rdi                ; NODE_CALL
    ; allocate 16 bytes: [tag:8][payload:8]
    push r13
    push r14
    mov rdi,16
    call sym_alloc_bytes
    mov r15,rax
    pop r14
    pop r13
    push r15
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    mov rdi,2
    mov rdx,r15
    call sym_push_arr
    pop r15
    ; store tag at base offset
    mov rdi,MIR_ICONST
    mov rsi,r13
    call m2
    mov rdi,MIR_SSTORE
    mov rsi,r15
    call m2
    ; store payload at base-8 (first arg of constructor call)
    mov rdi,[r14+16]
    test rdi,rdi
    jz .done
    push r15
    call lower_expr
    pop r15
    mov rdi,MIR_SSTORE
    mov rsi,r15
    sub rsi,8
    call m2
    jmp .done

; array: let name [:: [type]] = [expr, expr, ...]
.let_arr:
    mov rdi,[r12+16]
    mov r13,[rdi+8]            ; element count
    mov r14,rdi                ; array node
    ; resolve element type and size
    call resolve_let_type
    mov [arr_elem_type],rax
    call type_size
    mov [arr_elem_size],rax
    ; allocate stack space: elem_size * count
    push r13
    push r14
    mov rdi,rax
    imul rdi,r13
    call sym_alloc_bytes
    mov r15,rax                ; base offset
    pop r14
    pop r13
    ; register array in symbol table
    push r15
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    mov rdi,r13
    mov rdx,r15
    call sym_push_arr
    mov rdi,[arr_elem_type]
    call sym_set_last_type
    pop r15
    ; compile and store each element
    mov rbx,[r14+16]
    xor r14,r14                ; element index
.arr_st:
    test rbx,rbx
    jz .done
    push rbx
    push r14
    push r15
    mov rdi,rbx
    call lower_expr
    pop r15
    pop r14
    mov rdi,MIR_SSTORE
    mov rsi,r15
    mov rax,[arr_elem_size]
    imul rax,r14
    sub rsi,rax
    mov rdx,[arr_elem_type]
    call mir_emit
    pop rbx
    inc r14
    mov rbx,[rbx+32]
    jmp .arr_st

; record literal: let name = TypeName { field = expr, ... }
.let_rec:
    mov rdi,[r12+16]
    mov rsi,[rdi+48]
    mov rcx,[rdi+56]
    push rdi
    call treg_lookup
    pop rdi
    cmp rax,-1
    je .done
    mov r13,rax                ; type index
    push rdi
    push r13
    ; get total byte size of this record type
    mov rdi,r13
    call treg_total_size
    mov rdi,rax
    call sym_alloc_bytes
    mov r15,rax                ; base offset
    pop r13
    push r15
    push r13
    ; get field count for sym_push_arr
    mov rdi,r13
    call treg_field_count
    mov rdi,rax
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    mov rdx,r15
    call sym_push_arr
    pop r13
    mov rdi,r13
    call sym_set_rec_type
    pop r15
    pop rdi
    ; compile each field initializer
    mov rbx,[rdi+16]           ; first field-def node in literal
.rec_st:
    test rbx,rbx
    jz .done
    ; look up field index in type definition
    push rbx
    mov rdi,r13
    mov rsi,[rbx+48]
    mov rcx,[rbx+56]
    call treg_field_index
    pop rbx
    cmp rax,-1
    je .rec_nx
    ; get field byte offset and type from type registry
    mov rcx,r13
    imul rcx,rcx,MAX_REC_FIELDS
    add rcx,rax
    mov rax,[treg_foff+rcx*8]
    mov [rec_fld_off],rax
    mov rax,[treg_ftype+rcx*8]
    mov [rec_fld_type],rax
    ; compile field value expression
    push rbx
    mov rdi,[rbx+16]
    call lower_expr
    pop rbx
    ; store at correct offset with correct type
    mov rdi,MIR_SSTORE
    mov rsi,r15
    sub rsi,[rec_fld_off]
    mov rdx,[rec_fld_type]
    call mir_emit
.rec_nx:
    mov rbx,[rbx+32]
    jmp .rec_st

; ---- return ----
.ret:
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_LEAVE
    xor rsi,rsi
    call m2
    jmp .done

; ---- print(expr) ----
.prn:
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_MOV_RDI_RAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_CALL
    mov rsi,[rt_print_label]
    call m2
    jmp .done

; ---- print_str(expr) ----
.pstr:
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_CALL
    mov rsi,[rt_pstr_label]
    call m2
    jmp .done

; ---- if/else ----
.if_:
    call mir_new_label
    mov r13,rax                ; else label
    call mir_new_label
    mov r14,rax                ; end label
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_TEST
    xor rsi,rsi
    call m2
    mov rdi,MIR_JZ
    mov rsi,r13
    call m2
    inc qword[sym_depth]
    mov rdi,[r12+24]
    call lower_stmt_list
    call sym_leave_scope
    dec qword[sym_depth]
    mov rdi,MIR_JMP
    mov rsi,r14
    call m2
    mov rdi,MIR_LABEL
    mov rsi,r13
    call m2
    cmp qword[r12+8],0
    je .if_end
    inc qword[sym_depth]
    mov rdi,[r12+8]
    call lower_stmt_list
    call sym_leave_scope
    dec qword[sym_depth]
.if_end:
    mov rdi,MIR_LABEL
    mov rsi,r14
    call m2
    jmp .done

; ---- name[index] = value ----
.idx_set:
    mov rdi,[r12+24]
    call lower_expr
    mov rdi,MIR_PUSH
    xor rsi,rsi
    call m2
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_PUSH
    xor rsi,rsi
    call m2
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call sym_get_index
    cmp rax,-1
    je .done
    mov rbx,rax
    push r11
    mov r11,[sym_off]
    mov rsi,[r11+rbx*8]
    pop r11
    mov rdi,MIR_SLEA
    call m2
    mov rdi,MIR_POP_RBX
    xor rsi,rsi
    call m2
    mov rdi,MIR_POP_RCX
    xor rsi,rsi
    call m2
    push r11
    mov r11,[sym_type]
    mov rsi,[r11+rbx*8]
    pop r11
    mov rdi,MIR_IDX_STORE
    xor rdx,rdx
    call mir_emit
    jmp .done

; ---- match ----
.match:
    ; check for union match (first arm kind=3)
    mov rbx,[r12+24]
    test rbx,rbx
    jz .done
    cmp qword[rbx+40],3
    je .match_union
    ; regular match: evaluate subject, store in temp slot
    mov rdi,8
    call sym_alloc_bytes
    mov r13,rax                ; temp offset
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_SSTORE
    mov rsi,r13
    call m2
    call mir_new_label
    mov r14,rax                ; end label
    mov rbx,[r12+24]
.ma_loop:
    test rbx,rbx
    jz .ma_end
    mov rax,[rbx+40]
    cmp rax,0
    je .ma_lit
    cmp rax,1
    je .ma_wild
    cmp rax,2
    je .ma_bind
    mov rbx,[rbx+32]
    jmp .ma_loop
; literal arm: compare and skip if not equal
.ma_lit:
    call mir_new_label
    push rax
    mov rdi,MIR_CMP_MEM_IMM
    mov rsi,r13
    mov rdx,[rbx+8]
    call m3
    mov rdi,MIR_JNE
    mov rsi,[rsp]
    call m2
    push rbx
    mov rdi,[rbx+16]
    call lower_stmt
    pop rbx
    mov rdi,MIR_JMP
    mov rsi,r14
    call m2
    pop rax
    mov rdi,MIR_LABEL
    mov rsi,rax
    call m2
    mov rbx,[rbx+32]
    jmp .ma_loop
; wildcard arm: always matches
.ma_wild:
    push rbx
    mov rdi,[rbx+16]
    call lower_stmt
    pop rbx
    mov rdi,MIR_JMP
    mov rsi,r14
    call m2
    mov rbx,[rbx+32]
    jmp .ma_loop
; bind arm: bind value to name, optionally check guard
.ma_bind:
    call mir_new_label
    push rax                   ; next label
    inc qword[sym_depth]
    ; load matched value
    mov rdi,MIR_SLOAD
    mov rsi,r13
    call m2
    ; bind to name
    push rbx
    mov rsi,[rbx+48]
    mov rcx,[rbx+56]
    call sym_push
    pop rbx
    mov rdi,MIR_SSTORE
    mov rsi,rax
    call m2
    ; guard check
    mov rax,[rbx+24]
    test rax,rax
    jz .mb_ng
    push rbx
    mov rdi,rax
    call lower_expr
    pop rbx
    mov rdi,MIR_TEST
    xor rsi,rsi
    call m2
    mov rdi,MIR_JZ
    mov rsi,[rsp]
    call m2
.mb_ng:
    push rbx
    mov rdi,[rbx+16]
    call lower_stmt
    pop rbx
    call sym_leave_scope
    dec qword[sym_depth]
    mov rdi,MIR_JMP
    mov rsi,r14
    call m2
    pop rax
    mov rdi,MIR_LABEL
    mov rsi,rax
    call m2
    mov rbx,[rbx+32]
    jmp .ma_loop
.ma_end:
    mov rdi,MIR_LABEL
    mov rsi,r14
    call m2
    jmp .done

; ---- union match: match var { Variant(bind) => ...; } ----
.match_union:
    mov rdi,[r12+16]
    cmp qword[rdi],NODE_IDENT
    jne .done
    mov rsi,[rdi+48]
    mov rcx,[rdi+56]
    call sym_get_index
    cmp rax,-1
    je .done
    mov r13,rax                ; sym index of matched variable
    call mir_new_label
    mov r14,rax                ; end label
    mov rbx,[r12+24]
.mu_loop:
    test rbx,rbx
    jz .mu_end
    mov rax,[rbx+40]
    cmp rax,3
    je .mu_var
    cmp rax,1
    je .mu_wild
    mov rbx,[rbx+32]
    jmp .mu_loop
.mu_var:
    ; look up variant tag
    push rbx
    mov rsi,[rbx+48]
    mov rcx,[rbx+56]
    call treg_lookup_variant
    pop rbx
    cmp rax,-1
    je .mu_nx
    mov r15,rax                ; tag value
    call mir_new_label
    push rax                   ; next label
    ; compare tag at [rbp - sym_off]
    push r11
    mov r11,[sym_off]
    mov rsi,[r11+r13*8]
    pop r11
    mov rdi,MIR_CMP_MEM_IMM
    mov rdx,r15
    call m3
    mov rdi,MIR_JNE
    mov rsi,[rsp]
    call m2
    ; bind payload if destructor has a name
    mov rax,[rbx+24]
    test rax,rax
    jz .mu_body
    inc qword[sym_depth]
    push rbx
    mov rax,[rbx+24]
    mov rsi,[rax+48]
    mov rcx,[rax+56]
    call sym_push
    pop rbx
    push rax
    ; load payload from [rbp - (sym_off - 8)]
    push r11
    mov r11,[sym_off]
    mov rsi,[r11+r13*8]
    pop r11
    sub rsi,8
    mov rdi,MIR_SLOAD
    call m2
    pop rsi
    mov rdi,MIR_SSTORE
    call m2
.mu_body:
    push rbx
    mov rdi,[rbx+16]
    call lower_stmt
    pop rbx
    ; leave scope if we bound a name
    mov rax,[rbx+24]
    test rax,rax
    jz .mu_noscope
    call sym_leave_scope
    dec qword[sym_depth]
.mu_noscope:
    mov rdi,MIR_JMP
    mov rsi,r14
    call m2
    pop rax
    mov rdi,MIR_LABEL
    mov rsi,rax
    call m2
.mu_nx:
    mov rbx,[rbx+32]
    jmp .mu_loop
.mu_wild:
    push rbx
    mov rdi,[rbx+16]
    call lower_stmt
    pop rbx
    mov rdi,MIR_JMP
    mov rsi,r14
    call m2
    mov rbx,[rbx+32]
    jmp .mu_loop
.mu_end:
    mov rdi,MIR_LABEL
    mov rsi,r14
    call m2
    jmp .done

; ---- anchor name { body } ----
.anchor:
    mov rdi,CKPT_BYTES
    call sym_alloc_bytes
    mov r13,rax
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    mov rdx,r13
    call anc_push
    call mir_new_label
    mov r14,rax                ; skip
    call mir_new_label
    mov r15,rax                ; end
    ; lea rdi, checkpoint buffer; call save
    mov rdi,MIR_SLEA
    mov rsi,r13
    call m2
    mov rdi,MIR_MOV_RDI_RAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_CALL
    mov rsi,[rt_ckpt_save_label]
    call m2
    ; if save returned nonzero, skip body (we're unwinding)
    mov rdi,MIR_TEST
    xor rsi,rsi
    call m2
    mov rdi,MIR_JNZ
    mov rsi,r14
    call m2
    ; body
    inc qword[sym_depth]
    mov rdi,[r12+16]
    call lower_stmt_list
    call sym_leave_scope
    dec qword[sym_depth]
    mov rdi,MIR_JMP
    mov rsi,r15
    call m2
    mov rdi,MIR_LABEL
    mov rsi,r14
    call m2
    mov rdi,MIR_LABEL
    mov rsi,r15
    call m2
    call anc_pop
    jmp .done

; ---- supervise { body } ----
.super:
    mov rdi,CKPT_BYTES
    call sym_alloc_bytes
    mov r13,rax                ; checkpoint offset
    mov rdi,8
    call sym_alloc_bytes
    push rax                   ; saved sv_current offset
    ; save old sv_current
    mov rdi,MIR_LOAD_DATA
    mov rsi,DATA_SV_CURRENT
    call m2
    mov rdi,MIR_SSTORE
    mov rsi,[rsp]
    call m2
    call mir_new_label
    mov r14,rax                ; skip
    call mir_new_label
    mov r15,rax                ; end
    ; save checkpoint
    mov rdi,MIR_SLEA
    mov rsi,r13
    call m2
    mov rdi,MIR_MOV_RDI_RAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_CALL
    mov rsi,[rt_ckpt_save_label]
    call m2
    mov rdi,MIR_TEST
    xor rsi,rsi
    call m2
    mov rdi,MIR_JNZ
    mov rsi,r14
    call m2
    ; set sv_current to our checkpoint
    mov rdi,MIR_SLEA
    mov rsi,r13
    call m2
    mov rdi,MIR_STORE_DATA
    mov rsi,DATA_SV_CURRENT
    call m2
    ; body
    inc qword[sym_depth]
    mov rdi,[r12+16]
    call lower_stmt_list
    call sym_leave_scope
    dec qword[sym_depth]
    mov rdi,MIR_JMP
    mov rsi,r15
    call m2
    mov rdi,MIR_LABEL
    mov rsi,r14
    call m2
    mov rdi,MIR_LABEL
    mov rsi,r15
    call m2
    ; restore old sv_current
    mov rdi,MIR_SLOAD
    pop rsi
    call m2
    mov rdi,MIR_STORE_DATA
    mov rsi,DATA_SV_CURRENT
    call m2
    jmp .done

; ---- unwind name; ----
.unwind:
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call anc_lookup
    test rax,rax
    jz .done
    mov r13,rax
    mov rdi,MIR_SLEA
    mov rsi,r13
    call m2
    mov rdi,MIR_MOV_RDI_RAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_ICONST
    mov rsi,1
    call m2
    mov rdi,MIR_MOV_RSI_RAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_CALL
    mov rsi,[rt_ckpt_restore_label]
    call m2
    jmp .done

; ---- store(ptr, offset, value) ----
.store_:
    mov rdi,[r12+8]
    call lower_expr
    mov rdi,MIR_PUSH
    xor rsi,rsi
    call m2
    mov rdi,[r12+24]
    call lower_expr
    mov rdi,MIR_PUSH
    xor rsi,rsi
    call m2
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_POP_RBX
    xor rsi,rsi
    call m2
    mov rdi,MIR_POP_RCX
    xor rsi,rsi
    call m2
    mov rdi,MIR_IDX_STORE
    xor rsi,rsi
    call m2
    jmp .done

; ---- release(ptr) ----
.release_:
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_MOV_RDI_RAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_CALL
    mov rsi,[rt_release_label]
    call m2
    jmp .done

; ---- pool_drain(pool) ----
.pdrain:
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_MOV_RDI_RAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_CALL
    mov rsi,[rt_pool_drain_label]
    call m2
    jmp .done

; ---- name.field = expr ----
.field_set:
    mov rdi,[r12+16]
    test rdi,rdi
    jz .done
    cmp qword[rdi],NODE_IDENT
    jne .done
    mov rsi,[rdi+48]
    mov rcx,[rdi+56]
    call sym_get_index
    cmp rax,-1
    je .done
    mov rbx,rax
    ; check if variable is a record
    push r11
    mov r11,[sym_rec_type]
    mov rax,[r11+rbx*8]
    pop r11
    cmp rax,0xFFFFFFFFFFFFFFFF
    je .done
    mov r13,rax                ; type index
    ; look up field
    mov rdi,rax
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call treg_field_index
    cmp rax,-1
    je .done
    ; get field offset and type
    mov rcx,r13
    imul rcx,rcx,MAX_REC_FIELDS
    add rcx,rax
    mov rax,[treg_foff+rcx*8]
    mov [rec_fld_off],rax
    mov rax,[treg_ftype+rcx*8]
    mov [rec_fld_type],rax
    ; compile value
    mov rdi,[r12+24]
    call lower_expr
    ; store at field offset with proper type
    push r11
    mov r11,[sym_off]
    mov rsi,[r11+rbx*8]
    pop r11
    sub rsi,[rec_fld_off]
    mov rdx,[rec_fld_type]
    mov rdi,MIR_SSTORE
    call mir_emit
    jmp .done

; ---- raw { body } ----
.raw_blk:
    inc qword[sym_depth]
    mov rdi,[r12+16]
    call lower_stmt_list
    call sym_leave_scope
    dec qword[sym_depth]

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rcx
    pop rbx
    ret

; ==================== EXPRESSIONS ====================

lower_expr:
    push rbx
    push rcx
    push r12
    push r13
    test rdi,rdi
    jz .zero
    mov r12,rdi
    mov rax,[r12]
    cmp rax,NODE_NUMBER
    je .num
    cmp rax,NODE_BOOL
    je .num
    cmp rax,NODE_IDENT
    je .id
    cmp rax,NODE_BINOP
    je .bin
    cmp rax,NODE_CALL
    je .call
    cmp rax,NODE_ATOM
    je .atom
    cmp rax,NODE_ADDR
    je .addr
    cmp rax,NODE_DEREF
    je .deref
    cmp rax,NODE_INDEX
    je .idx
    cmp rax,NODE_ARRLEN
    je .arrlen
    cmp rax,NODE_STRING
    je .string
    cmp rax,NODE_LEN
    je .len_
    cmp rax,NODE_CLAIM
    je .claim
    cmp rax,NODE_CLAIM_G
    je .claim
    cmp rax,NODE_LOAD
    je .load_
    cmp rax,NODE_POOL_NEW
    je .pool_new
    cmp rax,NODE_POOL_CLAIM
    je .pool_claim
    cmp rax,NODE_FIELD_ACCESS
    je .field_access
    cmp rax,NODE_BORROW
    je .borrow
.zero:
    mov rdi,MIR_XOR_EAX
    xor rsi,rsi
    call m2
    jmp .d

.num:
    mov rdi,MIR_ICONST
    mov rsi,[r12+8]
    call m2
    jmp .d

; identifier: load from stack (typed if available)
.id:
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call sym_get_index
    cmp rax,-1
    je .zero
    push r11
    mov r11,[sym_arrlen]
    mov rbx,[r11+rax*8]
    pop r11
    test rbx,rbx
    jnz .id_arr
    ; scalar: load with type
    push r11
    mov r11,[sym_type]
    mov rdx,[r11+rax*8]
    mov r11,[sym_off]
    mov rsi,[r11+rax*8]
    pop r11
    mov rdi,MIR_SLOAD
    call mir_emit
    jmp .d
.id_arr:
    push r11
    mov r11,[sym_off]
    mov rsi,[r11+rax*8]
    pop r11
    mov rdi,MIR_SLEA
    call m2
    jmp .d

.atom:
    ; hash atom name to i64
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    mov rax,5381
.ah:test rcx,rcx
    jz .ae
    movzx rdx,byte[rsi]
    imul rax,rax,33
    add rax,rdx
    inc rsi
    dec rcx
    jmp .ah
.ae:mov rdi,MIR_ICONST
    mov rsi,rax
    call m2
    jmp .d

.addr:
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call sym_lookup
    test rax,rax
    jz .zero
    mov rdi,MIR_SLEA
    mov rsi,rax
    call m2
    jmp .d

.deref:
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_DEREF
    xor rsi,rsi
    call m2
    jmp .d

; array indexing: arr[index]
.idx:
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_MOV_RBX_RAX
    xor rsi,rsi
    call m2
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call sym_get_index
    cmp rax,-1
    je .zero
    mov rbx,rax
    push r11
    mov r11,[sym_off]
    mov rsi,[r11+rbx*8]
    pop r11
    mov rdi,MIR_SLEA
    call m2
    ; load with element type
    push r11
    mov r11,[sym_type]
    mov rsi,[r11+rbx*8]
    pop r11
    mov rdi,MIR_IDX_LOAD
    xor rdx,rdx
    call mir_emit
    jmp .d

; arrlen(name)
.arrlen:
    mov rdi,[r12+16]
    test rdi,rdi
    jz .zero
    cmp qword[rdi],NODE_IDENT
    jne .zero
    mov rsi,[rdi+48]
    mov rcx,[rdi+56]
    call sym_get_index
    cmp rax,-1
    je .zero
    push r11
    mov r11,[sym_arrlen]
    mov rax,[r11+rax*8]
    pop r11
    mov rdi,MIR_ICONST
    mov rsi,rax
    call m2
    jmp .d

; string literal: register in pool, set rdi=ptr rsi=len
.string:
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call str_pool_register
    add rax,IMPORT_DATA_SIZE
    mov rdi,MIR_LEA_DATA
    mov rsi,rax
    call m2
    mov rdi,MIR_MOV_RDI_RAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_ICONST
    mov rsi,[r12+56]
    call m2
    mov rdi,MIR_MOV_RSI_RAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_MOV_RAX_RDI
    xor rsi,rsi
    call m2
    jmp .d

.len_:
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_MOV_RAX_RSI
    xor rsi,rsi
    call m2
    jmp .d

.claim:
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_MOV_RDI_RAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_CALL
    mov rsi,[rt_claim_label]
    call m2
    jmp .d

; load(ptr, offset) -> [ptr + offset*8]
.load_:
    mov rdi,[r12+24]
    call lower_expr
    mov rdi,MIR_PUSH
    xor rsi,rsi
    call m2
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_POP_RBX
    xor rsi,rsi
    call m2
    mov rdi,MIR_IDX_LOAD
    xor rsi,rsi
    call m2
    jmp .d

.pool_new:
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_MOV_RDI_RAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_CALL
    mov rsi,[rt_pool_create_label]
    call m2
    jmp .d

.pool_claim:
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_PUSH
    xor rsi,rsi
    call m2
    mov rdi,[r12+24]
    call lower_expr
    mov rdi,MIR_MOV_RSI_RAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_POP_RDI
    xor rsi,rsi
    call m2
    mov rdi,MIR_CALL
    mov rsi,[rt_pool_claim_label]
    call m2
    jmp .d

; record.field -> load from computed offset with field type
.field_access:
    mov rdi,[r12+16]
    test rdi,rdi
    jz .zero
    cmp qword[rdi],NODE_IDENT
    jne .zero
    mov rsi,[rdi+48]
    mov rcx,[rdi+56]
    call sym_get_index
    cmp rax,-1
    je .zero
    mov rbx,rax
    push r11
    mov r11,[sym_rec_type]
    mov rax,[r11+rbx*8]
    pop r11
    cmp rax,0xFFFFFFFFFFFFFFFF
    je .zero
    mov r13,rax
    mov rdi,rax
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call treg_field_index
    cmp rax,-1
    je .zero
    ; get field byte offset and type
    mov rcx,r13
    imul rcx,rcx,MAX_REC_FIELDS
    add rcx,rax
    mov rdx,[treg_ftype+rcx*8]
    mov rax,[treg_foff+rcx*8]
    push r11
    mov r11,[sym_off]
    mov rsi,[r11+rbx*8]
    pop r11
    sub rsi,rax
    mov rdi,MIR_SLOAD
    call mir_emit
    jmp .d

; borrow: &name -> load value (alias offset set during let)
.borrow:
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call sym_lookup
    test rax,rax
    jz .zero
    mov rdi,MIR_SLOAD
    mov rsi,rax
    call m2
    jmp .d

; binary operator
.bin:
    ; evaluate left, push, evaluate right, pop rbx
    mov rdi,[r12+16]
    call lower_expr
    mov rdi,MIR_PUSH
    xor rsi,rsi
    call m2
    mov rdi,[r12+24]
    call lower_expr
    mov rdi,MIR_POP_RBX
    xor rsi,rsi
    call m2
    ; dispatch on operator token
    mov rbx,[r12+8]
    cmp rbx,TOK_PLUS
    je .ba
    cmp rbx,TOK_MINUS
    je .bs
    cmp rbx,TOK_STAR
    je .bm
    cmp rbx,TOK_SLASH
    je .bv
    cmp rbx,TOK_EQ
    je .beq
    cmp rbx,TOK_NEQ
    je .bne
    cmp rbx,TOK_LT
    je .blt
    cmp rbx,TOK_GT
    je .bgt
    cmp rbx,TOK_LE
    je .ble
    cmp rbx,TOK_GE
    je .bge
    jmp .d
.ba:mov rdi,MIR_ADD
    jmp .binop
.bs:mov rdi,MIR_SUB
    jmp .binop
.bm:mov rdi,MIR_MUL
    jmp .binop

; safe division: check for zero, unwind via sv_current if available
.bv:
    call mir_new_label
    push rax                   ; ok_label [rsp+16]
    call mir_new_label
    push rax                   ; fallback [rsp+8]
    call mir_new_label
    push rax                   ; end [rsp]
    ; test divisor (rax)
    mov rdi,MIR_TEST
    xor rsi,rsi
    call m2
    mov rdi,MIR_JNZ
    mov rsi,[rsp+16]
    call m2
    ; divisor is zero: check if supervise is active
    mov rdi,MIR_LOAD_DATA
    mov rsi,DATA_SV_CURRENT
    call m2
    mov rdi,MIR_TEST
    xor rsi,rsi
    call m2
    mov rdi,MIR_JZ
    mov rsi,[rsp+8]
    call m2
    ; unwind via supervise checkpoint
    mov rdi,MIR_MOV_RDI_RAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_ICONST
    mov rsi,1
    call m2
    mov rdi,MIR_MOV_RSI_RAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_CALL
    mov rsi,[rt_ckpt_restore_label]
    call m2
    ; fallback: return 0
    mov rdi,MIR_LABEL
    mov rsi,[rsp+8]
    call m2
    mov rdi,MIR_XOR_EAX
    xor rsi,rsi
    call m2
    mov rdi,MIR_JMP
    mov rsi,[rsp]
    call m2
    ; ok: normal division
    mov rdi,MIR_LABEL
    mov rsi,[rsp+16]
    call m2
    mov rdi,MIR_XCHG_RBX
    xor rsi,rsi
    call m2
    mov rdi,MIR_CQO
    xor rsi,rsi
    call m2
    mov rdi,MIR_IDIV_RBX
    xor rsi,rsi
    call m2
    ; end
    mov rdi,MIR_LABEL
    mov rsi,[rsp]
    call m2
    add rsp,24
    jmp .d

.beq:mov rdi,MIR_CMP_EQ
    jmp .binop
.bne:mov rdi,MIR_CMP_NE
    jmp .binop
.blt:mov rdi,MIR_CMP_LT
    jmp .binop
.bgt:mov rdi,MIR_CMP_GT
    jmp .binop
.ble:mov rdi,MIR_CMP_LE
    jmp .binop
.bge:mov rdi,MIR_CMP_GE
.binop:
    xor rsi,rsi
    call m2
    jmp .d

; function call: push args, pop into registers, call
.call:
    xor r13,r13
    mov rbx,[r12+16]
.ca_e:test rbx,rbx
    jz .ca_p
    push rbx
    push r13
    mov rdi,rbx
    call lower_expr
    mov rdi,MIR_PUSH
    xor rsi,rsi
    call m2
    pop r13
    pop rbx
    inc r13
    mov rbx,[rbx+32]
    jmp .ca_e
.ca_p:
    test r13,r13
    jz .ca_c
    mov rbx,r13
    dec rbx
.ca_pl:
    cmp rbx,0
    jl .ca_c
    cmp rbx,0
    je .ca_rdi
    cmp rbx,1
    je .ca_rsi
    cmp rbx,2
    je .ca_rdx
    cmp rbx,3
    je .ca_rcx
    cmp rbx,4
    je .ca_r8
    cmp rbx,5
    je .ca_r9
    jmp .ca_nx
.ca_rdi:mov rdi,MIR_POP_RDI
    jmp .ca_em
.ca_rsi:mov rdi,MIR_POP_RSI
    jmp .ca_em
.ca_rdx:mov rdi,MIR_POP_RDX
    jmp .ca_em
.ca_rcx:mov rdi,MIR_POP_RCX
    jmp .ca_em
.ca_r8:mov rdi,MIR_POP_R8
    jmp .ca_em
.ca_r9:mov rdi,MIR_POP_R9
.ca_em:xor rsi,rsi
    call m2
.ca_nx:dec rbx
    jmp .ca_pl
.ca_c:
    mov rsi,[r12+48]
    mov rcx,[r12+56]
    call fn_lookup_label
    cmp rax,-1
    je .d
    mov rdi,MIR_CALL
    mov rsi,rax
    call m2
.d: pop r13
    pop r12
    pop rcx
    pop rbx
    ret