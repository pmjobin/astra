# Explicit CFG

[NUM-CONV-1](numeric-conversions.md) retains exact scalar integer↔floating
conversion kind, types, signedness and policy. Core keeps the explicit operation;
CFG and SSA add an ordered, destination-specific numeric guard before
floating→integer conversion. SSA validates the proof producer and dominance.
Integer→floating needs no trap guard. Suffixed literals arrive as exact constants;
no downstream stage recovers suffixes or conversion types from syntax.

[BUFFER-1](owned-runtime-arrays.md) adds checked target-lowerable allocation,
complete PTR/I32 owner groups, bounded slice borrows and static buffer cleanup.
Existing Slice bounds, ownership flow and source-ordered capture/commit machinery
remain authoritative. Concrete Resource/buffer rearm accepts OWNED → OWNED,
with incoming production before old cleanup. Mixed field epilogues remain exact
reverse declaration order. CFG independently rejects invalid groups and stale
field borrows after Core is destroyed.

OWN-FIELD-1 expands [owned Resource field transfers](owned-resource-fields.md)
into receiver validation, incoming production, concrete Resource capture/source
consumption, old-handle cleanup and store. Initialization omits old cleanup.
Normal destructor exits append reverse-order cleanup of current field contents
after the user body. Capture/store and destructor order are independently checked;
no trap edge unwinds and no generic owner field or persistent field state exists.

[Native struct boundaries](struct-values.md) flatten to concrete leaf parameters,
argument-position snapshots and leaf returns. StructValueShape/StructBoundaryGroup
retain exact nominal grouping. One CfgStructCallResults owns N ordinary results;
CfgStructResultConsume records a bounded complete consumer without producing a
Value. Parameters initialize independent local field Places at entry, and
CfgStructReturn captures all result leaves before cleanup. No aggregate CFG Value
or mandatory memory is introduced.

GEN-1 [monomorphization](generics.md) finishes before CFG construction.
CfgBuilder invokes CoreVerifier.verify_concrete, rejecting generic definitions,
unresolved generic calls and type parameters. Instances use ordinary concrete
Places, branches, loops, ownership and cleanup. No generic CFG nodes or types exist.

[Property accessors](properties.md) reuse ordinary callable CFG bodies and
CfgCallInstruction. CfgProperty owns exact getter/setter identities. The shared
call routine captures and validates the receiver before building the setter's
single RHS argument. Getter calls produce ordinary call-result values. Both
accessors remain effectful, and no property Place or backing storage is added.

F64-1 generalizes floating constants to `CfgFloatValue` with exact BinaryFloatFormat,
bits, canonical FloatingType and source provenance. F64 is one ordinary scalar
CFG value through arithmetic, comparisons, branches, loops, Places and calls.
Explicit FLOAT_WIDEN/FLOAT_NARROW nodes retain exact source/destination types and
rounding kind after upstream destruction; ICONV remains separate. Verifiers reject
cross-format operands, wrong constant formats and unsupported conversions.
Existing F32 dump bytes remain stable. See [floating values](floating-values.md).

[Owned object results](object-results.md) add a function-owned result-storage input and direct result-constructor calls. Shared ownership return capture evaluates fresh/null/forwarded pointers or commits a parameter move before lexical cleanup. The result is excluded from callee cleanup. Caller acquisition cleans the returned pointer, including null no-op, without activating candidate cleanup.

OBJ-OWN-1 uses the existing OwnershipFlow, acquisition, owned-borrow capture,
pending owned argument and call-commit nodes for object responsibilities. The
ClassType owner Place carries exact class cleanup and optional local ObjectStorage.
Semantic move precedes later arguments; physical disarm waits until the same
OWNBOUND commit. Conditional owners use the existing possibility-state joins.
One lexical cleanup planner handles fixed objects, transferable objects and
Resources. See [object ownership](object-ownership.md) for exact temporary-view
lifetime checks and the fixed/transferable verifier distinction.

OBJ-BOUND-1 retains one exact ClassType CfgParameter and BORROWED_NOESCAPE
contract. CfgParameterValue can be copied, evaluated and forwarded as one operand.
An explicit evaluation captures its source-order argument position before later
Resource capture/effects and the existing delayed transfer commit. No object
commit or cleanup action is added. Existing CfgObjectValidateValue runs only on
field/method use, before field RHS or method arguments; passing null alone does
not validate it. CFG remains complete after Core release.
See [object values](object-values.md) and [ADR 0051](../decisions/0051-borrowed-object-boundaries.md).

OBJ-LIFE-1 lowers CoreConstructor/CoreDestructor through ordinary function CFGs.
Constructor function-end denotes successful fallthrough. Explicit lifecycle calls
retain exact storage receiver/target and void result; reference publication follows
constructor success. The existing CleanupScope list holds Resource and ObjectStorage
actions in one reverse lexical order on fallthrough, return, break, continue and
backedge. Return evaluation precedes cleanup. Separate validation fixed points
check field initialization and explicit lifecycle transitions; they never insert
cleanup or produce runtime flags. Traps have no destructor unwind edge. See
[lifecycle IR](object-lifecycle.md).

OBJ-1 retains CfgClass and separate CfgObjectStorage identities. Construction
lowers source-written initializers to exact object field initialization Places,
then publishes one ClassType CfgObjectReferenceValue and initializes the reference
local. Reference copies, rebinding and equality use ordinary value flow.
CfgObjectValidateValue is captured in an explicit evaluation instruction before
field RHS effects or explicit method arguments. Its ClassType result feeds an
indirect field Place; its ReceiverType result feeds the same CfgMethod call and
owned-transfer machinery used by structs. Initialization dominance and guard
contracts are verified. See [object values](object-values.md) and
[storage](object-storage.md); backing storage never joins as an aggregate value.

