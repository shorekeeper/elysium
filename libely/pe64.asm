; pe64.asm - PE64 executable builder
default rel
%include "defs.inc"
global pe_build_header, build_import_data_win
global pe_get_header, pe_get_import_data
global pe_get_padding_size, pe_get_section_raw_size, pe_get_data_start

section .data

align 8
pe_template:
; DOS Header (64 bytes)
    dw 0x5A4D
    times 29 dw 0
    dd 64
; PE Signature
    dd 0x00004550
; COFF Header (20 bytes)
    dw 0x8664
    dw 1
    dd 0,0,0
    dw 240
    dw 0x0022
; Optional Header PE32+
    dw 0x020B
    db 1,0
pe_t_SizeOfCode equ 92
    dd 0                ; SizeOfCode [92]
    dd 0                ; SizeOfInitializedData [96]
    dd 0                ; SizeOfUninitializedData [100]
pe_t_Entry equ 104
    dd 0                ; AddressOfEntryPoint [104]
    dd PE_SECTION_RVA   ; BaseOfCode [108]
    dq PE_IMAGE_BASE    ; ImageBase [112]
    dd PE_SECT_ALIGN    ; SectionAlignment [120]
    dd PE_FILE_ALIGN    ; FileAlignment [124]
    dw 6,0
    dw 0,0
    dw 6,0
    dd 0
pe_t_SizeOfImage equ 144
    dd 0                ; SizeOfImage [144]
    dd PE_FILE_ALIGN    ; SizeOfHeaders [148]
    dd 0
    dw 3                ; CONSOLE
    dw 0
    dq 0x100000,0x1000
    dq 0x100000,0x1000
    dd 0
    dd 16
; Data Directories
    dq 0                ; Export
pe_t_ImportDir equ 208
    dd 0,0              ; Import RVA, Size
    times 10 dq 0
pe_t_IAT equ 296
    dd 0,0              ; IAT RVA, Size
    times 3 dq 0
; Section Table
    db '.all',0,0,0,0
pe_t_VirtSize equ 336
    dd 0                ; VirtualSize
    dd PE_SECTION_RVA   ; VirtualAddress
pe_t_RawSize equ 344
    dd 0                ; SizeOfRawData
    dd PE_FILE_ALIGN    ; PointerToRawData
    dd 0,0
    dw 0,0
    dd 0xE0000060
pe_template_size equ $ - pe_template

section .bss
pe_buf: resb 0x200
import_block: resb IMPORT_DATA_SIZE

section .text

; pe_build_header: rdi=code_len, rsi=data_start, rdx=entry_offset, rcx=total_data_size
pe_build_header:
    push rbx
    push rcx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx

    push rdi
    push rsi
    lea rdi, [pe_buf]
    lea rsi, [pe_template]
    mov rcx, pe_template_size
    rep movsb
    pop rsi
    pop rdi
    lea rdi, [pe_buf+pe_template_size]
    mov rcx, PE_FILE_ALIGN - pe_template_size
    xor al, al
    rep stosb

    ; section_total = data_start + total_data_size
    mov rax, r13
    add rax, r15
    mov rbx, rax

    ; raw_size = align(section_total, PE_FILE_ALIGN)
    mov rcx, rax
    add rcx, PE_FILE_ALIGN-1
    and rcx, -PE_FILE_ALIGN

    ; virt_size = align(section_total, PE_SECT_ALIGN)
    mov rdx, rax
    add rdx, PE_SECT_ALIGN-1
    and rdx, -PE_SECT_ALIGN

    mov [pe_buf+pe_t_SizeOfCode], ebx
    mov [pe_buf+96], ebx
    mov eax, r14d
    add eax, PE_SECTION_RVA
    mov [pe_buf+pe_t_Entry], eax
    mov eax, edx
    add eax, PE_SECTION_RVA
    mov [pe_buf+pe_t_SizeOfImage], eax
    ; Import Directory at data_start + 0x60
    mov eax, PE_SECTION_RVA
    add eax, r13d
    add eax, 0x60
    mov [pe_buf+pe_t_ImportDir], eax
    mov dword[pe_buf+pe_t_ImportDir+4], 40
    ; IAT at data_start + 0
    mov eax, PE_SECTION_RVA
    add eax, r13d
    mov [pe_buf+pe_t_IAT], eax
    mov dword[pe_buf+pe_t_IAT+4], 48
    ; Section sizes
    mov [pe_buf+pe_t_VirtSize], ebx
    mov [pe_buf+pe_t_RawSize], ecx

    pop r15
    pop r14
    pop r13
    pop r12
    pop rcx
    pop rbx
    ret

