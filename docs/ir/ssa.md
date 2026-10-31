# SSA values, memory, and cleanup through ASTRA-OWNBOUND-1

[NUM-CONV-1](numeric-conversions.md) retains exact scalar integer↔floating
conversion kind, types, signedness and policy. Core keeps the explicit operation;
CFG and SSA add an ordered, destination-specific numeric guard before
floating→integer conversion. SSA validates the proof producer and dominance.
Integer→floating needs no trap guard. Suffixed literals arrive as exact constants;
no downstream stage recovers suffixes or conversion types from syntax.

[BUFFER-1](owned-runtime-arrays.md) uses ordinary PTR/I32 Values with bounded
SsaBufferPair metadata and complete allocation/read/write/deallocation actions.
The pair is not an aggregate SSA Value. Exact provenance, consumer, disarm,
slot-lifetime and borrow checks reject partial transport, copies, mismatches,
missing cleanup and invalidated views after CFG destruction. Only LLVM creates a
multi-leaf return carrier. Resource and buffer replacement share the same static
ownership-flow authority without runtime active flags.

[Owned Resource fields](owned-resource-fields.md) use existing pointer values
and memory-backed class fields. Concrete capture becomes an incoming value and
ordinary source null-disarm. Replacement preserves incoming evaluation, old
load/cleanup, then store. Destructor epilogues are reverse-order handle loads and
exact cleanup calls after normal user-body completion. SSA adds no high-level
field ownership type or runtime state.

[Native struct boundary SSA](struct-values.md) remains leaf-oriented. Calls define
N ordinary SsaInstructionResults grouped by one SsaStructCallResults identity;
the group is not an SsaValue. A resultless bounded-consumption marker survives
field promotion. Returns forward ordered leaves, and control flow merges each
concrete leaf independently. Exact nominal shape metadata is retained for
verification and NABI planning without aggregate Values or phis. Scalarized
parameters and results need no addressable storage.

GEN-1 [generic instances](generics.md) arrive through concrete Core and CFG.
Existing promotion produces concrete block parameters: f64 for choose<f64>, and
exact vectors for choose<i16<8>>. No phi<T>, generic call or unresolved substitution
can enter SSA; its existing concrete type verifier remains the firewall. Generic
metadata never becomes an SSA operand or runtime parameter.

[Property accessors](properties.md) retain SsaProperty and exact getter/setter
callable targets with one ordinary implicit SsaReceiver definition. Reads become
one SsaCallInstruction result; writes become one call consuming the RHS. Values
use ordinary SSA joins and vector extraction. No property or lane Place, backing
storage or property-specific phi is introduced. Struct receiver storage is still
selected per used instance.

F64-1 generalizes floating constants to `SsaFloatConstant` with exact BinaryFloatFormat,
bits, canonical FloatingType and source provenance. F64 is one ordinary scalar
SSA value through arithmetic, comparisons, branches, loops, Places and calls.
Explicit FLOAT_WIDEN/FLOAT_NARROW nodes retain exact source/destination types and
rounding kind after upstream destruction; ICONV remains separate. Verifiers reject
cross-format operands, wrong constant formats and unsupported conversions.
Existing F32 dump bytes remain stable. See [floating values](floating-values.md).

[Owned object results](object-results.md) retain `SsaResultObjectStorage` as a compiler-owned pointer-like input. Calls distinguish candidate storage from forwarded result storage. The returned ClassType SSA value is one nullable owner pointer; result construction has no whole-object SSA value or copy. `SsaOwnedResultUse.FORWARD` records direct owned-object result consumption.

OBJ-OWN-1 promotes each object owner as one ClassType pointer-like value. Existing
owned-call commit definitions clear source capability to null; conditional joins
may merge the original pointer and null. SsaOwnedArgument retains exact class
cleanup, source ordinal, null definition and original local ObjectStorage where
present. SsaCleanupInstruction uses that capability and the same native destructor.
No runtime boolean or object copy is introduced. Source MOVED state remains the
upstream ownership analysis's authority. See [object ownership](object-ownership.md).

OBJ-BOUND-1 uses one SsaFunctionParameter with exact ClassType and the shared
BORROWED_NOESCAPE contract. Copies and forwarding can use the incoming value
directly; branch/loop phis preserve ClassType. Field storage remains caller memory
and existing null validation/direct method instructions are reused. Parameters
create no SsaObjectStorage, aggregate argument or cleanup slot. Exact type and
contract verification precedes NABI's PTR parameter mapping, with no reconstruction
from pointer bits after CFG destruction.
See [object values](object-values.md) and [ADR 0051](../decisions/0051-borrowed-object-boundaries.md).

OBJ-LIFE-1 retains SsaConstructor/SsaDestructor and INITIALIZING/LIVE receiver
inputs. SsaInitializeInstruction writes exact receiver field storage. Storage
receiver instructions name existing ObjectStorage; resultless lifecycle calls
construct or deinitialize it. Reference publication follows successful construction,
and ordinary ClassType SSA copies/phis/rebinding own no destruction. The independent
SSA verifier checks exact lifecycle identities, field dataflow, activation, cleanup
and storage ranks after CFG dies. No runtime lifecycle state exists. See
[lifecycle IR](object-lifecycle.md).

