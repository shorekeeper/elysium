; Renders structured error blocks with UTF-8 box drawing, source context,
; underlines, location pointers, and help/note suggestions.
default rel
%include "defs.inc"
extern platform_write

global diag_init, diag_get_errors, diag_get_warnings, diag_summary
global diag_err_undef_var, diag_err_undef_fn, diag_err_wrong_argc
global diag_err_type_range, diag_err_dup_var
global diag_warn_unreachable, diag_warn_shadow_var
global diag_err_missing_return, diag_warn_unused_var
global diag_err_leak_unwind, diag_warn_div_supervise

ANNOT_COL equ 52

section .data
; UTF-8 box drawing: heavy ━ and light ─
d_heavy76: times 76 db 0xE2,0x94,0x81
d_heavy76_len equ $ - d_heavy76
d_light72: times 72 db 0xE2,0x94,0x80
d_light72_len equ $ - d_light72
d_spaces: times 80 db ' '
d_tildes: times 80 db '~'

; ANSI escape sequences
c_rs:   db 27,"[0m",0
c_red:  db 27,"[31m",0
c_cyan: db 27,"[36m",0
c_white:db 27,"[37m",0
c_gray: db 27,"[90m",0
c_bred: db 27,"[1;31m",0
c_byel: db 27,"[1;33m",0
c_bwht: db 27,"[1;37m",0

; format tokens
s_error:    db "error",0
s_warning:  db "warning",0
s_lbr:      db "[",0
s_rbr_col:  db "]: ",0
s_arrow:    db " --> ",0
s_pipe_sep: db " | ",0
s_eq_help:  db "  = help: ",0
s_eq_note:  db "  = note: ",0
s_dots:     db " | ...",0

; E001 undefined variable
s_e001:      db "E001",0
s_e001_msg:  db "undefined variable",0
s_e001_ann:  db "not in scope",0
s_e001_help: db "check spelling or declare before use",0
; E002 wrong argument count
s_e002:      db "E002",0
s_e002_msg:  db "wrong argument count",0
s_e002_def:  db ". defined: ",0
s_e002_params:db " params",0
s_e002_call: db "* called: ",0
s_e002_args: db " args",0
s_e002_exp:  db "expected ",0
s_e002_got:  db " arguments, got ",0
; E003 undefined function
s_e003:      db "E003",0
s_e003_msg:  db "undefined function",0
s_e003_ann:  db "not defined",0
s_e003_help: db "check function name or add definition",0
; E004 type mismatch
s_e004:      db "E004",0
s_e004_msg:  db "type mismatch",0
s_e004_oor:  db "! value out of range",0
s_e004_range:db " range: ",0
s_e004_dd:   db "..",0
s_e004_help: db "use wider type or cast explicitly",0
; E005 duplicate variable
s_e005:      db "E005",0
s_e005_msg:  db "duplicate variable",0
s_e005_ann:  db "already defined in this scope",0
s_e005_help: db "rename or remove duplicate declaration",0
; E006 missing return
s_e006:      db "E006",0
s_e006_msg:  db "missing return statement",0
s_e006_ann:  db "return type declared but no return in body",0
s_e006_help: db "add 'return <expr>;' at end of function body",0
; E007 unreachable code
s_e007:      db "E007",0
s_e007_msg:  db "unreachable code",0
s_e007_ann:  db "unreachable after return",0
s_e007_help: db "remove dead code or move before return",0
; E008 unused variable
s_e008:      db "E008",0
s_e008_msg:  db "unused variable",0
s_e008_ann:  db "declared but never used",0
s_e008_help: db "remove or prefix with underscore",0
; E009 variable shadows outer scope
s_e009:      db "E009",0
s_e009_msg:  db "variable shadows outer scope",0
s_e009_ann:  db "shadows outer definition",0
s_e009_help: db "rename to avoid confusion",0
; E010 potential leak in unwind path
s_e010:       db "E010",0
s_e010_msg:   db "potential leak in unwind path",0
s_e010_anc:   db "* scope opens",0
s_e010_alloc: db "* alloc",0
s_e010_exit:  db "! exits without release",0
s_e010_n1:    db "'",0
s_e010_n2:    db "' from :",0
s_e010_n3:    db " never released before unwind at :",0
s_e010_h1:    db "add 'release(",0
s_e010_h2:    db ");' before unwind",0
; E011 division inside supervise
s_e011:       db "E011",0
s_e011_msg:   db "division inside supervise block",0
s_e011_sup:   db "* supervised scope",0
s_e011_div:   db "! potential div/0",0
s_e011_note:  db "if divisor is zero, supervise catches and resumes after block",0
s_e011_help:  db "check divisor explicitly or handle the zero case",0
    
