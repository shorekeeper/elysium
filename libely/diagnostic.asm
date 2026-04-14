; diagnostic.asm -- structured error formatter with ANSI color
; E001: undefined variable
; E002: wrong argument count
; E003: undefined function
; E004: type mismatch / value out of range
default rel
%include "defs.inc"
extern platform_write

global diag_init, diag_get_errors, diag_summary
global diag_err_undef_var, diag_err_undef_fn, diag_err_wrong_argc
global diag_err_type_range

ANNOT_COL equ 52

section .data
d_spaces: times 80 db ' '
d_tildes: times 80 db '~'

; ANSI color sequences (27 = ESC)
c_rs:   db 27,"[0m",0
c_red:  db 27,"[31m",0
c_cyan: db 27,"[36m",0
c_white:db 27,"[37m",0
c_gray: db 27,"[90m",0
c_bred: db 27,"[1;31m",0
c_byel: db 27,"[1;33m",0
c_bcyan:db 27,"[1;36m",0
c_bwht: db 27,"[1;37m",0

; error tags
de001h: db "ERR[E001]",0
de001t: db " undefined variable",0
de002h: db "ERR[E002]",0
de002t: db " wrong argument count",0
de003h: db "ERR[E003]",0
de003t: db " undefined function",0
de004h: db "ERR[E004]",0
de004t: db " type mismatch",0

; annotations
da_noscope: db "not in scope",0
da_notdef:  db "not defined",0
da_defn:    db ". defined: ",0
da_params:  db " params",0
da_call:    db "* called: ",0
da_args:    db " args",0
da_expect:  db "expected ",0
da_got:     db " arguments, got ",0
da_oor:     db " out of range for ",0
da_range:   db " range: ",0
da_dotdot:  db "..",0
da_usewider:db "use wider type or cast explicitly",0

; type names for diagnostics
dt_i8:  db "i8",0
dt_u8:  db "u8",0
dt_i16: db "i16",0
dt_u16: db "u16",0
dt_i32: db "i32",0
dt_u32: db "u32",0

; rendering
dr_pipe: db ": ",0
dr_hint: db "'- ",0
dr_dots: db "...",0

; summary
sm_pre_err:  db " error(s), ",0
sm_pre_warn: db " warning(s)",0

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

; buffer: reset position
d_reset:
    mov qword[d_lpos], 0
    ret

; buffer: flush to stdout
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

; buffer: append byte al
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

; buffer: append rsi=ptr rdx=len
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

; buffer: append null-terminated rdi
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

; buffer: append rcx spaces
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

; buffer: append rcx tildes
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

; buffer: CRLF + flush
d_nl:
    mov al, 13
    call d_putc
    mov al, 10
    call d_putc
    call d_flush
    ret

; buffer: append decimal rax (signed)
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

; append rax right-justified in rcx chars
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

; color helpers: each appends ANSI escape to buffer
d_bred:  lea rdi,[c_bred]
    jmp d_putz
d_bwht:  lea rdi,[c_bwht]
    jmp d_putz
d_byel:  lea rdi,[c_byel]
    jmp d_putz
d_red:   lea rdi,[c_red]
    jmp d_putz
d_cyan:  lea rdi,[c_cyan]
    jmp d_putz
d_gray:  lea rdi,[c_gray]
    jmp d_putz
d_white: lea rdi,[c_white]
    jmp d_putz
d_rs:    lea rdi,[c_rs]
    jmp d_putz

; source: rdi=ptr -> rax=line number (1-based)
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

; source: rdi=ptr -> rax=column (0-based)
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

; source: rdi=line_num -> rax=pointer to line start
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

; source: rdi=line_start_ptr -> rax=length (no CRLF)
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

; render: gray line number right-justified in 4 chars + 2 spaces
emit_gutter_num:
    push rcx
    call d_gray
    mov rcx, 4
    call d_numr
    mov rcx, 2
    call d_pad
    call d_rs
    pop rcx
    ret

; render: 6 blank spaces (for non-numbered lines)
emit_gutter_blank:
    push rcx
    mov rcx, 6
    call d_pad
    pop rcx
    ret

; render: gray ": "
emit_pipe:
    call d_gray
    lea rdi, [dr_pipe]
    call d_putz
    call d_rs
    ret

; render full source line: "  NN  : source text"
; rax = line number
emit_source_line:
    push r12
    push r13
    mov r12, rax
    call d_reset
    mov rax, r12
    call emit_gutter_num
    call emit_pipe
    call d_white
    mov rdi, r12
    call get_line_start
    mov r13, rax
    mov rdi, rax
    call get_line_len
    mov rsi, r13
    mov rdx, rax
    call d_putb
    call d_rs
    call d_nl
    pop r13
    pop r12
    ret