OBJ-1 keeps every class object's SsaObjectStorage in explicit memory, separately
from promoted ClassType references. SsaObjectReferenceInstruction publishes one
scalar reference after complete initialization. Branch/loop reference locals
promote to ordinary single-value block arguments, including object/null merges;
fields stay behind SsaIndirectFieldPlace loads/stores. SsaObjectValidateInstruction
executes before field RHS or method-argument effects, forming either the same
ClassType or the existing nonnull ReceiverType. Class methods use SsaMethod and
SsaCallInstruction. No whole-object SSA value or promoted field shadow is added.
Exact class, storage, field, receiver, dominance and publication contracts survive
CFG destruction. See [reference values](object-values.md) and
[object storage](object-storage.md).

METHOD-1 adds [SsaMethod and SsaReceiver](methods.md). Each method has one
implicit immutable SsaDefinition with exact ReceiverType, separately from its
ordinary explicit parameters. SsaCallInstruction retains exact method identity,
receiver and ordered arguments. Receiver field Places remain explicit memory
loads/stores, and `this.method()` reuses the incoming receiver without an alloca
or copy. Caller instances marked by receiver use share existing SsaStorage with
direct fields and typed-pointer aliases. Nonreceiver instances of the same type
still scalarize. Method declaring layouts survive selective descriptor retention
without forcing instance memory; retained struct ordinals remain source ordinals.
Borrowed slices remain one SliceValue and owned boundaries reuse their existing
instructions. Receiver pointer realization occurs only at NABI/backend lowering.

SLICE-1 adds [SsaSliceConstructInstruction](slice-values.md), one SliceType result,
and SsaSliceLengthInstruction. Slice copies and rebindings promote to one logical
block argument through branches/loops. Base and runtime length never become
unrelated Astra locals. [SsaSliceElementPlace](slice-places.md) uses one captured
view and a dominating exact-view bounds result for ordinary scalar/vector
Load/Store. Arrays and structs remain non-value storage; no LanePlace is added.

ARRAY-1 retains [one explicit array storage object](array-places.md) in
SsaAddressableLocal, with SsaArrayInitialize and SsaArrayElementPlace. Dynamic
SsaArrayBoundsCheck results retain exact IntegerType and storage-specific bound
authority; verifiers check dominance before element access. Array objects and
synthetic per-element locals never promote. Scalar Load/Store uses scalar values;
vector element Load/Store uses one whole vector value. Backend SROA is downstream.

VEC-MEM-1 uses SsaAddressableLocal/SsaLocalMemoryPlace for address-taken numeric
vectors and SsaDereferencePlace for indirect access. One SsaLoadInstruction
returns one vector SSA value; one SsaStoreInstruction consumes one vector value.
Such locals have no promoted authoritative block argument; unaffected vectors
and pointer values still promote. `(*p)[k]` is load then extract, with no lane
Place or semantic scalarization. See [vector memory](vector-memory.md).

BIT-1: SsaPrefixInstruction/SsaBinaryInstruction retain exact bitwise kinds. SsaIntegerShiftInstruction produces one whole scalar/vector result from one value and one independently typed scalar count; its trap contract survives block parameters, branch joins and loops.
See [bitwise/shift IR](bitwise-shifts.md) for verifier, lifetime, evaluation
and backend guard/normalization rules. NABI/CABI/VAPI remain unchanged.

VEC-DOT-1 adds `SsaVectorDotInstruction`. Each integer-wrap or strict F32
dot/MAC remains exactly one instruction and one scalar result, with two whole
vectors and an optional scalar accumulator. Mode, source/result identity and
ordering authority survive CFG destruction. Physical lane extraction/reduction
is confined to the backend. See [dot/MAC IR](vector-dot.md).

VEC-DSP-1 adds `SsaDspInstruction`. Its bounded kind distinguishes
saturating add/sub, low/high widening, wrap/saturating packing and low/high
interleave. Exact source/result/element identities and ordered operands survive
CFG destruction. Every vector DSP primitive defines one whole-vector SSA result;
no lane Place or vector memory is introduced. See [DSP IR](vector-dsp.md).

VEC-LANE-1 adds SsaVectorSplatInstruction, SsaVectorExtractInstruction,
SsaVectorInsertInstruction, SsaVectorShuffleInstruction and SsaVectorSelectInstruction.
Each has one result, with compile-time ordinal metadata outside the SSA value
space. Extract yields a scalar; other primitives yield whole vectors. No lane
Place or proactive scalarization occurs. Whole-vector assignment, branches and
loop block arguments use ordinary promotion. See [vector primitives](vector-primitives.md).

VEC-1 preserves one whole vector per SSA value. SsaVectorConstructInstruction
has N scalar inputs and one VectorType result; ordinary prefix/binary instructions
produce one numeric vector or bool<N> mask. SsaVectorReductionInstruction has one
mask operand and one scalar bool result. Existing dominance and promotion produce
whole-vector/mask branch and loop block parameters, with no lane Place or source
vector memory. Backend legalization may scalarize later.
See [vector values](vector-values.md).

F32-1 adds `SsaFloatConstant`, retaining immutable `BinaryFloatValue` BINARY32 bits,
canonical `F32Type`, and source provenance after the upstream stage is destroyed.
Dumps print `(f32 0x80000000 : f32)` for negative zero. No decimal reparsing or
host/LLVM floating authority enters SSA. Shared prefix/binary operators enforce
exact f32 operands and bool comparison results; `%` is rejected. Existing
Places, field storage, scalar promotion, block arguments, and instruction results
carry f32 without a second IR architecture. See [f32](../language/f32.md).

INTS-1 retains exact [IntegerType](../language/integers.md) identity and immutable
`AstraIntegerValue` bits in `SsaIntegerConstant`. `int` and `i32` share one type,
canonically displayed as `int`. Constants never reparse source spelling. The
verifier checks both canonical type identity and exact value/type agreement;
signed and unsigned values with identical bits remain distinct. SSA retains
these authorities after upstream objects die. Locals, fields, block parameters,
and loop carries use the existing scalar machinery at every integer width.