; type names for E004
dt_i8: db "i8",0
dt_u8: db "u8",0
dt_i16:db "i16",0
dt_u16:db "u16",0
dt_i32:db "i32",0
dt_u32:db "u32",0

; session summary
s_sum_title: db "elysiumc: compilation session summary",0
s_sum_errs:  db " error(s)  |  ",0
s_sum_warns: db " warning(s)",0
s_sum_break: db "-- Breakdown --",0
s_sum_err_t: db "   ERR   ",0
s_sum_wrn_t: db "  WARN   ",0
s_sum_x:     db "  x",0
s_sum_src:   db "Source: ",0
s_sum_lp:    db " (",0
s_sum_bytes: db " bytes)",0
s_sum_tgt:   db "Target: win64",0
s_sum_fix:   db "fix all errors before compilation can proceed",0
s_sum_clean: db "all checks passed",0

; breakdown metadata
d_code_is_warn: db 0, 0,0,0,0,0,0,1,1,1, 0,1,0,0,0,0
;                   _ 1 2 3 4 5 6 7 8 9  10 11

align 8
d_code_ptrs:
    dq 0
    dq s_e001, s_e002, s_e003, s_e004, s_e005, s_e006, s_e007, s_e008, s_e009
    dq s_e010, s_e011, 0,0,0,0

section .bss
d_src:      resq 1
d_srclen:   resq 1
d_fname:    resq 1
d_fnamelen: resq 1
d_errors:   resq 1
d_warnings: resq 1
d_lbuf:     resb 2048
d_lpos:     resq 1
d_code_cnt: resq 16

section .text

; buffer management
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

d_nl:
    mov al, 13
    call d_putc
    mov al, 10
    call d_putc
    call d_flush
    ret

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
.ext:test rax, rax
    jz .bld
    xor rdx, rdx
    div rbx
    add dl, '0'
    push rdx
    inc rcx
    jmp .ext
.bld:test rcx, rcx
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

d_digits:
    push rax
    push rbx
    push rdx
    xor rcx, rcx
    test rax, rax
    jnz .nz
    mov rcx, 1
    jmp .d
.nz:mov rbx, 10
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

d_numr:
    push r12
    push r13
    mov r12, rax
    mov r13, rcx
    call d_digits
    sub r13, rcx
    test r13, r13
    jle .n
    mov rcx, r13
    call d_pad
.n: mov rax, r12
    call d_num
    pop r13
    pop r12
    ret

; color helpers
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

; source lookup
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
.bad:xor rax, rax
    pop rdx
    pop rcx
    pop rsi
    ret

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

; type helpers for E004
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

; rendering: heavy rule "  ━━━━━━━━..."
emit_heavy_rule:
    call d_reset
    mov rcx, 2
    call d_pad
    call d_gray
    lea rsi, [d_heavy76]
    mov rdx, d_heavy76_len
    call d_putb
    call d_rs
    call d_nl
    ret

; rendering: light rule "      |  ────..."
emit_light_rule:
    call d_reset
    call d_gray
    mov rcx, 6
    call d_pad
    mov al, '|'
    call d_putc
    mov al, ' '
    call d_putc
    mov al, ' '
    call d_putc
    lea rsi, [d_light72]
    mov rdx, d_light72_len
    call d_putb
    call d_rs
    call d_nl
    ret

; rendering: "  error[CODE]: MSG"
; rdi=code_str, rsi=msg_str
emit_error_head:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    call d_reset
    mov rcx, 2
    call d_pad
    call d_bred
    lea rdi, [s_error]
    call d_putz
    lea rdi, [s_lbr]
    call d_putz
    mov rdi, r12
    call d_putz
    lea rdi, [s_rbr_col]
    call d_putz
    call d_rs
    call d_bwht
    mov rdi, r13
    call d_putz
    call d_rs
    call d_nl
    pop r13
    pop r12
    ret

