# Astra Native Scalar ABI v0

ASTRA-NABI-1 introduces Astra's first compiler-owned physical call-signature
authority. It is an unstable internal ABI for one compiler invocation. There
is no cross-version, module, object-file, shared-library, or exported-symbol
compatibility promise. Pre-release compiler versions may deliberately change
this contract. [ADR 0014](../decisions/0014-native-scalar-abi.md) records the decision.

## Boundary and physical channels

```text
SsaProgram ──────────────→ NativeAbiProgram
    │                     physical signature sidecar
    │                            │
    └────────────────────────────┴──→ verified LLVM body lowering
```

SSA remains authoritative for bodies: blocks, values, instructions, calls,
control flow, block arguments, and effect order. NativeAbiProgram owns physical
parameter/result contracts and native function identity. It contains no body,
call graph, NativeBlock, NativeInstruction, phi, branch, or arithmetic operations.

| Semantic authority | Native authority | Transport contract |
| --- | --- | --- |
| `TypeKind.INT` | `NativeScalarType.I32` | Exactly 32 bits; Astra two's-complement signed int |
| `TypeKind.BOOL` | `NativeScalarType.B1` | Exactly one logical false/true value |
| `TypeKind.VOID`, only as result | Null `NativeResult` | No transported result |

I32 represents exactly -2147483648 through 2147483647. It is an Astra physical
type, not an alias for SemanticType, a host type, a foreign type, or a backend
type. Its signed interpretation comes from [SCALAR-1](../language/scalars.md).
Signatures do not redefine arithmetic.

B1 carries one bit of logical information. It does **not** imply
`sizeof(bool) == 1 bit`, bit-packed fields, one-bit addressable storage, or any
memory size or alignment. Bool objects and fields are outside this milestone.
A future backend may realize B1 with a wider machine carrier. It must preserve
canonical false/true values: unused bits or alternate integer encodings cannot
become additional Astra bool values. NABI-1 implements no widening or encoding.

`NativeScalarType` has exactly I32 and B1, with no VOID enumerator. Void is valid
only in result context. `NativeTypeMapper.map_scalar(SemanticType)` centrally
maps INT and BOOL and raises NativeAbiError.INVALID_TYPE for void or unsupported
types. `map_result` returns null for void, otherwise one mapped NativeResult.
Every parameter, SSA argument, and call-result mapping uses this authority.

## Signatures and ownership

```text
src/nabi/
	native-model.vala        physical enums, channels, signatures, function/program identity
	native-verifier.vala     structural checks without upstream models
	native-dump.vala         verified deterministic physical signature dump
	native-type-mapper.vala  centralized semantic-to-native scalar boundary
	native-builder.vala      verified SSA planning with a temporary exact callee map
	native-validator.vala    declaration and direct-call physical compatibility
```

| Model | Owned information |
| --- | --- |
| `NativeAbiProgram` | ABI version, program SourceSpan, ordered NativeFunctions |
| `NativeFunction` | Dense source ordinal, copied debug name, source/name spans, signature, linkage; weak program owner |
| `NativeSignature` | ABI version, ordered direct NativeParameters, optional direct NativeResult |
| `NativeParameter` | Dense source ordinal, NativeScalarType, copied debug name, source/name spans |
| `NativeResult` | One NativeScalarType |

`NativeAbiVersion.SCALAR_V0` spells `scalar-v0` in artifacts. Each signature
carries this identity, verified against its containing program. It has no
public semantic-versioning significance.

Every scalar source parameter creates one direct channel, in source order.
A scalar return creates one direct result. A void return creates none. There
are no indirect, split, by-reference, or adaptation channels and no synthetic
channel for a zero-argument function. Parameter names are provenance only.

| Source signature | Physical signature |
| --- | --- |
| `void ping()` | `() -> void` |
| `int one()` | `() -> I32` |
| `bool yes()` | `() -> B1` |
| `int transform(int x)` | `(I32) -> I32` |
| `void ping(bool enabled)` | `(B1) -> void` |
| `bool predicate(int x)` | `(I32) -> B1` |
| `int choose(bool c, int a, int b)` | `(B1, I32, I32) -> I32` |

There is no context/runtime pointer, ownership metadata, type/provider metadata,
sret pointer, closure context, async frame, or exception channel. Those concepts
have no representation in scalar v0.

