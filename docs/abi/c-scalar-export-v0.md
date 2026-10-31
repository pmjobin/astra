# C scalar export profile v0

ASTRA-CEXPORT-1 extends `CAbiProfile.SCALAR_V0` to C callers of Astra functions.
It versions Astra's supported foreign subset, not the host C ABI, and promises
no stable native ABI or general cross-version binary compatibility.

| Boundary channel | CABI | Native target | LLVM payload |
| --- | --- | --- | --- |
| int parameter | CAbiScalarType.I32 | NativeScalarType.I32 | i32 |
| int result | CAbiScalarType.I32 | NativeScalarType.I32 | i32 |
| void result | absent result | absent result | void |

Parameters are direct, ordered, signed 32-bit channels qualified against C
`int32_t`. No hidden channels, C bool, pointers, aggregates, or ownership exist.
The two I32 enums are distinct domain identities. Their current representation
compatibility requires no conversion but always requires the ABI wrapper.

## Physical model and authority

`CAbiProgram.functions` retains the accepted `CAbiFunction` import contracts.
`CAbiProgram.exports` owns distinct `CAbiExport` wrapper contracts. The entry
type explicitly identifies direction, and dumps label `import` or `export`.
Each list has independent deterministic declaration-order ordinals. One verifier
checks external symbol uniqueness across both lists, including synthetic
import/export collisions that source namespace validation normally prevents.

A `CAbiExport` owns its external symbol, export ordinal, `CAbiSignature`, copied
span/name provenance, and `native_function_ordinal`. Its program backreference
is weak. It retains no semantic type, SSA target, NABI object, or LLVM resource.
The native ordinal identifies an internal function within this compilation; it
is not a stable symbol, public ABI, or replacement for exact source identity.

`CAbiBuilder.build(ssa, nabi)` verifies both inputs and their native correspondence.
It maps exact `SsaCExport.target` identities to `NativeFunction` objects before
copying their ordinals. All import/export entries exist before compatibility
validation. The validator checks exact target correspondence, ordinal existence,
external symbol, parameter count, semantic int/C I32/native I32 channels, and
exact result presence/type. Mismatches after semantic validation are compiler
errors. CABI structural verification remains standalone; target existence and
native compatibility belong to the construction/LLVM input boundary with NABI.

Completed CABI can be verified and dumped after syntax, semantic/Core/CFG/SSA,
NABI, and semantic types die. Only shared source provenance remains. The model,
verifier, and dumper compile with provenance utilities alone; the builder and
compatibility validator depend on SSA/NABI but remain LLVM-free.

For a source export at native ordinal 1, the additional contract is:

```text
(export #0
	(symbol "astra_export_add")
	(native-function #1)
	(signature
		(parameters
			(parameter #0 I32)
			(parameter #1 I32))
		(result I32)))
```

## LLVM and object realization

All internal native functions exist before wrapper construction. LLVM resolves
the stored native ordinal through the verified physical correspondence; copied
debug names do not choose targets. The wrapper type comes only from CABI.

```llvm
define internal fastcc i32 @astra.fn.1(i32 %a, i32 %b) {
	%sum = add i32 %a, %b
	ret i32 %sum
}
define i32 @astra_export_add(i32 %a, i32 %b) {
	%result = call fastcc i32 @astra.fn.1(i32 %a, i32 %b)
	ret i32 %result
}
```

The default convention in the second definition is ccc (LLVM omits its spelling).
Void wrappers issue a fastcc void call and `ret void`. Exact LLVM argument values
are forwarded, and the native result is returned directly. No arithmetic or
sign conversion appears in the wrapper. Native calls and recursive calls bypass
it, preserving Astra's ordered effects, wrapping arithmetic, control flow, and
traps. There is no alias, shared body, or wrapper removal optimization.

Artifact-owned verification records contain copied symbols and borrowed LLVM
handles only. They check exact external wrapper name/type/linkage/convention,
exact internal fastcc target and call type/convention, one block containing only
call and return, and exact argument/result forwarding. LLVM's verifier checks
module structure as well. The artifact remains complete after CABI destruction.

Object emission exposes the wrapper as a global definition while `astra.fn.N`
remains local. Tests inspect readelf/nm symbols and the companion's undefined
wrapper reference, destroy LLVM resources, then link and execute the C caller.
This qualifies ordinary executable/object flow; no shared-library mode exists.
An exported `main` passes stage modes but collides with EXEC's separate launch
wrapper and is rejected before executable output creation.

See [ADR 0021](../decisions/0021-c-scalar-exports.md),
[language rules](../language/c-exports.md), and
qualification evidence.


## Coexistence with VAPI imports

VAPI-1 feeds ordinary CABI imports alongside source externs and these unchanged
export contracts. VAPI has no export declarations; `export(C)` remains attached
to Astra-native definitions. Unified callable-name validation rejects a VAPI
import colliding with an exported native name, and CABI external-symbol
uniqueness remains an independent guard. Import ordering gains CLI/file order
after source externs; export ordinals remain independent source order. The
C → Astra → C round-trip tests also pass with external [VAPI input](../language/vapi.md).

## Pointer-capable successor

Pointer exports select [C pointer v1](c-pointer-v1.md); scalar-v0 remains frozen.
`export(C) void* echo(void* p)` plans a C (PTR)->PTR wrapper around a native
internal/fastcc (PTR)->PTR implementation. Exact C and native type maps are
validated separately. The external/ccc wrapper is mandatory even though both
channels map to LLVM ptr. Pointer exports do not enable foreign bool, ownership,
nonnull guarantees, or conversions.
