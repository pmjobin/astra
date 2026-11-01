# Compiler architecture

The complete compiler is the Vala implementation in `bootstrap/`. Astra's
source/diagnostic and lexer components live in `compiler/`; parser/AST and later
stages remain the next self-hosting work. The [canonical roadmap](../history/ASTRA_VISION_AND_ROADMAP_v2.0_2026-10-18.md)
and [current capability matrix](../language/capabilities.md) describe direction
and implemented scope respectively.

Syntax, semantic, Core, CFG, SSA, native ABI, C ABI and LLVM retain separate
representations and verification authorities. A valid earlier representation does
not excuse later verification. Generic materialization happens before concrete
flow/lowering; opaque native units and foreign products retain explicit identity,
layout and lifetime boundaries. See [invariants](invariants.md),
[native units](../language/native-units.md) and [runtime composition](../language/executor-composition.md).
LLVM layout caches belong to their module; no disposed LLVM context may remain a
global cache identity.

The sections below explain component design at introduction. Later structural,
runtime and native-unit contracts extend their initial domains; an old excluded
feature or qualification status is not a current rejection rule. The
[historical latency study](../compiler/latency-study.md) remains a scoped
measurement, not authorization to remove independent verification.

## Component design background

OWN-SWAP-1 adds a dedicated ownership statement for exchanging two initialized
buffer slots. Semantic/Core preserve exact owner and field identity; CFG/SSA check
ordered destination capture, both-sided borrow invalidation and one closed owner
permutation. LLVM verifies complete pre-store snapshots and their opposite-slot
stores. No mutable reference API, field hole, runtime exchange helper or ABI change
is introduced. See [ADR 0084](../decisions/0084-owned-buffer-exchange.md) and
[exchange IR](../ir/owned-buffer-exchange.md).

CONST-1 completes exact scalar constant evaluation in the semantic stage. Exact
constant symbols and dependency states never become runtime storage; the Core
builder erases declarations and emits existing scalar values. Array extents resolve
through the same authority before ArrayType construction. See
[constant evaluation](constant-evaluation.md) and [ADR 0072](../decisions/0072-compile-time-constants.md).

BASELIB-1 places reusable numerical code outside the compiler under `lib/astra`.
Clients explicitly select pure sources, contract sources and one failure provider,
hosted equality reporters, or math VAPI. All declarations follow existing pipeline
and specialization authorities. Only execution plumbing adds a typed ordered link
input stream for `--link-object`/`--link-library`, retaining output transactions.
No new language, ownership, ABI, optimizer or runtime abstraction is introduced.
See [ADR 0071](../decisions/0071-base-library-foundation.md) and
[component dependencies](../library/base.md).

GEN-INFER-1 adds a bounded semantic GenericCallInference authority after exact
function lookup. Direct T/owned T arguments expose canonical semantic identities,
including exact outer parameters under the resolved §75 policy. The analyzer
retains temporary checked arguments and structured ownership proof fragments,
then uses the existing transport, capability and call-contract checks. A failed
call discards those fragments; a valid call composes them in source argument order.
No inference state is attached to Checked calls. Existing parameterized Core and
TypeSubstitution handle outer identities; all downstream representations and
specialization keys are unchanged. See [ADR 0070](../decisions/0070-generic-call-inference.md).

SOURCES-1 introduces [SourceSet and SyntaxProgram](source-program.md) above the
single-file parser. Independently parsed units feed one global declaration
collection and body-checking pass. Normalized path order stabilizes existing
per-kind queues without defining execution order. Exact spans retain each file;
Checked and later stages share one program and keep existing ownership, generic,
ABI and LLVM authority. [ADR 0069](../decisions/0069-multi-source-compilation.md)
excludes modules, imports and separate compilation.

PARAM-BORROW-1 resolves plain native HandleType/ClassType/SliceType parameters
to the existing BORROWED_NOESCAPE during semantic signature collection. Owned,
value, pointer, generic and foreign contracts retain their own authority. CFG's
existing through-invocation owner checks now reject Class same-owner borrow plus
transfer, as Resource/buffer already do. No new IR/type, lifetime tracker, NABI
profile or backend logic is added. See [ADR 0068](../decisions/0068-default-parameter-borrowing.md).

INFER-1 ends at semantic local construction. A reserved VAR token and dedicated
InferredLocalDeclarationSyntax retain source provenance; the bounded
`SemanticAnalyzer.check_inferred_local` authority checks the initializer without
a destination type and constructs existing exact local, storage and ownership
nodes. The shared call-result checker preserves exact generic specialization
and bounded struct COPY_VALUE producers. Checked has no inferred type/category;
Core, CFG, SSA, NABI, CABI and LLVM are unchanged and contain no inference
operation. See [ADR 0067](../decisions/0067-local-var-inference.md).

NUM-CONV-1 extends `as` through stage-owned scalar conversion nodes. The
LLVM-free NumericConversionKind/Policy authority reuses canonical IntegerType
signedness/ranges and F32Type/F64Type formats. Independent CFG/SSA verifiers check
an explicit ordered float→integer guard and its destination-specific proof.
The lexer retains suffix text only until semantic literal construction chooses
precision and rounds once using the unchanged exact decimal authority. See
[ADR 0066](../decisions/0066-explicit-numeric-conversions.md) and
[stage contracts](../ir/numeric-conversions.md).

BUFFER-1 adds [owned runtime arrays](../language/owned-runtime-arrays.md) as unique
cleanup contracts over existing SliceType identity. [Independent IR groups](../ir/owned-runtime-arrays.md)
carry complete PTR/I32 ownership through native [buffer-v8](../abi/native-buffer-v8.md)
boundaries. Core retains target-neutral allocation, while one
[host allocator strategy](../backend/host-buffer-allocation-v0.md) realizes it.
Concrete Resource/buffer locals and parameters share automatic RAII replacement;
class fields preserve existing definite-init, alias and destructor rules.
No universal aggregate SSA, runtime ownership flags, mandatory heap for buffer-free
code, or compiler dependency is introduced. See [ADR 0065](../decisions/0065-owned-runtime-arrays.md).

OWN-FIELD-1 adds deterministic RAII for explicit nominal Resource owner slots
in native classes. Shared field identities carry exact release contracts through
Checked and independent Core; CFG expands transfers and destructor epilogues to
concrete ownership actions; SSA and LLVM retain ordinary handles and memory.
The existing constructor analysis, object storage, Ownable specialization and
PTR/result-storage ABIs remain authoritative. See
[ADR 0064](../decisions/0064-owned-resource-fields.md) and
[owned-field IR](../ir/owned-resource-fields.md).

[STRUCT-ABI-1](../ir/struct-values.md) connects copyable concrete struct boundaries
to the existing leaf pipeline. Checked/Core retain exact COPY_VALUE contracts and
bounded Place/call producers. CFG/SSA carry ordinary leaf parameters, snapshots
and grouped call results. NABI adds aggregate-v7 physical plans; only LLVM uses
aggregate return carriers. One CopyabilityAuthority and one StructLeafOrder serve
whole copy and native boundaries. Parameter storage is independent, result values
have no source storage identity, and C ABI/generic Copy remain separate.

STRUCT-COPY-1 extends recursive storage with [Place-to-Place whole
copy](../ir/struct-copy.md). One stage-neutral recursive Copyability authority is
queried over each stage's exact field graph. Checked/Core keep structured copy
statements; CFG expands to complete leaf snapshots followed by writes. SSA keeps
ordinary scalar/vector values and existing promotion. Explicit Place validation
orders null traps without leaf reads. Copy adds no general aggregate Value,
aggregate ABI, runtime metadata or generic capability. Ownable and GEN1_PLAIN_COPY
remain unchanged. See [ADR 0061](../decisions/0061-whole-struct-copy.md).

