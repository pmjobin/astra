# Exporting scalar Astra functions to C

`export(C)` lets C code call an Astra-native function through a generated C-ABI
wrapper. The definition and all Astra calls remain native:

```astra
export(C) int astra_export_add(int a, int b) {
	return a + b;
}

int native_user() {
	return astra_export_add(1, 2);
}
```

The grammar is `exported-function-definition := "export" "(" identifier ")"
function-declaration`, where the ordinary native declaration requires a body.
`export` is a keyword. The ABI must be the case-sensitive identifier `C`, which
remains usable as a function, parameter, or local name elsewhere.

Parameters may be `int`, `void*`, `f32` or `f64`; results additionally permit
`void`. CABI-FP-1 qualifies f32 as C float and f64 as C double through the same
scalar wrapper. No implicit conversion or separate export system is involved.
A void export may return or fall through normally. Foreign bool remains
unsupported; native bool/B1 is not a C `_Bool` contract. See
[scalar-fp-v2](../abi/c-fp-v2.md) for target and exact-transport requirements.

`export(C) int f();` is invalid: export requires an Astra definition.
`extern(C) int f();` instead declares a C import with an external implementation.
Combining extern and export in either order is invalid. Duplicate source function
names reject, regardless of signature or import/export status.

The external C symbol is exactly the source function name. There are no aliases
or generated headers. A C caller manually declares the current exact-width
contract, for example:

```c
#include <stdint.h>
extern int32_t astra_export_add(int32_t, int32_t);
extern void astra_export_record(int32_t);

int32_t c_call_astra_add(int32_t a, int32_t b) {
	return astra_export_add(a, b);
}
```

Astra may import `c_call_astra_add` and call it from native `main`, proving the
round trip Astra → C → Astra. Exported bodies may call C imports too. Link the
caller object with the existing `--link-object` option. Missing implementations
or caller objects remain link-time errors; failed links preserve existing output.

The generated external wrapper uses C convention (ccc) and calls the separate
internal Astra function with fastcc. Astra source calls use that native identity
directly. Self recursion and mutual calls between exported functions stay native;
they do not repeatedly enter the C wrapper. Export status changes no expression,
call, evaluation-order, short-circuit, loop, wrapping, or trap semantics.

`--dump-semantics`, `--dump-core`, `--dump-cfg`, and `--dump-ssa` show separate
export metadata alongside ordinary native bodies. NABI shows the unchanged
native signature only. CABI additionally shows the export's C signature, symbol,
and native target ordinal. `--dump-llvm` shows the actual export wrapper.
`--check` includes CABI planning, wrapper generation, and LLVM verification,
without resolving any external symbols or requiring a C caller.

`export(C) int main() { return 0; }` is accepted by stage modes, including check,
CABI dump, and LLVM dump. Executable compilation diagnoses ``C export symbol `main` conflicts with the executable entry wrapper``. EXEC still selects a defined
native `int main()`; imports or export metadata do not substitute for that entry.

There are no C headers, export aliases, pointers, strings, structs, callbacks,
variadics, C bool, ownership annotations, shared-library production, or stable
native ABI guarantees. [VAPI](vapi.md) supplies external input for import declarations, not an
export-definition mechanism. See [C interop](c-interop.md),
[the physical contract](../abi/c-scalar-export-v0.md), and
[ADR 0021](../decisions/0021-c-scalar-exports.md).