METHOD-1 adds [CfgMethod and CfgReceiver](methods.md), preserving exact member
and declaring-struct identity while reusing ordinary function blocks and flow.
The receiver is an immutable implicit input outside explicit parameter arrays.
CfgCallInstruction retains a method target and separate receiver: direct-local
addresses are captured before explicit arguments; `this` forwards the same input.
Owned argument captures and final OwnedCallTransferCommit keep their existing
order. Receiver fields use ordinary indirect field Places and memory effects.
Method calls remain effectful direct calls, including recursion, branches, loops
and short circuit. No new ownership flow or receiver storage class exists.

SLICE-1 retains [one SliceType value](slice-values.md) per captured construction.
Start and count are evaluated in order before range validation. A
[CfgSliceElementPlace](slice-places.md) captures its view before index evaluation;
CfgSliceBoundsCheck yields validated-index authority for that exact view before
an assignment RHS. Slice locals participate in ordinary value flow; arrays stay
explicit storage. Verifiers retain initialization and guard dominance.

ARRAY-1 retains [explicit indexed array storage](array-places.md).
CfgArrayInitialize contains N ordered captured element values for one
non-promotable CfgLocalPlace. CfgArrayBoundsCheck is an ordered potentially
trapping evaluation whose integer result carries validated-index authority for
exact array storage. CfgArrayElementPlace consumes that result (or a valid
constant), retaining type, length and provenance. The check precedes RHS lowering;
ordinary Load/Store and existing expression-region control flow remain intact.

VEC-MEM-1 carries addressable numeric vectors in CfgLocalPlace and uses the same
CfgDereferencePlace and ordinary load/store operations. Each read/store handles
one whole vector, with the existing null-trap contract. Pointer base capture
precedes RHS evaluation; short-circuit successors and backend physical-block
authority are unchanged. See [vector memory](vector-memory.md).

BIT-1: Eager bool uses normal binary value traversal without short-circuit branches. CfgIntegerShiftInstruction captures value then count and remains one ordered potentially trapping operation, including before owned-transfer commits.
See [bitwise/shift IR](bitwise-shifts.md) for verifier, lifetime, evaluation
and backend guard/normalization rules. NABI/CABI/VAPI remain unchanged.

VEC-DOT-1 adds `CfgVectorDotInstruction`/`CfgVectorDotValue`. CFG captures
accumulator (MAC only), a, then b in source order and retains one pure dot/MAC
primitive with one scalar result. There is no lane expansion or reduction loop.
Scalar results merge and recur through ordinary promotion. Pending owned
transfers retain the existing evaluation/commit boundary. See
[dot/MAC IR](vector-dot.md).

VEC-DSP-1 adds `CfgDspInstruction`/`CfgDspValue`: operands are captured
left to right before one pure operation with one evaluated result. Captures retain
traps, reads and nested ownership-transfer ordering; saturation creates no Astra
CFG branches. DSP results use ordinary whole-vector local promotion and joins.
See [DSP IR](vector-dsp.md).

VEC-LANE-1 adds five CfgVector*Instruction/CfgVector*Value pairs for splat,
extract, insert, shuffle and select. Existing ordered operand capture preserves
reads, traps and calls before subsequent operands. Select evaluates mask, true
vector and false vector and emits one value instruction with no branch or join.
No lane Place or vector memory is introduced. See [vector primitives](vector-primitives.md).

VEC-1 adds CfgVectorConstructInstruction and CfgVectorReductionInstruction as
specializations of the existing ordered evaluation/result authority. Their
CfgVectorConstructValue/CfgVectorReductionValue operands retain exact vector
identity; each instruction defines one result. Construction captures lanes in
source order before the next lane's effects. Vector locals remain whole Places;
branch/loop lowering and ownership flow retain their existing authorities.
See [vector values](vector-values.md).

F32-1 adds `CfgFloatValue`, retaining immutable `BinaryFloatValue` BINARY32 bits,
canonical `F32Type`, and source provenance after the upstream stage is destroyed.
Dumps print `(f32 0x80000000 : f32)` for negative zero. No decimal reparsing or
host/LLVM floating authority enters CFG. Shared prefix/binary operators enforce
exact f32 operands and bool comparison results; `%` is rejected. Existing
Places, field storage, scalar promotion, block arguments, and instruction results
carry f32 without a second IR architecture. See [f32](../language/f32.md).

INTS-1 retains exact [IntegerType](../language/integers.md) identity and immutable
`AstraIntegerValue` bits in `CfgIntegerValue`. `int` and `i32` share one type,
canonically displayed as `int`. Constants never reparse source spelling. The
verifier checks both canonical type identity and exact value/type agreement;
signed and unsigned values with identical bits remain distinct. CFG retains
these authorities after upstream objects die. Locals, fields, block parameters,
and loop carries use the existing scalar machinery at every integer width.

