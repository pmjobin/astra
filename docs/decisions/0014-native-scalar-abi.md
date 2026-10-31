# ADR 0014: Native scalar ABI signatures

Status: accepted for ASTRA-NABI-1.

## Context

SCALAR-1 establishes signed 32-bit int semantics, exact bool values, explicit
zero-divisor traps, and evaluation order through SSA. CALL-1 establishes exact
cross-stage function identity and reclaimable recursion. Neither semantic
authority supplies a physical call contract for a future backend.

The first physicalization boundary is a signature sidecar built from verified
SSA. SSA continues to own blocks, values, instructions, calls, control flow,
block arguments, and effect order. Native ABI planning owns only the physical
function contracts. It neither translates nor duplicates bodies.

## Decision

1. Astra native ABI is compiler-owned and architecturally distinct from C ABI.
2. The initial ABI is unstable and internal. It promises no compatibility
   between compiler versions, independently compiled objects, or modules.
3. **Astra Native Scalar ABI v0**, represented by
   `NativeAbiVersion.SCALAR_V0`, identifies an internal physical contract.
   It is not semantic versioning, a public stability guarantee, or an
   object-file compatibility promise. Pre-release Astra may change it deliberately.
4. NABI-1 defines abstract physical channels. It assigns no registers, stack
   slots, offsets, save rules, red zones, or permanent machine calling convention.
5. Semantic `int` maps to `NativeScalarType.I32`: exactly 32 transported bits
   with Astra's two's-complement signed interpretation, covering exactly
   -2147483648 through 2147483647. SCALAR-1 remains arithmetic authority.
6. Semantic `bool` maps to `NativeScalarType.B1`: a logical scalar transport
   value with exactly false and true as its possible values.
7. B1 does not define bool memory size, field packing, alignment, addressable
   storage, or register encoding. A future target may use a wider carrier while
   preserving canonical false/true; alternate encodings or unused bits cannot
   introduce a third Astra bool value. NABI-1 performs no widening.
8. Each scalar source parameter contributes exactly one direct channel, in
   source parameter order, with dense ordinals starting at zero.
9. A scalar-returning function has exactly one direct I32 or B1 result channel.
10. A void function has no result channel. There is no native VOID scalar type;
    void cannot be a parameter, SSA value, or direct transported scalar.
11. There are no hidden parameters or results: no context, runtime, metadata,
    provider, ownership, sret, exception, closure, or async channels.
12. `NativeSignature` is physical compiler authority, containing Astra-owned
    scalar enums, ordered parameters, an optional result, and ABI version.
    It contains no semantic type objects or LLVM types.
13. `NativeFunction` is a distinct downstream identity with copied source/debug
    name and SourceSpan provenance. Every function has
    `NativeLinkage.NATIVE_INTERNAL` intent. Source names promise no external
    linker spelling; this milestone defines no mangling scheme.
14. Machine calling-convention realization belongs to the backend and target.
    The same abstract scalar signature describes eventual x86-64, AArch64, or
    SH-4 lowering without target configuration or ABI tables here.
15. Physical signatures preserve all earlier language contracts. Future body
    lowering must preserve wrapping, signed comparisons, division/remainder
    exceptions, explicit traps, call effects, and left-to-right evaluation.
    These obligations are not encoded by inventing signature channels.
16. C/VAPI interoperability is a separate future ABI boundary. Similarities
    between eventual machine conventions do not turn native signatures into
    C signatures or introduce C types, promotions, or symbol policy.

## Representation and ownership

`src/nabi/native-model.vala` defines NativeAbiProgram, NativeFunction,
NativeSignature, NativeParameter, NativeResult, and the physical enums.
NativeAbiProgram strongly owns functions in deterministic source order;
functions strongly own signatures; signatures own parameter channels and an
optional result. SourceSpan retains SourceFile for provenance. Names are copied.

A function's containing program uses GLib WeakRef, following CALL-1's expired
reference discipline. Normal construction claims one program owner and rejects
sharing a live function between programs. The verifier checks membership and
array ordering even if an internal caller changes the array-based model.
The weak owner never retains the program. NABI has no call edges or recursive
ownership graph. Completed artifacts retain neither SSA nor semantic types.

The representation cannot express indirect/split/by-reference channels, hidden
channels, multiple results, or a void scalar. Normal constructors require a
signature. Malformed tests use existing internal constructors, enum casts, and
array contents; there are no test-only mutation APIs or weakened constructors.

## Planning and validation

`NativeTypeMapper.map_scalar` is the one semantic-to-native mapping authority:
INT → I32, BOOL → B1; VOID and unknown semantic kinds raise internal errors.
`map_result` maps VOID to null and otherwise uses that same scalar mapper.
SemanticType itself gains no physical conversion API.

`NativeAbiBuilder.build(SsaProgram)` first runs SsaVerifier, including for direct
API clients. It creates every NativeFunction and complete signature, inserting
each exact SsaFunction → NativeFunction pair in a temporary direct-hash table.
Source arrays determine ordering; no table iteration or source-name lookup
determines identity. After all declarations exist, it structurally verifies
the sidecar and invokes NativeAbiValidator with both programs and that map.

The construction-time validator checks a complete one-to-one correspondence,
matching declaration channels, and every SsaCallInstruction. Each exact call
target must map to the corresponding program-owned NativeFunction. Argument
counts and mapped scalar types must match each parameter; result presence and
type must match the optional direct result. Discarding a scalar result does
not remove its channel. Forward, self, and mutual calls use the same algorithm.
The helper returns the resolved native identity while validating; the completed
program retains neither the map nor call-site references.

