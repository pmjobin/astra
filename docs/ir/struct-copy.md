# Whole native struct copy IR

[Indexed struct roots](struct-elements.md) use the existing bounded copy lowering: destination capture/validation, complete source leaf snapshot, then writes. The indexed root is shared across all recursive projections; copied unaddressed locals remain eligible for promotion.

[Native value boundaries](struct-values.md) now share this copy model. StructLeafOrder
factors the one recursive declaration-order walk; CoreStructLeaves resolves its
paths to exact Core fields. Native arguments/results add bounded producers and
leaf grouping, while ordinary Place-to-Place copy retains its existing nodes.
Padding is never enumerated or promised preserved. No general aggregate Value is
needed for either operation.

`StructCopy(destination: Place<S>, source: Place<S>)` is a storage operation.
It is never Load-of-aggregate followed by Store-of-aggregate. No StructValue,
AggregateValue, TupleValue, aggregate SSA Value or whole-aggregate ABI is added.

CheckedStructCopy is a CheckedStatement, with exact destination/source
CheckedPlaces, SemanticType, Copyability result, initialization/assignment mode,
and SourceSpan. Direct locals and recursive FieldPlaces retain exact symbols;
dereferences retain pointer expressions and ordinary provenance. Local scope
visibility proves complete source initialization. Fresh copy destinations become
visible only after checking their source. Assignment uses existing initialized
mutable storage. There is no ownership state transition.

```text
(struct-copy (type Pair) initialize
	(destination (local-place #1 : Pair))
	(source (local-place #0 : Pair))
	copyable snapshot-before-write)
```

CopyabilityAuthority.of(type, fields) is stage-neutral and LLVM-free. Its one
closed leaf rule accepts bool, current integers, f32/f64, void* and all supported
vectors. Concrete struct storage recurses through the resolver's exact field
types. In-progress and completed identity states reject cycles and reuse shared
subgraphs. Missing descriptors, parameterized storage and unsupported types fail
closed. No physical layout or generic-origin query decides copyability. Owned and
borrowed contracts do not enter whole struct storage; existing field policy
excludes them. Future legal noncopyable fields naturally make the result negative.

CoreStructCopy retains the exact independent CorePlaces, type, mode and span.
CoreVerifier independently resolves its own field graph through the same semantic
rule. It checks exact nominal equality, valid Place ownership and membership,
complete source visibility, fresh initialization or initialized assignment, and
lifecycle exclusion. Destroying Checked nodes and symbols changes none of these
checks. The existing materializer maps fully concrete generic application types
and fields to ordinary StructTypes and CoreFieldPlaces in this same node.
Parameterized application copy never qualifies. No CoreGenericStructCopy exists.

CoreStructLeaves.enumerate walks concrete fields in recursive declaration order.
For `O { I left; i16<8> vector; I right; }` and `I { int x; f64 y; }`, the order is
`left.x`, `left.y`, `vector`, `right.x`, `right.y`. Field identities establish
paths; names and offsets only describe them. VectorType is one leaf, never lanes.

Core→CFG lowering has four ordered phases:

1. Capture the destination Place root and validate any indirect address.
2. Capture the source Place root and validate any indirect address.
3. Emit CfgEvaluateInstruction(CfgLoadValue(source leaf), CfgEvaluatedValue) for every leaf.
4. Emit CfgInitialize or CfgStore for every destination leaf, using those snapshots.

CfgValidatePlace performs address/null validation without loading or storing a
leaf and has no result Value. Local roots need no validation instruction or
address merely to copy. Canonical local projections continue to drive promotion;
indirect projections retain ordinary recursive address semantics. No high-level
copy node survives CFG construction. Snapshots are scalar/vector Values, including
one whole vector Value per vector leaf. All reads precede all writes even for
self-copy, pointer aliases and mixed scalarized/memory storage.

SSA consumes those existing leaf operations. Promoted fields participate in
ordinary definitions and block arguments; memory leaves emit ordered loads and
stores. SsaValidatePlaceInstruction owns an ordinary SsaMemoryPlace with no result.
Its backend lowering calls the existing recursive address/null authority. That is
the only backend addition. It needs no aggregate transport, runtime helper,
memcpy/memmove, ownership flag, heap, layout query or descriptor. LLVM may optimize
these ordinary operations provided their alias and trap behavior is preserved.

Pipeline tests destroy Checked, Core, CFG and SSA in turn, independently verify
the next stage, then destroy SSA/NABI/CABI before verifying the LLVM artifact.
Standalone parser, semantic, Core, CFG, SSA and NABI targets enforce source and
linkage firewalls. Core/CFG/SSA malformed tests reject mismatched types, foreign
Places, uninitialized sources/destinations and uses before snapshot definition.
Focused CFG/SSA and frontend LLVM assertions prove complete snapshot ordering;
source syntax cannot currently observe a trapped local via a recovery construct.

CABI, VAPI, generic capabilities and Ownable are unchanged. Native boundaries
use [aggregate-v7](../abi/native-aggregates-v7.md) with the same CopyabilityAuthority
and leaf order. GEN-COPY-1 reuses that authority for ordinary record generic arguments and
scoped symbolic transport. Public Copy/Move capabilities remain deferred.

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
