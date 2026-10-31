# Scalar records and synchronous C callbacks

On GNU Linux x86-64 LP64, an explicitly annotated import can borrow a native
record containing one through 32 copied numeric scalar fields:

```astra
struct Counter { i64 total; int calls; int bias; }
[CCode(record_abi="natural-lp64")]
extern(C) int inspect(borrowed Counter* counter, int input);
```

The C declaration is `int32_t inspect(struct Counter*, int32_t)`, where the C
record has matching natural layout and scalar types. `i8/u8/i16/u16/int/u32`
correspond to exact-width C integer types; `i64/u64` to `int64_t/uint64_t`;
`isize/usize` to `ptrdiff_t/size_t`; `f32/f64` to C `float/double`. Offsets,
padding, extent and alignment are verified against the selected target.
Initialize padding bytes explicitly in C before comparing entire object bytes;
ordinary Astra field initialization does not promise defined padding contents.

A provider may synchronously call a named native function with that record as
its borrowed context:

```astra
int add(borrowed Counter* counter, int value) {
    counter->total = counter->total + ((value + counter->bias) as i64);
    counter->calls = counter->calls + 1;
    return counter->calls;
}
[CCode(record_abi="natural-lp64", callback="add",
       callback_abi="i32-context-i32-sync")]
extern(C) int visit(borrowed Counter* counter, int input);
```

Its exact C signature is:

```c
int32_t visit(int32_t (*callback)(void *, int32_t),
              struct Counter *counter, int32_t input);
```

Call it normally with `visit(&counter, input)`. The compiler supplies the typed
thunk and the same context pointer. The nominated function cannot throw, be
async, be generic, consume its context, or change the exact signature. Qualified
names use the ordinary source namespace/visibility rules.

The foreign implementation must finish all access and callback invocation
before returning. It must retain neither function pointer, context nor aliases;
it must not free the context, overrun its layout or unwind across the callback.
This is a trusted foreign obligation. No lifetime/ownership transfers to C.

This original slice accepts pointer transport only. The later explicit
[by-value union projections](c-unions.md) have their own representation and
active-member contract. This borrowed-record slice rejects packed/over-aligned,
empty, nested, owning, pointer-bearing or bool-bearing records and C unions,
bitfields, variadics and by-value aggregate results. Record imports cannot return
pointer-like values or derive an owner from the borrowed context. It does not expose arbitrary
native callable objects or retained C closure environments.

Run `python3 tests/language-runtime-3/cabi-qualify.py /absolute/build/astrac
/absolute/external/runtime/cabi` for independent GCC/Clang layout and public
O0/O1/O2 execution, object/C linkage, varied inputs, negative source and Valgrind
witnesses. `meson test -C /absolute/build cabi-record-proof --print-errorlogs`
checks deliberate Core/CFG/SSA/CABI/LLVM corruption before execution.