OWNBOUND-1 normalizes each owned parameter slot's initial current value to its
incoming `SsaFunctionParameter`. Slot mutation remains scalar SSA, with no alloca
or state flag. Pending arguments capture the old value at evaluation; commit
pushes typed null for each source immediately before the native call.
`SsaOwnedArgument` records exact parameter, captured value, cleanup, source ordinal
and committed null proof. `SsaCallInstruction.owned_result_use` records ACQUIRE
or REARM for a Resource result, and ACQUIRE or FORWARD for an owned object result. `SsaOwnershipReturn` returns the captured
pointer after source disarm and ordinary cleanups. Native signatures still retain
semantic ownership contracts, but the possibility lattice is absent from SSA.
See [ownership boundaries](ownership-boundaries.md).

RESOURCE-1 adds `SsaHandle` descriptors with an exact HandleType token,
independent cleanup authority, provenance, optional copied header and ordinal.
HandleType contains no upstream syntax/symbol/cleanup backlink. Each program
registers its exact descriptors before validating scalar values; verifiers reject
undeclared/impostor types, nominal mismatches and type/cleanup disagreement.
Handles remain ordinary scalar values and promotable Places, with typed null
and same-type block parameters. Existing ownership operations are reused.
See [ADR 0033](../decisions/0033-nominal-resource-handles.md).

Astra SSA makes reaching scalar values explicit after CFG flow validation:

```text
source → syntax → checked model → structured Core → source-preserving CFG
                                                               ↓
                                               reachability / flow validation
                                                               ↓
                                               reachable SSA values, ordered memory and cleanup
                                                               ↓
                                      physical ABI planning / LLVM lowering
```

The [block-argument decision](../decisions/0011-ssa-block-arguments.md) freezes
scalar value promotion. TPTR-1 preserves aliasable storage and ordered memory
operations alongside SSA values. OWN-1 materializes lexical cleanup in CFG before
promotion and preserves it as ordered SSA effects.

## Source structure and ownership

```text
src/ssa/
	ssa-nodes.vala     independent SSA representation and internal errors
	dominance.vala     CFG dominators, immediate dominators, tree, frontiers
	ssa-builder.vala   validated CFG projection, placement, renaming, flattening
	ssa-verifier.vala  independent SSA structural and value-flow verification
	ssa-dump.vala      deterministic verified internal dump
```

| Model | Owned information |
| --- | --- |
| `SsaProgram` | Source provenance; functions in source order |
| `SsaFunction` | Name/name span, declaration span, return type, ordinal, function parameters, reachable blocks, entry |
| `SsaBlock` | Span, dense SSA ordinal, copied source ordinal, ordered block parameters/instructions, one write-once terminator |
| `SsaFunctionParameter` | SSA value identity/type and copied source name/spans |
| `SsaBlockParameter` | SSA value identity/type and copied scalar-local, field, or synthetic temporary origin |
| `SsaCallInstruction` | Non-owning exact SsaFunction, ordered arguments, optional result, provenance |
| `SsaCleanupContract` | Exact cleanup symbol, provenance, ordinal, intrinsic void(void*) semantics |
| `SsaCleanupInstruction` | Pointer operand, exact cleanup contract, provenance, no result |
| `SsaInstructionResult` | SSA value identity, semantic type, instruction provenance |
| `SsaIntegerConstant` | Immutable AstraIntegerValue, exact IntegerType, source provenance |
| `SsaBooleanConstant` | Semantic truth payload, bool type, source span |
| `SsaPrefixInstruction` | Semantic prefix operator, operand, one independently owned result |
| `SsaBinaryInstruction` | Semantic binary operator, left/right operands, one independently owned result |
| `SsaReturn` / `SsaFunctionEnd` | Optional returned value / no value; source provenance; no edges |
| `SsaBranch` | One terminator-owned `SsaEdge` |
| `SsaConditionalBranch` | Bool condition and independent true/false `SsaEdge` objects |
| `SsaEdge` | Weak successor block reference and ordered value arguments |

Function arrays own blocks. GLib.WeakRef edge targets avoid graph ownership cycles;
expired/foreign targets fail verification. Value uses retain the actual SSA
definitions, which have no back reference to instructions, blocks, or functions.
Block parameters contain no predecessor table. `successors()` returns a fresh
snapshot of terminator targets and cannot mutate graph authority.

No SSA node retains CFG, Core, checked nodes, symbols, or syntax. Immutable semantic integer values, semantic types,
operators, source files/spans, and copied debug fields are legitimate shared
authorities. Source ordinals/names provide provenance, not downstream bindings.
Bounded SSA memory Places and Initialize/Load/Store represent aliasable struct
fields. There are no aggregate values, phi instructions, physical alloca,
copy/move, scalar select, or casts. Vector select is an explicit value primitive. SSA is not a register or physical storage model.

## Reachable projection and analysis

`SsaBuilder.build(CfgProgram)` enforces CFG verification and flow validity for
direct API callers, then builds and verifies the entire SSA result. The CLI
checks source flow first so a source error retains its normal diagnostic.

CFG stays unchanged. Blocks without a path from entry are excluded from SSA,
including disconnected post-return statements and full-return-if joins. Blocks
on both explicit edges of `if (true)` and `if (false)` remain included. No
condition is evaluated and no predecessor edge is invented.