Only a program owns its function membership. A function's GLib WeakRef owner
supports deterministic rejection of foreign or expired ownership without a
reference cycle. Signatures own channels; SourceSpan owns SourceFile. Completed
NABI retains no syntax, symbols, checked model, Core, CFG, SSA, SemanticType,
AstraIntValue, builder map, or call-site references. Debug names and spans remain
usable after upstream destruction; retaining source bytes is provenance, not a
second representation of the body.

## Identity, planning, and calls

`NativeAbiBuilder.build` verifies SSA before constructing physical artifacts.
It creates **all** NativeFunctions and signatures in source order, recording an
exact temporary `HashTable<SsaFunction, NativeFunction>` using direct object
hash/equality. It then verifies the sidecar and validates calls. This order
supports forward calls, self recursion, and mutual recursion uniformly.

NativeAbiValidator is an internal construction-time utility. Its inputs are
verified SSA, verified NABI, and the exact temporary map. It checks that the
programs and map correspond one-to-one in source order, that each declaration's
parameters/result physicalize exactly, and that every SSA call resolves through
the map to a program-owned NativeFunction. Each argument's mapped type must
match the corresponding ordered parameter, and call-result presence/type must
match the result channel. An unused non-void result still has a channel.

No validation searches by name or reconstructs a signature from source text.
Even identical debug names and physical shapes leave distinct function
identities. The completed program keeps no call edges and no SSA map; the
construction-time map is released before `build` returns.

NativeAbiVerifier requires recognized program/signature ABI version, unique
source-ordered function identities and ordinals, exact program ownership,
native-internal linkage, an existing signature, dense ordered unique parameter
ordinals, and only I32/B1 channels. Optional NativeResult structurally prevents
multiple results; the channel model cannot express hidden channels or void
parameters. Unsupported enum casts are rejected deterministically. Constructors
are not weakened for malformed tests.

## Linkage and target realization

Every function has `NativeLinkage.NATIVE_INTERNAL` intent. Its source name is
for diagnostics, debugging, and dumps; `add` does not promise the linker symbol
`"add"`. There is no stable mangling, external/public/weak linkage, export
syntax, or DLL visibility policy. LLVM-1 uses backend-local `astra.fn.N` names
and LLVM internal linkage without making them an external ABI.

Native signatures specify what crosses a call boundary. Backend/target lowering
will decide registers, stack locations, machine carriers, and calling-convention
realization. LLVM-1 realizes calls/definitions with fastcc, an internal backend
choice rather than a permanent native ABI promise. Scalar v0 has no target-specific branching, configuration, machine
ABI tables, stack layout, alignment, or data-layout decisions. It does not model
SysV, Windows x64, AAPCS, or SH-4 calling conventions.

Astra-native and C/VAPI signatures remain distinct boundaries. There are no C
types, promotions, calling-convention rules, or symbols in this contract.
Future machine-level similarities do not establish foreign interoperability.
EXEC-1 keeps this contract unchanged while generating host objects and
executables downstream. Source `int main()` remains native-internal/fastcc.
A backend-private external/default-CC wrapper calls that exact native entry;
it creates no user C ABI or separate-compilation compatibility. Host layout
and code-generation machinery remain outside NABI. No ownership, aggregates,
objects, generics, closures, async, or SIMD is implemented here. See
[host-native execution](../backend/native-execution-v0.md).

## LLVM-1 realization and continuing lowering obligations

Physicalization cannot weaken language meaning. Every lowering must preserve:

- I32 wrapping addition, subtraction, multiplication, and unary negation modulo
  2^32; unary plus remains identity. Overflow must not become undefined behavior.
- Signed ordering for integer comparisons and exact scalar equality.
- Signed division truncating toward zero and dividend-signed remainder.
- An explicit observable zero-divisor runtime trap for division and remainder,
  with no result value on the trapping path.
- `INT_MIN / -1 == INT_MIN` and `INT_MIN % -1 == 0`; neither backend poison nor
  a machine overflow trap implements these cases.
- Exactly false/true on every B1 channel, including any future wider carrier.
- Left-to-right operand and argument evaluation, arguments before their call,
  conservatively effectful calls, and preserved order between calls and
  trap-capable operations.

For example, in `a / b + effect()` and `pair(a % b, effect())`, the division or
remainder must finish before the later call executes. SCALAR-1 already preserves
that sequencing through CFG evaluations and ordered SSA instructions. A backend
must explicitly preserve zero checks, exceptional signed-division results, and
observable sequencing; naive division that introduces undefined behavior or
speculation across effects is invalid. The scalar reference tests remain an
oracle. NABI adds no body operations; LLVM-1 implements these rules downstream.

