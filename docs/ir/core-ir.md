# Semantic Core IR

[NUM-CONV-1](numeric-conversions.md) retains exact scalar integer↔floating
conversion kind, types, signedness and policy. Core keeps the explicit operation;
CFG and SSA add an ordered, destination-specific numeric guard before
floating→integer conversion. SSA validates the proof producer and dominance.
Integer→floating needs no trap guard. Suffixed literals arrive as exact constants;
no downstream stage recovers suffixes or conversion types from syntax.

[Owned runtime arrays](owned-runtime-arrays.md) retain CoreOwnedBufferAllocate
with exact count/element authority and static buffer cleanup over SliceType.
Core ownership, borrow, rearm, return and field contracts verify after Checked
destruction. Allocation is target-neutral; no libc allocator symbol enters Core.
Concrete Resource and buffer rearm additionally permits live RAII replacement.

OWN-FIELD-1 extends exact class fields with independent Resource release
contracts. CoreOwnedFieldTransfer distinguishes initialization from live
replacement; CoreOwnedFieldBorrow preserves temporary source identity.
CoreDestructor retains a verified reverse-order field-cleanup epilogue after
normal user-body completion, synthesized even without user deinit. See
[owned-field IR](owned-resource-fields.md).

[Native struct value boundaries](struct-values.md) retain independent exact
StructValueContracts for parameters/results. CoreStructSnapshot and
CoreStructCallResult are bounded producers, not general CoreValues. An exact
argument adapter, result-store statement or struct-return statement supplies the
only consumers. CoreAcquireStructParameter initializes independent read-only
local leaves before body execution. Core rechecks CopyabilityAuthority and exact
nominality after Checked destruction; CoreStructLeaves uses shared StructLeafOrder.

GEN-1 adds [parameterized Core generic definitions](generics.md), held separately
from ordinary functions. Exact CoreTypeParameter identities and CoreGenericCall
nodes exist only before the CoreGenericMonomorphizer runs. Its consuming pass
produces ordinary concrete CoreFunctions with fresh local identities and preserved
global targets. `--dump-core` exposes definitions; `--dump-instances` exposes
concrete bodies and canonical instance inventory. CFG accepts only concrete Core.

[CoreProperty and CorePropertyGetter/Setter](properties.md) retain exact member,
owner, value-type and accessor authority after checked semantics is released.
CoreCallValue/CoreCallStatement targeting those accessors represent property
get/set; Core verification checks parentage, signatures, receiver and namespace.
No property Place or Store specialization exists. F64 property values stay f64.

F64-1 generalizes floating constants to `CoreFloatValue` with exact BinaryFloatFormat,
bits, canonical FloatingType and source provenance. F64 is one ordinary scalar
Core value through arithmetic, comparisons, branches, loops, Places and calls.
Explicit FLOAT_WIDEN/FLOAT_NARROW nodes retain exact source/destination types and
rounding kind after upstream destruction; ICONV remains separate. Verifiers reject
cross-format operands, wrong constant formats and unsupported conversions.
Existing F32 dump bytes remain stable. See [floating values](floating-values.md).

[Owned object results](object-results.md) retain exact ClassType, owned-transfer contract and `CoreResultObjectStorage`. `CoreOwnedObjectResultConstruction` is the producer of a shared `CoreOwnershipReturn`. The verifier rejects local/borrowed escape and mismatched constructor/storage identity. Candidate allocations are separate from acquired owner pointers.

OBJ-OWN-1 generalizes CoreCleanupContract with an exact native class payload.
CoreOwnedLocal relates an owner Place to fresh ordinary ObjectStorage, or an owned
incoming parameter. CoreObjectConstruction acquires that responsibility;
CoreOwnedArgumentValue retains the existing explicit move/call form. Fixed versus
transferable cleanup remains verifier-visible. No owned ClassType variant or
second storage model is introduced. See [object ownership](object-ownership.md).

OBJ-BOUND-1 reuses CoreParameter with exact ClassType and BORROWED_NOESCAPE,
plus ordinary CoreParameterValue and one CoreValue per call argument. No semantic
PTR erasure occurs. Existing indirect object field Places and CoreObjectReceiverValue
supply null behavior and exact member targets. ClassType copies initialize ordinary
reference locals; the parameter creates no CoreObjectStorage or cleanup. The Core
verifier rejects unmanaged class parameters and mismatched contracts. PARAM-BORROW-1
canonicalizes plain and explicitly borrowed native parameters before Core; owned
Class parameters/results retain their existing separate transfer contracts. Its independent classes/contracts survive checked-stage destruction.
See [object values](object-values.md) and [ADR 0051](../decisions/0051-borrowed-object-boundaries.md).

OBJ-LIFE-1 adds CoreConstructor/CoreDestructor, exact INITIALIZING/LIVE receiver
modes, CoreConstructorObjectInitialization and CoreFieldInitialize. Structured
Core validation independently checks definite/possible field sets, missing reads
and completion, exact-once writes and forbidden constructor loops/returns/calls.
CoreObjectStorage retains exact destructor responsibility and stable lexical rank.
CoreCleanupAction distinguishes RESOURCE_DESTROY and OBJECT_DEINIT for the existing
lexical planner. No reference local owns cleanup. See [lifecycle IR](object-lifecycle.md).