`CfgPredecessors.analyze(function)` accepts a verified CFG. It traverses entry
reachability, then scans reachable CFG blocks in ordinal order and derives each
predecessor edge from `terminator.successors()`. Parallel edges remain separate
entries; edges from one conditional follow true then false. `blocks()` and
`predecessors(block)` return fresh arrays. Unreachable blocks have no entries.

`CfgDominance.analyze(function)` computes deterministic snapshots independently
of SSA nodes. It initializes entry's dominators to itself and other reachable
sets to all reachable blocks, then iterates predecessor-set intersection plus
self until stable. Immediate dominators are the strict dominators dominated by
every other strict dominator of the block. An array stores one parent per
reachable block; entry and excluded blocks return null. Tree children follow
block ordinal order.

The frontier calculation directly implements: `y` belongs to `DF(x)` when `x`
dominates a predecessor of `y` but does not strictly dominate `y`. This includes
self-frontiers when graph edges require them. The simple matrix algorithms are
intended for current graph sizes and work for finite reducible/irreducible graphs;
they do not assume acyclicity. Available queries are `dominates(a, b)`,
`dominators(block)`, `immediate_dominator(block)`, `children(block)`, and
`dominance_frontier(block)`. Array answers follow original CFG ordinal order.
Recompute snapshots after editing the input graph.

## Placement and promotion

Each exact promotable CfgPlace (scalar local, non-address-taken field, or temporary) has one
construction-only definition-state object. Reachable
Initialize and Store blocks form its definition-site worklist. Iterated
dominance-frontier placement adds one block parameter per selected Place/block
pair and feeds new merge definitions back into the worklist.

A candidate must be dominated by the Place's initialization block. This is an
availability boundary for branch/loop-local Places, not a liveness test. Sibling
locals called `x` remain independent, and no argument is requested where a
local has no incoming value. A nested join within its initialization's dominated
region still receives a merge. Unused merges within that region remain, as
shown by [dead-merge.ssa](../../tests/ssa/fixtures/dead-merge.ssa). There is no
liveness/pruned SSA or dead block-argument removal.

Parameters are placed by scalar local ordinal, then field projections by
containing local ordinal and recursive field declaration order, then temporary ordinal,
independent of store
order or spelling. Renaming visits the dominator tree with a stack per exact
Place. A block parameter becomes that Place's entry definition. Initialize and
Store lower their RHS and push the resulting value; Load returns the current
top. Each successor edge receives the current values for its ordered block
parameters. Stack depths are restored on leaving the subtree.

Every reachable load must have a definition. Missing definitions throw a
deterministic internal construction error; no zero, false, undef, poison, or
source-order substitute is fabricated. The malformed-CFG regression preserves
one structural initialization but makes it load itself, proving this check.

Eligible scalar Places disappear because their storage cannot be aliased and any
OWN-1 cleanup obligations have already become explicit CFG effects. Erasing
Initialize versus Store preserves those effects; owner pointers use ordinary SSA
values. Address-taken fields retain explicit memory. Future transfers and native
destructible values must establish their own promotion rules. Core/CFG storage
semantics remain inspectable.

## Deterministic values and computation

Functions retain source order. Reachable blocks are projected in original CFG
ordinal order and receive dense SSA ordinals from zero. `source_ordinal` keeps
the copied original ordinal for debugging even when projection leaves gaps.

One increasing value counter per function numbers:

1. Function parameters in declaration order.
2. Block parameters in projected block order, then scalar-local, field-projection, and temporary order.
3. Instruction results in dominator-tree preorder, with children in CFG block
   ordinal order and instructions in computation order.

Constants stay inline without IDs. Hash tables are identity lookup machinery;
their iteration order and object addresses never affect dumps. Instruction
numbers need not increase in textual block-array order because dominator-tree
order can differ. Each operation constructs a fresh result. The verifier checks
both object identity and ordinal uniqueness within a function.

Nested expressions flatten operand-first, visiting binary left before right:

```text
(%2 : int = binary + %0 (integer 2 : int))
(%3 : int = prefix - %2)
(%4 : int = binary * %3 %1)
(%5 : int = binary % %4 (integer 3 : int))
(return %5)
```

This [arithmetic golden](../../tests/ssa/fixtures/arithmetic.ssa) preserves
association and every operation. The [comparison golden](../../tests/ssa/fixtures/comparison.ssa)
produces bool for `<`, compares it with `true`, and negates the equality result.
CALL-1 freezes left-to-right operand and argument evaluation as observable
language semantics. CFG sequences calls explicitly; SSA preserves their order.
Repeated operations, unused instructions, `x + 0`, constant branches, and unused merge parameters
are retained. There is no general optimization or integer conversion.

## Mutable joins

The [choose golden](../../tests/ssa/fixtures/choose.ssa) contains:

```text
(block #0
	(conditional-branch %0
		(true #1 ())
		(false #2 ())
	)
)
(block #1
	(branch #3 (%1))
)
(block #2
	(branch #3 (%2))
)
(block #3
	(arguments
		(%3 "x" : int)
	)
	(return %3)
)
```

`%0`, `%1`, `%2` are function parameters `condition`, `a`, `b`. Local storage for
`x` has disappeared; `%3` is the join's scalar definition. In
[maybe](../../tests/ssa/fixtures/maybe.ssa), the true arm supplies `1` and the
entry's false edge supplies old `0`. Their argument counts differ from the
entry's true edge, which targets a block without parameters.