OWNBOUND-1 preserves native ownership signatures and seeds owned parameter slots
with `CfgAcquireParameter` at entry. `CfgOwnedArgumentCapture` defines an exact
`CfgPendingOwnedArgument` at its left-to-right expression position; ownership flow
moves its source immediately. `CfgOwnedCallTransferCommit` retains the transfer
list and associated call and must immediately precede it after all argument
values have evaluated. Verification rejects duplicate sources, mismatched
parameters, missing captures/commits, unevaluated argument trees and cleanup or
exit between capture and commit. `CfgOwnershipReturnInstruction` captures the
result and moves its source before cleanup; `CfgOwnershipReturn` exits with that
captured responsibility. See [ownership boundaries](ownership-boundaries.md).

RESOURCE-1 adds `CfgHandle` descriptors with an exact HandleType token,
independent cleanup authority, provenance, optional copied header and ordinal.
HandleType contains no upstream syntax/symbol/cleanup backlink. Each program
registers its exact descriptors before validating scalar values; verifiers reject
undeclared/impostor types, nominal mismatches and type/cleanup disagreement.
Handles remain ordinary scalar values and promotable Places, with typed null
and same-type block parameters. Existing ownership operations are reused.
See [ADR 0033](../decisions/0033-nominal-resource-handles.md).

CFG gives Astra explicit execution boundaries after typed semantic computation:

```text
source → syntax → checked semantic model → verified Core → verified CFG
                                                              ↓
                                                    reachability / flow checks
                                                              ↓
                                               reachable scalar SSA / block arguments
                                                              ↓
                                                 future physical lowering / LLVM
```

Core preserves structured source computation. CFG identifies which blocks can
execute and how functions complete. The decision is frozen in
[ADR 0008](../decisions/0008-explicit-cfg.md). Neither representation chooses
physical int/bool layout or an ABI. [Scalar semantics](../language/scalars.md)
now fixes int's signed 32-bit range and wrapping arithmetic independently.
PLACE-1 adds [local Places, loads, and ordered storage instructions](place-storage.md)
under [ADR 0009](../decisions/0009-place-storage.md). BRANCH-1 adds
[conditional control flow](conditional-control-flow.md) under
[ADR 0010](../decisions/0010-conditional-control-flow.md).
ASTRA-SSA-1 consumes validated reachable CFG through
[scalar promotion](ssa.md), without changing this source-preserving graph.

## Inventory and identity

All implementation classes are in `Astra.Cfg`:

```text
src/cfg/
	cfg-nodes.vala     CFG identities, Places, values, instructions, terminators
	cfg-builder.vala   verified Core → CFG conversion
	cfg-verifier.vala  structural compiler invariants
	reachability.vala  entry/successor traversal and separate analysis result
	flow-checker.vala  function-completion source validation and result
	cfg-dump.vala      deterministic verified internal dump
```

The CFG-specific builder/verifier basenames avoid generated-C collisions with
the existing Core sources. No additional source directories anticipate later
compiler stages.

| Class | Owned information |
| --- | --- |
| `CfgProgram` | Source span and functions in deterministic source order |
| `CfgFunction` | Name, name/declaration spans, semantic return type, program ordinal, ordered parameters/locals/temporaries/blocks, entry block |
| `CfgParameter` | Name, name/declaration spans, semantic type, function-local ordinal |
| `CfgLocalPlace : CfgPlace` | Name, name/declaration spans, semantic type, function-local ordinal; storage authority |
| `CfgBlock` | Source span, function-local ordinal, ordered instructions followed by exactly one terminator |
| `CfgCallInstruction` | Non-owning exact CfgFunction, ordered arguments, optional call result, provenance |
| `CfgCallResultValue : CfgValue` | Exact result identity, semantic type, provenance; no instruction backlink |
| `CfgInitialize : CfgInstruction` | Exact target Place and typed initializer value |
| `CfgStore : CfgInstruction` | Exact target Place and typed replacement value |
| `CfgTerminator` | Source span and authoritative `successors()` interface |
| `CfgBranch` | Exact containing-function target block; one successor |
| `CfgConditionalBranch` | Bool condition and exact true/false target blocks; two ordered successors |
| `CfgReturn` | Optional CFG value, no successors |
| `CfgFunctionEnd` | Body span, no value field, no successors |

Functions/parameters/local Places/blocks are distinct CFG objects. Containment in declaration
arrays establishes ownership, checked by the verifier. Numeric ordinals equal
array positions and are deterministic debugging IDs, not object addresses.
Bindings use exact objects, never names or equal-looking ordinals/spans.
There are no strong parent references.
Function arrays own blocks. Branch and conditional targets use expiring
GLib.WeakRef references, so ordinary backedges cannot form strong ownership
cycles. Detached expired targets are rejected before graph analysis.

Every value owns its semantic type and source span:

| Value | Computation |
| --- | --- |
| `CfgBooleanValue` | Canonical bool type and semantic `BooleanLiteral.TRUE/FALSE` payload |
| `CfgIntegerValue` | Immutable AstraIntegerValue, exact IntegerType, and retained source provenance |
| `CfgParameterValue` | Exact containing `CfgParameter`; type derived from that declaration |
| `CfgLoadValue` | Explicit load from an exact containing local Place; type derived from that Place |
| `CfgPrefixValue` | Shared semantic `POSITIVE`/`NEGATIVE`/`NOT` operator and ordered operand |
| `CfgBinaryValue` | Shared semantic arithmetic, relational, or equality operator and left/right operands |

Values retain exact integer, bool, pointer, or nominal handle types; void is
only a return type. Arithmetic requires same-type integers; unary minus requires
signed integers. Negation `!` uses bool; relations use same-type integers and
produce bool. Equality accepts matching supported non-void types and produces
bool. Boolean payloads print `true`/`false`, without numeric or machine encoding.
CFG values contain no `TokenKind` or Core references. Integer constants retain
AstraIntegerValue directly; source spans recover leading zeroes while dumps print
canonical signed or unsigned values. Huge out-of-range magnitudes fail before Core/CFG.
Nested arithmetic, association, nonliteral unary plus, and even `1 / 0` remain
explicit computation under Astra's wrapping/truncating/trapping semantics.
Only direct signed literal formation normalizes upstream; no general constant
folding or simplification occurs.

## Core conversion and completion

`CfgBuilder.build(CoreProgram)` first runs `CoreVerifier`. Invalid input produces
`CfgError.INVALID_CORE`, an internal defect. First declare every CfgFunction,
its parameters/Places, and pending entry, retaining a temporary exact
CoreFunction-to-CfgFunction map. Only after all declarations exist, translate
bodies in source order:

1. Use the declared parameters and local Places, preserving order, names,
   types, and spans. Temporary exact Core-parameter and Core-local maps resolve
   references. Names and ordinal equality are never binding authority.
2. Start a pending entry numbered zero with an empty instruction array. Translate
   Core statements in source order; Initialize and Store append the corresponding
   CFG instruction. Every nested Core load becomes a CFG load from its mapped Place.
3. Translate each CoreReturn's optional value and complete the pending block with
   CfgReturn. Later statements begin the next disconnected pending block with a
   fresh instruction array. There is no edge from the preceding return.
4. For CoreIf, reserve then, optional else, and join in that order before
   recursively lowering either arm. Terminate the current block with a
   ConditionalBranch to then and else (or join without else). Arm fallthrough
   uses Branch(join); an arm return has no join edge. Resume in the reserved join.
5. An empty body or remaining continuation completes with CfgFunctionEnd, whose
   provenance is the Core body span. Ordinary final returns create no trailing
   block, but every conditional keeps its explicit join, even if unreachable.
6. Create the CFG function with these parameters/locals/completed blocks and
   entry `blocks[0]`.

Block identities are reserved before their terminators are known, permitting
forward targets without a second edge graph. Internal write-once completion fixes
the block span and terminator; a second completion throws. The original completed
constructor remains available. The verifier rejects incomplete blocks before
successor traversal. The recursive lowerer receives the enclosing completion
terminator, so nested arm continuations follow the same algorithm.
The typed instruction array cannot contain terminators, and FunctionEnd cannot
carry a value. Instructions execute in array order before the terminator;
they do not define edges. Block provenance covers its first statement through
return, or through the body end for pending instructions; an empty entry uses
the body span. Types and provenance are
copied from Core authority, without rereading syntax to infer semantics.

For `void sequential() { return; return; }`:

```text
(cfg-program
	(function #0 "sequential" -> void
		(parameters)
		(entry #0)
		(block #0 reachable
			(return)
		)
		(block #1 unreachable
			(return)
		)
	)
)
```

Both returns survive in distinct blocks. CFG construction and reachability do
not remove unreachable source structure, manufacture fall-through edges, merge
blocks, renumber by reachability, or emit unreachable-code warnings. Semantic
analysis still checks names/types in every statement, including unreachable ones.
The [post-return storage golden](../../tests/place/fixtures/post-return.cfg)
likewise preserves a reachable Initialize/Return block and a disconnected
Store/Return block. A declaration after a return also retains its initialization.

## Reachability and return-path validation

`CfgReachability.analyze(CfgFunction)` expects a structurally verified function.
It seeds an iterative worklist with the explicit entry, marks blocks in an
object-identity set, and enqueues each newly visited terminator successor.
It never traverses the function's block array to infer an edge. Branch provides
one successor; ConditionalBranch provides true then false; Return and FunctionEnd
provide none. The existing worklist requires no branch-specific changes. Both
structural successors are traversed even when the condition is constant.

`CfgReachabilityResult.is_reachable(block)` queries a separate snapshot; blocks
have no mutable reachability flag. Recompute it after graph edits. The tests
also designate block #1 as a synthetic entry, proving block/source order cannot
substitute for entry identity or successor authority. Builder-produced entries
are always block #0.

`CfgFlowChecker.check(CfgProgram)` verifies the CFG, computes each function's
reachability, then checks reachable blocks in deterministic declaration order:

| Reachable terminator | Function return type | Flow result |
| --- | --- | --- |
| `Return(value)` | `int` or `bool` | Valid |
| `Return` | `void` | Valid |
| `FunctionEnd` | `void` | Valid; keep the distinct terminator |
| `FunctionEnd` | `int` or `bool` | Source diagnostic at the function name |

An unreachable `FunctionEnd` imposes no completion requirement. Flow checking
returns `CfgFlowResult` with a nullable `Diagnostic`; ordinary missing-return
programs never throw an invariant exception. The first invalid function in
source order is reported:

```text
empty-int.astra:1:5: error: not all paths in function 'missing' return a value
```

## Structural verification

`CfgVerifier.verify(CfgProgram)` checks unique function identities and ordinals,
unique parameter/block containment and ordinals, owned entry blocks, one
terminator per block, same-function successors, supported terminator/value
kinds, canonical semantic type identity, integer/bool/pointer/handle values/parameters, exact
parameter ownership, semantic operator operand/result rules, bool literal payloads,
bool branch conditions, and return value shape/type. Branch successors must match
its exact target; conditional successors must match its true/false targets in
order. Return and FunctionEnd must have no successors.

