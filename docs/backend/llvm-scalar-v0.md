# LLVM scalar backend v0

VEC-1 realizes [native vector-v4](../abi/native-vectors-v4.md) as fixed LLVM
vectors: integer lanes use i8/i16/i32, f32 uses float, and masks use i1.
Construction uses exact constants or insertion into a defined zero vector.
Scalar arithmetic dispatch is shared with vectors: wrapping integer operations
have no nsw/nuw; f32 operations have no fast-math flags or contraction. Comparisons
retain signedness and OEQ/UNE/ordered F32 predicates. Backend extraction plus
AND/OR implements all/any; vector block parameters become vector phis. No source
vector memory is introduced, and physical scalarization remains permissible.

ASTRA-LLVM-1 implements the first real Astra body-lowering backend. Inputs are
SsaProgram, its native-only NativeAbiProgram sidecar, and its import/export
CAbiProgram sidecar. Output is an independently owned,
LLVM-verified module for the complete current scalar language subset.
[ADR 0015](../decisions/0015-llvm-scalar-lowering.md) freezes this boundary.

```text
source → syntax → checked semantics → Core → CFG / flow → verified SSA
                                                          ↓
                                                 verified native ABI + C ABI
                                                          ↓
                                              SSA + NABI + CABI → LLVM lowering
                                                          ↓
                                                 verified LLVM module
```

## Implementation and ownership

All physical implementation and bindings reside under `src/backend/llvm/`:

| File | Responsibility |
| --- | --- |
| llvm-module.vala | LlvmError; owning LlvmModuleArtifact; verification and textual dump |
| llvm-type-mapper.vala | Central NABI → LLVM scalar, result, and function mapping |
| llvm-lowering.vala | Input validation, ordinal correspondence, declaration and identity maps |
| llvm-function-lowering.vala | Parameters, primary blocks, phis, stored instructions, calls, terminators, physical end blocks |
| llvm-scalar-lowering.vala | Constants, operators, explicit trap/overflow control flow |
| capi/llvm.vapi | Only required LLVM 22 C API declarations |
| capi/llvm-test.vapi | Read-only structural inspection declarations used only by tests |
| capi/check.c; smoke.vala | System-header/link qualification and original verifier smoke control |

LlvmModuleArtifact owns exactly one LLVMContextRef and LLVMModuleRef. It disposes
the module before its context. Temporary per-function builders are disposed on
both success and error; function/block/value maps and NativeSignature references
are discarded before lowering returns. LLVM values/blocks are borrowed handles
whose owning module supplies their lifetime. Nothing in the artifact retains
source buffers, spans, semantic types, or upstream compiler graphs.

`verify()` invokes LLVMVerifyModule with LLVMReturnStatusAction. `dump()` verifies
again, then uses LLVMPrintModuleToString. Both copy LLVM-owned messages before
LLVMDisposeMessage. The module remains printable and verifiable after every
upstream stage is destroyed. There is no process-global compiler context.

## Types, signatures, and identity

| Native authority | LLVM realization |
| --- | --- |
| NativeScalarType.I8 / U8 | i8 |
| NativeScalarType.I16 / U16 | i16 |
| NativeScalarType.I32 / U32 | i32 |
| NativeScalarType.PTR | ptr |
| NativeScalarType.B1 | i1 |
| absent NativeResult | void function result |

SSA values map SemanticType → existing NativeTypeMapper → NativeScalarType →
LlvmTypeMapper. Native LLVM signatures are constructed from NativeSignature only.
There are no hidden arguments, extensions, attributes encoding a C ABI, or
addressable bool storage. B1 → i1 defines only this backend's value/call channels.