OBJ-1 adds CoreClass through the shared CoreNativeInstance member owner and a
separate CoreObjectStorage per lexical construction. CoreObjectConstruction
retains exact storage, target ClassType reference local, lexical scope/region and
complete field initializers in written order. CoreIndirectFieldPlace accepts an
exact class reference with a null-trap contract; CoreObjectReceiverValue forms
the existing ReceiverType for the shared CoreMethod/call nodes. Reference locals,
nulls and identity comparisons use ordinary scalar Core values; no whole-object
aggregate value appears. Verifiers reject missing/duplicate construction,
incorrect class/member/storage identities and explicit object boundaries.
See [object values](object-values.md) and [object storage](object-storage.md).

METHOD-1 adds [CoreMethod and CoreReceiver](methods.md). CoreMethod is an exact
member owned by CoreStruct and included in ordinary function-body processing.
A temporary MethodSymbol-to-CoreMethod identity map binds all declarations before
bodies. CoreCallValue/Statement retain the exact method target and a separate
receiver operand; explicit arguments/results retain native contracts. `this.field`
uses CoreIndirectFieldPlace with exact CoreReceiverValue and CoreStructField.
Direct-local receivers reuse CoreAddressOfValue and existing address-taken local
Places, without copying aggregates. Standalone verification enforces receiver
ownership/type, member namespace, storage and call contracts. No semantic symbol,
name lookup, physical PTR, LLVM type or runtime descriptor becomes Core authority.

SLICE-1 adds [CoreSliceFromArrayValue/CoreSliceLengthValue](slice-values.md) and
[CoreSliceElementPlace](slice-places.md). SliceType is one exact local value type;
arrays remain non-value storage. Construction retains array storage, paired
range operands and immutable lexical proof. Core verifies exact element types,
initialized visible storage, provenance and local-only boundaries. CoreScope
routes bare lexical blocks through existing scope/cleanup handling.

ARRAY-1 adds [CoreArrayInitialize and CoreArrayElementPlace](array-places.md).
ArrayType is an immutable exact element/length identity. CoreLocalPlace retains
one explicit non-promotable array object; initialization carries exactly N
ordered, exact-typed Values. Index Places retain exact storage/type, integer
index and provenance. Reads/writes use ordinary Load/Store, with bounds and
LHS-before-RHS authority. No whole-array Value or vector LanePlace is introduced.

VEC-MEM-1 permits numeric VectorType pointees through the same TypedPointerType,
CoreAddressOfValue, CoreDereferencePlace and generic CoreLoadValue/CoreStore.
CoreLocalPlace.address_taken suppresses vector promotion; untouched vectors
remain promotable. The verifier recursively checks exact vector identity and
rejects bool-vector memory. See [vector memory](vector-memory.md).

BIT-1: CorePrefixValue/CoreBinaryValue extend exact operator kinds; CoreIntegerShiftValue retains direction, exact value/result identity and independently typed scalar count with the invalid-count trap contract.
See [bitwise/shift IR](bitwise-shifts.md) for verifier, lifetime, evaluation
and backend guard/normalization rules. NABI/CABI/VAPI remain unchanged.

VEC-DOT-1 adds `CoreVectorDotValue`: four explicit integer-wrap/F32 dot/MAC
modes retain source VectorType, scalar result type, optional accumulator, both
vector operands and provenance after checked semantic destruction. The verifier
checks exact operand types, accumulator arity/domain and integer destination
width. F32 modes fix ascending non-fused reduction; integer modes permit modular
regrouping. See [dot/MAC IR](vector-dot.md).

VEC-DSP-1 adds `CoreDspValue` with a bounded, explicit primitive kind,
exact source/result types, destination element where applicable, operands and
provenance. The verifier checks saturation, widen, pack and interleave contracts
without LLVM or checked-node backlinks. Each is one value operation and creates
no Place or memory. See [DSP IR](vector-dsp.md).

VEC-LANE-1 adds CoreVectorSplatValue, CoreVectorExtractValue, CoreVectorInsertValue,
CoreVectorShuffleValue and CoreVectorSelectValue. They retain explicit operands,
exact result types and independently owned constant lane metadata. Extraction
returns a scalar value; insertion returns a new whole vector. No lane Place
exists. See [vector primitives](vector-primitives.md).

VEC-1 adds CoreVectorConstructValue (ordered scalar lanes → one exact VectorType)
and CoreVectorReductionValue (ALL/ANY mask → scalar bool). Existing prefix/binary
nodes apply scalar lane rules and produce bool<N> comparisons. Whole-vector
LocalPlaces retain whole-value promotion; VEC-MEM later permits numeric vector
addressability and STRUCT-AGG-1 permits vector struct fields. Lane Places remain
absent. Independent verification retains canonical shape/element identity
and rejects malformed operands/results. See [vector values](vector-values.md).