NativeAbiVerifier and NativeAbiDump have no semantic or SSA dependencies.
Verification checks recognized ABI version, unique dense function identity and
ordinals, owner membership, valid linkage, a signature with matching version,
ordered dense parameter ordinals, and supported parameter/result scalar types.
The dumper verifies first and produces one complete string using tabs and LF.
Malformed structures and physical mismatches use deterministic NativeAbiError
messages through the compiler-internal diagnostic path, not source diagnoses.

## Alternatives and consequences

Retaining SsaFunction or SemanticType in the physical model would avoid copying
names/provenance, but would leave upstream authority alive at the physical
boundary. Copying the small signature payload and retaining only SourceSpan
makes semantic-type and SSA destruction testable.

A second native body graph would duplicate SSA without enabling any NABI-1
behavior. The sidecar preserves one body authority for future lowering.
Retaining translated call edges would similarly add ownership and identity
machinery solely for facts already held by SSA; temporary validation suffices.

Widening bool to I32 now would lose the abstract boolean channel distinction
and prematurely select a carrier. B1 instead specifies canonical logical
transport while deferring memory and machine realization.

Dense source ordinals support deterministic correspondence and inspection,
without defining stable external names. Future lowering consumes both SSA and
the sidecar during one invocation and establishes its own temporary exact
identity associations. No separate-compilation contract is implied.

Ownership-bearing values, aggregates, generics, objects, interfaces, closures,
async, or SIMD may require a deliberate future ABI version. No reserved fields
or speculative channels anticipate them here. See the
[native scalar v0 contract](../abi/native-scalar-v0.md), particularly the
backend obligations that ASTRA-LLVM-1 must obey.

## NABI-1 qualification

Validated on 2026-09-06 from the clean accepted SCALAR-1 baseline
`b0e80b9f01ba14d27817ddd57b74358ec860cae6`, on branch `astra-nabi-1`:

```sh
CCACHE_DISABLE=1 meson setup build-nabi-1-final -Dwerror=true
CCACHE_DISABLE=1 meson compile -C build-nabi-1-final
CCACHE_DISABLE=1 meson test -C build-nabi-1-final --print-errorlogs
```

The build directory was fresh. All **712 Meson entries and 682 GLib/TAP cases**
passed, with no warnings or failures. All **340 C compile commands** retained
`VALA_STRICT_C` and `-Werror`. All 648 previous Meson entries remain; NABI adds
64 entries, including 34 pipeline/call/lifetime and 17 standalone cases.

| GLib/TAP suite | Passing cases |
| --- | --- |
| Frontend | 149 |
| Semantic | 141 |
| Core / standalone Core | 107 / 5 |
| CFG / standalone CFG | 116 / 9 |
| Dominance | 8 |
| SSA / standalone SSA | 17 / 40 |
| Calls | 13 |
| Scalar reference / optimized UB-trapping reference | 9 / 9 |
| Scalar pipeline | 8 |
| NABI pipeline, mapping, calls, lifetime | 34 |
| Standalone NABI | 17 |

The 23 new NABI goldens were derived independently from fixture declarations,
then checked against compiler output. They cover four new signature/transport
fixtures, all 12 retained CALL-1 success fixtures, all six SCALAR-1 boundary and
ordering fixtures, and an empty program. Existing dumps, fixtures, and test
sources are unchanged. Malformed signatures and compatibility errors have
explicit deterministic expectations. Same-spelled distinct SSA functions prove
that identity cannot be replaced with name resolution.

Five NABI lifetime cases cover forward, self-recursive, mutual-recursive,
representative scalar, and bool/void-call programs. Weak references prove that
syntax, checked models, Core, CFG, SSA functions/blocks/calls, the type universe,
and all three semantic types die before the completed sidecar is verified,
dumped, and queried for names, physical channels, and source locations. Releasing
the sidecar then reclaims native functions/signatures/channels and source data.

All **17 protected executables** pass actual link-command, `ldd`, `readelf`, and
`nm` audits, including both NABI targets and the CLI harness. The unchanged LLVM
smoke executable fails the firewall as the required negative control.
Standalone NABI's compile-input and symbol audits contain only its test,
model/verifier/dumper, and SourceFile/SourceSpan/Diagnostic; no semantic or SSA
authority is compiled or linked into it. There are no NABI backend handles,
target conventions, symbol mangling, C ABI, or duplicated body structures.

**22 representative Valgrind runs** report zero errors and zero definitely,
indirectly, or possibly lost bytes, with no added suppressions. They cover both
complete NABI suites, complete SSA/call and Core/CFG/SSA standalone suites,
scalar reference/pipeline suites, and 13 CLI paths: representative/zero/mixed/
bool-transport signatures, forward/self/mutual/bool calls, scalar boundaries,
trap order, recursive `--check`, scalar overflow rejection, and late flow
rejection. No baseline GLib leak finding was encountered on these paths.

During development, the initial standalone input list omitted Diagnostic,
which SourceFile's encoding validation references; including this legitimate
shared utility fixed the compile failure. GCC also rejected Vala-generated
zero-length enum-array allocations in a test helper under `-Werror`; the
helper now uses a null empty array. Source review confirmed that a plain Vala
weak field does not clear upon owner destruction; the new owner uses GLib
WeakRef and its lifetime tests pass. No warning suppression, upstream redesign,
expected-output repair, or dependency was introduced for these findings.

There are no architectural deviations or new production/test dependencies.
No Vala/LLVM-v2 implementation source was copied. Native body lowering, LLVM
lowering, executable/object generation, foreign ABI, data layout, and ownership
channels remain unimplemented. ASTRA-LLVM-1 must consume SSA and this sidecar
together, establish temporary exact backend identity mappings, realize I32/B1
carriers, and explicitly preserve SCALAR-1's trap and exceptional division
behavior. Stable linkage and target ABI policy remain future decisions.