GEN-1 adds [semantic generic functions](../ir/generics.md) above the existing
concrete pipeline. Definitions own exact lexical type parameters with bounded
GEN1_PLAIN_COPY capability and are checked once. Demand-driven Core substitution
uses canonical semantic identities, a global registry and recursion placeholders.
Concrete instances preserve resolved global targets and reach ordinary CFG/SSA/
NABI/LLVM without any generic type or runtime metadata. [ADR 0056](../decisions/0056-semantic-generic-functions.md)
freezes identity, scope, argument eligibility and future extension rules.

PROP-1 adds [computed property identities](../ir/properties.md) alongside fields
and methods in the native member namespace. Getter/setter identities extend the
common callable kinds and reuse the existing body, receiver, CFG, SSA and ABI
pipeline. Explicit exact accessor targets survive stage destruction, so property
reads and writes remain calls through verification and LLVM emission. No Place,
backing field, property runtime, virtual dispatch or production dependency is
introduced. [ADR 0055](../decisions/0055-native-computed-properties.md) freezes
these semantics and their future interface/storage extension points.

F64-1 adds [exact binary64](../language/f64.md) through a closed shared
BinaryFloatFormat/BinaryFloatValue authority. F32Type/F64Type remain distinct,
contextual decimals convert directly to their format, and explicit floating
widen/narrow nodes survive checked/Core/CFG/SSA lifetimes. F32 semantics/dumps are
preserved. Ordinary scalar storage, object fields and call ownership rules extend
without parallel architectures. NABI [fp64-v6](../abi/native-fp64-v6.md) adds one
F64 channel; pointers/slices remain their existing groups. LLVM realizes the
already-chosen type and bits as double. [ADR 0054](../decisions/0054-exact-binary64.md)
freezes the accepted floating semantics reused by PROP-1.

OBJ-RET-1 adds [owned object results](../ir/object-results.md) using caller storage and the existing ownership-result framework. Result storage and source provenance survive each stage independently. The physical signature is hidden PTR plus existing arguments returning PTR; no heap, copy, runtime active flag, new profile or CABI object support is needed.

OBJ-OWN-1 makes object transfer an explicit binding/call contract while keeping
ClassType and ObjectStorage identity unchanged. The existing owner slots,
possibility-state fixed point, borrowed argument events, pending moves and delayed
call commit now carry exact native class/destructor cleanup as well as Resource
cleanup. The one lexical planner orders fixed storage and owner responsibilities.
SSA uses original pointers and null disarming; NABI uses existing PTR and profiles.
Temporary-view lifetime checks close captured-base and same-call alias/forwarding
hazards within that same ownership analysis. See
[ADR 0052](../decisions/0052-transferable-object-ownership.md) and
[ownership IR](../ir/object-ownership.md).

OBJ-BOUND-1 extends shared ordinary parameter semantics to explicit borrowed
ClassType. The existing BORROWED_NOESCAPE contract and function lexical region
allow nullable, mutable, aliasable references, local copies and forwarding.
Class/struct methods and constructors reuse the same checker and object access
nodes. One exact ClassType parameter and operand survive Core/CFG/SSA; NABI alone
maps the boundary to existing PTR, with existing vector/slice profile selection.
No receiver redesign, ObjectStorage ownership transfer, cleanup change, runtime
metadata, object result or LLVM backend change is needed. See
[ADR 0051](../decisions/0051-borrowed-object-boundaries.md).

OBJ-LIFE-1 adds lifecycle authority to the existing ObjectStorage identity.
ConstructorSymbol and DestructorSymbol are distinct from MethodSymbol while sharing
callable bodies, parameters and physical lowering. Constructor INITIALIZING receivers
preserve exact field Initialize and definite/possible dataflow through SSA; successful
fallthrough precedes caller reference publication and destructor activation.
Core/CFG/SSA each retain independent lifecycle identities. The existing lexical
cleanup list contains both Resource slot and ObjectStorage actions, so return,
break, continue and loop backedge share deterministic LIFO order. References never
own cleanup. Existing PTR and v0-v5 profiles produce internal fastcc void ctor/dtor
functions using original caller storage. Traps never unwind; no runtime lifecycle
flag, stack, header, heap or production dependency is added. See
[ADR 0050](../decisions/0050-native-object-lifecycle.md) and
[lifecycle IR](../ir/object-lifecycle.md).

OBJ-1 introduces nominal ClassType references and distinct lexical object storage.
NativeInstanceSymbol and equivalent stage owners share member infrastructure
between StructSymbol and ClassSymbol. MethodSymbol, ReceiverSymbol and all existing
method/call stages remain one system. LexicalObjectStorageSymbol and independent
Core/CFG/SSA storage descriptors outlive reference rebinding; class field storage
is explicit memory while reference locals promote normally. Existing LexicalRegion
rules reject escapes. Explicit null validation precedes field RHS and method
argument effects, then forms the existing nonnull receiver contract. LLVM uses
private object layouts and lexical allocas, with a one-byte identity anchor for
empty objects. No heap, runtime descriptor, lifecycle machinery or explicit object
ABI channel is added. See [ADR 0049](../decisions/0049-native-object-identity.md)
and [object storage](../ir/object-storage.md).

METHOD-1 adds exact native struct member identity and an implicit storage receiver.
MethodSymbol belongs to one StructSymbol; specialized Checked/Core/CFG/SSA method
bodies reuse ordinary native call and function machinery. ReceiverType retains
exact StructType, non-owning/mutable/nonnull semantics, and no source pointer or
assignable-local behavior. Direct receiver use marks existing address-taken
storage per instance; declaring methods alone leaves instances scalarizable.
Field Places unify direct, pointer-alias and method mutation. Receiver evaluation
precedes ordinary ordered arguments and unchanged owned transfer commit. Existing
NABI PTR precedes scalar/vector/slice channels, with internal LLVM fastcc direct
calls. No vtable, RTTI, GObject, allocation or lifecycle machinery is added.
OBJ-1 classes reuse this member/call foundation through shared native instance owners.
See [method IR](../ir/methods.md) and [ADR 0048](../decisions/0048-native-struct-methods.md).

SLICE-1 adds [bounded borrowed views](../language/slices.md) over fixed array
storage. SliceType owns exact element identity; one SliceValue carries runtime
extent through Core, CFG and SSA promotion. Existing lexical borrow rules govern
copies/rebinding and permit overlapping mutation. SliceElementPlace uses ordinary
Load/Store with runtime bounds validation before RHS effects. LLVM alone chooses
`{ ptr, i32 }`, guards, empty-base handling and plain GEPs. No NABI/CABI slice
channel or runtime dependency is added. See [ADR 0046](../decisions/0046-bounded-borrowed-slices.md).

ARRAY-1 adds [fixed local arrays](../language/arrays.md) as explicit contiguous
storage aggregates. Canonical ArrayType is separate from VectorType, pointers,
and slices. ArrayElementPlace survives checked/Core/CFG/SSA stages with
exact storage, element type, length, integer ordinal and provenance. Ordered
bounds checks precede assignment RHS effects; LLVM alone realizes array GEP.
Arrays have no whole-value/ABI form and never decay. Numeric vector elements
remain whole Values after loads; lanes remain non-writable. This supplies the
storage/bounds foundation explicitly borrowed by SLICE-1.

VEC-MEM-1 extends the general typed-pointer memory foundation to numeric
VectorTypes: TypedPointerType<VectorType>, ordinary DereferencePlace, and
existing addressable local storage. Direct and indirect accesses remain coherent;
only addressed vectors cease promotion. Loads and stores use one whole vector
value, and extraction remains a value operation. Lexical lifetimes, aliasing,
null traps, ownership and physical predecessor authority are shared with DPTR.
Alignment is backend-owned and guaranteed by construction. Pointers use PTR,
independently of by-value vector-v4 channels. See [ADR 0044](../decisions/0044-vector-memory.md).

BIT-1 extends existing exact unary/binary authority for bitwise integer and eager
boolean operations. A separate checked/Core/CFG/SSA shift node preserves its
independent scalar count domain, exact result and invalid-count trap contract.
CFG orders evaluation; LLVM validates before physical normalization/splat and
flag-free shifts, using existing final-physical-predecessor authority. No type,
ABI profile, ownership model, Place or production dependency is added. See
[ADR 0042](../decisions/0042-bitwise-and-shift-semantics.md) and
[bit/shift IR](../ir/bitwise-shifts.md).

VEC-DOT-1 adds [four whole-vector dot/MAC special forms](../language/vector-dot.md)
through a bounded `VectorDotKind` and dedicated checked/Core/CFG/SSA nodes.
Integer products use source mathematical values and explicit accumulator modulo
semantics; strict F32 products and ascending additions each round separately.
One operation survives to SSA, while backend-private expansion may widen or
extract physical lanes. No source VectorType, ownership, memory or ABI model
changes. See [ADR 0041](../decisions/0041-vector-dot-products.md) and
[dot/MAC IR](../ir/vector-dot.md).

VEC-DSP-1 adds [eight reserved DSP special forms](../language/vector-dsp.md)
through a bounded `DspPrimitiveKind` and independent checked/Core/CFG/SSA nodes.
The scalar IntegerValue authority owns saturation and saturating conversion;
ICONV continues to own wrapping conversion. Shapes, operands and provenance stay
explicit, vector operations remain single SSA values, and left-to-right captures
preserve ownership boundaries. NABI/CABI/VAPI and vector storage identities are
unchanged. [ADR 0040](../decisions/0040-vector-dsp-foundations.md) records the
representation choice and exact backend derivations preceding VEC-DOT-1.

VEC-LANE-1 adds [vector component value operations](../language/vector-lanes.md)
through explicit checked/Core/CFG/SSA primitives. Constant extraction observes
a value without creating storage; insertion transforms the whole value.
Splat and shuffle evaluate once, while select eagerly evaluates mask/true/false
before one value operation. Each stage owns immutable ordinal/selector snapshots.
NABI vector-v4 and existing Places, ownership, dominance and scalar authorities
remain unchanged. Vector memory uses whole-vector load/insert/store. Writable indexing and
swizzles remain deferred without a lane Place. See [ADR 0038](../decisions/0038-vector-lane-primitives.md).

VEC-1 introduces [exact VectorType identity](../language/vectors.md) from an
existing scalar element plus fixed lane count. Dedicated construction/reduction
nodes retain one value through checked semantics, Core, CFG, and SSA; existing
Places/dominance/ownership remain authoritative. [NABI vector-v4](../abi/native-vectors-v4.md)
separates scalar and vector channel forms while retaining signedness. LLVM is the
physical realization and may legalize into SIMD or scalar operations. Source
dynamic/writable lane access, vector memory, C ABI, and const generics are not prerequisites or
part of this milestone. [ADR 0037](../decisions/0037-short-vectors.md) freezes the
boundary and future generic compatibility.

F32-1 adds [one binary32 semantic identity](../language/f32.md), a uint32 value
container, and a bounded exact decimal midpoint converter. Syntax retains the
float token; checking resolves bits once. Core/CFG/SSA retain them independently
of upstream graphs. Existing scalar operations, Places, promotion, and mutable
struct memory carry f32. [NABI F32/v3](../abi/native-f32-v3.md) is separate physical
authority; LLVM realizes it with float, bit-exact constants, and ordinary floating
operations. No host floating parser, production dependency, ownership redesign,
or positive CABI change is needed. [ADR 0036](../decisions/0036-binary32-semantics.md)
records the proof and the deliberately restricted target qualification.

INTS-1 introduces [six exact IntegerTypes](../language/integers.md) and one typed
bit-pattern value authority. `int` aliases canonical i32 by object identity.
Decimal context is resolved in semantics before the existing Core/CFG/SSA
pipeline; every stage retains exact width/sign without source reparsing. Generic
Places and scalar promotion handle narrow fields and loop carries unchanged.
[Native integer v2](../abi/native-integers-v2.md) preserves signedness while LLVM
realizes exact-width operations and guarded division. CABI and ownership
architecture remain unchanged. See [ADR 0035](../decisions/0035-exact-width-integers.md).

OWNBOUND-1 adds native ownership call contracts for exact nominal Resource
parameters and results. Owned parameters normalize from incoming values into the
existing root cleanup slots. Checked/Core/CFG retain explicit argument and return
transfers; flow validates semantic moves at expression positions, then SSA delays
physical caller nulling until call commit and disarms return sources before
cleanup. Native and foreign owned calls share the producer consumption contract.
NABI/LLVM remain ordinary PTR/fastcc with no runtime ownership metadata or new
dependency. See [ADR 0034](../decisions/0034-owned-native-boundaries.md) and
[boundary IR](../ir/ownership-boundaries.md).

RESOURCE-1 adds VAPI-only nominal handle declarations and type collection before
signature resolution. HandleSymbol and canonical HandleType separate semantic
identity from ownership responsibility and PTR transport. CoreHandle, CfgHandle
and SsaHandle retain exact nominal tokens with independently owned cleanup
contracts. Type identities have no upstream backlinks, so stage lifetime
independence holds. The local ownership solver and LLVM backend are unchanged.
See [ADR 0033](../decisions/0033-nominal-resource-handles.md).

Source through explicit CFG, flow validation, scalar SSA, native scalar
signature planning, verified LLVM body lowering, and host-native executable
production exist through ASTRA-VEC-LANE-1, including fixed-lane vectors/masks, exact binary32 and exact-width native integers, owned native Resource boundaries and foreign handles with lexical
cleanup, explicit moves, temporary borrowed owner parameters, native stored
borrows, and external typed C declaration
input with symbol aliases and descriptive headers, scalar C imports and exports,
short-circuit bool expressions and exact break/continue targets
and cyclic while control flow.
The current pipeline is:

```text
Astra source
    ↓
source file / byte spans
    ↓
lexer / tokens
    ↓
parser
    ↓
syntax tree
    ↓
checked semantic model ← normalized foreign declaration input ← VAPI syntax
    ↓
semantic Core IR / values / Places / initialize / store / owned acquisition
    ↓
explicit CFG / lexical cleanup insertion / terminators / reachability / flow validation
    ↓
reachable scalar SSA / ordered cleanup / block arguments / edge arguments
    ├──────────────────────────→ verified native scalar ABI signature sidecar
    ├──────────────────────────→ verified C import/export/cleanup ABI signature sidecar
    ↓
LLVM backend (consumes SSA, NABI, and CABI)
    ↓
verified target-independent LLVM IR
    ↓
host target machine / triple / data layout / backend-private launch wrapper
    ↓
verified configured LLVM module → native relocatable object
    ↓
configured host C driver / user link objects / CRT → transactional executable publication
```

Property reads/writes now retain exact property/accessor identities on ordinary
direct-call operations through SSA; existing object construction also retains
its semantic identity. Future virtual/interface calls, runtime type checks and
lazy-property operations must preserve their contracts until the appropriate
lowering stage. Those future operations remain unimplemented.

Local Places now represent authoritative storage independently of computed values
and LLVM pointer types. Non-address-taken scalar Places disappear during SSA promotion
because their storage identity is unobservable and OWN-1 cleanup obligations are already
explicit CFG effects. Address-taken integer/f32 locals and aggregate fields retain
memory operations. Pointer locals themselves remain promotable.
Future aggregate ownership and destructible native values must establish their
own storage and promotion rules.
Native ABI decisions, C/VAPI
interoperability, and any future GObject adapter each belong at explicit physical
lowering boundaries. The native object model is independent of GObject.

