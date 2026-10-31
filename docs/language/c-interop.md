# Explicit scalar and pointer C interoperability

The optional [GObject/GIR boundary](gobject-interop.md) adds checked foreign
Resource identity, property snapshots and real retained signals. It is separate
from native Class identity and from the scalar profiles documented below.

RESOURCE-1 imports [nominal handle types](resource-handles.md) from VAPI.
C imports accept unmanaged Resource parameters/results, borrowed Resource
parameters, and owned Resource results. `extern(C) owned Resource create(int id);`
uses Resource's cleanup authority and normalizes like VAPI. Handles remain PTR
with exact semantic checking before physical erasure. C exports of handle types
are deliberately unsupported.

Astra can directly call explicitly declared external C functions:

```astra
extern(C) int astra_test_add(int a, int b);
extern(C) void astra_test_reset();

int main() {
	astra_test_reset();
	if (astra_test_add(20, 22) != 42) {
		return 1;
	}
	return 0;
}
```

The grammar is:

```text
foreign-function-declaration := "extern" "(" identifier ")" type-name identifier "(" parameter-list? ")" ";"
```

`extern` is a keyword; `C` remains an ordinary identifier. Semantic analysis
requires the ABI spelling to be exactly `C`, case-sensitive. Imports have no
body and must end with a semicolon. Ordinary native definitions still require
a body; `int f();` does not become foreign implicitly.

Foreign parameters may be int, f32, f64, void* or an imported handle. Results may also be void. An argument's
semantic type must match exactly; there are no coercions or promotions. An int
result can be used in any ordinary int expression or discarded in a call
statement. A void call can only be a statement. Foreign bool parameters/results
are rejected even though bool is valid for native Astra functions. Native B1 is
not a model of C `_Bool`. The separate explicit
[`CImport`/`CExport` C99 boolean profile](c-booleans.md) admits copied boolean
channels with its own checked ABI; legacy `extern(C)` keeps this refusal.

A foreign int channel means exactly signed 32-bit values, tested against C
`int32_t` from `<stdint.h>`. It does not equate Astra `int` permanently with C
source-level `int` on all targets. The external implementation must match the
explicit declaration; Astra neither parses headers nor infers signatures.

Native definitions and C imports share one direct-function namespace. Repeated
names reject across and within domains, including different signatures. All
signatures are collected before checking native bodies, so an import may follow
its callers. Direct calls are independent of lexical local/parameter lookup.
Executable entry requires a defined native `int main()`; `extern(C) int main();`
does not satisfy that requirement or select a wrapper target.

Calls resolve their domain and exact target once during semantic checking.
Every C call is conservatively effectful, including a discarded int call. Astra
retains left-to-right argument and operand evaluation. For
`c_outer(c_left(), c_right())`, execution is left, right, outer. C source-language
evaluation rules do not replace Astra's rules at the ABI boundary.

Short-circuit operators may suppress a C call on their RHS, for example
`condition && (c_probe() != 0)`. Calls can also occur in while conditions, bodies,
and before break/continue. Existing control-flow and trap ordering is unchanged.
Calls after an unconditional transfer remain unreachable.

For source `extern(C)`, the external symbol is exactly the declared name. Source
extern/export annotations and aliases are unsupported. VAPI may supply an
explicit physical alias through `[CCode (cname = "physical")]`; its local name
still controls Astra lookup. There is no manual name mangling, underscore
insertion, or platform decoration.
LLVM and the object toolchain handle platform symbol realization. Native
functions retain their separate NABI/internal/fastcc convention; imports are
external C-convention declarations.

To supply C implementations as relocatable objects:

```sh
cc -c helper.c -o helper.o
astrac program.astra --link-object helper.o -o program
astrac --link-object helper1.o --link-object helper2.o program.astra -o program
```

`--link-object` applies to executable compilation, may occur before or after the
source, and preserves object order. Paths are passed as literal argv entries,
including spaces and shell punctuation. Use `./` for an object basename starting
with `-`. Check/dump modes reject `-o` and `--link-object`; they accept declaration input
through repeatable `--vapi`. No archive,
library search, `-l`, `-L`, pkg-config, or arbitrary linker flags are supported.

`--check` validates through Core, CFG, SSA, NABI, CABI, and LLVM without linking.
`--dump-cabi` shows explicit import/export physical contracts; `--dump-nabi`
shows native signatures, including exported implementations; `--dump-llvm` shows the mixed module without needing objects.
An unresolved external symbol is a link-phase error. A failed link leaves any
existing output intact and removes compiler temporary files.

CEXPORT-1 adds scalar [C exports](c-exports.md) through separate wrappers.
VAPI-1 adds external [declaration files](vapi.md): `--vapi helper.vapi` supplies
the same semantic CFunctionSymbol imports as source extern(C), using the same
Core/CFG/SSA/CABI/LLVM machinery. Files contain `int f(int x);` or `void f();`,
without extern(C), exports, or bodies. Multiple VAPI inputs merge before body
checking and never supply objects or libraries implicitly.
META-1 adds `[CCode (cname = "physical", cheader_filename = "helper.h")]`
before VAPI declarations. Both fields are nonempty, NUL-free strings; headers
are descriptive metadata only. Astra never opens/parses them, requires their
existence, or infers linker inputs. Header metadata does not change CABI channels
or LLVM IR. Physical-symbol uniqueness is checked at CABI separately from local
callable-name uniqueness, including import/export collisions. NABI is unaffected.
See [metadata v0](../vapi/vapi-c-metadata-v0.md). Unknown or duplicate metadata
keys reject. There is no generated header, header parser, library/link metadata,
foreign bool, typed pointers, strings, structs, callbacks, variadics, ownership transfer, GIR,
or GObject.
See [ADR 0020](../decisions/0020-c-scalar-imports.md) and the
[C scalar physical contract](../abi/c-scalar-import-v0.md).