Lowering first verifies SSA and NABI, builds the within-compilation ordinal
SsaFunction → NativeFunction correspondence, and invokes the existing
NativeAbiValidator for declarations and calls. Names are not correspondence
keys. All native functions are created before bodies, with deterministic `astra.fn.N`
names, LLVM internal linkage, and fastcc. Temporary maps bind both native and
SSA identities to one LLVM function/type record. Parameter `pN` maps to the
exact SSA parameter in the same ordinal slot. A direct call uses that record's
function type and function value, then sets fastcc at the call site. Void calls
have no result; unused scalar call results still have their call instruction.

Forward, self-recursive, and mutually recursive calls need no special patching.
Source/debug names may change without affecting LLVM callee identity. The names
and fastcc are unstable backend details, not public ABI promises. The trap
intrinsic retains LLVM's own intrinsic declaration/calling-convention policy;
it is not an Astra-native function or a foreign-call feature.

## Blocks and phis

All reachable primary blocks exist before instructions, named `bN`, with the
designated entry created first. All block-parameter phis are then created at
the start of their primary blocks in SSA parameter order. Values use exact
SsaValue identity maps; printed `vN` names are never definition lookup keys.

Bodies are visited in iterative depth-first order so dominating instructions
exist before cross-block uses even if block ordinals are not topological.
Each block's instructions are lowered in stored order. A per-block state
tracks its primary and current physical end block. Division/remainder can
advance the latter through multiple continuations. Returns/branches originate
there, and outgoing phi arguments use that actual predecessor.

For example, ordinary choose produces:

```llvm
b1:
	br label %b3
b2:
	br label %b3
b3:
	%v3 = phi i32 [ %p1, %b1 ], [ %p2, %b2 ]
	ret i32 %v3
```

An arm containing division instead supplies its `.continue` block as the phi
predecessor. Multiple block arguments produce multiple ordered phis. Bool block
arguments and all their incoming values are i1.

If a conditional has two edges to the same target, the backend creates
`bN.edge.true` and `bN.edge.false`. Each independently branches to the target
and supplies its arguments from its own physical predecessor. This also works
when the conditional originates in a division continuation. Ordinary distinct
successors do not acquire edge blocks. LLVM helper blocks/phis never become
Astra CFG/SSA nodes.

## Scalar semantics

Integer constants use AstraIntValue.signed_value. Negative values add 2^32 in
int64, then convert the nonnegative result to uint64 for LLVMConstInt. This
constructs exact i32 bits without source reparsing or signed narrowing casts.
False/true become i1 0/1, with no other bool bit pattern.

Add/subtract/multiply use ordinary LLVM add/sub/mul, with neither nsw nor nuw.
Unary minus uses sub i32 0, operand with the same wrapping behavior; unary plus
maps directly to its operand. Bool negation uses xor i1 with true. Integer
ordering uses slt/sle/sgt/sge. Int/bool equality uses eq/ne at the operand's
physical width.

Division and remainder create the following physical control flow at exactly
their stored SSA position:

```text
current block: rhs == 0 ? trap : nonzero
trap:         call LLVM trap intrinsic; unreachable
nonzero:      (lhs == INT_MIN && rhs == -1) ? special : normal
special:      branch continue, supplying INT_MIN for / or zero for %
normal:       raw sdiv/srem lhs, rhs; branch continue
continue:     phi of special/normal results; subsequent SSA instructions
```

LLVMLookupIntrinsicID identifies `llvm.trap`; LLVMGetIntrinsicDeclaration and
LLVMIntrinsicGetType obtain its proper declaration and type. No runtime library
call is invented. The raw operation executes only where Astra and LLVM semantics
coincide. In particular, both zero and INT_MIN/-1 are excluded for both operators.
This is required by LLVM 22's [signed division and remainder rules](https://releases.llvm.org/22.1.0/docs/LangRef.html#sdiv-instruction).

The ordinary LLVM C builder can fold constant comparisons/arithmetic without
running a pass. If either exceptional guard is already true, the impossible
normal block is terminated with unreachable and contributes no phi incoming
value. This avoids constructing a constant invalid raw operation or dead poison.
Guards, special blocks, and trap blocks remain explicit; no optimization pipeline
is invoked and no pass is needed to repair semantics.