; render source line padded to ANNOT_COL (no newline, caller appends annotation)
; rax = line number
emit_src_padded:
    push r12
    push r13
    mov r12, rax
    call d_reset
    mov rax, r12
    call emit_gutter_num
    call emit_pipe
    call d_white
    mov rdi, r12
    call get_line_start
    mov r13, rax
    mov rdi, rax
    call get_line_len
    mov rsi, r13
    mov rdx, rax
    call d_putb
    call d_rs
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

; render underline: "      :  <col spaces><tildes>  <message>"
; rcx=col, r8=tilde_len, rdi=message (printed in red)
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
    call d_red
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
    call d_rs
    call d_nl
    pop r14
    pop r13
    pop r12
    ret

; render context line: "      :"
emit_ctx_line:
    call d_reset
    call emit_gutter_blank
    call d_gray
    mov al, ':'
    call d_putc
    call d_rs
    call d_nl
    ret

; render hint: "      '- <message>"
; rdi = message (cyan prefix, gray text)
emit_hint:
    push r12
    mov r12, rdi
    call d_reset
    call emit_gutter_blank
    call d_cyan
    lea rdi, [dr_hint]
    call d_putz
    call d_rs
    call d_gray
    mov rdi, r12
    call d_putz
    call d_rs
    call d_nl
    pop r12
    ret

; render dots separator: "      : ..."
emit_dots_line:
    call d_reset
    call emit_gutter_blank
    call emit_pipe
    call d_gray
    lea rdi, [dr_dots]
    call d_putz
    call d_rs
    call d_nl
    ret

; render error header: "  ERR[Exxx] title" (bold red tag, bold white title)
; rdi=tag string, rsi=title string
emit_header:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    call d_reset
    mov rcx, 2
    call d_pad
    call d_bred
    mov rdi, r12
    call d_putz
    call d_rs
    call d_bwht
    mov rdi, r13
    call d_putz
    call d_rs
    call d_nl
    call d_reset
    call d_nl
    pop r13
    pop r12
    ret

; render filename: "      <filename>" in cyan
emit_filename:
    call d_reset
    call emit_gutter_blank
    call d_cyan
    mov rsi, [d_fname]
    mov rdx, [d_fnamelen]
    call d_putb
    call d_rs
    call d_nl
    ret

; render blank line
emit_blank:
    call d_reset
    call d_nl
    ret

; type info helpers for E004
; rdi=TYPE_* -> emit type name to buffer
d_type_name:
    cmp rdi, TYPE_I8
    je .i8
    cmp rdi, TYPE_U8
    je .u8
    cmp rdi, TYPE_I16
    je .i16
    cmp rdi, TYPE_U16
    je .u16
    cmp rdi, TYPE_I32
    je .i32
    cmp rdi, TYPE_U32
    je .u32
    ret
.i8:  lea rdi,[dt_i8]
    jmp d_putz
.u8:  lea rdi,[dt_u8]
    jmp d_putz
.i16: lea rdi,[dt_i16]
    jmp d_putz
.u16: lea rdi,[dt_u16]
    jmp d_putz
.i32: lea rdi,[dt_i32]
    jmp d_putz
.u32: lea rdi,[dt_u32]
    jmp d_putz

; rdi=TYPE_* -> rax=min value for range
d_type_min:
    cmp rdi, TYPE_I8
    je .i8
    cmp rdi, TYPE_I16
    je .i16
    cmp rdi, TYPE_I32
    je .i32
    xor rax, rax
    ret
.i8:  mov rax, -128
    ret
.i16: mov rax, -32768
    ret
.i32: mov rax, -2147483648
    ret

; rdi=TYPE_* -> rax=max value for range
d_type_max:
    cmp rdi, TYPE_I8
    je .i8
    cmp rdi, TYPE_U8
    je .u8
    cmp rdi, TYPE_I16
    je .i16
    cmp rdi, TYPE_U16
    je .u16
    cmp rdi, TYPE_I32
    je .i32
    cmp rdi, TYPE_U32
    je .u32
    mov rax, 0x7FFFFFFFFFFFFFFF
    ret
.i8:  mov rax, 127
    ret
.u8:  mov rax, 255
    ret
.i16: mov rax, 32767
    ret
.u16: mov rax, 65535
    ret
.i32: mov rax, 2147483647
    ret
.u32: mov rax, 4294967295
    ret

; public: init diagnostics
; rdi=src_buf, rsi=src_len, rdx=fname, rcx=fname_len
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