Local Places must have unique containing-function authority, deterministic
ordinals, and valid non-void types. Every load source and Initialize/Store
target must be an owned local Place; load result and initialize/store value types must match the
Place type. Every local has exactly one CfgInitialize across all blocks,
including unreachable blocks. Unsupported instruction/Place kinds fail.
The verifier does not infer initialization flow from block order or perform
general definite-assignment analysis. Source construction and Core's structured
order checks establish the current initialization-before-use guarantee.

The verifier establishes declaration ownership first, then checks entry and
instruction/terminator/value uses in deterministic block and instruction order,
descending operands left to right.
Failures throw `CfgError.INVALID_CFG` with deterministic structural paths,
without addresses. It accepts unreachable joins and reachable non-void
`FunctionEnd`; flow checking handles the latter's source legality.

Synthetic tests cover foreign/unowned parameters, repeated/shared declarations,
duplicate block ordinals/identities, missing blocks, foreign entry, function and
parameter ordinals, non-void returns without values, void returns with values,
void/unknown/mixed-identity types, invalid operands/operators, and corrupt
successor semantics/ownership. The malformed successor fixture subclasses
return solely to test verifier rejection; it is not a supported operation.
Write-once completion prevents a second terminator, and verification rejects
an uncompleted reservation. Constructors prevent a value-bearing FunctionEnd
or a parameter/load value whose type differs from its declaration/Place.
Branch targets may coincide; reachability visits each block once.

## CLI stage distinction and dumping

| Mode | Last implemented stage / output |
| --- | --- |
| `--parse FILE` | Syntax validation, silent success |
| `--dump-syntax FILE` | Syntax representation |
| `--dump-semantics FILE` | Checked semantic representation |
| `--dump-core FILE` | Verified structured semantic Core |
| `--dump-cfg FILE` | Verified CFG after reachability and flow validation |
| `--dump-ssa FILE` | Verified scalar SSA projected from flow-valid reachable CFG |
| `--check FILE` | All implemented validation through SSA construction/verification, silent success |

An empty `int missing() {}` parses, has a checked semantic model, and has valid
Core. Its pre-flow CFG is block #0 with reachable `FunctionEnd`. Thus semantic
and Core dumps still succeed, while `--check`, `--dump-cfg`, and `--dump-ssa` exit 1 with the
flow diagnostic. This deepens `--check` intentionally; it does not move the
completion rule into the semantic analyzer.

`--dump-cfg` retains unreachable source structure and local storage operations.
`--dump-ssa` excludes disconnected post-return blocks and unreachable joins,
then replaces current local storage with reaching values and block arguments.
Both sides of a literal conditional remain graph-reachable. This boundary
normalizes reachable computation without changing CFG or folding conditions.

File/encoding/syntax/semantic/flow errors print deterministic stderr diagnostics
and exit 1. Incorrect mode arity retains exit 2. `--dump-cfg` emits no partial
stdout, even if a later function fails. Plain `astrac FILE` still exits 2 and
reports compilation unimplemented; no source mode generates target code.

`CfgDump.format` verifies the entire CFG before formatting a complete string,
and analyzes reachability for each function. The internal dumper may inspect
structurally valid pre-flow CFG; the CLI enforces flow validity before calling it.
The dump uses tabs, LF endings, source-order function/parameter/block IDs,
explicit entry, reachability, terminators, and nested semantic values. It is an
internal debugging format, not a stable serialization contract. Local Place
tables and Initialize/Store instructions make storage distinct from loads.
Empty local tables are omitted, preserving earlier golden output. It contains no
LLVM names/types, Core IDs, physical widths, or object addresses. The
[arithmetic](../../tests/cfg/fixtures/arithmetic.cfg),
[sequential returns](../../tests/cfg/fixtures/sequential.cfg),
[empty void](../../tests/cfg/fixtures/empty-void.cfg), and
[scalar boundaries](../../tests/scalar/fixtures/boundaries.cfg) goldens record representative output.

## Lifetime and dependency firewalls

After construction, CFG requires no `CoreProgram`, function, parameter, local
Place, block, statement, or value to stay alive. It retains immutable semantic integer values, semantic types, and
source files/spans, without keeping the `BuiltinTypes` container or earlier
models as authority. Weak-reference tests prove that syntax/tokens, checked
nodes/symbols, and Core nodes are destroyed before CFG verification,
reachability, flow checking, dumping, numeric value/provenance, and source
location lookup. Releasing CFG releases the retained type/source authorities.
Local regressions additionally prove semantic LocalSymbols, checked local
declarations/assignments/references, and Core Place/Initialize/Store/Load objects
are destroyed before the equivalent CFG operations are inspected. The 1,003-digit
valid INT_MAX spelling (leading zeroes) survives through a local initializer
and exact returned load binding. Its semantic value remains INT_MAX.

Meson compiles `astra-cfg-standalone-tests` from the CFG nodes, verifier,
reachability, flow checker, and dumper plus only source/diagnostic and semantic
type/operator sources. The syntax, checked model, symbols, Core, CFG builder,
and backend are omitted. That target constructs, verifies, analyzes, and dumps
CFG directly. It proves the completed representation is not a Core wrapper.
Both CFG executables join the existing `ldd`/`nm` LLVM linkage firewall tests,
with optional `readelf` dynamic-library checks. Standalone bool/branch fixtures
execute against block ordering. Branch lifetime tests drop earlier conditionals
and sibling Places, then inspect CFG truth values, successor identities, and
shared join storage; releasing CFG also releases its blocks and Places.
The separate LLVM smoke test remains the negative firewall control.