Calls preceding an operation remain before its zero check. Later calls are
emitted only in its continuation. LLVM lowering consumes SCALAR-1's narrow CFG
evaluation-order mechanism through SSA; it never re-walks an expression tree.
`left() + right()` remains call/call/add/ret; nested arguments remain ordered
identity(1), identity(2), pair. Choose-call retains one transform call per arm,
followed by a join phi and return.

## CLI, determinism, and scope

`astrac --dump-llvm FILE` runs the full pipeline and prints the verified LLVM
module. Successful `--check FILE` includes the same lowering/verifier and stays
silent. Source/semantic/flow errors retain existing diagnostics, exit 1, and
empty stdout. Invalid LLVM inputs/construction/verification report deterministic
internal compiler errors. Arity errors exit 2. Earlier dump modes stop at their
original stages. EXEC-1 extends plain source invocation to native executable
production, with separate entry/target/emission/link diagnostics and `-o` support.

Each compilation unit has fixed module ID/source filename `astra.scalar`.
Construction and assigned names are deterministic, independent of hash
iteration, source path, timestamps, addresses, or temporary directories.
LLVM owns final printer formatting. Goldens describe LLVM 22 output and explicitly
do not establish a stable symbol ABI.

The ordinary body-lowering artifact and `--dump-llvm` remain free of target
triple/data layout and process wrapper. EXEC-1 can bind an exact selected entry
to borrowed LLVM function/type handles during lowering, without changing the
dump or retaining upstream representations. Its downstream configured artifact
adds host triple/layout and the private launch wrapper, then verifies again.
See [native execution v0](native-execution-v0.md). No explicit optimizer pipeline,
JIT or debug info is added. CABI-1 separately adds explicit scalar C imports.

## Cyclic phi realization in LOOP-1

ASTRA-LOOP-1 requires no body-lowering change. All primary blocks and block
parameter phis exist before the visited traversal lowers instructions. A
loop header phi receives its initial value from the preheader and its updated
value from the ordinary backedge. Header calls consume that phi and execute
again on each header visit. Bool uses i1 phis; nested loops use the same mapping.

Physical end-block tracking applies to cycles: if a body division/remainder
splits execution, the header phi's incoming predecessor is its continuation
block. Header division guards remain in the header execution path and precede
later calls on every visit. Tests inspect these exact predecessors, guard/call
order, phi types/counts, and nested values through the C API; all artifacts
verify. [Loop goldens](../../tests/loop/fixtures/count.ll) retain wrapping
operations without nsw/nuw. Loop correctness uses no optimization pass.

## Validation and next boundary

Dedicated backend tests inspect LLVM types, flags, predicates, exact callees,
call conventions, phi values/predecessors, and helper blocks. A graph test proves
nonzero domination of each representative raw divide/remainder and explores
all unknown branch choices with exceptional operands fixed, proving neither
exceptional case can reach the raw instruction. Constant special paths are
checked separately. Synthetic parallel edges carry distinguishable arguments,
including a case after a division split; another valid SSA fixture deliberately
puts definitions later in block array order.

Weak-reference tests destroy source, syntax, checked models/types, Core, CFG,
SSA, and NABI before verifying/dumping the remaining artifact, then destroy the
artifact. Valgrind checks LLVM resources as well as Astra-owned allocations.
Fifteen CLI goldens include constants, wrapping, comparisons, choose, multiple
merge, bool phi, choose-call, ordered/nested/forward/recursive calls, division,
division order, and division-to-join predecessors. Error tests enforce empty
stdout. The existing upstream suites remain unchanged.