; E001: undefined variable
; rdi=name_ptr (into source), rsi=name_len
diag_err_undef_var:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    inc qword[d_errors]
    ; find position
    mov rdi, r12
    call ptr_to_line
    mov r14, rax
    mov rdi, r12
    call ptr_to_col
    mov r15, rax
    ; header + filename
    lea rdi, [de001h]
    lea rsi, [de001t]
    call emit_header
    call emit_filename
    ; source line
    mov rax, r14
    call emit_source_line
    ; underline at name position
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

; E003: undefined function
; rdi=name_ptr, rsi=name_len
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

; E002: wrong argument count
; rdi=call_ptr, rsi=call_len, rdx=expected, rcx=got, r8=def_ptr, r9=def_len
diag_err_wrong_argc:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 48
    mov [rsp+0], rdi
    mov [rsp+8], rsi
    mov [rsp+16], rdx
    mov [rsp+24], rcx
    mov [rsp+32], r8
    mov [rsp+40], r9
    inc qword[d_errors]
    ; header
    lea rdi, [de002h]
    lea rsi, [de002t]
    call emit_header
    call emit_filename
    ; definition line with right annotation (gray)
    mov rdi, [rsp+32]
    test rdi, rdi
    jz .no_def
    call ptr_to_line
    test rax, rax
    jz .no_def
    call emit_src_padded
    call d_gray
    lea rdi, [da_defn]
    call d_putz
    mov rax, [rsp+16]
    call d_num
    lea rdi, [da_params]
    call d_putz
    call d_rs
    call d_nl
    call emit_dots_line
.no_def:
    ; call site line with red annotation
    mov rdi, [rsp+0]
    call ptr_to_line
    call emit_src_padded
    call d_red
    lea rdi, [da_call]
    call d_putz
    mov rax, [rsp+24]
    call d_num
    lea rdi, [da_args]
    call d_putz
    call d_rs
    call d_nl
    ; context
    call emit_ctx_line
    ; hint line: "expected N arguments, got M"
    call d_reset
    call emit_gutter_blank
    call d_cyan
    lea rdi, [dr_hint]
    call d_putz
    call d_rs
    call d_gray
    lea rdi, [da_expect]
    call d_putz
    mov rax, [rsp+16]
    call d_num
    lea rdi, [da_got]
    call d_putz
    mov rax, [rsp+24]
    call d_num
    call d_rs
    call d_nl
    call emit_blank
    add rsp, 48
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; E004: type mismatch / value out of range
; rdi=name_ptr, rsi=name_len, rdx=value, rcx=type_id
diag_err_type_range:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r12, rdi       ; name ptr (source position)
    mov r13, rsi       ; name len
    mov r14, rdx       ; literal value
    mov r15, rcx       ; TYPE_*
    inc qword[d_errors]
    ; header
    lea rdi, [de004h]
    lea rsi, [de004t]
    call emit_header
    call emit_filename
    ; source line with right annotation: "! <value> out of range for <type>"
    mov rdi, r12
    call ptr_to_line
    call emit_src_padded
    call d_red
    mov al, '!'
    call d_putc
    mov al, ' '
    call d_putc
    mov rax, r14
    call d_num
    lea rdi, [da_oor]
    call d_putz
    mov rdi, r15
    call d_type_name
    call d_rs
    call d_nl
    ; context line
    call emit_ctx_line
    ; hint: "<type> range: <min>..<max>"
    call d_reset
    call emit_gutter_blank
    call d_cyan
    lea rdi, [dr_hint]
    call d_putz
    call d_rs
    call d_gray
    mov rdi, r15
    call d_type_name
    lea rdi, [da_range]
    call d_putz
    mov rdi, r15
    call d_type_min
    call d_num
    lea rdi, [da_dotdot]
    call d_putz
    mov rdi, r15
    call d_type_max
    call d_num
    call d_rs
    call d_nl
    ; second hint: suggestion
    lea rdi, [da_usewider]
    call emit_hint
    call emit_blank
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; summary: "  N error(s), M warning(s)" with colors
diag_summary:
    call d_reset
    call emit_blank
    call d_reset
    mov rcx, 2
    call d_pad
    ; error count: bold red if > 0, else white
    cmp qword[d_errors], 0
    je .err_ok
    call d_bred
    jmp .perr
.err_ok:
    call d_white
.perr:
    mov rax, [d_errors]
    call d_num
    lea rdi, [sm_pre_err]
    call d_putz
    call d_rs
    ; warning count: bold yellow if > 0, else gray
    cmp qword[d_warnings], 0
    je .warn_ok
    call d_byel
    jmp .pwarn
.warn_ok:
    call d_gray
.pwarn:
    mov rax, [d_warnings]
    call d_num
    lea rdi, [sm_pre_warn]
    call d_putz
    call d_rs
    call d_nl
    ret