The downstream [SSA layer](ssa.md) adds predecessor/dominator/frontier analysis
over this CFG, plus block-argument promotion. CFG itself remains non-SSA and
retains explicit storage operations. No dependencies, owned aggregate boundaries, physical
storage, ABI, LLVM representation, or runtime implementation are added.
LOOP-1 adds [cyclic control flow](cyclic-control-flow.md); SHORTCIRCUIT-1 adds
[expression control flow](expression-control-flow.md) and synthetic bool Places. See the [mutable join](../../tests/branch/fixtures/choose.cfg),
[full return](../../tests/branch/fixtures/choose-direct.cfg), and
[nested joins](../../tests/branch/fixtures/nested.cfg) for the canonical graph shapes.

## While loops in LOOP-1

LOOP-1's [cyclic graph construction](cyclic-control-flow.md) uses the same
terminators. The current block branches to a reserved header; the header
evaluates its condition and branches to the reserved body/exit. Body
fallthrough branches back to the header, and following source starts at exit.
Reservation order is header, body, exit before nested allocations. Returns
remain successor-free; disconnected continuations may retain structural
backedges but never become reachable. Reachability's visited worklist terminates
on cycles and retains both literal-condition edges.

## Ordered direct calls in CALL-1

CoreCallValue lowering visits arguments left-to-right, emits an ordered
CfgCallInstruction, and returns its CfgCallResultValue. Prefix operands lower
first; binary left lowers before right. A call statement uses the same path.
Void calls have no result; non-void calls define exactly one correctly typed
result; only unmanaged results may be discarded. Calls precede consuming initialization, stores,
returns, or conditional branches. Remaining values use trees; SCALAR-1
materializes potential traps before later calls as described below.

Callees translate by exact CoreFunction identity and are held through GLib
WeakRef. The verifier checks same-program membership, arity, argument types,
result shape/type, unique call/result definition slots, and result use after
definition in the same block or on every incoming path (SHORTCIRCUIT-1). Results are Values, never Places, and have no
backlink that could cycle with their defining instruction.

Calls are conservatively effectful instructions, never CFG successor edges;
reachability never visits callees. Disconnected calls remain visible in CFG.
Standalone and pipeline tests prove recursive reclamation and independence
from Core. [Direct-call IR](direct-calls.md) records the complete stage contract.

## Potential traps before later calls in SCALAR-1

Zero-divisor traps expose observable behavior in division/remainder trees.
For `a / b + effect()`, CALL-1's deferred arithmetic would otherwise let the
call precede division. CFG now inserts `CfgEvaluateInstruction(value, result)`
for a potentially trapping left tree before lowering a right subtree containing
calls. Earlier arguments are likewise evaluated before later arguments that
contain calls. Potential traps nested in prefixes or comparisons are included;
no literal divisor is analyzed or folded.

`CfgEvaluatedValue` is a distinct value with no backlink or Place. The verifier
requires one definition, matching non-void result type, and use after its
definition in the same block or on every incoming path (SHORTCIRCUIT-1). Dumps show `evaluate`/`evaluated` identities in a
separate namespace from call results. SSA evaluates the tree at that instruction
position and maps result uses to the existing SSA value. Standalone tests cover
construction, destruction, wrong types, missing/later/cross-block definitions,
and duplicate instructions/results.

Arithmetic trees without a later call retain their established form. This
narrow correction preserves left-to-right trap/call order without changing
calls, CFG edges, source reachability, or Place promotion. See
[ADR 0013](../decisions/0013-scalar-semantics.md).

## Break and continue in LOOPCTRL-1

Before lowering a CoreWhile body, CfgBuilder maps its exact CoreLoopTarget to the
reserved header and exit. Nested mappings coexist. CoreBreak becomes
`CfgBranch(exit)` and CoreContinue becomes `CfgBranch(header)`, directly from
that map. There are no CfgBreak/CfgContinue terminators, special edge kinds,
source-nesting reconstruction, or retained Core target objects in CFG.

Both transfers end the current block. Subsequent source starts a disconnected
block using the existing post-return policy; its structural fallthrough may
still point to a header or join but never reconnects from the terminated path.
A break/continue arm does not fall through to its if join. Reachability excludes
disconnected calls/stores and their edges from the ordinary SSA projection.
Return remains a successor-free function transfer. Reachable FunctionEnd checks
and structurally present constant-condition false edges remain unchanged.

Headers can have preheader, multiple continue, and fallthrough predecessors;
exits can have header-false and multiple break predecessors. The existing weak
successor targets, deterministic predecessor ordering, and graph algorithms
handle them directly. See [cyclic IR](cyclic-control-flow.md).

## Generated expression temporaries

CfgFunction.temporaries owns CfgTemporaryPlace objects separately from source
locals. Each carries a bool type, span, and construction-order ordinal starting
at zero per function; no source name or LocalSymbol exists. Verification requires
unique exact ownership/ordinal, bool type, one initialization, and matching
Initialize/Store/Load types. Successor targets remain weak.

Each logical operator first branches to a dedicated evaluation entry. After
lowering the left, it initializes false for AND or true for OR, then branches to
RHS/join or join/RHS respectively. Only the RHS region evaluates the right and
stores its result. The join returns Load(temp). The builder's current-block field
tracks any recursive splits. If/while, return, local initialization, assignment,
and calls consume the completed join value without condition fusion.

