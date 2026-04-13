

# Elysium

A compiled programming language with native code generation, written entirely in x86-64 assembly (NASM). The compiler produces PE executables directly, without any external assembler or linker.

## Quick Start

Requirements: NASM, Microsoft `link.exe` (from Visual Studio / Build Tools).

```pwsh
build_compiler.bat
.\elysiumc.exe demo.ely
demo.exe
```

## Language Overview

Elysium combines imperative control flow with pattern matching, algebraic data types, and memory safety primitives.

```rust
module Main {
  type Point { x :: i64; y :: i64; }
  type Result = | Ok(i64) | Err(i64)

  fn fib(0) -> i64 { return 0; }
  fn fib(1) -> i64 { return 1; }
  fn fib(n) -> i64 { return fib(n - 1) + fib(n - 2); }

  fn double(x) -> i64 { return x * 2; }

  public fn main() -> i64 {
    print_str("fibonacci: ");
    print(fib(10));

    let result = 5 |> double |> add(1);
    print(result);

    let p = Point { x = 10, y = 20 };
    print(p.x + p.y);

    let r = Ok(42);
    match r {
      Ok(v) => print(v);
      Err(e) => print(e);
    }

    return 0;
  }
}
```

## Features

### Type System

Sized integer types with proper sign/zero extension:

```rust
let a :: i8 = 127;
let b :: u8 = 255;
let c :: i16 = 1000;
let d :: u32 = 100000;
let e :: i64 = 0;
```

### Pattern Matching

In function arguments:

```rust
fn factorial(0) -> i64 { return 1; }
fn factorial(n) -> i64 { return n * factorial(n - 1); }
```

In match expressions with guards:

```rust
match value {
  0 => print(0);
  n guard [n > 100] => print(n);
  _ => print(1);
}
```

### Records

```rust
type Color { r :: u8; g :: u8; b :: u8; }

let c = Color { r = 255, g = 0, b = 128 };
print(c.r);
c.g = 64;
```

### Tagged Unions

```rust
type Option = | Some(i64) | None(i64)

let x = Some(42);
match x {
  Some(v) => print(v);
  None(v) => print(0);
}
```

### Pipes

```rust
fn double(x) -> i64 { return x * 2; }
fn inc(x) -> i64 { return x + 1; }

let r = 5 |> double |> inc;
// r = 11
```

### Arrays

```rust
let arr = [10, 20, 30, 40, 50];
print(arr[2]);
arr[0] = 99;
print(arrlen(arr));
```

Typed arrays:

```rust
let buf :: [u8] = [72, 101, 108, 108, 111];
```

### Checkpoint / Recovery

`anchor` saves execution state, `unwind` restores it:

```rust
anchor safe {
  print(1);
  unwind safe;
  print(2);    // never reached
}
print(3);      // continues here
```

`supervise` catches fatal errors like division by zero:

```rust
supervise {
  let x = 10 / 0;  // would crash
  print(x);         // never reached
}
print(99);          // continues here
```

### Memory Management

Heap allocation via OS primitives:

```rust
let mem = claim(64);
store(mem, 0, 42);
print(load(mem, 0));
release(mem);
```

Pool allocator for bulk allocation:

```rust
let pool = pool_create(4096);
let a = pool_claim(pool, 8);
let b = pool_claim(pool, 8);
store(a, 0, 100);
store(b, 0, 200);
pool_drain(pool);
```

### Borrow Tracking

```rust
let x = 42;
let r = &x;       // shared borrow
let m = &mut x;   // exclusive borrow
```

### Access Modifiers

```rust
module Lib {
  public fn api_call() -> i64 { return 1; }
  private fn internal() -> i64 { return 2; }
  protected fn subclass_only() -> i64 { return 3; }
  sealed fn same_module() -> i64 { return 4; }
}
```

### Atoms

Runtime-hashed symbolic constants:

```rust
let status = :ok;
let err = :not_found;
```

## Architecture

The compiler is structured as a pipeline:

```
Source -> Lexer -> Parser -> AST -> MIR Lowering -> x86 Encoding -> PE Writer -> .exe
```

- **Lexer** (`lexer.asm`): Tokenizer with escape sequences, line tracking, keyword recognition.
- **Parser** (`parser.asm`): Recursive descent, produces a linked AST.
- **MIR** (`ir.asm`, `lower.asm`): Flat intermediate representation. Each instruction is 24 bytes: `[opcode:8][op1:8][op2:8]`.
- **x86 Encoder** (`x86enc.asm`): Two-pass encoder. First pass emits machine code with placeholder offsets. Second pass patches all relative jumps and calls.
- **PE Writer** (`pe64.asm`): Builds PE headers, import directory (kernel32.dll), IAT, and writes the final executable.

No external libraries are used at compile time. The generated executables import only from `kernel32.dll` (`ExitProcess`, `GetStdHandle`, `WriteFile`, `VirtualAlloc`, `VirtualFree`).

All internal buffers are heap-allocated and grow dynamically. There are no fixed limits on source size, token count, symbol count, or code size.

## Project Structure

```shell
elysium/
  defs.inc                  -- shared constants
  build_compiler.bat        -- build script (Windows)
  libely/
    vmem.asm                -- OS virtual memory primitives
    arena.asm               -- growable arena allocator
    lexer.asm               -- tokenizer
    parser.asm              -- recursive descent parser
    frontend.asm            -- parsing facade
    types.asm               -- type resolution and sizing
    typetab.asm             -- record and union type registry
    symtab.asm              -- symbol table with hash lookup
    ir.asm                  -- MIR buffer management
    lower.asm               -- AST to MIR lowering
    x86enc.asm              -- MIR to x86-64 machine code
    pe64.asm                -- PE executable builder
    emit.asm                -- text output buffer (legacy backend)
    codegen_rt.asm          -- legacy text codegen: runtime
    codegen_expr.asm        -- legacy text codegen: expressions
    codegen_stmt.asm        -- legacy text codegen: statements
    codegen_func.asm        -- legacy text codegen: functions
    backend.asm             -- compilation driver
  compiler/
    elysiumc_win64.asm      -- compiler entry point (Windows)
    elysiumc_linux.asm      -- compiler entry point (Linux)
  tests/
    run_tests.bat           -- E2E test runner
    build_internals.bat     -- internal unit test builder
    test_internals.asm      -- unit tests for compiler subsystems
    e2e/                    -- end-to-end test cases
```

## Building

Windows with Visual Studio Build Tools:

```shell
:: open Developer Command Prompt
build_compiler.bat
```

This produces `elysiumc.exe` which compiles `.ely` files to `.exe` directly.

## Testing

```shell
:: end-to-end tests
tests\run_tests.bat

:: internal subsystem tests
tests\build_internals.bat
```