; rendering: "  warning[CODE]: MSG"
emit_warn_head:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    call d_reset
    mov rcx, 2
    call d_pad
    call d_byel
    lea rdi, [s_warning]
    call d_putz
    lea rdi, [s_lbr]
    call d_putz
    mov rdi, r12
    call d_putz
    lea rdi, [s_rbr_col]
    call d_putz
    call d_rs
    call d_bwht
    mov rdi, r13
    call d_putz
    call d_rs
    call d_nl
    pop r13
    pop r12
    ret

; rendering: " --> file:line:col"
; rdi=line, rsi=col
emit_location:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    call d_reset
    call d_cyan
    lea rdi, [s_arrow]
    call d_putz
    call d_rs
    call d_white
    mov rsi, [d_fname]
    mov rdx, [d_fnamelen]
    call d_putb
    mov al, ':'
    call d_putc
    mov rax, r12
    call d_num
    mov al, ':'
    call d_putc
    mov rax, r13
    call d_num
    call d_rs
    call d_nl
    pop r13
    pop r12
    ret

; rendering: "      |" (empty pipe line)
emit_pipe_empty:
    call d_reset
    call d_gray
    mov rcx, 6
    call d_pad
    mov al, '|'
    call d_putc
    call d_rs
    call d_nl
    ret

; rendering: "    N | source text" (source line with gutter)
; rax=line_number
emit_pipe_src:
    push r12
    push r13
    mov r12, rax
    call d_reset
    call d_gray
    mov rax, r12
    mov rcx, 5
    call d_numr
    lea rdi, [s_pipe_sep]
    call d_putz
    call d_rs
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

; rendering: source line padded to ANNOT_COL (no newline, caller appends)
; rax=line_number
emit_pipe_src_pad:
    push r12
    push r13
    mov r12, rax
    call d_reset
    call d_gray
    mov rax, r12
    mov rcx, 5
    call d_numr
    lea rdi, [s_pipe_sep]
    call d_putz
    call d_rs
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
.pk:mov rcx, rax
    call d_pad
    pop r13
    pop r12
    ret

; rendering: "      | [col spaces][tildes] [msg]"
; rcx=col, r8=tilde_count, rdi=msg, rsi=color_str (c_red or c_byel)
emit_pipe_under:
    push r12
    push r13
    push r14
    push r15
    mov r12, rcx
    mov r13, r8
    mov r14, rdi
    mov r15, rsi
    call d_reset
    call d_gray
    mov rcx, 6
    call d_pad
    mov al, '|'
    call d_putc
    mov al, ' '
    call d_putc
    call d_rs
    ; col spaces
    mov rcx, r12
    call d_pad
    ; tildes in specified color
    mov rdi, r15
    call d_putz
    mov rcx, r13
    call d_tilde
    mov al, ' '
    call d_putc
    mov rdi, r14
    call d_putz
    call d_rs
    call d_nl
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; rendering: "  = help: text"
; rdi=help_text
emit_help:
    push r12
    mov r12, rdi
    call d_reset
    call d_cyan
    lea rdi, [s_eq_help]
    call d_putz
    call d_rs
    call d_gray
    mov rdi, r12
    call d_putz
    call d_rs
    call d_nl
    pop r12
    ret

; rendering: blank line
emit_blank:
    call d_reset
    call d_nl
    ret

; public: init
diag_init:
    mov [d_src], rdi
    mov [d_srclen], rsi
    mov [d_fname], rdx
    mov [d_fnamelen], rcx
    mov qword[d_errors], 0
    mov qword[d_warnings], 0
    ; zero all code counters
    push rdi
    push rcx
    lea rdi, [d_code_cnt]
    mov rcx, 16
    xor rax, rax
    rep stosq
    pop rcx
    pop rdi
    ret

diag_get_errors:
    mov rax, [d_errors]
    ret

diag_get_warnings:
    mov rax, [d_warnings]
    ret