Negative linkage tests keep upstream/standalone executables LLVM-free. Positive
tests require exactly one libLLVM, resolved to the same real library selected
by llvm-config 22, plus the expected ELF dependency and C API imports. Opposing
negative controls prove each check rejects the wrong executable class. See
[toolchain evidence](../toolchain.md#astra-llvm-1-qualification).

ASTRA-EXEC-1 qualifies a host target machine, entry/object/link policy, and
machine behavior without treating internal names or fastcc as stable ABI.
Runtime trap tests require no normal continuation. LLVM documents a possible abort
fallback for targets lacking a trap instruction in its
[trap intrinsic contract](https://releases.llvm.org/22.1.0/docs/LangRef.html#llvm-trap-intrinsic).
EXEC-1 uses this intrinsic lowering directly, without an Astra trap runtime.

## Multiple control predecessors in LOOPCTRL-1

Break/continue arrive as existing SSA branches with ordered arguments. Header
phis accept the preheader, multiple continue paths, and ordinary fallthrough;
exit phis accept header-false and multiple break paths. No LLVM-specific loop
control enters upstream IR, and no LLVM production change is needed.

Physical end-block authority remains exact after division/remainder splitting.
A transfer path's final `.continue` block supplies the phi incoming predecessor,
not its primary SSA block. Tests inspect incoming values, block identities, and
all physical predecessor counts for three/four-way headers, three-way exits,
and nested loops. Ordered calls precede transfers; unreachable tail calls are
absent after SSA projection. Every workload passes LLVM verification, including
after source SSA/NABI reclamation. See [qualification](../toolchain.md#astra-loopctrl-1-qualification).

## Short-circuit expressions

SHORTCIRCUIT-1 reaches LLVM as ordinary branches and bool block parameters. Existing
lowering emits `br i1` and `phi i1`; no direct logical source handling or eager
source `and`/`or` is added. Existing division overflow guards retain their internal
`and`. Calls/traps remain solely on the required RHS path. A division/remainder
RHS phi predecessor is the final physical `.continue` block, never the original
RHS primary block. Structural tests inspect exact incoming predecessors and LLVM
verification runs on every module. The [trap golden](../../tests/shortcircuit/fixtures/trap-short.ll)
and [loop golden](../../tests/shortcircuit/fixtures/loop-short.ll) qualify these shapes.

## C ABI import lowering

LlvmLowering consumes verified SSA, NABI, and CABI. It constructs all native
functions and all C declarations before native body lowering. LlvmCTypeMapper
maps CAbiScalarType.I32 to i32 and an absent CAbiResult to LLVM void, independently
of NativeTypeMapper. Each CAbiFunction supplies the exact external name. Import
declarations have external linkage, no blocks/body, and CApi.CallConv.C; every
SsaCCallInstruction uses that convention too. LLVM omits default `ccc` in text.

Temporary SsaCFunction → CAbiFunction → LlvmCFunctionBinding identity maps supply
foreign calls. No LLVM string lookup occurs during call lowering. Ordinary
native calls remain internal fastcc `astra.fn.N` with native I32/B1 signatures.
No effect/purity attributes, hidden channels, bool adaptation, or optimization
are added for imports. LLVM instruction order and existing branch/phi paths
preserve Astra argument, trap, short-circuit, and loop ordering.

The artifact retains C import contract records containing copied symbol names
and borrowed LLVM declaration/type/call handles only. Its verifier checks exact
name, type, target, declaration-only status, external linkage, and C convention
before LLVMVerifyModule. This catches architecture errors that general LLVM IR
validity alone cannot describe. SSA/NABI/CABI and all source provenance may die
before artifact verification, printing, and object emission.
See [CABI v0](../abi/c-scalar-import-v0.md).

## C export wrapper lowering

CEXPORT-1 validates export correspondence against verified SSA/NABI/CABI, creates
all internal native functions, then creates one external ccc wrapper per CAbiExport.
Its LLVM type comes exclusively from CAbiSignature. The copied native ordinal
binds its exact internal function, independently of debug names. For current I32
channels, the wrapper forwards exact LLVM arguments into one fastcc native call
and returns its result, or emits ret void. No conversion or optimization removes
this separate ABI boundary. Native source calls and recursive calls bypass it.

Artifact-owned checks enforce wrapper name/type/external linkage/ccc, native
target internal linkage/fastcc, exact call type/target/fastcc, and call/return-only
structure with exact argument/result forwarding. General LLVM verification still
runs. Contracts retain copied symbols and borrowed LLVM handles, allowing SSA,
NABI, CABI, and source provenance to die. Object emission retains global wrappers
and local native implementations. Symbol collision checks precede wrapper creation;
executable-entry validation rejects exported main, while stage LLVM supports it.
See [export contract](../abi/c-scalar-export-v0.md) and
qualification.

## PTR-1 realization

NativeScalarType.PTR and CAbiScalarType.PTR have separate LLVM mappers; both use
LLVMPointerTypeInContext(context, 0). Semantic null lowers with the qualified
LLVMConstPointerNull API, never integer zero or inttoptr. Existing equality
lowering applies LLVMBuildICmp EQ/NE directly to ptr operands; no ptrtoint is
needed. Pointer SSA block parameters use ordinary phi ptr and exact physical
predecessor bookkeeping, including parallel and trap-split edges.

Native pointer definitions/calls stay internal/fastcc; C pointer imports and
export wrappers stay external/ccc. Wrappers forward exact PTR arguments/results
through a native fastcc call. No nonnull, noalias, dereferenceable, align,
nocapture, readonly, or writeonly promise is inferred from void*. Target data
layout supplies physical pointer width during native emission. Completed LLVM
artifacts contain no semantic/SSA/ABI/provenance objects or ownership actions.
See [C pointer v1](../abi/c-pointer-v1.md).

## Native local structs

Non-address-taken STRUCT-1 field Places disappear through generic scalar SSA promotion before the
backend boundary. LLVM receives only existing i32/i1/ptr values and ordinary
field merge/loop phis. No LLVM struct type, extractvalue, insertvalue, aggregate
alloca, size/alignment, or field-offset calculation is required. NABI/CABI remain
scalar/pointer-only because struct parameters and results reject semantically.
The original scalarized STRUCT-1 path is unchanged.

Execution tests cover basic fields, mutation, recorder order 21, single/multiple
field joins, zero/one/many loop iterations, bool fields, pointer identity, null
short circuit, and break/continue. Structural tests verify scalar phi predecessors,
trap ordering, identical LLVM for representative scalar equivalents, independent
stage lifetime, and object/linkage authority. See STRUCT-1 qualification.

## TPTR-1 addressable native structs

Typed native pointer parameters use existing PTR/LLVM ptr without new channels.
Only addressable locals or indirect field access require a backend-private
struct type. One entry alloca per addressable local supplies exact direct field
GEPs; indirect fields use the pointee's exact struct type and field ordinal.
Loads/stores remain scalar, with no whole aggregate copy or stable layout.

Indirect accesses branch through explicit null guards to llvm.trap/unreachable
or a non-null GEP/access continuation. Store guards follow RHS effects. Physical
end-block tracking preserves phi predecessors after null splits, including loops
and short-circuit joins. No pointer conversion or parameter alias/null/access
attribute is inferred. See [native struct storage v0](native-struct-storage-v0.md).

Qualification executes caller mutation, before/after loads, same-object aliases,
distinct locals, nullable pointer locals, recursion, loops with break/continue,
and both skipped and required short-circuit dereferences. Read/write null cases
terminate abnormally. Stage tests release SSA before emission and LLVM before
linking/running an addressable executable. The toolchain remains LLVM 22.1.8,
with no new dependency or target runtime. See TPTR-1 qualification.

## OWN-1 nullable cleanup

CABI supplies one external ccc void(ptr) declaration per cleanup identity.
SsaCleanupInstruction emits an icmp-eq-null guard, optional ordinary ccc call, and
continuation. The compiler explicitly sets/verifies ccc even though LLVM's printer
omits its default spelling. No cleanup effect, alias, or pointer attribute is
inferred. Each guard updates LlvmBlockState.end; subsequent cleanup chains and
phi incoming edges use the actual physical continuation. Traps still terminate
without cleanup and no invoke/personality is introduced. See [cleanup IR](../ir/cleanup.md).

## Exact-width integers

INTS-1 realizes semantic width with exact i8/i16/i32 operations, phis, native
parameters/results, and addressable field loads/stores. Constants use
`AstraIntegerValue.bits` with LLVMConstInt; signed host casts and source parsing
supply no authority. Canonical int/i32 lowering stays byte-identical.

Ordinary add/sub/mul and signed `0 - x` carry no nsw/nuw flags. Unary plus is
identity. Signed comparisons select slt/sle/sgt/sge; unsigned comparisons select
ult/ule/ugt/uge. eq/ne require equal exact source types before lowering.

Every divisor first passes an explicit zero guard to llvm.trap/unreachable.
For signed widths, MIN/-1 branches to MIN (division) or zero (remainder), with
sdiv/srem only on the safe normal path. Constants on impossible paths never
create poison. Unsigned udiv/urem need only the zero guard, with no signed
special branch. Every split updates `LlvmBlockState.end`; branch, loop, and
short-circuit phis use the actual final physical predecessor, including narrow
signed `.continue` and unsigned `.nonzero` blocks. No SSA graph redesign occurs.

The [v2 native sidecar](../abi/native-integers-v2.md) retains sign distinctions
that LLVM integer types do not. C mappings remain separate and unchanged.
INTS-1 qualification covers module verification,
exact physical predecessor audits, native execution, and lifetime/object checks.

## Exact binary32

F32-1 maps Native F32 to LLVM float for signatures, constants, operations, phis,
and struct fields. LLVMConstInt(i32, exact_bits) followed by LLVMConstBitCast
constructs constants without host floating values or decimal text. The test
suite round-trips all value classes, including signed zero and NaN patterns.
Unary plus is identity; unary minus uses fneg. fadd/fsub/fmul/fdiv are ordinary
operations with no fast-math flags. fdiv bypasses the integer guard/trap path.
Comparisons are oeq, une, olt, ole, ogt, oge. In particular, UNE includes NaNs.

The default LLVM 22 [floating environment](https://releases.llvm.org/22.1.0/docs/LangRef.html#floating-point-environment)
uses nearest rounding and preserved subnormals. Absent denormal attributes mean
ieee/ieee. No extra attributes or constrained intrinsics are needed here.
F32-1 qualifies x86-64 Linux with CPU/features empty and code-generation level
NONE; scalar SSE/SSE2 instructions round after each binary32 operation. F32
emission for other target configurations rejects pending qualification. Astra
sets no FTZ/DAZ mode. Foreign code must restore the required default environment.

Source multiply-plus-add stays fmul then fadd without contract permission.
IR and object audits also lower the witness with FMA enabled at code-generation
O2 to check that the absence of permission survives target instruction selection.
No unsafe no-NaN/no-infinity/no-signed-zero attributes or reassociation are added.
Float memory uses existing GEP/load/store and physical predecessor handling.
See [ADR 0036](../decisions/0036-binary32-semantics.md) and
F32-1 qualification.

TEXT-IO-1 extends imported calls using independently verified CABI text groups.
Each captured StringType argument supplies adjacent PTR/I32 operands at its
logical position; the native paired-view representation remains intact until
that extraction. Source evaluation and numeric-guard final-continuation/phi
bookkeeping remain the existing SSA authority. Imported text metadata supplies
no readonly/readnone, noalias, nonnull or speculative attributes. The artifact
records a separate C text target requirement, checked before object emission;
C floating compatibility remains independent. See [C text views](../abi/c-text-views.md).
