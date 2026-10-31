# C scalar import profile v0

`CAbiProfile.SCALAR_V0` identifies Astra's initial C interoperability subset.
It does not version or define the host C ABI. This physical authority is separate
from [Native Scalar ABI v0](native-scalar-v0.md).

| Declaration channel | CABI representation | LLVM realization |
| --- | --- | --- |
| `int` parameter | One direct `CAbiScalarType.I32` | `i32` |
| `int` result | One `CAbiResult(I32)` | `i32` result |
| `void` result | Absent `CAbiResult` | `void` function result |
| `bool` parameter/result | Rejected | None |

I32 transports an exact signed 32-bit value. Qualification uses C `int32_t`
functions from `<stdint.h>`, including INT32_MIN and INT32_MAX identity calls.
Astra `int` is not permanently defined as C source-level `int` on every target.
Foreign bool is deferred: native B1 and LLVM i1 do not establish C `_Bool`'s ABI.
There are no conversions, hidden parameters, varargs, or foreign source types
such as `c_int`, `c_long`, or `c_bool`.

`CAbiFunction` owns a declaration ordinal, source/debug name, exact external
symbol, generic `CForeignMetadata` (including descriptive headers), provenance,
and `CAbiSignature`; it has no body or native linkage field.
A signature owns ordered `CAbiParameter` channels and an optional result.
`CAbiProgram` strongly owns imports in declaration order, with weak backreferences
for ownership verification. No syntax, semantic type, Core, CFG, SSA, NABI, or
LLVM object is retained. Parameter provenance currently identifies the enclosing
foreign declaration; parameter names are not part of physical authority.

`CAbiBuilder.build(ssa, nabi)` verifies SSA, NABI, and their native correspondence,
maps every `SsaCFunction` into a new physical import identity, verifies the
sidecar, and validates C calls with an exact temporary map.
`CAbiValidator` checks one-to-one correspondence, external symbols, channel
counts, semantic-to-CABI types, and result presence/type. Signature or mapping
mismatches are internal compiler errors, not link-time symbol failures.
`CAbiVerifier` and `CAbiDump` independently reject invalid profiles, ordinals,
ownership, empty/duplicate symbols, and unsupported physical scalar channels.
They compile standalone with shared source/provenance and immutable generic
foreign metadata only. Physical-symbol collisions carry source diagnostics at
CABI; Core/CFG/SSA verify structural identities/signatures without enforcing
this separate physical namespace.

For `extern(C) int astra_test_add(int a, int b);`, or the equivalent
`int astra_test_add(int a, int b);` supplied through `--vapi`, `--dump-cabi` produces:

```text
(c-abi scalar-v0
	(import #0
		(name "astra_test_add")
		(symbol "astra_test_add")
		(signature
			(parameters
				(parameter #0 I32)
				(parameter #1 I32)
			)
			(result I32)
		)
	)
)
```

Native functions never appear here. Conversely `--dump-nabi` contains no C
imports. This format is internal inspection output, not a serialized ABI file.

LLVM realizes CABI through `LlvmCTypeMapper`, creating exact-name external
function declarations and default-C-convention calls. It constructs all native
and imported LLVM identities before lowering native bodies. Foreign calls follow
`SsaCFunction → CAbiFunction → LLVM declaration` identity maps. The call site never
searches by symbol spelling. Native definitions and calls remain internal/fastcc.
Imports are effectful and acquire no purity or memory-effect attributes.

Symbols are resolved only by the host linker. Objects may be supplied through
repeatable `--link-object PATH`. The caller's declaration must match the actual
foreign implementation; Astra does not inspect headers or infer C declarations.
Only host-native scalar imports are qualified. Future richer foreign declarations
and types must extend this contract explicitly, independently of native semantics.

## Shared CABI authority with exports

CEXPORT-1 preserves CAbiFunction as the import identity and adds distinct
CAbiExport contracts in CAbiProgram.exports. The same SCALAR_V0 profile and C I32
identity describe both directions. One external-symbol set enforces uniqueness
across imports and exports. Imports still have no native body or NABI entry and
lower to external ccc declarations plus ordered effectful calls. Exports instead
bind a separate ccc wrapper to an internal fastcc native ordinal. Completed CABI
retains no NABI or SSA object. See [export profile v0](c-scalar-export-v0.md).


## External VAPI declaration input

VAPI supplies ordinary CFunctionSymbol imports through the same physical model
and exact LLVM mapping. META-1 enriches imported declarations with generic
CForeignMetadata; `[CCode (cname = "physical", cheader_filename = "helper.h")]`
normalizes before semantics. `cname` selects the exact CABI/LLVM symbol while
the local declaration name controls Astra call lookup. Source externs and
unannotated VAPI default external symbols to their local names and no headers.
CABI imports retain both names and the metadata after SSA/frontend destruction.
Optional `(headers ...)` dump stanzas are omitted when absent. Header names
are never read/parsed or required to exist, never imply linking, and never
change CABI channels or LLVM IR. CABI validates physical uniqueness separately
from semantic local-name uniqueness, including import/export collisions.
Exports keep their source-name policy; NABI remains native-only and unchanged.
See [metadata v0](../vapi/vapi-c-metadata-v0.md) for syntax, diagnostics, and the
unsupported richer-type, ownership, header-parsing, and link-metadata features.

Import ordinals are source extern order first, then CLI VAPI file order and declaration order within
each file. Source/VAPI differential tests require exact CABI dump equality for
equivalent ordered declarations. SourceSpan may retain VAPI provenance; no VAPI
syntax or origin-specific physical type survives into CABI. The standalone CABI
target remains VAPI-free. See [format v0](../vapi/vapi-scalar-v0.md).

`--vapi` never implies `--link-object` or another link input. A valid declaration
can pass check/CABI/LLVM modes and still fail executable linking for an unresolved
symbol, using the existing output-preservation and temporary-cleanup boundary.

## Pointer-capable successor

PTR-1 preserves scalar-v0 for pointer-free C boundary signatures. Any pointer
parameter/result on an import or export selects CAbiProfile.SCALAR_PTR_V1 once
for the program, adding CAbiScalarType.PTR. This independent domain is not native
PTR. Metadata normalization and source/VAPI equivalence are unchanged. The C
mapper realizes ptr without width in semantics or header-derived layout. See
[C pointer v1](c-pointer-v1.md).
