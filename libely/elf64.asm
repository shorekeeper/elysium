; elf64.asm - write minimal ELF64 executable
; exports: elf_write(rdi=filename, rsi=code_buf, rdx=code_len)
default rel
%include "defs.inc"
global elf_write

SYS_OPEN  equ 2
SYS_WRITE equ 1
SYS_CLOSE equ 3
SYS_CHMOD equ 90
O_WR_CR_TR equ 0x241

section .data
align 8
; ELF64 header (64 bytes)
elf_hdr:
    db 0x7F, "ELF"             ; magic
    db 2                        ; 64-bit
    db 1                        ; little endian
    db 1                        ; ELF version
    db 0                        ; OS/ABI
    dq 0                        ; padding
    dw 2                        ; ET_EXEC
    dw 0x3E                     ; x86-64
    dd 1                        ; version
    dq 0                        ; entry point (patched)
    dq 64                       ; phdr offset
    dq 0                        ; shdr offset
    dd 0                        ; flags
    dw 64                       ; ehdr size
    dw 56                       ; phdr entry size
    dw 1                        ; phdr count
    dw 64                       ; shdr entry size
    dw 0                        ; shdr count
    dw 0                        ; shstrndx
elf_hdr_size equ $ - elf_hdr

; Program header (56 bytes)
elf_phdr:
    dd 1                        ; PT_LOAD
    dd 7                        ; PF_R | PF_W | PF_X
    dq ELF_CODE_OFF             ; file offset
    dq ELF_BASE + ELF_CODE_OFF  ; vaddr
    dq ELF_BASE + ELF_CODE_OFF  ; paddr
    dq 0                        ; filesz (patched)
    dq 0                        ; memsz (patched)
    dq 0x1000                   ; alignment
elf_phdr_size equ $ - elf_phdr

section .bss
elf_buf: resb 0x2000            ; header + padding buffer
elf_fd: resq 1

section .text

; elf_write: rdi=filename, rsi=code_buf, rdx=code_len
elf_write:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi             ; filename
    mov r13, rsi             ; code ptr
    mov r14, rdx             ; code len

    ; build header in elf_buf
    ; copy elf header
    lea rdi, [elf_buf]
    lea rsi, [elf_hdr]
    mov rcx, elf_hdr_size
    rep movsb

    ; patch entry point (offset 24 in ehdr)
    ; entry = ELF_BASE + ELF_CODE_OFF (start of code)
    mov rax, ELF_BASE + ELF_CODE_OFF
    mov [elf_buf+24], rax

    ; copy program header
    lea rdi, [elf_buf+64]
    lea rsi, [elf_phdr]
    mov rcx, elf_phdr_size
    rep movsb

    ; patch phdr filesz and memsz (offset 32 and 40 in phdr, at file offset 64+32)
    mov [elf_buf+64+32], r14   ; filesz
    mov rax, r14
    add rax, 0x10000           ; memsz = filesz + extra for stack/bss
    mov [elf_buf+64+40], rax   ; memsz

    ; zero-fill padding from end of phdr to ELF_CODE_OFF
    lea rdi, [elf_buf+64+elf_phdr_size]
    mov rcx, ELF_CODE_OFF - 64 - elf_phdr_size
    xor al, al
    rep stosb

    ; open file
    mov rdi, r12
    mov rax, SYS_OPEN
    mov rsi, O_WR_CR_TR
    mov rdx, 0o755
    syscall
    test rax, rax
    js .err
    mov [elf_fd], rax

    ; write header + padding (ELF_CODE_OFF bytes)
    mov rdi, [elf_fd]
    mov rax, SYS_WRITE
    lea rsi, [elf_buf]
    mov rdx, ELF_CODE_OFF
    syscall

    ; write code
    mov rdi, [elf_fd]
    mov rax, SYS_WRITE
    mov rsi, r13
    mov rdx, r14
    syscall

    ; close
    mov rdi, [elf_fd]
    mov rax, SYS_CLOSE
    syscall

    ; chmod +x
    mov rdi, r12
    mov rax, SYS_CHMOD
    mov rsi, 0o755
    syscall

    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.err:
    mov eax, 1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret