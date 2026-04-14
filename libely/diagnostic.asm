; diagnostic.asm -- structured ASCII-art error formatter
; Renders source context with line numbers, underlines, and hints.
; Format:
;   ERR[E001] undefined variable
;
;       demo.ely
;    7  : print(ghost_var);
;       :       ~~~~~~~~~  not in scope
;       :
;
default rel
%include "defs.inc"
extern platform_write

global diag_init, diag_get_errors, diag_summary
global diag_err_undef_var, diag_err_undef_fn, diag_err_wrong_argc

ANNOT_COL equ 48

section .data
d_spaces: times 80 db ' '
d_tildes: times 80 db '~'

; error headers
de001h: db "ERR[E001]",0
de001t: db " undefined variable",0
de002h: db "ERR[E002]",0
de002t: db " wrong argument count",0
de003h: db "ERR[E003]",0
de003t: db " undefined function",0

; annotations
da_noscope: db "not in scope",0
da_notdef:  db "not defined",0
da_defn:    db ". defined: ",0
da_params:  db " params",0
da_call:    db "* called: ",0
da_args:    db " args",0
da_expect:  db "expected ",0
da_got:     db " arguments, got ",0

; rendering
dr_pipe:  db ": ",0
dr_hint:  db "'- ",0
dr_dots:  db "...",0

; summary
sm_err:  db " errors, ",0
sm_warn: db " warnings",0

section .bss
d_src:      resq 1
d_srclen:   resq 1
d_fname:    resq 1
d_fnamelen: resq 1
d_errors:   resq 1
d_warnings: resq 1
d_lbuf:     resb 2048
d_lpos:     resq 1

section .text

; ==================== BUFFER HELPERS ====================

d_reset:
    mov qword[d_lpos], 0
    ret

d_flush:
    push rsi
    push rdx
    lea rsi, [d_lbuf]
    mov rdx, [d_lpos]
    test rdx, rdx
    jz .d
    call platform_write
.d: mov qword[d_lpos], 0
    pop rdx
    pop rsi
    ret

; append byte al
d_putc:
    push rbx
    push rcx
    mov rbx, [d_lpos]
    lea rcx, [d_lbuf]
    mov [rcx+rbx], al
    inc qword[d_lpos]
    pop rcx
    pop rbx
    ret

; append rsi=ptr, rdx=len
d_putb:
    push rdi
    push rcx
    push rbx
    mov rbx, [d_lpos]
    lea rdi, [d_lbuf]
    add rdi, rbx
    mov rcx, rdx
    push rsi
    rep movsb
    pop rsi
    add [d_lpos], rdx
    pop rbx
    pop rcx
    pop rdi
    ret

; append null-terminated rdi
d_putz:
    push rsi
    push rdx
    mov rsi, rdi
    xor rdx, rdx
.l: cmp byte[rsi+rdx], 0
    je .g
    inc rdx
    jmp .l
.g: call d_putb
    pop rdx
    pop rsi
    ret

; append rcx spaces
d_pad:
    push rsi
    push rdx
    push rcx
    lea rsi, [d_spaces]
.l: test rcx, rcx
    jz .d
    mov rdx, rcx
    cmp rdx, 80
    jle .w
    mov rdx, 80
.w: call d_putb
    sub rcx, rdx
    jmp .l
.d: pop rcx
    pop rdx
    pop rsi
    ret

; append rcx tildes
d_tilde:
    push rsi
    push rdx
    push rcx
    lea rsi, [d_tildes]
.l: test rcx, rcx
    jz .d
    mov rdx, rcx
    cmp rdx, 80
    jle .w
    mov rdx, 80
.w: call d_putb
    sub rcx, rdx
    jmp .l
.d: pop rcx
    pop rdx
    pop rsi
    ret

; append CRLF and flush
d_nl:
    mov al, 13
    call d_putc
    mov al, 10
    call d_putc
    call d_flush
    ret

; append decimal rax
d_num:
    push rbx
    push rcx
    push rdx
    push rsi
    test rax, rax
    jns .pos
    push rax
    mov al, '-'
    call d_putc
    pop rax
    neg rax
.pos:
    test rax, rax
    jnz .nz
    mov al, '0'
    call d_putc
    jmp .end
.nz:
    xor rcx, rcx
    mov rbx, 10
.ext:
    test rax, rax
    jz .bld
    xor rdx, rdx
    div rbx
    add dl, '0'
    push rdx
    inc rcx
    jmp .ext
.bld:
    test rcx, rcx
    jz .end
    pop rax
    push rcx
    call d_putc
    pop rcx
    dec rcx
    jmp .bld
.end:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; count digits of rax -> rcx
d_digits:
    push rax
    push rbx
    push rdx
    xor rcx, rcx
    test rax, rax
    jnz .nz
    mov rcx, 1
    jmp .d
.nz:
    mov rbx, 10
.l: test rax, rax
    jz .d
    xor rdx, rdx
    div rbx
    inc rcx
    jmp .l
.d: pop rdx
    pop rbx
    pop rax
    ret

; append rax right-justified in rcx-char field
d_numr:
    push r12
    push r13
    mov r12, rax
    mov r13, rcx
    call d_digits
    sub r13, rcx
    test r13, r13
    jle .num
    mov rcx, r13
    call d_pad
.num:
    mov rax, r12
    call d_num
    pop r13
    pop r12
    ret

; ==================== SOURCE LOOKUP ====================

; ptr_to_line: rdi=ptr into source -> rax=line number (1-based), 0 if out of range
ptr_to_line:
    push rsi
    push rcx
    push rdx
    mov rsi, [d_src]
    mov rcx, rdi
    sub rcx, rsi
    test rcx, rcx
    jl .bad
    cmp rcx, [d_srclen]
    jg .bad
    xor rdx, rdx
    mov rax, 1
.l: cmp rdx, rcx
    jge .d
    cmp byte[rsi+rdx], 10
    jne .nx
    inc rax
.nx:inc rdx
    jmp .l
.d: pop rdx
    pop rcx
    pop rsi
    ret
.bad:
    xor rax, rax
    pop rdx
    pop rcx
    pop rsi
    ret

; ptr_to_col: rdi=ptr into source -> rax=column (0-based)
ptr_to_col:
    push rsi
    mov rsi, rdi
    xor rax, rax
.l: cmp rsi, [d_src]
    jle .d
    dec rsi
    cmp byte[rsi], 10
    je .d
    inc rax
    jmp .l
.d: pop rsi
    ret

; get_line_start: rdi=line_num (1-based) -> rax=pointer to line start
get_line_start:
    push rcx
    push rdx
    push rsi
    mov rsi, [d_src]
    mov rcx, rdi
    dec rcx
    xor rax, rax
    test rcx, rcx
    jz .found
.l: cmp rax, [d_srclen]
    jge .found
    cmp byte[rsi+rax], 10
    jne .nx
    dec rcx
    jz .nl
.nx:inc rax
    jmp .l
.nl:inc rax
.found:
    lea rax, [rsi+rax]
    pop rsi
    pop rdx
    pop rcx
    ret

; get_line_len: rdi=ptr to line start -> rax=length (no \r\n)
get_line_len:
    push rsi
    push rcx
    mov rsi, [d_src]
    add rsi, [d_srclen]
    xor rax, rax
.l: lea rcx, [rdi+rax]
    cmp rcx, rsi
    jge .d
    cmp byte[rdi+rax], 10
    je .d
    cmp byte[rdi+rax], 13
    je .d
    inc rax
    jmp .l
.d: pop rcx
    pop rsi
    ret

; ==================== LINE RENDERING ====================

; "  NN  " (4-char number + 2 spaces)
emit_gutter_num:
    push rcx
    mov rcx, 4
    call d_numr
    mov rcx, 2
    call d_pad
    pop rcx
    ret

; "      " (6 blank spaces for non-numbered lines)
emit_gutter_blank:
    push rcx
    mov rcx, 6
    call d_pad
    pop rcx
    ret

; ": "
emit_pipe:
    lea rdi, [dr_pipe]
    call d_putz
    ret

; full source line: "  NN  : source text\r\n"
emit_source_line:
    push r12
    push r13
    mov r12, rax
    call d_reset
    mov rax, r12
    call emit_gutter_num
    call emit_pipe
    mov rdi, r12
    call get_line_start
    mov r13, rax
    mov rdi, rax
    call get_line_len
    mov rsi, r13
    mov rdx, rax
    call d_putb
    call d_nl
    pop r13
    pop r12
    ret

; source line padded to ANNOT_COL (no newline, caller appends annotation then d_nl)
emit_src_padded:
    push r12
    push r13
    mov r12, rax
    call d_reset
    mov rax, r12
    call emit_gutter_num
    call emit_pipe
    mov rdi, r12
    call get_line_start
    mov r13, rax
    mov rdi, rax
    call get_line_len
    mov rsi, r13
    mov rdx, rax
    call d_putb
    ; pad to ANNOT_COL
    mov rcx, [d_lpos]
    mov rax, ANNOT_COL
    sub rax, rcx
    cmp rax, 2
    jge .pk
    mov rax, 2
.pk:
    mov rcx, rax
    call d_pad
    pop r13
    pop r12
    ret

; underline: "      :  col ~~~~  message\r\n"
; rcx=col, r8=tilde_len, rdi=message
emit_underline:
    push r12
    push r13
    push r14
    mov r12, rcx
    mov r13, r8
    mov r14, rdi
    call d_reset
    call emit_gutter_blank
    call emit_pipe
    mov rcx, r12
    call d_pad
    mov rcx, r13
    test rcx, rcx
    jz .msg
    call d_tilde
.msg:
    mov al, ' '
    call d_putc
    mov al, ' '
    call d_putc
    mov rdi, r14
    call d_putz
    call d_nl
    pop r14
    pop r13
    pop r12
    ret

; "      :\r\n"
emit_ctx_line:
    call d_reset
    call emit_gutter_blank
    mov al, ':'
    call d_putc
    call d_nl
    ret

; "      '- message\r\n" (rdi=message)
emit_hint:
    push r12
    mov r12, rdi
    call d_reset
    call emit_gutter_blank
    lea rdi, [dr_hint]
    call d_putz
    mov rdi, r12
    call d_putz
    call d_nl
    pop r12
    ret

; "      : ...\r\n"
emit_dots_line:
    call d_reset
    call emit_gutter_blank
    call emit_pipe
    lea rdi, [dr_dots]
    call d_putz
    call d_nl
    ret

; "  ERR[Exxx] title\r\n\r\n"
emit_header:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    call d_reset
    mov rcx, 2
    call d_pad
    mov rdi, r12
    call d_putz
    mov rdi, r13
    call d_putz
    call d_nl
    call d_reset
    call d_nl
    pop r13
    pop r12
    ret

; "      filename\r\n"
emit_filename:
    call d_reset
    call emit_gutter_blank
    mov rsi, [d_fname]
    mov rdx, [d_fnamelen]
    call d_putb
    call d_nl
    ret

emit_blank:
    call d_reset
    call d_nl
    ret

; ==================== PUBLIC API ====================

; diag_init: rdi=src_buf, rsi=src_len, rdx=fname, rcx=fname_len
diag_init:
    mov [d_src], rdi
    mov [d_srclen], rsi
    mov [d_fname], rdx
    mov [d_fnamelen], rcx
    mov qword[d_errors], 0
    mov qword[d_warnings], 0
    ret

diag_get_errors:
    mov rax, [d_errors]
    ret

; diag_err_undef_var: rdi=name_ptr, rsi=name_len
; ERR[E001] with source line and underline
diag_err_undef_var:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    inc qword[d_errors]
    ; compute position
    mov rdi, r12
    call ptr_to_line
    mov r14, rax
    mov rdi, r12
    call ptr_to_col
    mov r15, rax
    ; header
    lea rdi, [de001h]
    lea rsi, [de001t]
    call emit_header
    ; filename
    call emit_filename
    ; source line
    mov rax, r14
    call emit_source_line
    ; underline under the name
    mov rcx, r15
    mov r8, r13
    lea rdi, [da_noscope]
    call emit_underline
    ; context + blank
    call emit_ctx_line
    call emit_blank
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; diag_err_undef_fn: rdi=name_ptr, rsi=name_len
; ERR[E003] with source line and underline
diag_err_undef_fn:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    inc qword[d_errors]
    mov rdi, r12
    call ptr_to_line
    mov r14, rax
    mov rdi, r12
    call ptr_to_col
    mov r15, rax
    lea rdi, [de003h]
    lea rsi, [de003t]
    call emit_header
    call emit_filename
    mov rax, r14
    call emit_source_line
    mov rcx, r15
    mov r8, r13
    lea rdi, [da_notdef]
    call emit_underline
    call emit_ctx_line
    call emit_blank
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; diag_err_wrong_argc: rdi=call_ptr, rsi=call_len, rdx=expected, rcx=got,
;                      r8=def_ptr, r9=def_len
; ERR[E002] with definition line, dots, call line, hint
diag_err_wrong_argc:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 48
    mov [rsp+0], rdi       ; call name ptr
    mov [rsp+8], rsi       ; call name len
    mov [rsp+16], rdx      ; expected
    mov [rsp+24], rcx      ; got
    mov [rsp+32], r8       ; def name ptr
    mov [rsp+40], r9       ; def name len
    inc qword[d_errors]
    ; header
    lea rdi, [de002h]
    lea rsi, [de002t]
    call emit_header
    ; filename
    call emit_filename
    ; definition line with right annotation
    mov rdi, [rsp+32]
    test rdi, rdi
    jz .no_def
    call ptr_to_line
    test rax, rax
    jz .no_def
    ; padded source line (no newline yet)
    call emit_src_padded
    ; append ". defined: N params"
    lea rdi, [da_defn]
    call d_putz
    mov rax, [rsp+16]
    call d_num
    lea rdi, [da_params]
    call d_putz
    call d_nl
    ; dots separator
    call emit_dots_line
.no_def:
    ; call site line with right annotation
    mov rdi, [rsp+0]
    call ptr_to_line
    ; padded source line
    call emit_src_padded
    ; append "* called: M args"
    lea rdi, [da_call]
    call d_putz
    mov rax, [rsp+24]
    call d_num
    lea rdi, [da_args]
    call d_putz
    call d_nl
    ; context
    call emit_ctx_line
    ; hint: "expected N arguments, got M"
    call d_reset
    call emit_gutter_blank
    lea rdi, [dr_hint]
    call d_putz
    lea rdi, [da_expect]
    call d_putz
    mov rax, [rsp+16]
    call d_num
    lea rdi, [da_got]
    call d_putz
    mov rax, [rsp+24]
    call d_num
    call d_nl
    ; trailing blank
    call emit_blank
    add rsp, 48
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; diag_summary: "  N errors, M warnings\r\n"
diag_summary:
    call d_reset
    call emit_blank
    call d_reset
    mov rcx, 2
    call d_pad
    mov rax, [d_errors]
    call d_num
    lea rdi, [sm_err]
    call d_putz
    mov rax, [d_warnings]
    call d_num
    lea rdi, [sm_warn]
    call d_putz
    call d_nl
    ret