[Multiple locals](../../tests/ssa/fixtures/multiple.ssa) declare `x` then `y`, so
the join declares `%3` then `%4`; the true edge supplies `(a, b)` and false edge
`(b, a)`. [Nested joins](../../tests/ssa/fixtures/nested.ssa) use the same frontier
and renaming machinery: inner join `#6` supplies its block parameter to outer
join `#3`. [Bool locals](../../tests/ssa/fixtures/boolean-place.ssa) follow the
same promotion rules without physical bool encoding.

## Verification, CLI, and regressions

`SsaVerifier` establishes all owners/definitions before uses. It checks entry
membership, unique function/block/value identities and ordinals, complete and
reachable blocks, deterministic block-parameter ordering, canonical non-void
value types, supported operations, same-function edge targets, exact edge
counts/types, bool conditions, and matching return shape/type. Entry has no
block parameters requiring an unsupplied incoming argument.

Function parameters dominate every block. Block parameters are available at
entry. Instruction results must precede a same-block use and dominate uses in
other blocks. The verifier independently checks domination by searching paths
with a proposed defining block excluded. This implementation needs no CFG
objects or CFG analysis code. Its node inventory excludes promoted storage.

`--dump-ssa FILE` runs the pipeline through SSA, verifies, and prints a single
deterministic dump. `--check FILE` includes native signature planning,
structural/call compatibility validation, and LLVM-1 lowering/verifier silently.
Success exits 0; source/flow errors retain deterministic diagnostics and exit 1
without partial output; incorrect arity exits 2. Internal construction or
verification defects use `SsaError` and the existing `astrac: internal ...`
failure path. The dump is an internal debugging format using tabs and LF, not a
serialization contract. Previous dump modes stop at their original stages.

`tests/ssa/` includes CFG-analysis queries over fixed diamonds/nested joins and
512 synthetic finite graphs, promotion/value/projection tests, malformed SSA
tests, and CLI goldens. The lifetime test releases syntax, checked nodes,
symbols, Core, CFG, and the type-universe container before verifying/dumping SSA
and inspecting INT_MAX with a 1,003-digit leading-zero spelling, types, spans,
IDs, and edges.
Releasing SSA releases its retained source/type authorities.

`astra-ssa-standalone-tests` compiles only SSA nodes/verifier/dumper and shared
source/type/operator authorities. No syntax, checked nodes, Core, CFG, SSA
builder, LLVM bindings, or backend inputs are available. All three new test
executables join the `ldd`/`readelf`/`nm` firewall matrix. The LLVM smoke remains
its negative control. No dependencies are added; owned aggregate boundaries, liveness,
and optimization remain future work. NABI-1 adds separate
physical signature planning, without changing this standalone SSA boundary.

## Cyclic promotion in LOOP-1

LOOP-1 qualifies these existing analyses on [source-generated cycles](cyclic-control-flow.md).
For count, header b1 has predecessors b0/b2 and both b1 and b2 have frontier
{b1}. Iterated frontier placement creates one ordinary header block parameter.
Dominator-tree renaming supplies initial zero from b0 and the body increment
from b2; the header condition, body, and exit consume the merged value.
Multiple parameters follow local ordinals; bool follows the same rules.
A body-local initialization cannot dominate the outer header and therefore
requests no fictitious header value. Nested loops propagate outer total through
both headers while keeping inner storage within its initialization region.
No source-while case, liveness pass, or fabricated undef/poison is added.

## Direct calls in CALL-1

All SsaFunctions and their parameter/block identities are created before any
body is renamed. A temporary CfgFunction-to-SsaFunction map translates callees
exactly. GLib WeakRef call targets preserve non-owning program membership;
recursive bodies never own their functions.

SsaCallInstruction preserves CFG instruction order, lowering remaining argument
computations before each call. A temporary CfgCallResultValue-to-SSA-result map
resolves every use to its exact definition. Non-void calls own one result even
when unused, provided its result contract is unmanaged. Void calls own none and consume no value ID. SsaInstruction.result
is consequently optional, while prefix/binary computations still require one.
The dumper never sorts instructions by result ID.

The verifier checks program-owned callees, exact signatures, result shape/type,
unique definitions, and dominance for call arguments and result uses. Calls
remain conservatively effectful; no CSE, DCE, call motion, or inlining exists.
Non-address-taken scalar locals and struct fields remain promotable because
calls cannot alias their storage. Borrowed scalar locals/struct fields remain explicit memory,
so loads after calls observe mutations without invalidating promoted definitions. Call results pass as edge arguments into existing block-parameter
joins, as shown by [choose-call](../../tests/call/fixtures/choose-call.ssa).

Unreachable CFG calls are omitted only through the existing reachable
projection. Recursive lifetime tests destroy CFG before verifying and dumping
SSA. See [direct-call IR](direct-calls.md); semantic call signatures do not
choose any physical/native/C ABI or LLVM form.

## Concrete integer authority through INTS-1

`SsaIntegerConstant.value` retains immutable AstraIntegerValue directly from CFG;
SSA nodes retain no CfgIntegerValue identity. Canonical dumps show signed or unsigned
mathematical values, including every signed MIN and unsigned MAX. SourceSpan separately preserves `00042` or
`-((2147483648))`. Verifiers rely on valid value construction and still enforce
canonical non-void IntegerType. They never parse digits or inspect source text for
numeric meaning. Bool remains a symbolic true/false constant.

[Scalar semantics](../language/scalars.md) fixes wrapping arithmetic, signed
comparisons, truncating division/remainder, zero-divisor runtime traps, and
INT_MIN/-1. All corresponding SSA operations remain explicit. The reference
utility is not used to fold SSA, and there is no physical integer/LLVM object.

