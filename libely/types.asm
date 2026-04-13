; types.asm - type system helpers
default rel
%include "defs.inc"
global resolve_type_token, type_size, type_name, type_is_signed

section .data
tn_void: db "void",0
tn_bool: db "bool",0
tn_i8:   db "i8",0
tn_i16:  db "i16",0
tn_i32:  db "i32",0
tn_i64:  db "i64",0
tn_ptr:  db "ptr",0
tn_atom: db "atom",0
tn_str:  db "str",0
tn_u8:   db "u8",0
tn_u16:  db "u16",0
tn_u32:  db "u32",0
tn_u64:  db "u64",0
tn_unk:  db "?",0

section .text

resolve_type_token:
    cmp rax,TOK_VOID_KW
    je .void
    cmp rax,TOK_BOOL_KW
    je .bool
    cmp rax,TOK_I8_KW
    je .i8
    cmp rax,TOK_I16_KW
    je .i16
    cmp rax,TOK_I32_KW
    je .i32
    cmp rax,TOK_I64_KW
    je .i64
    cmp rax,TOK_PTR_KW
    je .ptr
    cmp rax,TOK_U8_KW
    je .u8
    cmp rax,TOK_U16_KW
    je .u16
    cmp rax,TOK_U32_KW
    je .u32
    cmp rax,TOK_U64_KW
    je .u64
    mov rax,TYPE_I64
    ret
.void: mov rax,TYPE_VOID
    ret
.bool: mov rax,TYPE_BOOL
    ret
.i8:  mov rax,TYPE_I8
    ret
.i16: mov rax,TYPE_I16
    ret
.i32: mov rax,TYPE_I32
    ret
.i64: mov rax,TYPE_I64
    ret
.ptr: mov rax,TYPE_PTR
    ret
.u8:  mov rax,TYPE_U8
    ret
.u16: mov rax,TYPE_U16
    ret
.u32: mov rax,TYPE_U32
    ret
.u64: mov rax,TYPE_U64
    ret

; type_size: rax=TYPE_* -> rax=size in bytes
type_size:
    cmp rax,TYPE_BOOL
    je .one
    cmp rax,TYPE_I8
    je .one
    cmp rax,TYPE_U8
    je .one
    cmp rax,TYPE_I16
    je .two
    cmp rax,TYPE_U16
    je .two
    cmp rax,TYPE_I32
    je .four
    cmp rax,TYPE_U32
    je .four
    mov rax,8
    ret
.one: mov rax,1
    ret
.two: mov rax,2
    ret
.four:mov rax,4
    ret

; type_is_signed: rax=TYPE_* -> rax=1 signed, 0 unsigned
type_is_signed:
    cmp rax,TYPE_I8
    je .y
    cmp rax,TYPE_I16
    je .y
    cmp rax,TYPE_I32
    je .y
    cmp rax,TYPE_I64
    je .y
    xor rax,rax
    ret
.y: mov rax,1
    ret

type_name:
    cmp rax,TYPE_U8
    je .tu8
    cmp rax,TYPE_U16
    je .tu16
    cmp rax,TYPE_U32
    je .tu32
    cmp rax,TYPE_U64
    je .tu64
    cmp rax,8
    ja .unk
    lea rcx,[.tbl]
    mov rax,[rcx+rax*8]
    ret
.tu8: lea rax,[tn_u8]
    ret
.tu16:lea rax,[tn_u16]
    ret
.tu32:lea rax,[tn_u32]
    ret
.tu64:lea rax,[tn_u64]
    ret
.unk: lea rax,[tn_unk]
    ret
.tbl: dq tn_void,tn_bool,tn_i8,tn_i16,tn_i32,tn_i64,tn_ptr,tn_atom,tn_str