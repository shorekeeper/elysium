; Provides both legacy text mode and binary PE mode.
; The binary path: AST -> MIR (lower) -> x86 (x86enc) -> PE (pe64)
; IAT and data patches are applied between x86 encoding and PE writing.
default rel
%include "defs.inc"
extern emit_init, emit_get_output, emit_flush_strings
extern sym_init
extern cg_emit_header, cg_emit_runtime, cg_emit_entry, cg_emit_footer
extern compile_module
extern mir_init, mir_count
extern x86_init, x86_encode, x86_get_code, x86_get_label_offset
extern x86_iat_patches, x86_iat_patch_count
extern x86_data_patches, x86_data_patch_count
extern lower_module, lower_emit_runtime_win, lower_emit_entry_win
extern lower_entry_label
extern str_pool, str_pool_pos
extern pe_build_header, build_import_data_win
extern pe_get_header, pe_get_import_data
extern pe_get_data_start, pe_get_padding_size, pe_get_section_raw_size
extern platform_write
extern CreateFileA, WriteFile, CloseHandle

global backend_init, backend_compile, backend_get_output
global backend_compile_binary_win
global be_target, be_mod_root

GENERIC_WRITE equ 0x40000000
CREATE_ALWAYS equ 2
FILE_ATTR_NORMAL equ 0x80
INVALID_HANDLE equ -1

section .data
msg_ew: db "  [error] write failed",13,10,0
msg_d1: db "  [debug] MIR emitted: ",0
msg_d2: db "  [debug] x86 encoded: ",0
msg_d3: db "  [debug] entry at: ",0
msg_d4: db "  [debug] writing file...",13,10,0
msg_d5: db "  [debug] file written OK",13,10,0
msg_d6: db "  [debug] string pool: ",0
msg_dnl:db 13,10,0
pe_zeros: times 4096 db 0
dbg_buf2: times 32 db 0

section .bss
be_target: resq 1
be_mod_root: resq 1
wr_tmp2: resd 1

section .text

; debug helper: print decimal number
be_print_num:
    push rbx
    push rcx
    push rdx
    push rsi
    test rax,rax
    jnz .nz
    mov byte[dbg_buf2],'0'
    mov rsi,dbg_buf2
    mov rdx,1
    call platform_write
    jmp .end
.nz:xor rcx,rcx
    mov rbx,10
.ext:test rax,rax
    jz .bld
    xor rdx,rdx
    div rbx
    add dl,'0'
    push rdx
    inc rcx
    jmp .ext
.bld:mov rbx,rcx
    xor rdx,rdx
.pop:test rcx,rcx
    jz .wr
    pop rax
    mov [dbg_buf2+rdx],al
    inc rdx
    dec rcx
    jmp .pop
.wr:mov rsi,dbg_buf2
    mov rdx,rbx
    call platform_write
.end:pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; debug helper: print null-terminated string
be_print:
    push rsi
    push rdx
    mov rsi,rdi
    xor rdx,rdx
.l: cmp byte[rsi+rdx],0
    je .g
    inc rdx
    jmp .l
.g: call platform_write
    pop rdx
    pop rsi
    ret

backend_init:
    call emit_init
    call sym_init
    mov qword[be_target],0
    mov qword[be_mod_root],0
    ret

; legacy text-mode compilation (produces NASM .asm text)
backend_compile:
    push rbx
    push rbp
    mov rbp,rsp
    mov [be_mod_root],rdi
    mov [be_target],rsi
    call cg_emit_header
    call cg_emit_runtime
    mov rdi,[be_mod_root]
    call compile_module
    call emit_flush_strings
    call cg_emit_entry
    call cg_emit_footer
    mov rsp,rbp
    pop rbp
    pop rbx
    ret