; build_import_data_win: rdi=data_rva
; Layout: IAT(48) ILT(48) ImportDir(40) HintNames DLLname Data
build_import_data_win:
    push rbx
    push rcx
    push rdi
    push rsi
    push rax
    mov rbx, rdi

    lea rdi, [import_block]
    xor al, al
    mov rcx, IMPORT_DATA_SIZE
    rep stosb

    lea rdi, [import_block]
    ; IAT 0x00: 5 entries + null
    mov rax, rbx
    add rax, 0x88
    mov [rdi], rax
    mov rax, rbx
    add rax, 0x96
    mov [rdi+0x08], rax
    mov rax, rbx
    add rax, 0xA6
    mov [rdi+0x10], rax
    mov rax, rbx
    add rax, 0xB2
    mov [rdi+0x18], rax
    mov rax, rbx
    add rax, 0xC2
    mov [rdi+0x20], rax
    mov qword[rdi+0x28], 0
    ; ILT 0x30: copy IAT
    mov rax, [rdi]
    mov [rdi+0x30], rax
    mov rax, [rdi+0x08]
    mov [rdi+0x38], rax
    mov rax, [rdi+0x10]
    mov [rdi+0x40], rax
    mov rax, [rdi+0x18]
    mov [rdi+0x48], rax
    mov rax, [rdi+0x20]
    mov [rdi+0x50], rax
    mov qword[rdi+0x58], 0
    ; Import Dir 0x60
    mov eax, ebx
    add eax, 0x30
    mov [rdi+0x60], eax
    mov dword[rdi+0x64], 0
    mov dword[rdi+0x68], 0
    mov eax, ebx
    add eax, 0xD0
    mov [rdi+0x6C], eax
    mov eax, ebx
    mov [rdi+0x70], eax
    ; HN ExitProcess 0x88
    mov word[rdi+0x88], 0
    mov byte[rdi+0x8A], 'E'
    mov byte[rdi+0x8B], 'x'
    mov byte[rdi+0x8C], 'i'
    mov byte[rdi+0x8D], 't'
    mov byte[rdi+0x8E], 'P'
    mov byte[rdi+0x8F], 'r'
    mov byte[rdi+0x90], 'o'
    mov byte[rdi+0x91], 'c'
    mov byte[rdi+0x92], 'e'
    mov byte[rdi+0x93], 's'
    mov byte[rdi+0x94], 's'
    mov byte[rdi+0x95], 0
    ; HN GetStdHandle 0x96
    mov word[rdi+0x96], 0
    mov byte[rdi+0x98], 'G'
    mov byte[rdi+0x99], 'e'
    mov byte[rdi+0x9A], 't'
    mov byte[rdi+0x9B], 'S'
    mov byte[rdi+0x9C], 't'
    mov byte[rdi+0x9D], 'd'
    mov byte[rdi+0x9E], 'H'
    mov byte[rdi+0x9F], 'a'
    mov byte[rdi+0xA0], 'n'
    mov byte[rdi+0xA1], 'd'
    mov byte[rdi+0xA2], 'l'
    mov byte[rdi+0xA3], 'e'
    mov byte[rdi+0xA4], 0
    ; HN WriteFile 0xA6
    mov word[rdi+0xA6], 0
    mov byte[rdi+0xA8], 'W'
    mov byte[rdi+0xA9], 'r'
    mov byte[rdi+0xAA], 'i'
    mov byte[rdi+0xAB], 't'
    mov byte[rdi+0xAC], 'e'
    mov byte[rdi+0xAD], 'F'
    mov byte[rdi+0xAE], 'i'
    mov byte[rdi+0xAF], 'l'
    mov byte[rdi+0xB0], 'e'
    mov byte[rdi+0xB1], 0
    ; HN VirtualAlloc 0xB2
    mov word[rdi+0xB2], 0
    mov byte[rdi+0xB4], 'V'
    mov byte[rdi+0xB5], 'i'
    mov byte[rdi+0xB6], 'r'
    mov byte[rdi+0xB7], 't'
    mov byte[rdi+0xB8], 'u'
    mov byte[rdi+0xB9], 'a'
    mov byte[rdi+0xBA], 'l'
    mov byte[rdi+0xBB], 'A'
    mov byte[rdi+0xBC], 'l'
    mov byte[rdi+0xBD], 'l'
    mov byte[rdi+0xBE], 'o'
    mov byte[rdi+0xBF], 'c'
    mov byte[rdi+0xC0], 0
    ; HN VirtualFree 0xC2
    mov word[rdi+0xC2], 0
    mov byte[rdi+0xC4], 'V'
    mov byte[rdi+0xC5], 'i'
    mov byte[rdi+0xC6], 'r'
    mov byte[rdi+0xC7], 't'
    mov byte[rdi+0xC8], 'u'
    mov byte[rdi+0xC9], 'a'
    mov byte[rdi+0xCA], 'l'
    mov byte[rdi+0xCB], 'F'
    mov byte[rdi+0xCC], 'r'
    mov byte[rdi+0xCD], 'e'
    mov byte[rdi+0xCE], 'e'
    mov byte[rdi+0xCF], 0
    ; DLL name 0xD0
    mov byte[rdi+0xD0], 'k'
    mov byte[rdi+0xD1], 'e'
    mov byte[rdi+0xD2], 'r'
    mov byte[rdi+0xD3], 'n'
    mov byte[rdi+0xD4], 'e'
    mov byte[rdi+0xD5], 'l'
    mov byte[rdi+0xD6], '3'
    mov byte[rdi+0xD7], '2'
    mov byte[rdi+0xD8], '.'
    mov byte[rdi+0xD9], 'd'
    mov byte[rdi+0xDA], 'l'
    mov byte[rdi+0xDB], 'l'
    mov byte[rdi+0xDC], 0

    pop rax
    pop rsi
    pop rdi
    pop rcx
    pop rbx
    ret

pe_get_header:
    lea rsi, [pe_buf]
    mov rdx, PE_FILE_ALIGN
    ret

pe_get_import_data:
    lea rsi, [import_block]
    mov rdx, IMPORT_DATA_SIZE
    ret

pe_get_data_start:
    mov rax, rdi
    add rax, 15
    and rax, -16
    ret

pe_get_padding_size:
    mov rax, rdi
    add rax, 15
    and rax, -16
    sub rax, rdi
    ret

; rdi=code_len, rsi=total_data_size -> rax=section raw size
pe_get_section_raw_size:
    mov rax, rdi
    add rax, 15
    and rax, -16
    add rax, rsi
    add rax, PE_FILE_ALIGN-1
    and rax, -PE_FILE_ALIGN
    ret