Earlier trapping trees are materialized before later calls or expression regions.
Call/evaluation result uses may cross blocks only when definition-before-use holds
on every incoming path, including disconnected source tails; unavailable values
are rejected. This adds no CFG phi or dependency on SSA analysis. See
[the full algorithm and stage goldens](expression-control-flow.md).

## C imports in CABI-1

CfgProgram owns native functions and separate CfgCFunction declarations.
Each import has exact independent identity, source/debug and external names,
ForeignAbi.C, semantic parameter/result types, a declaration ordinal, and
provenance; it has no body or blocks. All declarations precede native body
translation using an exact temporary CoreCFunction → CfgCFunction map.
No source-name lookup or upstream graph survives construction.

CfgCCallInstruction expose the foreign target domain explicitly and use
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

CfgProgram separately owns CfgCExport attachments with ABI C, source-order
export ordinal, exact external symbol, provenance, and a weak CfgFunction target.
The builder creates all native functions first and translates the exact CoreFunction
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

## PTR-1 values and Places

CfgNullPointerValue preserves the Core null's contextual raw-pointer type and provenance without
retaining Core identity. Ordinary CfgLocalPlace, Initialize, Load, Store, Call,
and Return machinery handles pointers. Equality/copy/null introduce no new
evaluation instruction; calls remain ordered and conservatively effectful.
Verifiers enforce canonical type/pointee identity and exact operand/Place/call
contracts, with no physical width. Existing flow validation applies to pointer
results. CFG remains usable after Core destruction. Pointer locals are eligible
for existing scalar promotion while no language operation exposes their storage
address. See [Place storage](place-storage.md).

## Native struct storage

STRUCT-1 adds program-owned CfgStruct/CfgStructField descriptors and
function-owned canonical CfgFieldPlaces. An ordinary CfgLocalPlace with
StructType is aggregate authority; recursive projections bind an exact Place base
and exact field descriptor. Shared StructType has no upstream symbol backlink. Temporary
identity maps translate the preceding stage without downstream name lookup.

Only scalar/vector leaf projections receive Initialize/Load/Store. Struct-valued
bases are not computed values. Recursive Core initialization lowers to ordinary
leaf initialization in written order. Verification checks descriptor ownership,
acyclic by-value field types, exact ordinals, complete recursive canonical projection
arrays, exactly one initialization per leaf, and leaf operation typing. Stage lifetime and standalone tests
exercise reclamation and malformed projections independently of LLVM.

See [field Places](field-places.md) for the precise initialization, ownership,
and promotion invariants. No physical struct layout or aggregate SSA Value is
needed for non-address-taken locals; their fields still scalar-promote.
Borrowed locals retain explicit addressable storage downstream.

## TPTR-1 and DPTR-1 typed pointers and addressable Places

CfgLocalPlace.address_taken explicitly records semantic addressability copied
from the previous stage. It applies throughout the function, including borrows
in preserved unreachable source. CfgAddressOfValue references that exact
scalar/aggregate base and its canonical TypedPointerType. CfgIndirectFieldPlace
references a typed pointer value and exact CfgStructField; ordinary Load
and Store implement indirect access without a whole-aggregate value.

The verifier checks exact canonical pointee and field ownership, valid
addressable scalar/aggregate targets, matching address/load/store types, and absence
of void* dereference or indirect initialization. Typed pointer returns/fields
and C boundary uses remain invalid. Direct address-taken fields and indirect
fields and address-taken scalar locals are not promotable; ordinary pointer locals and untouched struct fields
remain eligible. No physical offsets or LLVM types enter this representation.
Standalone tests construct, reject malformed identities, dump, and reclaim these
objects independently of upstream stages. See
[addressable storage](addressable-storage.md) for alias and lifetime authority.

CfgDereferencePlace is a genuine Place owning its pointer value, exact integer/f32
pointee type, immutable DataPointerProvenance snapshot, and null-trap contract.
Existing Load/Store consume it; indirect Initialize and whole-struct loads reject.
Pointer identity uses canonical TypedPointerType, distinct from raw void*.
Address-taken scalar locals use the existing explicit storage path throughout
their lifetime. Ordinary scalars and pointer values still promote. See
[dereference Places](dereference-places.md) for evaluation and lifetime authority.

Memory reads are captured with CfgEvaluateInstruction at the expression point.
The ordered-evaluation predicate includes memory reads and address values, so
earlier traps/reads cannot drift past a later memory operation or call.
Struct indirect-field assignment still evaluates its RHS before target access.
Scalar dereference assignment captures its base in CfgEvaluateInstruction before
lowering RHS; the Store follows both. Null checks
remain semantic effects of the indirect memory operation, realized downstream
without changing CFG successors or phi construction.

## OWN-1 lexical cleanup

Structured lowering keeps a temporary cleanup stack keyed by existing CoreBlock
scope identities. Successful initialization appends one owner; normal completion,
return, break, and continue emit the exited scopes in reverse lexical owner-slot order.
Return expressions are completely evaluated before cleanup. CfgCleanupInstruction
is an ordered resultless effect with ordinary void* CfgValue, exact program-owned
CfgCleanupContract, and provenance. Pointer locals remain promotable; null skips
the eventual call and traps do not unwind. See [cleanup IR](cleanup.md).

## MOVE-1 exact ownership events