F32-1 adds `CoreFloatValue`, retaining immutable `BinaryFloatValue` BINARY32 bits,
canonical `F32Type`, and source provenance after the upstream stage is destroyed.
Dumps print `(f32 0x80000000 : f32)` for negative zero. No decimal reparsing or
host/LLVM floating authority enters Core. Shared prefix/binary operators enforce
exact f32 operands and bool comparison results; `%` is rejected. Existing
Places, field storage, scalar promotion, block arguments, and instruction results
carry f32 without a second IR architecture. See [f32](../language/f32.md).

INTS-1 retains exact [IntegerType](../language/integers.md) identity and immutable
`AstraIntegerValue` bits in `CoreIntegerValue`. `int` and `i32` share one type,
canonically displayed as `int`. Constants never reparse source spelling. The
verifier checks both canonical type identity and exact value/type agreement;
signed and unsigned values with identical bits remain distinct. Core retains
these authorities after upstream objects die. Locals, fields, block parameters,
and loop carries use the existing scalar machinery at every integer width.

OWNBOUND-1 retains native parameter contracts UNMANAGED, BORROWED_NOESCAPE and
OWNED_TRANSFER; `CoreFunction.result_contract` is UNMANAGED or OWNED_TRANSFER,
with exact type cleanup in `owned_cleanup`. `CoreAcquireParameter` initializes
an owned parameter's `CoreLocalPlace` from its immutable incoming `CoreParameter`.
The existing `CoreOwnedLocal` supplies root scope and stable cleanup rank.
Parameters acquire in declaration order before root locals. This adds mutable
slot authority only for owned parameters; it does not make every parameter
addressable. `CoreOwnedArgumentValue` retains exact source, target parameter and
cleanup; `CoreOwnershipReturn` retains moved-source or owned-null transfer.
Core verifies exact nominal types, contracts, slots and consuming contexts
independently of checked objects. See [ownership boundaries](ownership-boundaries.md).

RESOURCE-1 adds `CoreHandle` descriptors with an exact HandleType token,
independent cleanup authority, provenance, optional copied header and ordinal.
HandleType contains no upstream syntax/symbol/cleanup backlink. Each program
registers its exact descriptors before validating scalar values; verifiers reject
undeclared/impostor types, nominal mismatches and type/cleanup disagreement.
Handles remain ordinary scalar values and promotable Places, with typed null
and same-type block parameters. Existing ownership operations are reused.
See [ADR 0033](../decisions/0033-nominal-resource-handles.md).

Core is Astra's compiler-owned representation of typed semantic computation.
It is a downstream representation built from the checked model, ready for later
compiler transformations; it is not another record of source grammar or a
machine representation.

```text
source → syntax → checked semantic model → Core IR
                                             ↓
                              explicit CFG / flow validation
                                             ↓
                           reachable scalar SSA / block arguments
                                             ↓
                                  verified NABI / LLVM lowering
                                             ↓
                                      native execution
```

The Core boundary is described in [ADR 0007](../decisions/0007-core-ir.md).
ASTRA-PLACE-1 added [local storage and Places](place-storage.md); BRANCH-1 adds
[booleans and structured conditionals](conditional-control-flow.md).
ASTRA-CFG-1 established downstream
[explicit CFG and flow validation](cfg.md); Core's structural validity remains
independent of completion validity. LOOP-1 adds [structured while loops](cyclic-control-flow.md);
native executable production is downstream of verified SSA/NABI/LLVM.

## Implementation and inventory

```text
src/core/
	core-nodes.vala  Core identities, Places, typed values, statements, errors
	builder.vala     checked-model-to-Core construction
	verifier.vala    internal structural invariants
	core-dump.vala   verified, deterministic internal dump
```

All classes are in `Astra.Core`. `CoreNode` supplies source provenance;
`CoreValue`, `CorePlace`, and `CoreStatement` are distinct abstract bases. The complete
current inventory is:

| Category | Operation/entity | Representation |
| --- | --- | --- |
| Container | Program | `CoreProgram`: ordered functions and source span |
| Entity | Function | `CoreFunction`: name, return type, ordered parameters/locals, body, declaration/name spans |
| Entity | Parameter | `CoreParameter`: name, type, zero-based ordinal, declaration/name spans |
| Storage | Local Place | `CoreLocalPlace : CorePlace`: name, type, local ordinal, declaration/name spans |
| Container | Block | `CoreBlock`: ordered statements and body span |
| Value | Boolean | `CoreBooleanValue`: canonical bool type, semantic `BooleanLiteral` payload, source span |
| Value | Integer | `CoreIntegerValue`: immutable AstraIntegerValue, exact IntegerType, and source span |
| Value | Parameter | `CoreParameterValue`: reference to the exact Core parameter |
| Value | Load | `CoreLoadValue`: exact source Place; result type derived from that Place |
| Value | Prefix | `CorePrefixValue`: semantic operator, operand, result type |
| Value | Binary | `CoreBinaryValue`: eager semantic operator, left/right operands, result type |
| Value | Short circuit | `CoreShortCircuitValue`: AND/OR, conditional RHS, bool result, provenance |
| Value | Direct call | `CoreCallValue`: non-owning exact CoreFunction, ordered arguments, non-void result type, provenance |
| Statement | Direct call | `CoreCallStatement`: non-owning exact CoreFunction, ordered arguments, provenance; result discarded |
| Statement | If | `CoreIf`: bool condition, then CoreBlock, optional else CoreBlock |
| Statement | While | `CoreWhile`: bool CoreValue condition, CoreBlock body, source provenance |
| Statement | Return | `CoreReturn`: optional Core value and return-statement span |
| Statement | Initialize | `CoreInitialize`: exact target Place and initializer value |
| Statement | Store | `CoreStore`: exact target Place and replacement value |