When CFG materializes a potentially trapping tree before a later call with
`CfgEvaluateInstruction`, SSA lowers that tree at its instruction position and
maps CfgEvaluatedValue to the result. No copy instruction, new SSA kind, or Place
is needed. This fixes the newly observable `a / b + effect()` ordering defect;
SSA retains division before call, then addition. Malformed CFG evaluations are
rejected at the input boundary, and lifetime tests destroy CFG before inspecting
the independent SSA computation. Promotion, dominance, and edges are unchanged.

## Native physical signature sidecar in NABI-1

Verified SsaProgram feeds NativeAbiBuilder. It first creates all independent
NativeFunction identities and signatures, using one exact temporary
SsaFunction → NativeFunction map. It then verifies native structure and checks
every SSA direct call against the mapped physical contract. Function order and
parameter order remain source order. Semantic int maps centrally to I32, bool
to logical B1, and void result to no channel, with no hidden parameters/results.

NativeAbiProgram is signature-only. SSA remains the authority for blocks,
instructions, values, calls, control flow, block arguments, and effect order.
The sidecar retains no SSA or SemanticType objects; lifetime tests destroy both
before inspecting/verifying/dumping physical signatures and provenance. Calls
remain SSA instructions, and no translated call graph is retained in NABI.
`--dump-ssa` output is unchanged; `--dump-nabi` inspects this new boundary.

Native-internal, unstable signatures freeze no linker names, machine placement,
C ABI, bool memory layout, or LLVM types. LLVM-1 body lowering consumes SSA and
the sidecar together while preserving signed wrapping, comparisons, explicit
zero-divisor traps, exceptional signed-division results, and left-to-right
effect order. See [native scalar v0](../abi/native-scalar-v0.md).

## Physical block arguments in LLVM-1

LLVM remains a downstream physical backend. NativeSignature supplies function
channels (i32/i1/void); SSA values pass through NativeTypeMapper and the same
central LLVM type mapper. Every function is declared with internal fastcc
before bodies. Function and value maps use exact SSA identity, never printed IDs.

Every reachable SSA block gets a primary LLVM block. All ordered block parameters
get corresponding phis before instruction lowering. An iterative DFS visits
dominators before uses even when block array order differs; within a block,
stored instruction order is preserved. Returns and branches use the block's
current physical end, which may be a guarded division/remainder continuation.
Phi incoming values use that actual predecessor. Parallel true/false edges to
one target get separate synthetic edge blocks carrying distinguishable arguments.

These LLVM phis/helper blocks do not change Astra's block-argument architecture,
CFG, or SSA. Int/bool joins become i32/i1 phis, including multiple parameters and
nested joins. Wrapping arithmetic, signed comparisons, explicit traps, and
INT_MIN/-1 special cases remain correct without optimization. The completed
LLVM artifact retains no SSA/NABI graph. Standalone SSA tests remain LLVM-free;
`astrac` now links LLVM for `--dump-llvm` and `--check`. See
[LLVM scalar v0](../backend/llvm-scalar-v0.md).

## Additional control edges in LOOPCTRL-1

Break and continue reach SSA only as ordinary CFG branches. Reachability,
predecessors, dominance, frontiers, placement, and renaming require no change.
Continue diamonds contribute header frontier sites; break diamonds contribute
exit frontier sites. Each outgoing edge captures the current definition stack,
including stores before a transfer and excluding stores after it.

The continue-merge fixture has header parameters `(i, x)` with incoming values
`(0, 0)`, `(next_i, 10)`, and `(next_i, 20)`. The break-merge fixture has an exit
parameter `x` receiving header-carried `x` and break-path `1`. The zero-iteration
case transports `5` from header-false and `10` from break. Multiple-sites tests
exercise four header predecessors and three exit predecessors, including exact
old/new value arguments and nested target graphs.

Initialization-dominated availability still excludes body-local `temp` from
headers/exits it cannot dominate. Available dead merges remain valid: there is
no fabricated undef/poison, pruned SSA, loop-control SSA operation, or optimizer.
Standalone branch-only shapes and detached-edge probes prove independence from
Core/CFG and cyclic reclamation. See [ADR 0018](../decisions/0018-loop-control-targets.md).

## Expression-result promotion

Short-circuit temporaries use exactly the existing definitions, iterated
frontiers, initialization-dominance restriction, and renaming. A construction-only
map relates each block parameter to its exact CfgPlace; copied debug metadata is
not identity. Source locals precede synthetic temporary parameters deterministically.
SsaBlockParameter.temporary records TEMPORARY/#N and no source-local ordinal/name.

The default bool and conditional RHS store meet at an ordinary bool block
parameter. No Place, load, store, initialization, or logical instruction survives.
A condition's dedicated evaluation entry keeps its initialization outside the
while header's incoming domain, so real locals remain carried there and the
expression result merges only within its valid region. No liveness pruning or
undef/poison is needed. See [expression control flow](expression-control-flow.md).

## C imports in CABI-1

SsaProgram owns native functions and separate SsaCFunction declarations.
Each import has exact independent identity, source/debug and external names,
ForeignAbi.C, semantic parameter/result types, a declaration ordinal, and
provenance; it has no body or blocks. All declarations precede native body
translation using an exact temporary CfgCFunction → SsaCFunction map.
No source-name lookup or upstream graph survives construction.

SsaCCallInstruction expose the foreign target domain explicitly and use
weak references to the program-owned import. Verifiers require same-program
target identity, ABI C, unique declarations, int/void* parameters, int/void*/void results,
exact arguments, and the correct result shape. Foreign bool is invalid.
Native call nodes remain distinct even with identical signatures and ordinals.
All C calls are conservatively effectful; arguments preserve Astra ordering.