Freestanding, embedded/Dreamcast, SIMD/short-vector, and AEP-class DSP/numerical
requirements constrain future design. No runtime library, universal allocation
policy, unwinder, target ABI, or object layout is frozen here.

## What exists in ASTRA-LOOP-1

`src/main.vala` provides help/version, `--parse`, `--dump-syntax`, `--check`,
`--dump-semantics`, `--dump-core`, `--dump-cfg`, `--dump-ssa`, `--dump-nabi`, and `--dump-llvm` developer modes. `src/config.vapi` exposes
build-generated version/milestone constants. Parsed source can be checked and
translated to verified Core, CFG, and SSA. `--check` includes reachability, flow
validation, SSA construction/verification, native signature planning/verification,
direct-call physical compatibility, LLVM body lowering, and LLVM verification.
Plain source invocation produces host-native `a.out`; `-o OUTPUT` works before
or after the source. Executable compilation separately requires `int main()`.
Check/dump modes retain their stage behavior without executable entry/target/link
requirements.

`src/source/` owns byte buffers, half-open spans, line/column mapping, and
diagnostics. `src/syntax/` contains the streaming lexer, span-based tokens,
syntax-only nodes, recursive-descent/Pratt parser, and internal syntax dumper.
A token/span retains its source file; it never borrows a temporary lexer buffer.
Syntax nodes retain operator and punctuation tokens, exact names/literal spellings,
and explicit parentheses. No node has a resolved type, symbol, ownership fact,
or LLVM representation. `ParseResult` separates success from a diagnostic;
ordinary parse errors do not use host exceptions.

`src/semantic/` adds the separate checked model:

```text
src/semantic/
	analyzer.vala       signature collection, body checking, SemanticResult
	types.vala          canonical Astra int/bool/void/void* identities and truth payloads
	int-value.vala      immutable int authority, range checks, reference arithmetic
	operators.vala      shared semantic prefix/binary operator identities
	symbols.vala        function, parameter, and local symbols
	checked-nodes.vala  typed expressions, locals/assignments, structured if/while/break/continue/returns and exact loop targets
	semantic-dump.vala  deterministic internal checked-model dump
```

The analyzer resolves all signatures before checking bodies. Checked nodes use
semantic operator enums, type objects, and distinct direct parameter/local references.
Only the analyzer depends on syntax classes; other semantic objects retain
source spans for provenance. Parentheses normalize away without modifying syntax.
SCALAR-1 checks decimal range and forms direct signed literals, including
parenthesized INT_MIN, before constructing checked integer nodes. Each carries
an immutable AstraIntValue alongside its canonical int type and source span.
`int` is signed 32-bit (-2147483648 through 2147483647), with wrapping arithmetic,
truncating division/remainder, zero-divisor runtime traps, and signed comparisons.
INT_MIN/-1 wraps to INT_MIN; INT_MIN%-1 is zero. Bool remains exactly true/false
without integer coercion. B1 transport is a separate downstream physical
authority and leaves memory layout open. See
[scalar semantics](../language/scalars.md).
`BuiltinTypes` owns one type universe per analysis, retained by `CheckedProgram`;
function symbols own ordered parameters, checked functions own ordered locals,
and expressions retain their types and referenced declarations. No containing-function back reference or ownership cycle
is needed. See [ADR 0006](../decisions/0006-semantic-model.md).
Locals require initializers and become visible only after initializer checking.
Lexical frames cover the function body and nested branch/loop blocks, with lookup
through enclosing locals to parameters. Visible-name shadowing is rejected for
now; sibling declarations may share spelling but retain distinct symbols and
function-wide source-order ordinals. General shadowing remains undecided.
Assignment targets only visible locals; parameter assignment is unsupported.

`src/core/` adds the typed semantic computation representation:

```text
src/core/
	core-nodes.vala  declarations, Places, typed values, initialize/store/if/return
	builder.vala     checked-model conversion using temporary identity maps
	verifier.vala    deterministic internal structural checks
	core-dump.vala   verified internal Core dump
```

Core has its own function/parameter/Place/value identity and retains the existing
semantic type objects. All Core declarations are created before bodies are
translated. Parameter values refer directly to Core parameters; names are
debugging/source spellings. Core nodes retain source spans, not checked nodes,
semantic symbols, tokens, or syntax objects. Core remains usable after frontend
model destruction, including semantic integer values, exact source provenance,
and source location lookup. CFG and SSA likewise retain AstraIntValue directly
without re-parsing text or retaining upstream constant nodes.

Blocks preserve ordered initialization, stores, structured CoreIf, and returns.
Each CoreIf owns a bool condition and then/optional else CoreBlocks. Values
preserve boolean, integer, parameter, load, prefix, and binary computations without
simplification. Bool has semantic identity independent of physical representation.
Core local references lower through exact symbol-to-Place maps to explicit loads.
Core verification
checks internal type/binding/statement invariants and raises internal errors;
it does not diagnose source errors or analyze reachability. Core is structured,
with no CFG/SSA, physical storage, LLVM, or ABI representation.
OWN-1 adds acquisition obligations and MOVE-1 adds exact transfer events tied
to its structured blocks. See
[ADR 0007](../decisions/0007-core-ir.md) and the
[implemented operation inventory](../ir/core-ir.md).

`src/cfg/` adds explicit control flow downstream of verified Core:

```text
src/cfg/
	cfg-nodes.vala     declarations, Places, blocks, values, instructions, terminators
	cfg-builder.vala   verified Core conversion with independent CFG identities
	cfg-verifier.vala  structural checks, including entry and successor ownership
	reachability.vala  iterative entry/successor traversal and separate result
	predecessors.vala  deterministic reachable predecessor snapshots
	ownership-flow.vala ownership-state fixpoint and source-use validation
	flow-checker.vala  reachable ownership/completion validation and diagnostics
	cfg-dump.vala      verified dump with deterministic IDs and reachability
```

Functions own ordered local Places and blocks plus an explicit entry. Every block
has ordered Initialize/Store instructions and exactly one completed terminator:
Return, FunctionEnd, Branch, or ConditionalBranch. Internal block reservation
permits forward identity; completion is write-once and verified. Terminators alone
define edges. Branch has one successor; ConditionalBranch has true/false targets
and a bool CfgValue. Return and FunctionEnd have none. Each CoreIf reserves then,
optional else, and join before recursive arm lowering; fallthrough arms branch
to the join, while returns terminate directly. Outer Places remain shared across
arms and join loads. Post-return statements
become disconnected blocks and survive without unreachable-code warnings.
Reachability follows the designated entry and terminator successors, never
source order. A reachable `FunctionEnd` is valid for void and receives a source
diagnostic for non-void returns. Empty non-void functions still have valid semantic/Core models
and structurally valid CFG; completion validity is a distinct control-flow check.

CFG owns its functions/parameters/Places/blocks/instructions/values and retains only legitimate
shared type/operator/source authorities. It survives destruction of Core and
earlier models. OWN-1 adds explicit ordered cleanup instructions; MOVE-1 adds
transfer instructions and ownership dataflow. CFG itself has
no SSA, optimization, physical storage,
or LLVM representation. See [ADR 0008](../decisions/0008-explicit-cfg.md)
and the [CFG inventory and CLI stage distinction](../ir/cfg.md).
[ADR 0010](../decisions/0010-conditional-control-flow.md) freezes bool conditions,
lexical branches, and explicit joins. Constant conditions keep both edges;
unreachable joins remain present. Short-circuit operators are deferred.
LOOP-1 adds structured CheckedWhile/CoreWhile, lowered only at CFG construction
to reserved header/body/exit blocks with ordinary branch backedges. Cyclic
reachability, dominance/frontiers, initialization-restricted promotion, and
dominator-tree renaming require no loop-specific SSA handling. CFG/SSA successor
references expire through WeakRef without owning blocks. LLVM realizes header
arguments as cyclic phis with exact physical predecessors; NABI and EXEC
architecture remain unchanged. See [cyclic IR](../ir/cyclic-control-flow.md).
The [Place decision](../decisions/0009-place-storage.md) and
[storage inventory](../ir/place-storage.md) record values versus storage,
explicit loads, and initialization versus replacement. Place identity is not a
backend pointer or a requirement for a physical memory location.

`src/ssa/` projects reachable CFG after flow validation. Predecessor snapshots
and iterative dominator analysis derive from CFG terminators; deterministic
immediate dominators, tree children, and dominance frontiers support promotion.
Iterated-frontier placement respects initialization dominance as a branch-local
availability boundary. Dominator-tree renaming replaces local storage with
reaching SSA definitions and terminator-carried arguments into block parameters.
SSA flattens remaining expression trees into single-result operations, without liveness
or general optimization. Function/block/value identities belong to SSA and
survive destruction of CFG and earlier models. Types and provenance remain
semantic. See [ADR 0011](../decisions/0011-ssa-block-arguments.md) and the
[SSA representation, algorithms, and numbering](../ir/ssa.md).

SSA verification checks graph structure, semantic types, edge arguments, unique
definitions, and domination of uses independently of CFG analysis. Function
arrays own blocks; terminator-owned edges weakly reference successors, avoiding
reference-counting cycles. Block parameters never store predecessor tables.
Core/CFG remain source-preserving; SSA omits unreachable blocks without folding
constant conditions. `--dump-cfg` and `--dump-ssa` expose this boundary directly.

`src/nabi/` establishes the first physicalization boundary:

```text
src/nabi/
	native-model.vala        ABI/scalar/linkage enums, channels, signatures, identities
	native-type-mapper.vala  semantic int → I32, bool → B1, void result → absent
	native-builder.vala      verified SSA → signature sidecar, temporary identity map
	native-validator.vala    exact declaration and direct-call physical compatibility
	native-verifier.vala     independent structural verification
	native-dump.vala         verified deterministic physical signatures
```

NativeAbiProgram owns functions and signatures, with one direct source-order
channel per parameter and an optional direct scalar result. It owns no bodies,
calls, blocks, values, or control flow; SSA remains that authority. All physical
function identities/signatures exist before call validation. The exact temporary
SsaFunction → NativeFunction map is discarded before planning returns. Names and
SourceSpan provenance are retained without upstream identities or SemanticType
objects. A GLib WeakRef program owner enforces function membership without cycles.

`NativeAbiVersion.SCALAR_V0` is an unstable compiler-internal artifact identity.
`NativeScalarType.I32` transports exactly 32 bits with Astra signed semantics;
`B1` transports exactly false/true without defining bool memory layout or a
machine carrier. Void is an absent NativeResult. Every function has
`NativeLinkage.NATIVE_INTERNAL`; there are no stable linker names, hidden
channels, target conventions, C signatures, or LLVM types. See
[native scalar v0](../abi/native-scalar-v0.md) and
[ADR 0014](../decisions/0014-native-scalar-abi.md).

Meson's `frontend_dependency` contains source/syntax and the existing host
dependencies. `semantic_dependency` adds the semantic sources on top of it.
`core_dependency` adds Core construction, nodes, verification, and dumping.
`cfg_dependency` adds the explicit CFG layer; `ssa_dependency` adds reachable
scalar SSA and CFG analyses. `tests/ssa/` builds analysis, promotion/lifetime,
and standalone SSA executables. The standalone SSA target uses only its own
nodes/verifier/dumper plus source/type/operator/integer-value authority, excluding CFG and all
other upstream representations. `tests/frontend/`, `tests/semantic/`,
`tests/core/`, and `tests/cfg/` each build an executable
with no LLVM bindings or link dependency. All include API tests and CLI goldens.
`nabi_dependency` adds the physical sidecar and SSA-dependent planner/validator.
`tests/nabi/` builds the pipeline/call/lifetime suite and a standalone model,
verifier, and dumper with only SourceFile/SourceSpan/Diagnostic. The standalone
physical target excludes semantic types and every upstream stage. Both NABI
executables join the LLVM firewall matrix.
Standalone Core and CFG executables compile their nodes, verifier, and dumper
with only source provenance, diagnostics, and semantic types/operators/integer values. The CFG
target also includes reachability/flow checking. Core, checked/syntax models, and
the CFG builder are omitted from that target; the Core target likewise excludes
checked/syntax models and its builder. This establishes compiled structural
dependency firewalls. `tests/place/` adds shared CLI storage fixtures;
`tests/branch/` adds bool, conditional, join, nested scope, and diagnostic goldens.
Where `ldd` and `nm` are available, tests reject LLVM linkage/backend symbols
in upstream and standalone executables. The LLVM smoke is the negative control.
`astrac` and backend tests intentionally link LLVM; positive checks also use
`readelf` to require exactly the shared library selected by llvm-config 22,
with a frontend executable as their opposing negative control.

`src/backend/llvm/` now contains the real scalar body backend. LlvmLowering
verifies SSA/NABI and their ordinal signature/call correspondence, declares all
internal fastcc functions, then lowers bodies through exact identity maps.
LlvmTypeMapper realizes NABI I32/B1/absent result as i32/i1/void; semantic values
pass through NativeTypeMapper first. Block arguments become phis. Physical end
blocks track arithmetic splits, and parallel SSA edges get separate physical
edge blocks. Wrapping arithmetic has no no-overflow flags, comparisons are
signed, and guarded division/remainder preserves traps and exceptional results
in stored SSA effect order. No optimization passes run.

LlvmModuleArtifact owns only its module/context, disposes them in dependency
order, and supports verification and deterministic LLVM printing after every
upstream graph dies. Bindings use only the LLVM 22 C API. Test-only inspection
bindings stay separate from production. See
[the backend inventory](../backend/llvm-scalar-v0.md) and
[ADR 0015](../decisions/0015-llvm-scalar-lowering.md).

`tests/smoke/llvm.vala` invokes that fixture in a separate, uninstalled executable.
The public `astrac` driver has no smoke switch and does not invoke or link the
test fixture. It now links libLLVM for real lowering through the C toolchain.
The C file under `capi/` is a
configure-time header/link probe, not a backend implementation or C++ shim.

`src/driver/` resolves source entry once to exact SSA identity, orchestrates
target configuration/object emission, invokes Meson's configured host C driver
with argv, and publishes successful output by same-filesystem rename. The
backend retains only LLVM entry handles and synthesizes external default-CC
`main` calling the internal fastcc Astra function. Recursion continues to use
the native function. Target-machine/data ownership stays under the LLVM backend;
object emission is independently usable without executable linking. There is
no C FFI, cross compilation, stable object ABI, or explicit optimizer pipeline.
See [native execution](../backend/native-execution-v0.md) and
[ADR 0016](../decisions/0016-host-native-execution.md).

Vala-generated C is only a host implementation artifact. GLib/GObject are host
dependencies; generated programs need only the ordinary host CRT, with no
Astra target runtime library.
Directories are added only when an implementation needs them.

## Direct function identity and effects

CALL-1 resolves direct identifiers once through compilation-unit function
authority. Every body-building stage creates all functions before translating bodies, using
exact FunctionSymbol → CoreFunction → CfgFunction → SsaFunction maps. Completed
stages never retain upstream callee authority or look up calls by spelling.
Programs own function entities; call sites hold non-owning GLib WeakRef targets
so self/mutual recursion is reclaimable and expired targets can be rejected.

