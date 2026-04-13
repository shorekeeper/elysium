; emit.asm -- growable text output buffer + string literal registry
; Used by the legacy text backend for .asm generation.
; All buffers are heap-allocated and double on overflow.
default rel
%include "defs.inc"
extern vmem_alloc, vmem_realloc
global emit_init, emit_raw, emit_cstr, emit_nl, emit_num
global emit_name, emit_label, emit_jmp_label, new_label
global emit_get_output, emit_str_data, emit_flush_strings
global str_data_count

section .data
s_dotL:     db ".L",0
s_colon_nl: db ":",10,0
s_nl:       db 10,0
s_sec_data: db 10,"section .data",10,0
s_sec_text: db 10,"section .text",10,0
s_str_pre:  db "__ely_str_",0
s_str_mid:  db ": db ",0
s_str_len_suf: db "_len equ ",0
s_comma:    db ",",0

section .bss
out_buf:    resq 1            ; -> output text buffer
out_pos:    resq 1            ; bytes written
out_cap:    resq 1            ; buffer capacity
label_cnt:  resq 1            ; monotonic label counter (text backend)
num_buf:    resb 32           ; scratch for decimal conversion
; string literal registry (parallel arrays)
str_ptrs:   resq 1            ; -> array of string content pointers
str_lens:   resq 1            ; -> array of string lengths
str_data_count: resq 1        ; number of registered strings
str_data_cap: resq 1          ; capacity of string arrays

section .text

; emit_init: allocate output buffer and string arrays
emit_init:
    mov qword[out_pos], 0
    mov qword[label_cnt], 0
    mov qword[str_data_count], 0
    ; output buffer
    mov qword[out_cap], INIT_OUTBUF
    mov rdi, INIT_OUTBUF
    call vmem_alloc
    mov [out_buf], rax
    ; string registry (start with 256 slots)
    mov qword[str_data_cap], 256
    mov rdi, 256*8
    call vmem_alloc
    mov [str_ptrs], rax
    mov rdi, 256*8
    call vmem_alloc
    mov [str_lens], rax
    ret

; emit_ensure: make sure out_buf has room for rdx more bytes
emit_ensure:
    push rax
    mov rax, [out_pos]
    add rax, rdx
    cmp rax, [out_cap]
    jl .ok
    push rdi
    push rsi
    push rdx
    mov rdi, [out_buf]
    mov rsi, [out_cap]
    mov rdx, [out_cap]
    shl rdx, 1                    ; double
    mov [out_cap], rdx
    call vmem_realloc
    mov [out_buf], rax
    pop rdx
    pop rsi
    pop rdi
.ok:pop rax
    ret

; emit_raw: rsi=buf, rdx=len -> append raw bytes to output
emit_raw:
    call emit_ensure
    push rdi
    push rcx
    mov rdi, [out_buf]
    add rdi, [out_pos]
    mov rcx, rdx
    push rsi
    rep movsb
    pop rsi
    add [out_pos], rdx
    pop rcx
    pop rdi
    ret

; emit_cstr: rdi=null-terminated -> append to output
emit_cstr:
    push rsi
    push rdx
    mov rsi, rdi
    xor rdx, rdx
.l: cmp byte[rsi+rdx], 0
    je .g
    inc rdx
    jmp .l
.g: call emit_raw
    pop rdx
    pop rsi
    ret

; emit_nl: append newline
emit_nl:
    push rdi
    mov rdi, s_nl
    call emit_cstr
    pop rdi
    ret

; emit_num: rax=int64 -> append decimal string
emit_num:
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
    call emit_raw
    pop rax
    neg rax
.pos:
    test rax, rax
    jnz .nz
    mov byte[num_buf], '0'
    mov rsi, num_buf
    mov rdx, 1
    call emit_raw
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
    mov rbx, rcx
    xor rdx, rdx
.pop:
    test rcx, rcx
    jz .wr
    pop rax
    mov [num_buf+rdx], al
    inc rdx
    dec rcx
    jmp .pop
.wr:
    mov rsi, num_buf
    mov rdx, rbx
    call emit_raw