`CoreBlock` is a container, not a basic block or a statement operation. The
current grammar permits initialized locals, assignments, if/else, while, break/continue, calls, and returns. No placeholder
operations for future language features are present.

Node properties have private setters and compiler-internal constructors. The
ordered `GenericArray` containers follow the existing checked-model convention
and remain mutable for compiler construction. Core must be verified after
changes and before consumption. The format, constructor API, and mutation policy
are internal and are not stable serialization or transformation contracts.

## Types, operators, and values

Every `CoreValue` holds a strong reference to the resolved `SemanticType` from
semantic analysis. Functions, parameters, and Places retain those same type identities.
There is no new Core type universe. Values include every IntegerType, bool,
raw pointers, and nominal Resource handles; void is only a function return type.
Integer width/sign are semantic facts, with no physical layout, alignment,
machine class, host C type, or ABI classification.

Semantic operator identity is shared with the checked model through
`src/semantic/operators.vala`. Prefix operations are `POSITIVE` (`+`) and
`NEGATIVE` (`-`) for signed integers and `NOT` (`!`) for bool. Positive is
identity for every integer. Arithmetic requires the exact same integer type on
both operands and result; relational operators require the exact same integer
operands and produce bool. Equality accepts matching supported non-void types
and produces bool. Shared semantic operator methods enforce the signatures. Core
does not use token kinds to decide their meaning.

Boolean values retain `BooleanLiteral.TRUE/FALSE` separately from provenance.
This semantic payload prints `true`/`false`; it has no target numeric encoding.

Integer constants retain the checked `AstraIntegerValue` as numeric authority and
copy its source span as provenance. `00042` has value 42; direct signed minimum
formation has value -2147483648, including through parentheses. Core never
re-parses literal text. Constants already fit their exact IntegerType before
construction. Dumps print signed or unsigned mathematical values accordingly.
SourceSpan still recovers exact spelling without a duplicated string.

[Scalar semantics](../language/scalars.md) defines wrapping arithmetic,
truncating division/remainder, zero-divisor traps, and INT_MIN/-1. Core preserves
these operations. No general constant folding, host integer cast, LLVM constant,
or physical-width descriptor is introduced. Historical huge magnitudes now
fail semantic analysis; their source/syntax fixtures remain exact.

The builder translates each checked integer, parameter reference, prefix, or
binary expression into its corresponding Core value, preserving the checked
type, provenance, operator, and ordered operands. Parentheses are absent from
checked semantics and Core. `1 + 2 * 3` stays an addition containing a multiply;
`+x`, `x + 0`, nested prefixes, and even `1 / 0` remain unevaluated operations.
A checked local reference becomes an explicit `CoreLoadValue` from the exact
Core local Place. The Place is authoritative storage, not the loaded value.

## Identity and construction

`CoreBuilder.build(CheckedProgram)` returns a distinct `CoreProgram`. A first
pass creates all Core functions, parameters, and local Places, preserving
declaration order and ordinals, with non-null empty body containers. A second pass fills
those bodies in statement order, recursively translating CheckedIf branch
blocks and CheckedWhile bodies to CoreBlocks. No CFG identity or branch terminator enters Core.

CoreWhile preserves a condition computation evaluated before every iteration.
The body owns its structured initialization/store operations; all references
to an outer local use the same exact CoreLocalPlace in condition, body, and
continuation. A body declaration has one function-owned Place without escaping
its lexical availability. Verification checks bool conditions, body structure,
Place ownership/availability, and existing scalar/call rules; it adds no graph,
dominance, backedge, or return-path analysis.

Temporary hash tables use object identity to map checked `FunctionSymbol` and
`ParameterSymbol` objects to Core functions and parameters, and `LocalSymbol`
objects to Core local Places. A parameter reference
must map to the exact parameter declared in the containing function. Matching
names, spans, types, or ordinals cannot substitute for declaration identity.
There is no repeated string lookup, type parsing, token interpretation, or
source-error diagnosis. Local declarations, assignments, and references map to
the same exact containing-function Place, including in either branch and after
a join. Sibling locals with the same spelling map to distinct Places. Tests explicitly distinguish identical-looking symbols
and show that checked binding wins even if its provenance spells another name.

Core names are copied strings used for debugging/source spelling. Core functions
own parameters and local Places through their arrays. Parameter values retain
parameters; loads and writes retain Places directly. There is no strong back reference to the containing
function. Values are computations; none implies addressable storage.