## C callers of native Astra definitions

`export(C)` attaches a C boundary to a native definition, while `extern(C)`
declares an implementation outside Astra. They cannot be combined. Both use
int/f32/f64/void* parameters and int/f32/f64/void*/void results. Export's symbol equals its source name,
and all import/export symbols share one explicitly verified external namespace.

An exported function remains a native FunctionSymbol and internal fastcc body.
A generated external ccc wrapper forwards to it; native callers and recursion
use the body directly. This supports both Astra → C imports and C → Astra exports,
including a C → Astra → C round trip, without changing body semantics. Test C
callers manually declare int32_t signatures; no header is generated. Stage modes
show and verify wrappers without linking, while exported `main` conflicts with
EXEC's separate launch wrapper at executable-entry validation. See the
[C export physical contract](../abi/c-scalar-export-v0.md).

## Opaque C pointer channels

`extern(C) void* handle();` and `extern(C) int is_null(void* p);` use the same
CFunctionSymbol path as VAPI declarations. `export(C) void* echo(void* p) {
return p; }` remains a native function with a separate C wrapper. CAbiScalarType.PTR
and NativeScalarType.PTR are distinct; both currently map to opaque LLVM `ptr`.
C imports/wrappers stay external/ccc and native implementations stay internal/fastcc.

Ordinary raw pointers are nullable and unmanaged. `null` crosses the C boundary as a
pointer null, without casts or implicit checks. C calls remain conservatively
effectful. Header metadata defines no pointer layout or implicit link input.
Use `--link-object` as before; `--check` needs no external implementation.
See [C pointer v1](../abi/c-pointer-v1.md) and [raw pointers](raw-pointers.md).

## Foreign owned results

[VAPI destroy_function](../vapi/owned-results.md) transfers one lexical cleanup
responsibility into `owned void*` locals. Source extern(C) has no producer-specific void* ownership metadata syntax; it supports owned nominal handle results. Cleanup is a separate physical CABI contract, not a source
callable; CABI rejects collisions with ordinary imports/exports. The signature
is exactly void(void*), ccc, using scalar-ptr-v1. Null skips the call. Ordinary
pointer parameters do not supply a borrow/noescape contract and cannot accept
owners in OWN-1. See [ownership](ownership.md).

## Borrowed C imports

`extern(C) int inspect(borrowed void* p);` promises non-owning noescape use during
the dynamic call. OWNED handles, unmanaged void* and null are accepted. Owners
remain OWNED and retain normal lexical cleanup. Binding authors are responsible
for C implementations; mutation and I/O are permitted, retention/destruction and
escape are forbidden. Native wrappers may forward borrowed parameters directly.
`export(C)` borrowed parameters remain unsupported. Physical PTR/ccc signatures
and scalar-ptr-v1 are unchanged, without LLVM borrow attributes. See
[borrowed parameters](borrowed-parameters.md) and [VAPI normalization](../vapi/borrowed-parameters.md).


## Exact floating boundaries

`extern(C) f32 echo_float(f32 value);` calls C float, and
`extern(C) f64 echo_double(f64 value);` calls C double. C exports permit the
same scalar widths through the existing wrapper system. VAPI spells these
`float` and `double`; ordinary Astra source remains f32 and f64. Parameters,
results, multiple floats and mixed `int/f32/f64/void*` signatures select
[CABI scalar-fp-v2](../abi/c-fp-v2.md). Body-local/native floats do not; unused
foreign declarations do, following the existing declaration policy.

Each call requires exact semantic types. C float requires f32; C double
requires f64. There is no implicit f32/f64 promotion, integer conversion or
bitcast through integers. Returned values can initialize locals and concrete
struct fields, enter nested calls, or participate in ordinary strict Astra
arithmetic. A native struct function using aggregate-v7 may call either C
floating channel without changing its native boundary contract.

The default x86-64 Linux C environment is qualified for IEEE binary32 float
and IEEE binary64 double. Other targets fail closed until their C
representations are qualified. Boundary-only transport preserves exact bits,
including quiet NaN payloads; C arithmetic is not a payload oracle. Calls
remain conservatively effectful and arguments execute left to right. Earlier
traps suppress later arguments for both widths. No float*/double*, C
aggregate ABI, varargs, callbacks, long double, runtime helper, libm layer or
process-argument support is added; executable entry remains `int main()`.

TEXT-IO-1 additionally permits explicitly annotated borrowed string imports,
using `[CCode (text_abi = "utf8-i32")]` on source extern(C) or VAPI declarations.
Each logical string becomes adjacent `const unsigned char *` and `int32_t`.
This trusted outbound contract is described in [C text views](../abi/c-text-views.md).
Unannotated string imports, string results and text exports remain rejected.

Surge-5 also defines an explicit finite C struct value contract:

```astra
struct Diagnostic { i64 count; f64 average; }
[CCode(record_abi="value-lp64")]
extern(C) Diagnostic summarize(Diagnostic input);
[CCode(record_abi="value-lp64")]
export(C) Diagnostic bridge(Diagnostic input) {
    Diagnostic result = summarize(input);
    return result;
}
```

The public C signature is `struct Diagnostic bridge(struct Diagnostic)`.
The bounded GNU x86-64 SysV LP64 layouts and register/stack lowering are described
in [ADR 0116](../decisions/0116-c-by-value-pod-records.md). The annotation selects
a foreign contract; ordinary native struct functions retain their native ABI.