; binary PE compilation: AST -> MIR -> x86 -> patch -> write .exe
; rdi=AST root, rsi=output filename
backend_compile_binary_win:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 256

    ; stack-local variables:
    ;   [rsp+0]  = output filename pointer
    ;   [rsp+8]  = AST root
    ;   [rsp+16] = code buffer pointer (after x86_get_code)
    ;   [rsp+24] = code byte count
    ;   [rsp+32] = entry point offset
    ;   [rsp+40] = data_start (code aligned to 16)
    ;   [rsp+48] = file handle
    ;   [rsp+56] = section raw size (file-aligned)
    ;   [rsp+64] = total data size (import block + string pool)

    mov [rsp+0], rsi
    mov [rsp+8], rdi
    mov qword[be_mod_root], rdi
    mov qword[be_target], TARGET_WIN64

    ; initialize all subsystems
    call mir_init
    call x86_init
    call sym_init

    ; emit runtime functions as MIR (print, checkpoint, alloc, etc.)
    call lower_emit_runtime_win

    ; lower all user functions from AST to MIR
    mov rdi, [rsp+8]
    call lower_module

    ; emit program entry point (_start -> __rt_init -> main -> ExitProcess)
    call lower_emit_entry_win

    ; debug output: MIR instruction count
    lea rdi, [msg_d1]
    call be_print
    call mir_count
    call be_print_num
    lea rdi, [msg_dnl]
    call be_print

    ; encode all MIR to x86 machine code
    lea rdi, [msg_d2]
    call be_print
    call x86_encode

    ; get the encoded bytes
    call x86_get_code
    mov [rsp+16], rsi          ; code buffer
    mov [rsp+24], rdx          ; code length
    mov rax, rdx
    call be_print_num
    lea rdi, [msg_dnl]
    call be_print

    ; look up entry point offset (label for _start)
    mov rdi, [lower_entry_label]
    call x86_get_label_offset
    mov [rsp+32], rax
    lea rdi, [msg_d3]
    call be_print
    mov rax, [rsp+32]
    call be_print_num
    lea rdi, [msg_dnl]
    call be_print

    ; compute data_start = code length rounded up to 16
    mov rdi, [rsp+24]
    call pe_get_data_start
    mov [rsp+40], rax

    ; total data = import data block + string pool bytes
    mov rax, IMPORT_DATA_SIZE
    add rax, [str_pool_pos]
    mov [rsp+64], rax

    ; debug: string pool size
    lea rdi, [msg_d6]
    call be_print
    mov rax, [str_pool_pos]
    call be_print_num
    lea rdi, [msg_dnl]
    call be_print

    ; compute file-aligned section size
    mov rdi, [rsp+24]
    mov rsi, [rsp+64]
    call pe_get_section_raw_size
    mov [rsp+56], rax

    ; build the import directory block (IAT, ILT, hint-names, DLL name)
    mov rdi, PE_SECTION_RVA
    add rdi, [rsp+40]
    call build_import_data_win

    ; === PATCH IAT REFERENCES ===
    ; Each IAT patch has: [code_offset, iat_slot_index]
    ; The x86 code has "call [rip+disp32]" with a placeholder disp32.
    ; We compute: disp32 = (data_start + slot*8) - code_offset - 4
    ; This makes the call go through the IAT entry at runtime.
    mov rcx, [x86_iat_patch_count]
    xor rdx, rdx
.iat:
    cmp rdx, rcx
    jge .iat_d
    push rcx
    push rdx
    mov rax, rdx
    shl rax, 4                 ; 16 bytes per entry
    push r11
    mov r11, [x86_iat_patches]
    mov rbx, [r11+rax]        ; code offset where disp32 lives
    mov rdi, [r11+rax+8]      ; IAT slot index (0=Exit, 1=GetStd, 2=Write, ...)
    pop r11
    imul rdi, rdi, 8           ; slot index * 8 = byte offset within IAT
    add rdi, [rsp+40+16]      ; + data_start (adjusted for 2 pushes above)
    sub rdi, rbx               ; - code_offset
    sub rdi, 4                 ; - 4 (size of the disp32 itself)
    push r11
    mov r11, [rsp+16+16+8]    ; code buffer pointer (adjusted for pushes)
    mov [r11+rbx], edi         ; write computed disp32
    pop r11
    pop rdx
    pop rcx
    inc rdx
    jmp .iat
.iat_d:

    ; === PATCH DATA REFERENCES ===
    ; Each data patch has: [code_offset, data_section_offset]
    ; Data section offset is relative to start of data area (after code).
    ; For import data fields: offset < IMPORT_DATA_SIZE (stdout, written, etc.)
    ; For string pool: offset >= IMPORT_DATA_SIZE
    ; disp32 = (data_start + data_offset) - code_offset - 4
    mov rcx, [x86_data_patch_count]
    xor rdx, rdx