## Statements and provenance

`CoreInitialize` evaluates its value then initializes fresh local storage.
`CoreStore` evaluates its value then replaces the existing stored state.
These remain distinct operations. OWN-1 attaches an explicit acquisition marker
to Initialize for an owned foreign local; ordinary Store cannot reassign it.
Neither implies an LLVM alloca, address, register, or stack location.

`CoreIf` retains its bool condition and ordered nested branch blocks. It has no
basic-block identities or successor edges. Both arms share mapped outer Places;
branch-local declarations remain distinct in the function-owned local array.

A return optionally carries a value according to the already checked function
return semantics. It has no CFG-terminator behavior. Both returns in
`void f() { return; return; }` survive, in order. An empty `int` function body
also remains representable: definite-return and reachability analysis belong
to the downstream CFG layer. Core construction never removes later statements.

All Core nodes retain a `SourceSpan`, whose half-open byte range strongly retains
its `SourceFile`. Functions, parameters, and locals also keep checked name spans. Return
and value spans are copied from the checked nodes; literal and inner operation
spans are not reconstructed by reading punctuation. No syntax node is kept to
recover a location.

Core does not retain `CheckedProgram`, checked functions/statements/expressions,
semantic symbols, syntax nodes, or tokens. Each referenced `AstraIntegerValue`, `SemanticType`, and
`SourceFile` can outlive the frontend models through normal strong references.
The lifetime regression uses weak references to prove the checked program,
function, symbols, expression, type-universe container, syntax tree, and token
have been destroyed. It then verifies/dumps Core, checks the parameter binding,
checks numeric 7, recovers source `007`, and resolves its source location. Releasing Core
also releases the remaining semantic type and source file.
The local lifetime regression additionally proves LocalSymbols and checked
declarations/assignments/references die while Core loads, initialization/store
targets, and a valid INT_MAX initializer with 1,003 decimal digits (leading
zeroes) remain exact and verifiable. Its numeric value is independent of its
preserved source spelling.

## Verification and errors

`CoreVerifier.verify(CoreProgram)` checks compiler invariants, not language
source errors. It validates:

- unique function identities and unique parameter declaration slots;
- parameter ordinals equal their ordered array positions;
- every parameter reference belongs to the containing function;
- present, supported semantic types and consistent canonical type identity
  within the translated program;
- integer constants with immutable valid AstraIntegerValue and matching exact type, bool literals, and supported truth payloads;
- integer/bool/pointer/handle parameters/Places/values with no void value types;
- supported semantic operators and their exact operand/result signatures;
- bool CoreIf conditions and structurally valid nested CoreBlocks;
- return value presence and type agree with the containing function;
- only the implemented statement/value operations occur.

Local verification additionally requires unique containment and ordinal order,
valid non-void Place types, containing-function Place ownership for every
load/initialize/store, matching load/write types, and exactly one initialization
per local. A structured-order availability set checks initialization before
loads/stores, including preserved post-return statements. Initializer values
are checked first, so self-loads fail. Entering a branch retains enclosing
availability; leaving it removes that block's declarations. A separate set
counts every initialization across the function. Repeated/cyclic CoreBlock
identities are rejected; no graph reachability or branch evaluation is needed. This is
not CFG dominance, reachability, or definite-assignment dataflow. Load constructors
derive their type directly from the source Place.

Declarations are visited before bodies, and operands are visited left to right.
The first failure throws `CoreError.INVALID_IR`, for example:

```text
internal Core verification error at function #0/statement #0/value: parameter reference is not owned by the containing function
```

Structural paths make failures deterministic without object addresses or name
lookup. The verifier does not parse literal text, check source namespaces, or
infer reachability. Non-null constructor arguments and private properties
prevent missing node/type fields through the normal construction API; in
particular, a parameter value derives its type directly from its parameter.
Integer constructors require a valid AstraIntegerValue; its private constructor
and range-checked factories prevent out-of-range payloads. The immutable value
and identity/type constructor invariants are tested. Synthetic tests exercise
constructible cross-function references, shared declarations, wrong ordinals,
return shape errors, void types, mixed semantic type identities, and invalid
operator enum values without process aborts.

Unsupported checked nodes or inconsistent declaration mappings raise
`CoreError.INVALID_CHECKED_MODEL` during construction. Both error codes describe
internal compiler defects, separate from parser/semantic source diagnostics.

## Internal dump and CLI

```sh
astrac --dump-core FILE
```

This runs parsing, semantic checking, Core construction, complete verification,
and then deterministic dumping. `CoreDump.format` performs verification before
formatting; the driver writes the returned complete string. Syntax or semantic
failures preserve their existing diagnostics and produce no Core output.

For `int identity(int x) { return (x); }`, the dump is:

```text
(core-program
	(function "identity" -> int
		(parameters
			(parameter #0 "x" : int)
		)
		(block
			(return
				(parameter #0 : int)
			)
		)
	)
)
```

