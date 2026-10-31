# C scalar and pointer ABI v1

RESOURCE-1 maps imported nominal handles to existing CAbiScalarType.PTR using
scalar-ptr-v1. Owned results link to the exact type's cleanup and borrowed
parameters retain BORROWED_NOESCAPE; neither changes the channel. Distinct handle
types may share an interned physical cleanup function without sharing semantic
identity. Header metadata is opaque and no stable named C typedef ABI is implied.
C exports of handles remain deferred.

`CAbiProfile.SCALAR_PTR_V1`, dumped as `scalar-ptr-v1`, extends C imports and
exports with the `CAbiScalarType.PTR` channel for C `void*`. The enum and profile
are independent of NativeScalarType and NativeAbiVersion. This profiles Astra's
supported C boundary subset, not the host ABI's version.

| Semantic form | C ABI channel |
| --- | --- |
| `int` | I32 |
| `void*` | PTR |
| `void` result | Absent result |
| `bool` | Unsupported |
| Native `StructName*` | Unsupported in TPTR-1 |

A CAbiProgram uses v1 exactly when any C import/export signature contains PTR.
Every signature in that program uses the same profile, including int-only
imports/exports. Imports retain declaration order, followed by source-ordered
exports in dumps. Native-only pointer signatures do not select the C profile.
Pointer-free programs preserve [import scalar-v0](c-scalar-import-v0.md) and
[export scalar-v0](c-scalar-export-v0.md) byte-for-byte. Verifiers reject PTR
channels under v0. No foreign bool support is implied.

```astra
extern(C) void* c_handle();
extern(C) int c_is_null(void* value);

export(C) void* astra_echo(void* value) {
	return value;
}
```

The equivalent independent VAPI type grammar is `type-name := identifier
("*")?`, in parameter/result positions only. The frontend also retains extra
stars for semantic unsupported-depth diagnostics. It creates no Astra syntax
nodes and supports no expressions. Normalization preserves canonical type
spelling separately from the complete provenance span, so spaces/comments
between `void` and `*` do not affect resolution.

```text
[CCode (cname = "astra_test_handle_a", cheader_filename = "nonexistent/pointer_api.h")]
void* handle_a();
```

Astra resolves `handle_a`; CABI/LLVM/linker use `astra_test_handle_a`. Generic
CForeignMetadata and CFunctionSymbol follow the established metadata path, with
no pointer-specific VAPI semantics, header parsing, includes, layout inference,
or implicit link inputs. Equivalent source extern and VAPI declarations produce
equivalent downstream models apart from provenance.

The separate LLVM C mapper realizes C PTR as default-address-space opaque `ptr`.
Imports are external/ccc. Exports remain explicit external/ccc forwarding
wrappers, calling their exact native internal/fastcc PTR target:

```llvm
define ptr @astra_echo(ptr %0) {
entry:
	%result = call fastcc ptr @astra.fn.0(ptr %0)
	ret ptr %result
}
```

The wrapper remains mandatory despite matching payloads. Native and C channel
validation consult their separate semantic maps. No pointer/integer conversion,
nonnull check, ownership operation, or pointer-derived LLVM attribute is added.
Pointer width is determined by the backend target/data layout.

`null` reaches C as an actual null pointer constant; C null results remain null
inside Astra. Non-null static C handle identities survive copies, SSA merges,
native recursion, and both roundtrip directions. C calls remain conservatively
effectful. `--check` needs no implementation; `--link-object` supplies one at link
time. Missing symbols remain linker errors and headers do not supply libraries.

TPTR-1 does not broaden this foreign contract. Source C imports/exports reject
typed native struct pointers before physical planning; VAPI rejects non-void
pointer spellings during foreign type resolution without consulting Astra
struct authority. CAbiTypeMapper also explicitly requires a void pointee.
LLVM ptr coincidence never permits an implicit Struct*/void* conversion.
Existing cname, cheader_filename, void*, profiles, and C ABI goldens are
unchanged. See [native typed pointers](../language/typed-struct-pointers.md).

## OWN-1 physical cleanup contracts

Owned results still use PTR under scalar-ptr-v1; native NABI is unaffected.
CAbiFunction.owned_cleanup refers to a program-owned CAbiCleanupFunction with
exact external symbol/provenance, deterministic ordinal, one PTR parameter and
absent result. Cleanup functions are not ordinary source imports. Interned
producers share one destroyer declaration; collisions with any ordinary
import/export reject before LLVM lowering. See [owned results](../vapi/owned-results.md).

## Supplemental borrowed behavior

OBORROW-1 adds PointerParameterContract to CAbiParameter: UNMANAGED (default) or
BORROWED_NOESCAPE. The latter is legal only with PTR, printed as
`(parameter #0 PTR (contract borrowed-noescape))`. CAbiValidator checks exact
agreement with SSA declaration metadata. Source extern/VAPI normalize identically
apart from provenance. No new profile or physical channel exists. Cleanup
parameters retain UNMANAGED under the separate destructive cleanup contract;
C exports with borrowed parameters reject. Native PTR channels and LLVM ptr/ccc
realization are unchanged; no borrow optimization attribute is emitted.
