# Hosted compiler and systems features

The hosted toolchain supports public LLVM optimization, object output, wide
integers, explicitly borrowed C byte buffers and opt-in source namespaces. The
qualified systems target is GNU Linux x86-64 LP64. These features extend the
existing whole-program compiler; source files remain explicit command inputs.

Build and run the focused campaign from the repository root:

```sh
export PM_CODEX_BUILD_DIR="$HOME/Workspace/codex/work/astra/build"
export PM_CODEX_RUNTIME_DIR="$HOME/Workspace/codex/work/astra/runtime/native-current"
sh tests/compiler-systems-2/verify.sh
# Broader touched-family and virtual-async qualification:
python3 tests/compiler-systems-2/regressions.py "$PM_CODEX_BUILD_DIR"
```

The recipe reuses the external build, checks its source routing and test profile,
and runs fresh public O0/O2 applications, independent LLVM O2 references, C
clients, scalar/ABI mutation tests and memory/file witnesses. The profile's
`linux_async=false` is a test choice; it does not change the product default.

For a directly linkable object:

```sh
out="$PM_CODEX_BUILD_DIR/examples/compiler-systems"
mkdir -p "$out"
"$PM_CODEX_BUILD_DIR/astrac" -O2 -c \
  examples/compiler-systems/object-link-client.astra \
  examples/compiler-systems/object-link-math.astra -o "$out/mix.o"
cc examples/compiler-systems/object-link-client.c "$out/mix.o" -o "$out/mix"
"$out/mix" 4294967297
```

`-O0`, `-O1`, `-O2` select the linked LLVM 22 IR pipeline and machine level.
`-c` emits one object without a process-entry wrapper. `export(C)` supplies
stable explicitly foreign entry points; private native function symbols have
no separate-compilation ABI. Executable mode and repeated `--link-object` /
`--link-library` retain their previous behavior. See [ADR 0104](../decisions/0104-public-native-optimization.md).

`i64` and `u64` are distinct exact-width types. `isize` and `usize` are distinct
host-qualified pointer-width types, requiring a verified eight-byte target
layout. `int` remains signed I32, and array/text/buffer lengths remain I32.
Integer add/subtract/multiply wrap modulo the destination width. Explicit
integer `as` conversions preserve low bits and use source signedness when
widening; implicit widening/narrowing is rejected. Signed MIN/-1 wraps to MIN;
its remainder is zero. Divide-by-zero and invalid shift counts trap. Wide
integer vectors remain unsupported. Floating conversions retain the existing
nearest/ties-even and truncate-with-range-trap policies. `append_i64` and
`append_u64` render decimal ASCII through the owned UTF-8 builder.

The safe synchronous foreign spelling is explicit:

```astra
[CCode(buffer_abi = "u8-i32")]
extern(C) int process(borrowed u8[] bytes);
```

One logical buffer becomes an adjacent C `unsigned char *` / `int32_t` count.
The compiler proves call-scoped native storage liveness. The foreign provider
must obey the declared bound, retain no pointer, and neither free nor resize the
storage. Overlapping views are allowed; this annotation supplies no noalias
promise. Other arrays, exports, owned/retained results and async borrowing remain
outside this contract. See [the counted C buffer guide](c-byte-buffers.md).

`FileHandle.read_bytes` / `write_bytes` return actual progress. Astra owns the
transfer loops, growth, errors and cleanup; the POSIX provider performs bounded
bulk syscalls. The previous `read_file`, `write_file`, `write_text_file` and
`FileBytes` surface is retained. Payload bytes are arbitrary, including NUL and
invalid UTF-8. Decoding remains explicit. Short transfers, EINTR, zero writes,
negative errno, checked flush/close and partial destructive output remain
observable. No throughput improvement is inferred solely from fewer syscalls.

Namespace files start with `namespace Name;`, and `using Name;` selects an
explicitly supplied namespace. Qualified `Name.Record` and `Name.function()`
resolve without loading directories. Public declarations are visible across
namespaces; `internal` declarations are confined to the same namespace. Class
field `private` retains its existing lexical identity rule. Cyclic lexical
imports are supported because no source loader or runtime initializer is
introduced. Global files and global executable `main` keep their existing
behavior. See [the module guide](modules.md).

The eight new programs are `optimized-diagnostics`, `bulk-copy`, `wide-counter`,
`namespace-same-name`, `module-config`, `file-digest64`, `object-link-client`, and
`systems-report`. Their tests record independent oracles, runtime input pairs,
compiler/source/product identities and actual public command lines. Historical
LAZY final qualification, live liburing provider coverage, cross-target embedded
execution, general foreign retained pointers and self-hosting remain separate.