Checked/Core represent call values and statements; CFG normalizes calls into
ordered instructions and call-result Values; SSA retains calls and maps their
results into ordinary SSA definitions. Call targets are not CFG successor edges.
Left-to-right expression/argument evaluation is now a language rule, and calls
are conservatively effectful. Scalar Place promotion remains valid because
caller locals have no alias channel. Semantic signatures are distinct from
physical/native ABI signatures, which NABI-1 plans separately. No callable
values, overloads, ownership channels, or stable mangling are introduced. See
[ADR 0012](../decisions/0012-direct-call-semantics.md).

## Scalar authority and trap ordering

`AstraIntValue` uses private int64 implementation storage for the exact signed
32-bit domain. Checked factories and safe wider arithmetic establish language
meaning independently of host overflow, target layout, or LLVM behavior. A
standalone reference suite tests wrap/div/rem/compare and explicit
`ZERO_DIVISOR_TRAP` outcomes; optimized trapping UB instrumentation is included
where supported without a sanitizer runtime dependency. Ordinary literal checking
uses exact value factories. CONST-1 additionally reuses the expanded finite-width
integer value operations in its bounded semantic evaluator.

Source spelling stays in SourceSpan; downstream dumps print canonical signed
values. Historical huge magnitudes remain syntax successes and become semantic
rejections before Core. Valid leading-zero boundary constants survive all
stage-lifetime tests with their type and exact provenance.

Division/remainder traps make arithmetic observably ordered relative to calls.
CFG inserts a narrow evaluation instruction when a potentially trapping tree
must finish before calls in a later operand/argument. Its independent result
has one definition preceding the use on every incoming path. SSA maps that result to the ordinary
lowered computation at that position. No Place, new SSA operation, or change to
call identity/dominance/edges is introduced. [ADR 0013](../decisions/0013-scalar-semantics.md)
records the concrete CALL-1 ordering defect and the alternatives considered.
Semantic width alone does not choose physical transport. NABI-1 separately
establishes I32/B1 channels without choosing C ABI or LLVM types. LLVM-1's body
lowering preserves wrapping, signed comparisons, explicit zero-divisor traps,
INT_MIN/-1 and INT_MIN%-1 results, and trap/effect order. Signatures neither
replace those contracts nor introduce body operations to implement them.

## Loop-control target authority

ASTRA-LOOPCTRL-1 adds exact structured loop identities at the checked and Core
stages. CheckedWhile owns a CheckedLoopTarget; semantic analysis resolves
CheckedBreak/CheckedContinue through an active-target stack once. CoreBuilder
translates exact target objects into CoreLoopTargets and structured
CoreBreak/CoreContinue. CfgBuilder translates exact Core targets into reserved
header/exit blocks and ordinary Branch terminators. No downstream pass derives
a target from lexical depth, source parents, or block proximity.

Targets carry function-local source-preorder ordinals for dumps, with non-owning
WeakRef transfer references and no parent backlinks. Downstream graphs outlive
upstream targets and remain reclaimable. Generic CFG/SSA analyses and LLVM
physical predecessor machinery handle multiple backedges and exits unchanged.
NABI, Place, call, scalar, and native execution architecture require no change.
See [ADR 0018](../decisions/0018-loop-control-targets.md).

## Short-circuit expression normalization

[ADR 0019](../decisions/0019-short-circuit-expression-control.md) adds a distinct
ShortCircuitExpressionSyntax, CheckedShortCircuitExpression, and CoreShortCircuitValue.
The Core structure owns conditional RHS semantics. CFG alone introduces evaluation
entry/RHS/join blocks and compiler-generated bool Places, with a current-block
continuation authority. Earlier effects retain their order across expression splits.
Generic scalar promotion produces ordinary bool block arguments with copied
synthetic debug origins. The existing LLVM branch/phi path realizes the result;
NABI and the backend implementation are unchanged. Dedicated per-evaluation regions
preserve the initialization-dominance rule inside loops, with no liveness or
fictitious values. Standalone and lifetime/firewall tests preserve every boundary.
See [the stage inventory](../ir/expression-control-flow.md).

## Explicit C import boundary

CABI-1 separates semantic callable domains at lookup. FunctionSymbol and
CFunctionSymbol derive from DirectCallableSymbol with explicit NATIVE/C domain;
imports retain ForeignAbi.C and exact external symbol identity. Native checked
bodies and foreign declarations have distinct ownership. Independent Core,
CFG, and SSA imported-function objects and C call nodes preserve that domain.
All transitions use temporary object-identity maps completed before body work.

NABI remains native-only. src/cabi/ owns a separate physical scalar profile,
I32 parameter/result channels, optional results, import symbols, verifier, and
dumper. Its model compiles without semantic or upstream-stage authority, and its
builder/validator remain LLVM-free. Future VAPI-like input creates the same
semantic foreign declarations; metadata never redefines native semantics.

LLVM uses native internal/fastcc and C external/default-CC in one module, with
separate physical mappers and exact call bindings. Astra's effect/evaluation
order applies before crossing either boundary. Link-time symbol availability
is independent of source/ABI validity. No native ABI, scalar, SSA, loop, or
short-circuit redesign is required. See [ADR 0020](../decisions/0020-c-scalar-imports.md).

## C export attachment and physical ingress

An exported Astra definition follows the unchanged native pipeline:
FunctionSymbol → CoreFunction → CfgFunction → SsaFunction → NativeFunction →
internal fastcc LLVM body. Program-owned CExportSymbol/CoreCExport/CfgCExport/
SsaCExport metadata weakly targets the exact native identity at each stage.
Temporary maps translate targets without names or retained upstream graphs.
Native callers and recursive calls never target export metadata or wrappers.

CABI planning consumes verified SSA plus NABI and adds CAbiExport contracts beside
existing CAbiFunction imports. Each contract independently owns its external
symbol, scalar C signature, export ordinal, native target ordinal, and provenance.
The standalone physical model survives both inputs. NABI remains native-only;
CABI remains foreign authority, and C I32 is distinct from native I32.

Only LLVM generates wrapper bodies: external ccc entry → one exact internal
fastcc call → return. They survive ordinary object emission and C linkage while
native implementations remain local. Exported main is stage-valid but collides
with EXEC's launch wrapper. No wrapper SSA, native ABI redesign, header generation,
C bool, pointers, ownership, or shared-library mode is introduced. Future VAPI
feeds import declarations through the existing boundary rather than defining
exports. See [ADR 0021](../decisions/0021-c-scalar-exports.md).


## External foreign declaration frontend

`src/vapi/` owns an independent lexer, tokens, syntax, parser, and normalizer.
Its standalone frontend uses only SourceFile/SourceSpan/Diagnostic and GLib;
it links neither Astra syntax nor semantics/IR/ABI/LLVM. The normalizer copies
ordered declarations into semantic ForeignDeclarationInput records. Those
records contain spelling/provenance spans, ordered parameter records, and
immutable origin-independent CForeignMetadata, with implicit C-import meaning.
Local Astra names and external C symbols have distinct authorities. Source
externs immediately create the same defaults in CFunctionSymbol. VAPI `CCode`
syntax may override the physical symbol with `cname` and retain one descriptive
`cheader_filename`; unknown/duplicate keys reject. SemanticAnalyzer resolves
the canonical signature and constructs the existing CFunctionSymbol class.

All VAPI files are read, parsed, and normalized before semantic checking.
External signatures are validated, all source signatures are collected, and
external declarations merge by local Astra name into the same direct-call
namespace before bodies.
Duplicate names get one deterministic error at the later declaration in merge
order: source externs first, then CLI file order and file declaration order.
Source extern diagnostics and source-only dump ordering remain unchanged.