Parameter/local ordinals expose bindings within each function. Dumps preserve source
order and canonical signed integer values, contain no addresses or machine type names,
and are internal/debug-only. The
[arithmetic golden](../../tests/core/fixtures/arithmetic.core) additionally shows
the full semantic tree for `-(a + 2) * b % 3`.
The [mutation golden](../../tests/place/fixtures/mutate.core) shows a local Place
declaration, distinct initialize/store operations, and explicit loads. Empty local
tables are omitted to preserve the earlier dumps.

## Boundaries and future work

ASTRA-SSA-1 adds [scalar SSA](ssa.md) downstream of validated reachable CFG.
Core remains structured and keeps Places, Loads, Initialize, and Store. The
SSA builder eliminates current promotable int/bool/void* storage without modifying
Core or making its identities depend on the downstream representation.

Core contains no CFG/SSA, basic blocks, branch terminators, phi nodes, scheduling,
reachability analysis, ownership transfer, optimizations, LLVM
types/values, or physical storage/ABI representation. Places include scalar
locals, aggregate locals, and exact direct/indirect scalar field projections;
only aggregate local address borrows are supported. Core resides outside the
LLVM backend and uses the existing host dependencies only.

Core tests and `astrac` do not import backend bindings or link libLLVM. Meson's
existing linkage/backend-symbol checks cover the Core test target as well as
the frontend, semantic tests, and driver; the LLVM smoke fixture remains a
separate negative control. Strict generated-C pointer checking is retained.
A standalone Core target compiles nodes/verifier/dumper from only source and
semantic type/operator authority, without syntax, checked nodes, symbols, or a
builder. Its samples exercise local Place/load/initialize/store operations and
CoreBooleanValue/CoreIf/comparison/negation. Branch lifetime regressions prove
checked conditionals and sibling LocalSymbols die while exact Core Places, bool
payloads, operators, and provenance remain usable.

The CFG layer consumes the ordered structured body, preserves sequential returns
as disconnected blocks, lowers CoreIf to explicit branches/joins, and diagnoses non-void completion without
treating Core construction as reachability or definite-return analysis. See
[ADR 0008](../decisions/0008-explicit-cfg.md). Multi-program type/identity
unification remains unsettled.

## Direct calls in CALL-1

All CoreFunction identities already exist before body translation. A temporary
FunctionSymbol-to-CoreFunction identity map translates CheckedCallExpression
and CheckedCallStatement; completed Core retains no checked symbols. Both call
forms use GLib WeakRef callees. Programs own functions, functions own bodies,
and call edges cannot create recursion ownership cycles.

CoreCallValue requires a non-void callee and matching semantic result type.
CoreCallStatement accepts either return shape. The verifier checks same-program
callee membership and exact argument count/types for both forms. Arguments and
binary operands preserve left-to-right evaluation; all calls are conservatively
effectful. There is no physical signature or calling convention.

Standalone recursive call models verify, dump, and reclaim their functions.
Pipeline regressions destroy syntax and checked models before inspecting exact
forward/recursive Core targets and provenance. See [direct-call IR](direct-calls.md).

## Exact loop targets in LOOPCTRL-1

CoreWhile owns `CoreLoopTarget(span, ordinal)` in addition to condition/body.
CoreBreak and CoreContinue are separate structured CoreStatements with exact,
non-owning GLib.WeakRef targets. The target contains no checked object, function
backlink, CFG block, or LLVM identity. Ordinals follow checked function-local
source preorder and are display/provenance aids, never identity keys.

CoreBuilder creates each target before the loop body and translates transfers
through its temporary CheckedLoopTarget-to-CoreLoopTarget map, with containing
function membership checks. It never chooses a CoreWhile from nesting. The
verifier rejects repeated targets, wrong ordinals, foreign/expired transfers,
and supplied targets that do not enclose their transfer; checking enclosure
validates an identity rather than resolving one. It does no reachability.

Dumps expose `(while #0 ...)`, `(break #0)`, and `(continue #0)`, including
unreachable source. Nested checked targets can die before Core is verified and
dumped; detached Core transfers expire safely after their owning loops die.
Standalone tests cover both statements, nested target inequality, lifetime,
foreign objects with matching ordinals, duplicates, and deterministic errors.
See [ADR 0018](../decisions/0018-loop-control-targets.md).

## Structured short-circuit values

CoreShortCircuitValue preserves AND/OR identity and conditional RHS evaluation.
Both operands and the result must be the canonical bool type; the verifier also
rejects unknown operators. It does not evaluate constants or inspect CFG.
The node owns independent Core children and SourceSpan, with no syntax, checked
node, or CFG block reference. Standalone construction, malformed signatures,
and upstream-destruction tests qualify it. See
[expression control flow](expression-control-flow.md).

## C imports in CABI-1

CoreProgram owns native functions and separate CoreCFunction declarations.
Each import has exact independent identity, source/debug and external names,
ForeignAbi.C, semantic parameter/result types, a declaration ordinal, and
provenance; it has no body or blocks. All declarations precede native body
translation using an exact temporary CFunctionSymbol → CoreCFunction map.
No source-name lookup or upstream graph survives construction.