.dat:
    cmp rdx, rcx
    jge .dat_d
    push rcx
    push rdx
    mov rax, rdx
    shl rax, 4
    push r11
    mov r11, [x86_data_patches]
    mov rbx, [r11+rax]        ; code offset where disp32 lives
    mov rdi, [r11+rax+8]      ; data section offset
    pop r11
    add rdi, [rsp+40+16]      ; + data_start
    sub rdi, rbx               ; - code_offset
    sub rdi, 4                 ; - 4
    push r11
    mov r11, [rsp+16+16+8]    ; code buffer pointer
    mov [r11+rbx], edi
    pop r11
    pop rdx
    pop rcx
    inc rdx
    jmp .dat
.dat_d:

    ; build PE header with all computed sizes
    mov rdi, [rsp+24]         ; code length
    mov rsi, [rsp+40]         ; data_start
    mov rdx, [rsp+32]         ; entry offset
    mov rcx, [rsp+64]         ; total data size
    call pe_build_header

    ; === WRITE FILE ===
    lea rdi, [msg_d4]
    call be_print

    ; create output file
    sub rsp, 64
    mov rcx, [rsp+0+64]       ; filename (adjusted for sub rsp,64)
    mov rdx, GENERIC_WRITE
    xor r8d, r8d
    xor r9d, r9d
    mov dword[rsp+32], CREATE_ALWAYS
    mov dword[rsp+40], FILE_ATTR_NORMAL
    mov qword[rsp+48], 0
    call CreateFileA
    add rsp, 64
    cmp rax, INVALID_HANDLE
    je .err
    mov [rsp+48], rax          ; save file handle

    ; write PE headers (exactly PE_FILE_ALIGN = 512 bytes)
    call pe_get_header
    mov r13, rsi
    mov r14, rdx
    sub rsp, 48
    mov rcx, [rsp+48+48]
    mov rdx, r13
    mov r8, r14
    lea r9, [wr_tmp2]
    mov qword[rsp+32], 0
    call WriteFile
    add rsp, 48

    ; write x86 code bytes
    mov r13, [rsp+16]
    mov r14, [rsp+24]
    sub rsp, 48
    mov rcx, [rsp+48+48]
    mov rdx, r13
    mov r8, r14
    lea r9, [wr_tmp2]
    mov qword[rsp+32], 0
    call WriteFile
    add rsp, 48

    ; write padding between code and data (align to 16)
    mov rdi, [rsp+24]
    call pe_get_padding_size
    test rax, rax
    jz .no_pad
    mov r14, rax
    sub rsp, 48
    mov rcx, [rsp+48+48]
    lea rdx, [pe_zeros]
    mov r8, r14
    lea r9, [wr_tmp2]
    mov qword[rsp+32], 0
    call WriteFile
    add rsp, 48
.no_pad:

    ; write import data block (IAT, ILT, directory, hint-names, DLL name, runtime data)
    call pe_get_import_data
    mov r13, rsi
    mov r14, rdx
    sub rsp, 48
    mov rcx, [rsp+48+48]
    mov rdx, r13
    mov r8, r14
    lea r9, [wr_tmp2]
    mov qword[rsp+32], 0
    call WriteFile
    add rsp, 48

    ; write string pool (registered string literals)
    mov r14, [str_pool_pos]
    test r14, r14
    jz .no_str
    sub rsp, 48
    mov rcx, [rsp+48+48]
    lea rdx, [str_pool]
    mov r8, r14
    lea r9, [wr_tmp2]
    mov qword[rsp+32], 0
    call WriteFile
    add rsp, 48
.no_str:

    ; write trailing zeros to fill section to file-aligned size
    mov rax, [rsp+40]         ; data_start
    add rax, [rsp+64]         ; + total data size
    mov r14, [rsp+56]         ; section raw size
    sub r14, rax               ; remaining bytes
    test r14, r14
    jle .no_fpad
    sub rsp, 48
    mov rcx, [rsp+48+48]
    lea rdx, [pe_zeros]
    mov r8, r14
    lea r9, [wr_tmp2]
    mov qword[rsp+32], 0
    call WriteFile
    add rsp, 48
.no_fpad:

    ; close file
    sub rsp, 32
    mov rcx, [rsp+48+32]
    call CloseHandle
    add rsp, 32

    lea rdi, [msg_d5]
    call be_print

    mov rsp, rbp
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.err:
    lea rdi, [msg_ew]
    call be_print
    mov rsp, rbp
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

backend_get_output:
    jmp emit_get_output