; E001: undefined variable
; rdi=name_ptr (source), rsi=name_len
diag_err_undef_var:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    inc qword[d_errors]
    inc qword[d_code_cnt + 1*8]
    mov rdi, r12
    call ptr_to_line
    mov r14, rax
    mov rdi, r12
    call ptr_to_col
    mov r15, rax
    call emit_heavy_rule
    lea rdi, [s_e001]
    lea rsi, [s_e001_msg]
    call emit_error_head
    mov rdi, r14
    mov rsi, r15
    call emit_location
    call emit_light_rule
    call emit_pipe_empty
    mov rax, r14
    call emit_pipe_src
    mov rcx, r15
    mov r8, r13
    lea rdi, [s_e001_ann]
    lea rsi, [c_red]
    call emit_pipe_under
    call emit_pipe_empty
    lea rdi, [s_e001_help]
    call emit_help
    call emit_heavy_rule
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
    inc qword[d_code_cnt + 3*8]
    mov rdi, r12
    call ptr_to_line
    mov r14, rax
    mov rdi, r12
    call ptr_to_col
    mov r15, rax
    call emit_heavy_rule
    lea rdi, [s_e003]
    lea rsi, [s_e003_msg]
    call emit_error_head
    mov rdi, r14
    mov rsi, r15
    call emit_location
    call emit_light_rule
    call emit_pipe_empty
    mov rax, r14
    call emit_pipe_src
    mov rcx, r15
    mov r8, r13
    lea rdi, [s_e003_ann]
    lea rsi, [c_red]
    call emit_pipe_under
    call emit_pipe_empty
    lea rdi, [s_e003_help]
    call emit_help
    call emit_heavy_rule
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
    inc qword[d_code_cnt + 2*8]
    ; header
    call emit_heavy_rule
    lea rdi, [s_e002]
    lea rsi, [s_e002_msg]
    call emit_error_head
    ; location at call site
    mov rdi, [rsp+0]
    call ptr_to_line
    push rax
    mov rdi, [rsp+8]
    call ptr_to_col
    mov rsi, rax
    pop rdi
    call emit_location
    call emit_light_rule
    call emit_pipe_empty
    ; definition line (if available) with right annotation
    mov rdi, [rsp+32]
    test rdi, rdi
    jz .no_def
    call ptr_to_line
    test rax, rax
    jz .no_def
    call emit_pipe_src_pad
    call d_gray
    lea rdi, [s_e002_def]
    call d_putz
    mov rax, [rsp+16]
    call d_num
    lea rdi, [s_e002_params]
    call d_putz
    call d_rs
    call d_nl
    ; dots
    call d_reset
    call d_gray
    mov rcx, 6
    call d_pad
    mov al, '|'
    call d_putc
    lea rdi, [s_dots]
    call d_putz
    call d_rs
    call d_nl
.no_def:
    ; call site line with right annotation
    mov rdi, [rsp+0]
    call ptr_to_line
    call emit_pipe_src_pad
    call d_red
    lea rdi, [s_e002_call]
    call d_putz
    mov rax, [rsp+24]
    call d_num
    lea rdi, [s_e002_args]
    call d_putz
    call d_rs
    call d_nl
    call emit_pipe_empty
    ; help: "expected N arguments, got M"
    call d_reset
    call d_cyan
    lea rdi, [s_eq_help]
    call d_putz
    call d_rs
    call d_gray
    lea rdi, [s_e002_exp]
    call d_putz
    mov rax, [rsp+16]
    call d_num
    lea rdi, [s_e002_got]
    call d_putz
    mov rax, [rsp+24]
    call d_num
    call d_rs
    call d_nl
    call emit_heavy_rule
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
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    inc qword[d_errors]
    inc qword[d_code_cnt + 4*8]
    mov rdi, r12
    call ptr_to_line
    mov rbp, rax
    mov rdi, r12
    call ptr_to_col
    mov rbx, rax
    call emit_heavy_rule
    lea rdi, [s_e004]
    lea rsi, [s_e004_msg]
    call emit_error_head
    mov rdi, rbp
    mov rsi, rbx
    call emit_location
    call emit_light_rule
    call emit_pipe_empty
    ; source line with right annotation
    mov rax, rbp
    call emit_pipe_src_pad
    call d_red
    lea rdi, [s_e004_oor]
    call d_putz
    call d_rs
    call d_nl
    ; underline under the value
    mov rcx, rbx
    mov r8, r13
    test r8, r8
    jz .no_under
    push rbx
    lea rdi, [c_rs]
    call d_putz
    pop rbx
    call d_reset
    call d_gray
    mov rcx, 6
    call d_pad
    mov al, '|'
    call d_putc
    mov al, ' '
    call d_putc
    call d_rs
    mov rcx, rbx
    call d_pad
    call d_red
    mov rcx, r13
    call d_tilde
    call d_rs
    call d_nl