.end:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; emit_name: rsi=buf, rdx=len -> append raw (alias for emit_raw)
emit_name:
    jmp emit_raw

; new_label: -> rax=unique label id
new_label:
    mov rax, [label_cnt]
    inc qword[label_cnt]
    ret

; emit_label: rax=label_id -> emit ".L<id>:\n"
emit_label:
    push rax
    mov rdi, s_dotL
    call emit_cstr
    pop rax
    push rax
    call emit_num
    mov rdi, s_colon_nl
    call emit_cstr
    pop rax
    ret

; emit_jmp_label: rdi=prefix, rax=label_id -> emit "<prefix>.L<id>\n"
emit_jmp_label:
    push rax
    call emit_cstr
    mov rdi, s_dotL
    call emit_cstr
    pop rax
    call emit_num
    call emit_nl
    ret

; emit_get_output: -> rsi=buffer, rdx=length
emit_get_output:
    mov rsi, [out_buf]
    mov rdx, [out_pos]
    ret

; emit_str_data: register string literal for .data emission
; rsi=content, rdx=len -> rax=string index
; Grows arrays if needed.
emit_str_data:
    push rbx
    push r11
    mov rbx, [str_data_count]
    cmp rbx, [str_data_cap]
    jl .ok
    ; grow both arrays
    push rsi
    push rdx
    mov rdi, [str_ptrs]
    mov rsi, [str_data_cap]
    shl rsi, 3                     ; old bytes
    mov rdx, [str_data_cap]
    shl rdx, 1                     ; double count
    mov [str_data_cap], rdx
    shl rdx, 3                     ; new bytes
    push rdx
    call vmem_realloc
    mov [str_ptrs], rax
    pop rdx
    mov rdi, [str_lens]
    mov rsi, rdx
    shr rsi, 1                     ; old bytes = new/2
    call vmem_realloc
    mov [str_lens], rax
    pop rdx
    pop rsi
    mov rbx, [str_data_count]
.ok:
    mov r11, [str_ptrs]
    mov [r11+rbx*8], rsi
    mov r11, [str_lens]
    mov [r11+rbx*8], rdx
    mov rax, rbx
    inc qword[str_data_count]
    pop r11
    pop rbx
    ret

; emit_flush_strings: write all registered strings as NASM .data entries
; then switch back to .text section
emit_flush_strings:
    push rbx
    push r12
    push r13
    push rsi
    push rdx
    mov r12, [str_data_count]
    test r12, r12
    jz .done
    mov rdi, s_sec_data
    call emit_cstr
    xor rbx, rbx
.lp:
    cmp rbx, r12
    jge .back
    ; __ely_str_N: db <bytes>
    mov rdi, s_str_pre
    call emit_cstr
    mov rax, rbx
    call emit_num
    mov rdi, s_str_mid
    call emit_cstr
    ; get string content and length
    push r11
    mov r11, [str_ptrs]
    mov rsi, [r11+rbx*8]
    mov r11, [str_lens]
    mov r13, [r11+rbx*8]
    pop r11
    ; emit each byte as decimal, comma-separated
    xor rcx, rcx
.bl:
    cmp rcx, r13
    jge .bd
    test rcx, rcx
    jz .nc
    push rcx
    push rsi
    push r13
    mov rdi, s_comma
    call emit_cstr
    pop r13
    pop rsi
    pop rcx
.nc:
    push rcx
    push rsi
    push r13
    movzx rax, byte[rsi+rcx]
    call emit_num
    pop r13
    pop rsi
    pop rcx
    inc rcx
    jmp .bl
.bd:
    call emit_nl
    ; __ely_str_N_len equ <length>
    mov rdi, s_str_pre
    call emit_cstr
    mov rax, rbx
    call emit_num
    mov rdi, s_str_len_suf
    call emit_cstr
    mov rax, r13
    call emit_num
    call emit_nl
    inc rbx
    jmp .lp
.back:
    mov rdi, s_sec_text
    call emit_cstr
.done:
    pop rdx
    pop rsi
    pop r13
    pop r12
    pop rbx
    ret