CoreCCallValue and CoreCCallStatement expose the foreign target domain explicitly and use
weak references to the program-owned import. Verifiers require same-program
target identity, ABI C, unique declarations, int/void* parameters, int/void*/void results,
exact arguments, and the correct result shape. Foreign bool is invalid.
Native call nodes remain distinct even with identical signatures and ordinals.
All C calls are conservatively effectful; arguments preserve Astra ordering.

Core retains structured expressions and independent semantic types; physical C signatures are not Core authority.

Completed imports/calls remain verifiable and dumpable after the upstream stage
dies. NABI contains only native signatures; CABI separately plans SSA imports.
See [ADR 0020](../decisions/0020-c-scalar-imports.md).

## C export metadata in CEXPORT-1

CoreProgram separately owns CoreCExport attachments with ABI C, source-order
export ordinal, exact external symbol, provenance, and a weak CoreFunction target.
The builder creates all native functions first and translates the exact checked FunctionSymbol
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

## PTR-1 values

CoreNullPointerValue owns its contextual semantic raw-pointer type and source provenance, with no
numeric or host pointer payload. Core verifiers validate canonical RawPointerType
and canonical void or exact owned struct pointee, null type, exact Place/value/call/return types, and
pointer equality through shared BinaryOperator rules. Pointer arithmetic and
ordering remain invalid. C import/export value checks now include void* while
still rejecting foreign bool. All existing parameter, Place, load/store, return,
and call identities remain generic. Types/null/provenance survive checked-model
destruction; raw-pointer destruction never acts on a foreign pointee. See
[ADR 0024](../decisions/0024-opaque-raw-pointers.md).

## Native struct storage

STRUCT-1 adds program-owned CoreStruct/CoreStructField descriptors and
function-owned canonical CoreFieldPlaces. An ordinary CoreLocalPlace with
StructType is aggregate authority; recursive projections bind an exact Place base
and exact field descriptor. Shared StructType has no upstream symbol backlink. Temporary
identity maps translate the preceding stage without downstream name lookup.

Only scalar/vector leaf projections receive Initialize/Load/Store. Struct-valued
bases are not computed values. CoreStructInitialize retains recursive direct-storage
initialization in written order. Verification checks descriptor ownership, acyclic
by-value field types, exact ordinals, complete recursive canonical projection arrays,
exactly one initialization per field, and leaf operation typing. Stage lifetime and standalone tests
exercise reclamation and malformed projections independently of LLVM.

See [field Places](field-places.md) for the precise initialization, ownership,
and promotion invariants. No physical struct layout or aggregate SSA Value is
needed for non-address-taken locals; their fields still scalar-promote.
Borrowed locals retain explicit addressable storage downstream.

## TPTR-1 and DPTR-1 typed pointers and addressable Places

CoreLocalPlace.address_taken explicitly records semantic addressability copied
from the previous stage. It applies throughout the function, including borrows
in preserved unreachable source. CoreAddressOfValue references that exact
scalar/aggregate base and its canonical TypedPointerType. CoreIndirectFieldPlace
references a typed pointer value and exact CoreStructField; ordinary Load
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

CoreDereferencePlace is a genuine Place owning its pointer value, exact integer/f32
pointee type, immutable DataPointerProvenance snapshot, and null-trap contract.
Existing Load/Store consume it; indirect Initialize and whole-struct loads reject.
Pointer identity uses canonical TypedPointerType, distinct from raw void*.
Address-taken scalar locals use the existing explicit storage path throughout
their lifetime. Ordinary scalars and pointer values still promote. See
[dereference Places](dereference-places.md) for evaluation and lifetime authority.

## OWN-1 acquisition

CoreOwnedLocal retains the exact ordinary CoreLocalPlace, CoreCleanupContract,
and weak scope reference to the CoreBlock normalized from the checked lexical
region. CoreInitialize.acquisition explicitly marks successful acquisition;
cleanup calls are not inserted here. CoreCFunction.owned_cleanup and the program
registry retain independent contracts after semantic metadata dies. The verifier
checks direct producer/contract matching and rejects owner escapes and raw stores;
CoreOwnershipRearm explicitly models same-contract reassignment after discharge.
See [cleanup IR](cleanup.md) for scope authority and downstream insertion.

## MOVE-1 transfer event

CoreOwnershipTransfer(source, destination, cleanup, span) identifies two exact
CoreOwnedLocal objects and their identical CoreCleanupContract. Both Places are
void*, the source must be initialized and visible, and the destination must have
one fresh initialization in its exact CoreBlock scope. A transfer is an ordered
statement, never an ordinary copy/store sequence. It retains checked move provenance
without retaining checked objects. CoreDump prints source/destination owner ordinals
and names plus the cleanup ordinal. Source scope/contract metadata is retained;
CFG lowering adds the destination to the existing lexical cleanup stack.
Definitive move-state checking is deferred to [reachable CFG flow](ownership-flow.md).

## Borrowed owner arguments (OBORROW-1)