.no_under:
    call emit_pipe_empty
    ; = note: type range
    call d_reset
    call d_cyan
    lea rdi, [s_eq_note]
    call d_putz
    call d_rs
    call d_gray
    mov rdi, r15
    call d_type_name
    lea rdi, [s_e004_range]
    call d_putz
    mov rdi, r15
    call d_type_min
    call d_num
    lea rdi, [s_e004_dd]
    call d_putz
    mov rdi, r15
    call d_type_max
    call d_num
    call d_rs
    call d_nl
    lea rdi, [s_e004_help]
    call emit_help
    call emit_heavy_rule
    call emit_blank
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; E005: duplicate variable
; rdi=name_ptr, rsi=name_len
diag_err_dup_var:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    inc qword[d_errors]
    inc qword[d_code_cnt + 5*8]
    mov rdi, r12
    call ptr_to_line
    mov r14, rax
    mov rdi, r12
    call ptr_to_col
    mov r15, rax
    call emit_heavy_rule
    lea rdi, [s_e005]
    lea rsi, [s_e005_msg]
    call emit_error_head
    mov rdi, r14
    mov rsi, r15
    call emit_location
    call emit_light_rule
    call emit_pipe_empty
    mov rax, r14
    call emit_pipe_src
    mov rcx, r15
    mov r8, r13
    lea rdi, [s_e005_ann]
    lea rsi, [c_red]
    call emit_pipe_under
    call emit_pipe_empty
    lea rdi, [s_e005_help]
    call emit_help
    call emit_heavy_rule
    call emit_blank
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; E007: unreachable code (warning)
; rdi=name_ptr, rsi=name_len
diag_warn_unreachable:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    inc qword[d_warnings]
    inc qword[d_code_cnt + 7*8]
    mov rdi, r12
    call ptr_to_line
    mov r14, rax
    mov rdi, r12
    call ptr_to_col
    mov r15, rax
    call emit_heavy_rule
    lea rdi, [s_e007]
    lea rsi, [s_e007_msg]
    call emit_warn_head
    mov rdi, r14
    mov rsi, r15
    call emit_location
    call emit_light_rule
    call emit_pipe_empty
    ; show the previous line (return) and the unreachable line
    mov rax, r14
    dec rax
    test rax, rax
    jz .no_prev
    call emit_pipe_src
.no_prev:
    mov rax, r14
    call emit_pipe_src
    mov rcx, r15
    mov r8, r13
    test r8, r8
    jz .skip_under
    lea rdi, [s_e007_ann]
    lea rsi, [c_byel]
    call emit_pipe_under
    jmp .after_under
.skip_under:
    ; if no name, just show annotation on empty underline
    call d_reset
    call d_gray
    mov rcx, 6
    call d_pad
    mov al, '|'
    call d_putc
    mov al, ' '
    call d_putc
    call d_rs
    call d_byel
    lea rdi, [s_e007_ann]
    call d_putz
    call d_rs
    call d_nl