No VAPI node or origin branch exists in Core, CFG, SSA, NABI, CABI, LLVM, or EXEC.
SourceSpan retains diagnostic provenance without keeping the VAPI tree alive.
CABI remains the physical C-call authority, its standalone target remains VAPI-free,
and NABI remains native-only. VAPI paths never become linker inputs. Exact
source-extern/VAPI differential and weak-reference lifetime regressions protect
these boundaries. See [ADR 0022](../decisions/0022-vapi-foreign-declarations.md).

META-1 retains CForeignMetadata on CFunctionSymbol, CoreCFunction, CfgCFunction,
SsaCFunction, and CAbiFunction, never on call instructions or arbitrary values.
The shared `src/foreign/` model depends only on GLib and source provenance; it
contains no syntax or semantic type authority. CABI owns physical external-symbol
uniqueness across imports and exports. Earlier IR verifiers check structural
identities/signatures, allowing independent local call targets to reach that
physical check. CABI's exact symbol feeds LLVM declarations; call lowering keeps
its exact identity maps. Header metadata survives CABI independently of SSA,
but never affects CABI channels or LLVM. Header names are not opened, parsed,
required to exist, or converted into link inputs. NABI and source-export policy
remain unchanged. Richer types, ownership transfer, header parsing, source/export aliases,
and library metadata remain future work. See
[ADR 0023](../decisions/0023-vapi-c-metadata.md) and
[metadata format v0](../vapi/vapi-c-metadata-v0.md).

## Opaque raw-pointer extension

PTR-1 adds one canonical RawPointerType with the universe's void pointee and an
explicit null value at each semantic IR stage. No host pointer typedef, numeric
width, LLVM type, ownership policy, or VAPI syntax becomes semantic authority.
Pointer locals use ordinary Places and generic SSA promotion, because their
storage addresses cannot escape. Future addressability/ownership work must
revisit that proof.

Independent native PTR and C PTR channels select scalar-ptr-v1 only when the
corresponding domain has a pointer signature. Pointer-free domain profiles stay
scalar-v0. Separate backend mappers realize both as LLVM ptr; null/equality/phis
need no integer conversion. Native functions remain internal/fastcc and C
imports/wrappers external/ccc. C metadata and header names remain orthogonal to
pointer semantics. See [ADR 0024](../decisions/0024-opaque-raw-pointers.md) and
[raw pointers](../language/raw-pointers.md).

## Native local aggregates without layout

STRUCT-1 adds [top-level native structs](../language/structs.md), scalar fields,
complete named initialization, and field access/assignment. The compiler collects
nominal type/field symbols before function bodies. Core and CFG independently own
struct/field descriptors and canonical FieldPlaces projecting exact aggregate
local bases. Shared StructType has no symbol/syntax backlink. Written initializer
order and complete-local visibility survive ordinary scalar Initialize/Load/Store.

Generic SSA promotes non-address-taken fields independently, excluding bases;
that path retains only ordinary scalar definitions and copied debug origins.
It needs no physical aggregate representation or new ABI channel. See [ADR 0025](../decisions/0025-native-local-structs.md) and
[field Places](../ir/field-places.md). Aggregate values, function channels, layout,
C/VAPI structs, escaping references, and native struct ownership are deferred.

## Typed borrows and explicit memory

DPTR-1 generalizes TPTR-1 into one canonical TypedPointerType for supported
integer/f32 and exact nominal StructType pointees. RawPointerType denotes only
opaque void*, independently of that constructor. Contextual null is the only new contextual typing rule; distinct
pointees and void* remain incompatible. Typed native parameters/locals work;
results, fields, and C/VAPI channels reject. `&direct_local` of a supported integer, f32, or native struct is the only address source. BORROW-1 makes it a general expression
with semantic lifetime checks for stored pointer values. Each checked block owns
an exact LexicalRegion with a GLib.WeakRef parent. Local declarations own their
regions; native parameters use the function root. Null imposes no lifetime
requirement, addresses use pointee regions, and pointer-local reads conservatively
guarantee their own regions. A source must equal or enclose every destination
pointer region. This admits same-scope late borrows and outer to inner copies,
rejects inner to outer stores, and permits transitive/recursive native calls.

Region ordinals restart per function in source preorder and serve only debugging.
Checked block containment owns the region tree; locals and queried provenance
may retain nodes but no region owns a symbol or block. Regions reclaim before
Core. Downstream DataPointerProvenance snapshots preserve origin/region ordinals
for source addresses and dereference Places, without a checked lifetime graph
or runtime borrow checks.
See [ADR 0027](../decisions/0027-lexical-borrow-regions.md).

Addressability is explicit LocalSymbol/CoreLocalPlace/CfgLocalPlace authority
for the whole function. Address-taken scalar locals, direct address-taken fields,
and exact indirect field/dereference Places cannot scalar-promote. SSA owns layout-free struct descriptors,
addressable storage, and direct/indirect memory Places. Ordered
AddressOf/Initialize/Load/Store coexist with scalar SSA and existing calls/control
flow. SsaAddressableLocal generalizes prior struct storage; SsaLocalMemoryPlace
and SsaDereferencePlace join the existing field memory hierarchy. Untouched
scalars/structs and pointer locals still promote normally.

Only the backend materializes required named LLVM structs, entry allocas, and
exact scalar alloca/load/store or struct field GEP/load/store. Null guards trap
before indirect access and after assignment RHS effects; existing physical end
tracking preserves phis. Scalar dereference captures its pointer base before
the RHS; struct field assignment retains its existing RHS-first order. Native
T* still uses PTR; CABI/VAPI remain excluded. No numeric alignment or native
layout promise is exposed. See [ADR 0043](../decisions/0043-typed-data-pointers.md)
and [dereference Places](../ir/dereference-places.md).
Native PTR remains sufficient; C PTR remains void*-only. Physical layout is
private, target-dependent, and never semantic field identity. See
[ADR 0026](../decisions/0026-typed-struct-pointers.md),
[addressable storage](../ir/addressable-storage.md), and
[backend storage](../backend/native-struct-storage-v0.md).

## OWN-1 ownership pipeline

VAPI owned-result metadata normalizes into generic immutable foreign contracts.
Semantic collection interns cleanup identities, classifies checked call results,
and establishes CheckedOwnedLocalDeclaration responsibility in the existing
LexicalRegion. CoreOwnedLocal and CoreInitialize.acquisition preserve that
responsibility, with the corresponding CoreBlock as normalized lexical authority.
CFG's temporary stack inserts exact reverse cleanup effects on normal exits after
return-expression evaluation. SSA promotes pointer locals and retains ordered,
resultless cleanup instructions. CABI owns distinct physical cleanup functions;
LLVM emits null guards and ccc calls using existing physical end-block tracking.
Each stage maps exact identity once and can release upstream ownership graphs.
OWN-1 itself added no NABI change, runtime destructor stack, owner borrowing into
calls, native ownership, or unwinding. OBORROW-1 and OWNBOUND-1 extend call contracts
while preserving that cleanup machinery. See [ADR 0028](../decisions/0028-owned-foreign-handles.md).

## MOVE-1 ownership pipeline

CheckedOwnershipMove resolves an exact source and contract. CoreOwnershipTransfer
and CfgOwnershipTransferInstruction retain transfer meaning and stage-owned
source/destination identities. The existing lexical cleanup stack records both
acquired and transferred owners. CfgFlowChecker runs deterministic reachable-CFG
ownership dataflow to a loop fixpoint, then rejects moved/maybe-moved source uses.