C calls are ordered non-terminator instructions and add no successor edges. Int results are ordinary typed call results; void has none. An unused int result retains its call. Existing short-circuit paths, loop targets, and promotion are unchanged.

Completed imports/calls remain verifiable and dumpable after the upstream stage
dies. NABI contains only native signatures; CABI separately plans SSA imports.
See [ADR 0020](../decisions/0020-c-scalar-imports.md).

## C export metadata in CEXPORT-1

SsaProgram separately owns SsaCExport attachments with ABI C, source-order
export ordinal, exact external symbol, provenance, and a weak SsaFunction target.
The builder creates all native functions first and translates the exact CfgFunction
target through its temporary identity map. No name re-resolution or upstream
object retention occurs. The previous stage's metadata and native functions may
die after construction.

The verifier checks a live native target in the same program, int parameters,
int/void*/void result, ABI/ordinal, and nonempty unique external symbols across imports
and exports. The dump labels attachments `c-export` apart from ordinary bodies.
There is no export wrapper body, C convention, special native call, or wrapper
control-flow graph here. Native calls and recursion remain unchanged. NABI
plans the ordinary native function; CABI independently plans its wrapper, and
only LLVM generates that physical adapter. See
[ADR 0021](../decisions/0021-c-scalar-exports.md).

## PTR-1 promotion and block arguments

SsaNullPointerConstant is a payload-free semantic pointer constant. Function
parameters, instruction results, and block parameters carry their canonical raw
pointer type using existing SSA definitions; there is no pointer register class.
Pointer local Places promote completely; their pointee storage is separate. choose_ptr passes a/b to one
pointer join argument; maybe_ptr passes p/null; select_ptr carries a pointer at
the loop header. No Place/Load/Store survives these cases. Standalone verification
checks canonical type/pointee identity and null types without CFG or width.

SSA retains neither CFG objects nor foreign pointees. LLVM realizes its pointer
block parameters as phi ptr with exact physical predecessors, including parallel
edge splitting and predecessors after trap-capable division. Calls still carry
exact native or C target identity. Typed native parameters may alias, and their
field memory operations stay ordered. Future escaping references, ref/out,
captures, or native aggregate ownership must reopen promotion eligibility. OWN-1 foreign
cleanup is explicit before pointer promotion. See
[native pointer v1](../abi/native-pointer-v1.md).

## Struct field scalarization

Non-address-taken scalar/vector leaf FieldPlaces use the same exact-Place definition sites, iterated dominance
frontiers, initialization-dominated availability, and renaming stacks. Aggregate
struct bases are excluded from promotion. Addressable bases translate instead
to distinct SsaAddressableLocal storage objects, never values. A single mutated
field gets a scalar block argument; two mutated fields get independent arguments.
The same rule handles loop-carried int/bool/pointer fields and body-local storage
without undef/poison or aggregate-specific merge logic.

SsaPromotionOrigin.FIELD carries only copied name/span, local ordinal, and recursive
field-ordinal path on ordinary leaf SsaBlockParameters. Fully scalarized structs retain
no type, descriptor, or Place unless separately required by typed pointers.
Debug names never determine SSA identity. Existing no-struct numbering and
dumps remain unchanged. See [field Places](field-places.md) for eligibility.

## TPTR-1 and DPTR-1 explicit mutable memory

SsaProgram owns layout-free SsaStruct/SsaStructField descriptors where typed
pointers or addressability need them. SsaFunction owns SsaAddressableLocal
objects with exact scalar type or struct descriptor, deterministic storage
ordinals, and copied local provenance. SsaLocalMemoryPlace represents a direct
address-taken local, including a struct storage base. SsaDereferencePlace owns one typed pointer value,
exact supported pointee type, immutable lexical provenance, and null-trap
contract. These join field projections under SsaMemoryPlace.
SsaDirectFieldPlace binds exact storage/field; SsaIndirectFieldPlace binds exact
pointer SSA value/field. SsaFieldPlace recursively projects another memory Place.
Storage and memory Places are not SSA values.

SsaAddressOfInstruction produces an ordinary typed pointer value.
SsaInitializeInstruction and SsaStoreInstruction have no result;
SsaLoadInstruction produces the exact scalar/vector leaf value. Instruction array
order preserves memory, calls, and traps; written initializer order remains
visible. No whole aggregate value, alias analysis, load forwarding, or optimizer
is introduced. Pointer locals still promote.

The independent verifier checks descriptor/storage ownership, exact projections,
type/pointee identity, initialization and SSA-use dominance, and promotion
origins that would overlap addressable storage. Results have no instruction
backlinks and fields have weak descriptor backlinks. CFG can die before
standalone verification/dumping, and SSA can die after LLVM lowering.
See [addressable storage](addressable-storage.md) and
[dereference Places](dereference-places.md) for the full contract. Address-taken
scalar locals never compete with a promoted SSA value; even pre-borrow direct
reads use memory. Pointer values themselves remain scalar-promotable.

## OWN-1 cleanup effects

CFG has materialized all lexical exits before promotion. Owner pointer Initialize
and Load disappear through ordinary scalar promotion; SsaCleanupInstruction
consumes the exact pointer SSA value and retains a separate SsaCleanupContract.
It has no result and remains ordered relative to memory, calls, trap-capable
computations, and other cleanup instructions. No SsaOwnedPlace, owner-state phi,
LexicalRegion, or moved-state solver is introduced. Standalone verification checks
contract authority, void* operands, and unique instruction slots. See
[cleanup IR](cleanup.md) and [ownership](../language/ownership.md).