.after_under:
    call emit_pipe_empty
    lea rdi, [s_e007_help]
    call emit_help
    call emit_heavy_rule
    call emit_blank
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; E009: variable shadows outer scope (warning)
; rdi=name_ptr, rsi=name_len
diag_warn_shadow_var:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    inc qword[d_warnings]
    inc qword[d_code_cnt + 9*8]
    mov rdi, r12
    call ptr_to_line
    mov r14, rax
    mov rdi, r12
    call ptr_to_col
    mov r15, rax
    call emit_heavy_rule
    lea rdi, [s_e009]
    lea rsi, [s_e009_msg]
    call emit_warn_head
    mov rdi, r14
    mov rsi, r15
    call emit_location
    call emit_light_rule
    call emit_pipe_empty
    mov rax, r14
    call emit_pipe_src
    mov rcx, r15
    mov r8, r13
    lea rdi, [s_e009_ann]
    lea rsi, [c_byel]
    call emit_pipe_under
    call emit_pipe_empty
    lea rdi, [s_e009_help]
    call emit_help
    call emit_heavy_rule
    call emit_blank
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; E006: missing return statement
; rdi=func_name_ptr (source), rsi=func_name_len
diag_err_missing_return:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    inc qword[d_errors]
    inc qword[d_code_cnt + 6*8]
    mov rdi, r12
    call ptr_to_line
    mov r14, rax
    mov rdi, r12
    call ptr_to_col
    mov r15, rax
    call emit_heavy_rule
    lea rdi, [s_e006]
    lea rsi, [s_e006_msg]
    call emit_error_head
    mov rdi, r14
    mov rsi, r15
    call emit_location
    call emit_light_rule
    call emit_pipe_empty
    mov rax, r14
    call emit_pipe_src
    ; underline the function name
    mov rcx, r15
    mov r8, r13
    lea rdi, [s_e006_ann]
    lea rsi, [c_red]
    call emit_pipe_under
    call emit_pipe_empty
    lea rdi, [s_e006_help]
    call emit_help
    call emit_heavy_rule
    call emit_blank
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; E008: unused variable (warning)
; rdi=name_ptr (source), rsi=name_len
diag_warn_unused_var:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    inc qword[d_warnings]
    inc qword[d_code_cnt + 8*8]
    mov rdi, r12
    call ptr_to_line
    mov r14, rax
    mov rdi, r12
    call ptr_to_col
    mov r15, rax
    call emit_heavy_rule
    lea rdi, [s_e008]
    lea rsi, [s_e008_msg]
    call emit_warn_head
    mov rdi, r14
    mov rsi, r15
    call emit_location
    call emit_light_rule
    call emit_pipe_empty
    mov rax, r14
    call emit_pipe_src
    mov rcx, r15
    mov r8, r13
    lea rdi, [s_e008_ann]
    lea rsi, [c_byel]
    call emit_pipe_under
    call emit_pipe_empty
    lea rdi, [s_e008_help]
    call emit_help
    call emit_heavy_rule
    call emit_blank
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
; E010: potential leak in unwind path
; rdi=anchor_nptr, rsi=anchor_nlen, rdx=alloc_nptr, rcx=alloc_nlen,
; r8=unwind_nptr, r9=unwind_nlen
diag_err_leak_unwind:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 64
    mov [rsp+0], rdi       ; anchor name ptr
    mov [rsp+8], rsi       ; anchor name len
    mov [rsp+16], rdx      ; alloc name ptr
    mov [rsp+24], rcx      ; alloc name len
    mov [rsp+32], r8       ; unwind name ptr
    mov [rsp+40], r9       ; unwind name len
    inc qword[d_errors]
    inc qword[d_code_cnt + 10*8]
    ; compute line numbers
    mov rdi, [rsp+0]
    call ptr_to_line
    mov [rsp+48], rax      ; anchor line
    mov rdi, [rsp+16]
    call ptr_to_line
    mov [rsp+56], rax      ; alloc line
    mov rdi, [rsp+32]
    call ptr_to_line
    mov r14, rax           ; unwind line
    mov rdi, [rsp+32]
    call ptr_to_col
    mov r15, rax           ; unwind col
    ; header
    call emit_heavy_rule
    lea rdi, [s_e010]
    lea rsi, [s_e010_msg]
    call emit_error_head
    mov rdi, r14
    mov rsi, r15
    call emit_location
    call emit_light_rule
    call emit_pipe_empty
    ; anchor line: "  N | anchor safe {                * scope opens"
    mov rax, [rsp+48]
    call emit_pipe_src_pad
    call d_cyan
    lea rdi, [s_e010_anc]
    call d_putz
    call d_rs
    call d_nl
    call emit_pipe_empty
    ; alloc line: " NN | let ptr = claim(64);          * alloc"
    mov rax, [rsp+56]
    call emit_pipe_src_pad
    call d_byel
    lea rdi, [s_e010_alloc]
    call d_putz
    call d_rs
    call d_nl
    call emit_pipe_empty
    ; unwind line: " NN | unwind safe;                 ! exits without release"
    mov rax, r14
    call emit_pipe_src_pad
    call d_red
    lea rdi, [s_e010_exit]
    call d_putz
    call d_rs
    call d_nl
    ; underline under unwind name
    call d_reset
    call d_gray
    mov rcx, 6
    call d_pad
    mov al, '|'
    call d_putc
    mov al, ' '
    call d_putc
    call d_rs
    mov rcx, r15
    call d_pad
    call d_red
    mov rcx, [rsp+40]
    call d_tilde
    call d_rs
    call d_nl
    call emit_pipe_empty
    ; = note: 'ptr' from :12 never released before unwind at :15
    call d_reset
    call d_cyan
    lea rdi, [s_eq_note]
    call d_putz
    call d_rs
    call d_gray
    lea rdi, [s_e010_n1]
    call d_putz
    mov rsi, [rsp+16]
    mov rdx, [rsp+24]
    call d_putb
    lea rdi, [s_e010_n2]
    call d_putz
    mov rax, [rsp+56]
    call d_num
    lea rdi, [s_e010_n3]
    call d_putz
    mov rax, r14
    call d_num
    call d_rs
    call d_nl
    ; = help: add 'release(ptr);' before unwind
    call d_reset
    call d_cyan
    lea rdi, [s_eq_help]
    call d_putz
    call d_rs
    call d_gray
    lea rdi, [s_e010_h1]
    call d_putz
    mov rsi, [rsp+16]
    mov rdx, [rsp+24]
    call d_putb
    lea rdi, [s_e010_h2]
    call d_putz
    call d_rs
    call d_nl
    call emit_heavy_rule
    call emit_blank
    add rsp, 64
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; E011: division inside supervise block (warning)
; rdi=stmt_nptr, rsi=stmt_nlen, rdx=super_body_nptr, rcx=super_body_nlen
diag_warn_div_supervise:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 32
    mov [rsp+0], rdi       ; stmt name ptr (near division)
    mov [rsp+8], rsi       ; stmt name len
    mov [rsp+16], rdx      ; supervise body first stmt ptr
    mov [rsp+24], rcx      ; supervise body first stmt len
    inc qword[d_warnings]
    inc qword[d_code_cnt + 11*8]
    ; division line
    mov rdi, [rsp+0]
    call ptr_to_line
    mov r14, rax
    mov rdi, [rsp+0]
    call ptr_to_col
    mov r15, rax
    ; supervise line (approximate: 1 before first body stmt)
    mov rdi, [rsp+16]
    test rdi, rdi
    jz .sup_guess
    call ptr_to_line
    dec rax
    test rax, rax
    jnz .sup_ok