CoreParameter retains PointerParameterContract separately from SemanticType.
CoreCFunction now retains the same stage parameter descriptors, including source
provenance; parameter_types is a verified mirror. CoreOwnedBorrowValue references
an exact CoreOwnedLocal and target CoreParameter with an argument SourceSpan.
Its semantic type is void*, and it is legal only as the direct argument of that
borrowed/noescape parameter. It creates no owner, transfer or cleanup operation.
CoreVerifier checks owner membership/availability and exact call context; ordinary
owned loads remain restricted. Borrowed native parameter values may appear only
in equality or direct borrowed arguments. Storage, return and unconstrained
forwarding fail even in standalone Core. Checked adaptations may die after build.

## RELEASE-1 explicit discharge

CoreOwnershipRelease(owner, cleanup, span) retains an exact CoreOwnedLocal and its
CoreCleanupContract. It is a statement, distinct from transfer and lexical cleanup.
Verification requires the registered void* owner, lexical availability and exact
contract; same-name owners or contracts are not interchangeable. Checked release
objects may die once mapped. The event remains explicit until reachable CFG
ownership validation proves definitely OWNED. See [release IR](ownership-release.md).

## REARM-1 stable owner assignment

CheckedOwnershipRearmAssignment normalizes to CoreOwnershipRearm, retaining the
exact CoreOwnedLocal, direct CoreCCallValue, stable CoreCleanupContract and source
span. It is distinct from CoreStore and CoreInitialize. Core verifies lexical
availability, owned void* storage, program-owned callee/contract and exact cleanup
identity; the subsequent CFG ownership fixpoint checks definitely disarmed state.
It adds no owned local, scope or cleanup obligation. Checked rearm objects may die
once this contract-complete model is built. See [rearm IR](ownership-rearm.md).

## Explicit generic capabilities

CoreGenericCapabilityRequirement retains an exact CoreTypeParameter, immutable
stage-neutral GenericCapabilityIdentity and provenance. CoreGenericCapabilityOperation
retains the authorizing identity, kind, exact parameter and operand/result shapes.
Core independently verifies these after checked semantics is released;
monomorphization resolves them to ordinary concrete operators.
See [capability IR](generic-capabilities.md).

## Recursive struct fields

STRUCT-AGG-1 makes CoreFieldPlace recursive over CorePlace, with exact owner/result
validation and an independently verified acyclic concrete struct graph.
CoreStructInitialize retains recursive direct-storage initialization, complete
children, source order and provenance without a Core aggregate Value. See
[recursive field Places](recursive-field-places.md).

## Generic native structs

GEN-STRUCT-1 adds independent CoreGenericStruct, CoreGenericStructField and CoreGenericStructApplicationType definitions, reusing CoreTypeParameter. Temporary CoreGenericStructFieldPlace participates in the same recursive storage tree through CoreStorageFieldPlace; CoreStructInitialize retains its existing ordered direct-storage initializer tree. Materialization maps exact origins into ordinary CoreStructs, CoreStructFields and CoreFieldPlaces. verify_concrete rejects surviving generic aggregates. See [generic aggregate IR](generic-structs.md).

## Generic ownership

Parameterized Core now retains exact Ownable ownership contracts on incoming parameter slots, owned arguments and owned returns. Core independently verifies their move state. The existing monomorphizer converts these contracts to ordinary Resource/Class ownership and removes all parameterized responsibility before concrete verification. See [generic ownership IR](generic-ownership.md).

## Whole struct copy

[CoreStructCopy](struct-copy.md) retains exact destination/source CorePlaces,
concrete storage type, initialization/assignment mode and provenance as a
statement. Core independently rederives recursive Copyability from its own field
graph and verifies complete source visibility and destination legality. Fully
concrete generic applications materialize in the same node. No aggregate CoreValue
or generic copy node is introduced. CFG expands it to ordinary leaf snapshots
followed by delayed writes; scalarization and stage lifetime independence remain.


## C floating values in CABI-FP-1

Foreign parameters/results carry the ordinary exact F32Type or F64Type and
ForeignAbi.C through Checked, Core, CFG and SSA. VAPI float/double has already
normalized to the same foreign symbols; source provenance remains available
without retaining the VAPI graph. CoreCCallValue and existing CFG/SSA C-call
results use ordinary f32/f64 values. There is no foreign-float semantic Value,
physical CABI channel in arithmetic, numeric conversion or allocation.

CABI later selects distinct C F32/float or F64/double under scalar-fp-v2.
Native f32/f64 and aggregate-v7 planning remain separate. Left-to-right
argument effects and earlier-trap suppression use the existing call lowering;
foreign calls remain conservatively effectful. See [ADR 0063](../decisions/0063-c-floating-point.md).

## Multi-source composition

SOURCES-1 builds one CoreProgram from the complete [source program](../architecture/source-program.md).
No CoreModule or source-unit barrier is introduced. Declarations and uses retain
original diagnostic spans while exact Core symbols replace Checked identities.
Core verification succeeds after all syntax and Checked graphs die. Generic keys
remain definition plus exact arguments; file/caller identity is excluded. During
monomorphization, buffer borrows preserve the exact callee parameter boundary,
just as Resource and owned-field borrows do.