CfgLocalPlace.cleanup retains the exact optional cleanup contract. CfgInitialize
has an explicit acquisition marker. CfgOwnershipTransferInstruction retains source
and destination owned Places, their exact cleanup and transfer provenance, at the
declaration execution point. Existing lexical cleanup insertion adds moved
destinations in declaration execution order; moved sources keep their cleanup.

CfgFlowChecker validates possibility sets over OWNED/MOVED/RELEASED on reachable CFG before SSA.
It reuses CfgPredecessors (now housed in `src/cfg/predecessors.vala`) and a deterministic
FIFO fixpoint. User owner loads require OWNED; compiler cleanup accepts all three
states and ends the lifetime. Unreachable predecessors are excluded. Duplicate
cleanup, inconsistent lexical lifetime and duplicate declaration acquisition are
malformed CFG. Explicit same-contract rearm requires definitely disarmed state.
See [ownership flow](ownership-flow.md) for the complete lattice, diagnostics,
standalone firewall, analysis dump and reclamation rules.

## Owner borrow events (OBORROW-1)

CfgParameter preserves the exact normalized pointer contract; imported parameters
use the same descriptors with provenance and a verified parameter_types mirror.
CoreOwnedBorrowValue lowers in left-to-right argument order to an ordered
CfgOwnedBorrowInstruction defining CfgOwnedBorrowValue(source, parameter, span).
The source is an exact owned CfgLocalPlace. The verifier requires unique event
identity and one direct use at its exact borrowed boundary, with ordinary
cross-block availability checks. Native borrowed parameter references remain
restricted to comparison or direct noescape forwarding.

[OwnershipFlow](ownership-flow.md) validates the event with the MOVE-1 fixpoint:
OWNED → OWNED; any other singleton or mixed state diagnoses. The event has no foreign effect and
changes no cleanup or ownership definition. Source moves are impossible inside
arguments; malformed standalone CFG also cannot move/release/clean between the event
and its use. Analysis and event objects may die after SSA construction.

## RELEASE-1 ordered event

CfgOwnershipReleaseInstruction(owner, cleanup, span) is an ordered effect with an
exact CfgLocalPlace and its existing CfgCleanupContract. Verification checks void*
owner identity, contract agreement and unique instruction placement. It does not
remove lexical cleanup or register an acquisition. OwnershipFlow requires `{OWNED}`
and assigns `{RELEASED}`; later compiler cleanup accepts any reachable state.
Release-break/continue/return use existing edges and loop fixpoints. After flow
validation SSA normalizes this event to cleanup plus a null pointer definition.
See [release IR](ownership-release.md) and [ownership flow](ownership-flow.md).

## REARM-1 ordered consumption

CfgOwnershipRearmInstruction retains the exact owned Place, producer result,
cleanup contract and provenance. The preceding C call keeps ordinary argument
and effect order. Owned-result verification requires one immediate acquisition
or rearm consumer; raw captures, extra uses, intervening effects and cross-block
consumption reject. Rearm keeps the existing cleanup scope list unchanged.

OwnershipFlow requires definitely_disarmed and transitions to OWNED after the
producer. Mixed MOVED/RELEASED succeeds; every OWNED possibility rejects. Safe
cycles and unsafe backedges reuse the same fixpoint. Core rearm objects may die
before verification. See [rearm IR](ownership-rearm.md).

## Explicit generic capabilities

GEN-CAP-1 capability operations must disappear before CFG. CfgBuilder retains its
existing concrete Core verification entry point, which rejects unresolved
capability operations, including comparisons whose result is already bool.
Concrete instances contain only ordinary arithmetic/comparison/shift operations.
See [capability IR](generic-capabilities.md).

## Recursive struct fields

STRUCT-AGG-1 recursively maps field bases, including Local→Field→Field and
Dereference→Field→Field. Canonical local projections use declaration preorder;
intermediate struct Places never load. Nested initialization lowers in written
order to ordinary leaf Initialize instructions. Scalarization and local-wide
addressability retain their existing authority. See [recursive Places](recursive-field-places.md).

## Generic native structs

GEN-STRUCT-1 materializes generic aggregate applications before CfgBuilder. The Core concrete verifier rejects generic definitions, application storage and generic field projections. CFG continues to contain only ordinary concrete structs and recursive CfgFieldPlaces. Its source/model has no generic aggregate representation. See [generic aggregate IR](generic-structs.md).

## Generic ownership

The existing concrete-Core firewall rejects unresolved Ownable parameters and ownership contracts. Specialized functions use the unchanged concrete ownership-flow solver, without a generic branch. Direct Resource result forwarding uses the existing owned-producer capture and exact immediate-consumer checks, as object forwarding already does. See [generic ownership IR](generic-ownership.md).

## Struct copy decomposition

[CoreStructCopy](struct-copy.md) is eliminated during Core→CFG construction.
Destination and source roots are captured in that order; CfgValidatePlace makes
indirect null validation explicit without loading a leaf. All source leaves then
produce ordinary CfgEvaluatedValue snapshots through Evaluate/Load operations.
Only after every snapshot does Initialize/Store update destination leaves in the
same recursive declaration order. Vectors are single leaves. No aggregate CFG
Value, aggregate temporary or memory intrinsic is introduced.

## Multi-source composition

SOURCES-1 supplies one complete function universe from all native files. CFG call
targets are exact program-owned functions, never paths or textual lookups. Canonical
source order stabilizes ordinals; it has no control-flow or initialization meaning.
Ownership checks retain the original caller use-site span across file boundaries.
The independent CFG model requires no SourceSet or syntax orchestration.