.sup_guess:
    mov rax, r14
    dec rax
.sup_ok:
    mov rbp, rax
    ; header
    call emit_heavy_rule
    lea rdi, [s_e011]
    lea rsi, [s_e011_msg]
    call emit_warn_head
    mov rdi, r14
    mov rsi, r15
    call emit_location
    call emit_light_rule
    call emit_pipe_empty
    ; supervise line
    mov rax, rbp
    call emit_pipe_src_pad
    call d_cyan
    lea rdi, [s_e011_sup]
    call d_putz
    call d_rs
    call d_nl
    call emit_pipe_empty
    ; division line
    mov rax, r14
    call emit_pipe_src_pad
    call d_red
    lea rdi, [s_e011_div]
    call d_putz
    call d_rs
    call d_nl
    call emit_pipe_empty
    ; = note
    call d_reset
    call d_cyan
    lea rdi, [s_eq_note]
    call d_putz
    call d_rs
    call d_gray
    lea rdi, [s_e011_note]
    call d_putz
    call d_rs
    call d_nl
    ; = help
    lea rdi, [s_e011_help]
    call emit_help
    call emit_heavy_rule
    call emit_blank
    add rsp, 32
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
; session summary with breakdown
diag_summary:
    push rbx
    push r12
    push r13
    call emit_blank
    call emit_heavy_rule
    ; title line
    call d_reset
    mov rcx, 2
    call d_pad
    call d_bwht
    lea rdi, [s_sum_title]
    call d_putz
    call d_rs
    call d_nl
    call emit_light_rule
    call emit_pipe_empty
    ; error/warning counts
    call d_reset
    call d_gray
    mov rcx, 6
    call d_pad
    mov al, '|'
    call d_putc
    mov al, ' '
    call d_putc
    mov al, ' '
    call d_putc
    mov al, ' '
    call d_putc
    call d_rs
    ; error count (red if >0)
    cmp qword[d_errors], 0
    je .ec_ok
    call d_bred
    jmp .ec_pr