## MOVE-1 pointer definitions

Ownership flow has converged and source uses have been validated before promotion.
CfgOwnershipTransferInstruction contributes a source definition site and destination
initialization/definition site. Renaming obtains current(source), defines destination
with that exact old SsaValue and defines source with a typed SsaNullPointerConstant
carrying transfer provenance. No SsaOwnershipTransferInstruction persists.

Moved-source cleanup consumes null. Conditional-source cleanup consumes an ordinary
void* block parameter, lowered to `phi ptr [null, moved], [resource, owning]`.
No ownership-state bool, cleanup-contract phi, runtime call or LLVM ownership lattice
is introduced. Source MAYBE_OWNED state is distinct from physical pointer nullness;
a producer's null pointer can be semantically OWNED. Cleanups remain ordered and
present even when their operands are definitely null. CfgPredecessors is shared
from the CFG layer; dominance/promotion rules remain otherwise unchanged.

## Borrow normalization (OBORROW-1)

After CFG ownership validation, SsaBuilder maps each owner borrow event to the
current reaching pointer definition. The call receives that existing SsaValue;
no instruction, source-null definition, destination definition, storage, cleanup
change, token, counter or new ownership state is introduced. A subsequent move
uses that same pointer and performs MOVE-1's ordinary source-null normalization.
Standalone SSA tests construct only a producer, ordinary pointer call and cleanup.

SsaFunctionParameter retains the normalized PointerParameterContract and spans;
C imports use independent descriptors of that same class. SsaVerifier enforces
obvious native parameter noescape uses but owns no responsibility lattice.
CABI copies behavioral contracts while NABI maps unchanged semantic pointer
types. LLVM needs only ptr arguments and its existing calling conventions.

## RELEASE-1 cleanup and current pointer

CfgOwnershipReleaseInstruction supplies an owner definition site after ownership
validation. At rename, SsaCleanupInstruction consumes current(owner), retains the
exact mapped contract and explicit release span, then the owner's definition
stack receives SsaNullPointerConstant. The original lexical cleanup consumes this
current pointer; it is null after definite release and a normal pointer block
parameter after conditional release. No source can read the null definition.

Release does not force owner memory storage. No SSA release result, ownership
state value, runtime bool, contract phi or persistent release class is added.
The CFG release event and ownership maps may die after construction. LLVM reuses
its existing cleanup guard and actual physical continuation. See
[release IR](ownership-release.md).

## REARM-1 pointer definitions

After CFG ownership validation, rearm adds a definition site for its existing
owner Place. Rename sets its current definition to the producer call's result.
No persistent SSA ownership operation remains and no storage becomes addressable.
A construction check follows the previous definition's pointer-phi graph,
including cycles, and verifies null terminal inputs. This proves the physical
consequence of definite disarmament, without using nullness to authorize rearm.

Single-arm rearm merges producer/null pointers; both-arm rearm merges two producer
results. Existing lexical cleanup consumes the current pointer and its exact
stable contract. SSA retains no CFG flow snapshot or physical-proof worklist.
LLVM needs only ordinary calls, pointer phis and cleanup guards; there is no armed
flag, contract dispatch value or cleanup-order tag. See [rearm IR](ownership-rearm.md).

## Explicit generic capabilities

Constrained generic functions reach SSA only as concrete Core/CFG instances.
Comparison results use existing bool control flow; arithmetic locals and loops
use existing exact scalar block parameters. No capability type, node, evidence
operand or phi<T> exists in SSA. See [capability IR](generic-capabilities.md).

## Recursive struct fields

STRUCT-AGG-1 promotes nested leaf Places through exact CFG identity and ordinary
SSA definitions. Copied ordinal paths are debug provenance only. Struct subobjects
never become SSA Values. Memory-backed SsaFieldPlace recursively projects existing
storage; sibling identity compares exact bases and fields. Vector leaves are whole
VectorValues and f64 remains exact. See [recursive Places](recursive-field-places.md).

## Generic native structs

GEN-STRUCT-1 arrives as ordinary concrete aggregate storage. Box<int>, Box<f64>, Box<i16<8>> and nested Bundle<f64> follow existing leaf promotion and selective root addressability. No aggregate SSA Value or generic field/category is introduced. Addressed instances retain ordinary transitive concrete descriptors and recursive memory Places. See [generic aggregate IR](generic-structs.md).

## Generic ownership

SSA contains no generic owner. Resource and Class instances use existing owned call-result, transfer, cleanup and return forms. Direct Resource producer forwarding is verified against the exact returned pointer and cleanup contract. No type parameter, ownership dictionary or additional SSA value category is introduced. See [generic ownership IR](generic-ownership.md).

## Struct copy leaves

[Whole copies](struct-copy.md) reach SSA as existing leaf reads and writes.
Eligible scalar/vector fields promote normally across branches and loops; mixed
and memory-backed copies retain all source loads before destination stores.
SsaValidatePlaceInstruction performs ordered address/null validation, with no
result Value. There is no StructCopy operation, aggregate Value or aggregate phi
in SSA. Vector fields remain single Values; copy adds no addressability penalty.

## Multi-source composition

SOURCES-1 keeps one source-independent SSA program. Cross-file calls use the same
exact function, parameter, result, memory and ownership identities as local calls.
There is no source-file SSA node. Predecessor destruction and independent verification
remain mandatory. NABI/CABI planning and LLVM lowering see the complete universe
without filename-based resolution or per-file channels.