LLVM-1 consumes verified SSA plus this verified sidecar and reuses the existing
ordinal declaration/call validator before declaring any functions. Signatures
come only from NativeSignature. The centralized backend mapper realizes I32
as i32, B1 as i1, and absent results as void. SSA values use NativeTypeMapper
before that same mapper. This i1 realization does not freeze bool memory layout.

All internal fastcc functions exist before body lowering; direct calls bind to
exact SSA identity, not debug spelling. Block arguments become LLVM phis, with
parallel edges split into distinct physical predecessor blocks. Wrapping
operators have no nsw/nuw; comparisons are signed. Explicit zero and INT_MIN/-1
guards protect raw sdiv/srem, retaining SSA effect/trap order without optimization
passes. The verified artifact owns its module/context and retains no NABI or
SSA graph. See [LLVM scalar v0](../backend/llvm-scalar-v0.md).

## CLI and inspection

`astrac --dump-nabi FILE` runs parsing, semantic analysis, Core, CFG, flow
validation, SSA construction/verification, native planning, call validation,
and native structural verification before printing one complete dump.
`astrac --check FILE` silently includes this boundary and LLVM lowering/verifier.
`astrac --dump-llvm FILE` prints the completed verified LLVM module.
Earlier parse and dump modes keep their original stages and output.

Success exits 0. Source/semantic/flow failures use existing diagnostics and
exit 1 with empty stdout; argument errors exit 2. Native mismatches are internal
compiler failures, reported deterministically as `astrac: internal native ABI
...`, also without partial native output. A previously valid program acquires
no new source validity restrictions.

For `int add(int a, int b) { return a + b; }`:

```text
(native-abi scalar-v0
	(function #0 "add"
		(linkage native-internal)
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

This is a deterministic internal debugging format using tabs and LF, not a
serialization promise. It shows no body, backend types, machine placement, or
linker spelling. With function names/signatures held fixed, changing literal
values, arithmetic, traps, control flow, or recursive calls leaves the dump
identical. The [representative fixture](../../tests/nabi/fixtures/signatures.nabi)
also shows `(I32) -> B1` and `(B1) -> void`.

## Native-only authority with C imports

CABI-1 leaves every native channel, linkage rule, and call convention unchanged.
NativeAbiBuilder traverses SsaProgram.functions only; NativeAbiValidator accepts
SsaCallInstruction and exact SsaFunction maps. SsaCFunction declarations and
SsaCCallInstruction nodes never enter NABI. A mixed `--dump-nabi` contains only
native functions; `--dump-cabi` separately contains imports and export wrappers.

[C scalar import profile v0](c-scalar-import-v0.md) independently defines foreign
I32 and absent-result channels. CAbiScalarType.I32 and NativeScalarType.I32 are
distinct identities despite their equal width. Native B1 says nothing about C
`_Bool`, which remains unsupported. The backend realizes native internal/fastcc
and C external/default-CC in one verified module.

## Exported implementations remain native

CEXPORT-1 changes no NABI production source or physical rule. Every exported
SsaFunction enters NativeAbiProgram exactly like an unexported definition, with
I32 channels, optional result, and NATIVE_INTERNAL linkage. Its native calls and
recursive calls use that identity. No C symbol, exported linkage, or wrapper
appears in NABI. A regression compares the entire NABI dump with the same source
after removing `export(C)` prefixes, while keeping C imports in both programs.

CABI additionally plans [export contracts](c-scalar-export-v0.md), validates exact
SSA/NABI correspondence, and copies the native ordinal for later wrapper binding.
This adds no stable native ABI promise. The external/ccc wrapper and its internal/
fastcc implementation remain different physical functions even when both carry i32.

## Pointer-capable successor

PTR-1 preserves this scalar-v0 contract and all pointer-free goldens. A program
with a pointer-containing native signature selects NativeAbiVersion.SCALAR_PTR_V1
and the distinct native PTR channel; body-only pointer locals do not. Existing
I32/B1 channels and internal/fastcc identity stay unchanged. Scalar-v0 verification
rejects PTR. See [native pointer v1](native-pointer-v1.md).

## Integer-capable successor

INTS-1 preserves this profile for signatures without i8/u8/i16/u16/u32.
`int` and `i32` both map to existing I32 and do not require a newer profile.
A native parameter/result using a new integer selects
[scalar-int-v2](native-integers-v2.md), which subsumes I32/B1/PTR and retains
I8/U8/I16/U16/U32 as distinct signedness-bearing channels. Body-only integer
locals or struct fields do not change profile selection. Existing v0/v1 golden
output remains byte-identical, and no C ABI capability is implied.