.ec_ok:
    call d_white
.ec_pr:
    mov rax, [d_errors]
    call d_num
    lea rdi, [s_sum_errs]
    call d_putz
    call d_rs
    ; warning count (yellow if >0)
    cmp qword[d_warnings], 0
    je .wc_ok
    call d_byel
    jmp .wc_pr
.wc_ok:
    call d_gray
.wc_pr:
    mov rax, [d_warnings]
    call d_num
    lea rdi, [s_sum_warns]
    call d_putz
    call d_rs
    call d_nl
    call emit_pipe_empty
    ; breakdown header
    call d_reset
    call d_gray
    mov rcx, 6
    call d_pad
    mov al, '|'
    call d_putc
    mov al, ' '
    call d_putc
    mov al, ' '
    call d_putc
    call d_rs
    call d_white
    lea rdi, [s_sum_break]
    call d_putz
    call d_rs
    call d_nl
    ; iterate codes 1..9
    xor rbx, rbx
    inc rbx
.bd_l:
    cmp rbx, 12
    jge .bd_d
    cmp qword[d_code_cnt + rbx*8], 0
    je .bd_nx
    ; print breakdown line
    call d_reset
    call d_gray
    mov rcx, 6
    call d_pad
    mov al, '|'
    call d_putc
    call d_rs
    ; ERR or WARN tag
    movzx eax, byte[d_code_is_warn + rbx]
    test al, al
    jnz .bd_w
    call d_red
    lea rdi, [s_sum_err_t]
    call d_putz
    call d_rs
    jmp .bd_code
.bd_w:
    call d_byel
    lea rdi, [s_sum_wrn_t]
    call d_putz
    call d_rs
.bd_code:
    call d_white
    mov rdi, [d_code_ptrs + rbx*8]
    test rdi, rdi
    jz .bd_nx2
    call d_putz
.bd_nx2:
    lea rdi, [s_sum_x]
    call d_putz
    mov rax, [d_code_cnt + rbx*8]
    call d_num
    call d_rs
    call d_nl
.bd_nx:
    inc rbx
    jmp .bd_l
.bd_d:
    call emit_pipe_empty
    call emit_light_rule
    ; source info
    call d_reset
    call d_gray
    mov rcx, 6
    call d_pad
    mov al, '|'
    call d_putc
    mov al, ' '
    call d_putc
    mov al, ' '
    call d_putc
    call d_rs
    call d_gray
    lea rdi, [s_sum_src]
    call d_putz
    mov rsi, [d_fname]
    mov rdx, [d_fnamelen]
    call d_putb
    lea rdi, [s_sum_lp]
    call d_putz
    mov rax, [d_srclen]
    call d_num
    lea rdi, [s_sum_bytes]
    call d_putz
    call d_rs
    call d_nl
    ; target
    call d_reset
    call d_gray
    mov rcx, 6
    call d_pad
    mov al, '|'
    call d_putc
    mov al, ' '
    call d_putc
    mov al, ' '
    call d_putc
    lea rdi, [s_sum_tgt]
    call d_putz
    call d_rs
    call d_nl
    call emit_pipe_empty
    ; help
    cmp qword[d_errors], 0
    je .sum_clean
    lea rdi, [s_sum_fix]
    call emit_help
    jmp .sum_end
.sum_clean:
    lea rdi, [s_sum_clean]
    call emit_help
.sum_end:
    call emit_heavy_rule
    call emit_blank
    pop r13
    pop r12
    pop rbx
    ret