SSA normalizes validated transfer to old-source destination and source-null
pointer definitions. Conditional values use pointer phis; cleanup guards use
existing physical predecessor tracking. No NABI/CABI/VAPI or production LLVM
implementation change is required. Analysis maps die before downstream stages;
Struct* borrow analysis remains independent. See [ADR 0029](../decisions/0029-ownership-transfer.md),
[ownership flow](../ir/ownership-flow.md) and qualification.

## Temporary borrowed owner views

OBORROW-1 adds origin-independent pointer parameter contracts to checked/native
and imported declarations through Core, CFG, SSA and CABI. Native expression
context checks enforce noescape without general void* alias dataflow. Explicit
CheckedOwnedBorrowValue and CoreOwnedBorrowValue preserve the owner/parameter
boundary. Ordered CFG borrow events reuse MOVE-1 flow, require OWNED and preserve
it. SSA captures the reaching ptr and drops the event, leaving NABI/CABI physical
channels and LLVM lowering unchanged. Struct* lexical borrowing remains separate.
See [ADR 0030](../decisions/0030-borrowed-owner-parameters.md).

## RELEASE-1 ownership pipeline

ReleaseStatementSyntax → CheckedOwnershipRelease → CoreOwnershipRelease →
CfgOwnershipReleaseInstruction preserves exact owner, cleanup and provenance.
Semantic checking proves an exact owned void* local; the existing reachable CFG
fixpoint proves `{OWNED}` and transitions to `{RELEASED}`. OwnershipState now
represents finite sets over OWNED/MOVED/RELEASED with union joins, separate from
pointer nullness and lexical scope. Borrow preserves OWNED, move transfers it,
and release ends responsibility without a recipient.

SSA emits ordered cleanup(current) and defines current=null, keeping lexical
cleanup sites intact. Conditional release uses pointer block parameters and LLVM
pointer phis. Existing CAbiCleanupFunction, ccc null guards and physical end-block
tracking suffice; NABI/CABI/VAPI/backend production models remain unchanged.
No runtime state or dependency is introduced. See [ADR 0031](../decisions/0031-explicit-release.md),
[release IR](../ir/ownership-release.md), and qualification.

## REARM-1 ownership pipeline

Existing assignment syntax recognizes an owned void* destination and creates
CheckedOwnershipRearmAssignment → CoreOwnershipRearm →
CfgOwnershipRearmInstruction. Each stage retains its own exact owner, producer,
cleanup contract and provenance. Semantic/Core checking proves a direct owned
producer with the slot's same contract; CFG validates one immediate result
consumer and uses definitely_disarmed in the existing ownership worklist.

An owner is a stable lexical cleanup slot. Release, move and rearm change its
current responsibility/value, while scope, ordinal, cleanup contract and rank
remain fixed. Automatic cleanup is reverse lexical owner-slot order; explicit
release stays immediate. This preserves every program without rearming.

Validated rearm becomes ordinary producer pointer flow in SSA. Branches use
pointer phis and existing lexical cleanup reads the current value. Construction
checks physically null old definitions; semantic state remains the authority.
There is no new runtime, dependency, ABI channel or LLVM primitive. See
[ADR 0032](../decisions/0032-owner-rearming.md), [IR](../ir/ownership-rearm.md),
and qualification.

## Explicit generic capabilities

Explicit generic capability authority is resolved during definition checking.
Exact requirement identities and uniform operator shapes survive through
parameterized Core, independent of the checked graph. Monomorphization selects
ordinary concrete operations before the existing CFG/SSA/NABI/LLVM firewall.
No runtime capability system is introduced.
See [ADR 0057](../decisions/0057-explicit-generic-capabilities.md) and
[capability IR](../ir/generic-capabilities.md).

## Recursive struct fields

STRUCT-AGG-1 generalizes ordinary native struct storage before generic aggregates.
Exact recursive Places and direct-storage initializer trees survive stage lifetimes;
semantic/Core cycle checks precede physical layout. Promotion handles eligible
nested leaves and memory-backed roots use one recursive address authority. Struct
and class field policies intentionally differ. GEN-STRUCT-1 materializes exact
generic applications into concrete structs and reuses this machinery.
See [ADR 0058](../decisions/0058-recursive-struct-fields.md).

## Generic native structs

GEN-STRUCT-1 extends the existing compilation-owned Core generic context with a separate aggregate registry and the shared TypeSubstitution authority. Checked generic function and struct graphs can die before materialization; Core generic definitions can die before CFG. Exact definition plus ordered semantic arguments selects an instance, and exact field origins map directly to ordinary CoreStructFields. Demand, canonical deduplication and cycle state precede all layout. See [ADR 0059](../decisions/0059-generic-native-structs.md) and [generic aggregate IR](../ir/generic-structs.md).

## Ownable generic ownership

GEN-OWN-1 separates PLAIN_COPY and OWNABLE generic transport. An explicit Ownable
requirement authorizes owned parameters/results and move, without copy or value
operator authority. The existing capability namespace and centralized matrix
select eligibility. Structured semantic/Core proofs establish generic ownership
before specialization. The existing Core monomorphizer then selects exact
Resource or Class contracts; only concrete ownership reaches CFG, SSA, NABI and
LLVM. Object storage provenance and caller-candidate semantics remain concrete
consequences, and the two ownership domains may have different ABIs. No runtime
generic ownership machinery is introduced. [ADR 0060](../decisions/0060-generic-ownership.md)
and [IR](../ir/generic-ownership.md) freeze these boundaries.


## Exact C floating-point boundaries (CABI-FP-1)

VAPI float/double normalizes to f32/f64 foreign declaration inputs. Ordinary
CFunctionSymbol, ForeignAbi.C and exact semantic types carry the mapping through
Core, CFG and SSA, with no extra floating semantic type. Physical CABI planning
adds separate F32/F64 channels under scalar-fp-v2; LLVM realizes them as float
and double with ccc. Existing export wrappers call their exact native fastcc
implementations. Native scalar-fp-v3, fp64-v6 and aggregate-v7 are unchanged.

CABI profile selection follows all foreign signatures, including unused ones,
and preserves prior integer/pointer/cleanup capabilities. A dedicated target
gate qualifies default x86-64 Linux C float/double representations before
emission and rejects other targets. C assertions and exact memcpy bit oracles
provide qualification evidence without defining Astra semantics. There is no
numeric conversion, runtime helper, allocator, typed floating C pointer,
C aggregate ABI or process-entry change. See [ADR 0063](../decisions/0063-c-floating-point.md).

TEXT-IO-1 keeps outbound foreign text as the existing complete StringType value
through Core, CFG and SSA. Source and VAPI callable declarations normalize
`text_abi="utf8-i32"` to immutable shared foreign metadata on the exact callee.
Independent CABI text-view-v3 groups own adjacent PTR/I32 channels and their
logical/physical correspondence. LLVM expands captured arguments using that
plan, with no source-name recovery, native-ABI authority, text decoding or
ownership analysis below checking. The ordinary output library/provider is
outside Core; see [the C text boundary](../abi/c-text-views.md).

## Generic copyable values (GEN-COPY-1)

[ADR 0078](../decisions/0078-generic-copyable-values.md) connects the existing
plain-copy contract to eligible record values and exact constructed arguments.
One shared structural proof supplies concrete admission and scoped symbolic
premises. Definitions remain checked once; bounded transport materializes into
existing scalar/vector or struct-copy/producer operations before concrete Core.
Record parameters use independent read-only storage; call arguments capture all
leaves before later effects. Named record-valued initializer entries accept
bounded producers in written order for ordinary and generic enclosing records.
No ownership, operator, zero, public Copy syntax, ABI profile or runtime machinery
is implied. Exact nominal keys, canonical applications and deterministic budgets
govern completion. See [transport IR](../ir/generic-copyable-values.md).
