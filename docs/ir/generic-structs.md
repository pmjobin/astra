# Generic aggregate Core and materialization

M17's explicitly bounded owning-storage profile closes record applications during
semantic analysis, before choosing the ordinary aggregate ownership flow. Its
immutable `OwnedRecordDefinitionContract` records nominal origin, owner parameter
roles and declared field patterns; `OwnedRecordApplicationContract` snapshots the
exact logical arguments. Checked symbols retain only weak definition associations.
Core rejects a substituted declaration or argument snapshot before lowering.

Core, CFG and SSA own separate concrete argument-demand arrays. A copyable generic
argument is projected to the Core application and then the ordinary materialized
record; phantom arguments remain metadata roots through SSA pruning. Each verifier
rechecks logical identity, capabilities, field inventory, ownership and visibility
against its own field graph. Core's pre-materialization ownership walk admits a
copied generic subtree only through its registered definition and independent
recursive plain-copy proof. It cannot hide a cleanup-bearing leaf.

The native model copies declared patterns, argument capabilities, physical field
types and recursive cleanup facts into stage-independent native data. It rebuilds
the expected scalar/buffer/record channel inventory and exact Class/Resource
retirement paths. It retains no semantic type or predecessor node. Detached tests
release each preceding graph before checking the next stage, then mutate fields,
argument demands, context capabilities, buffer channels and release identities.

The older unqualified generic-record pipeline below continues to use its existing
plain-copy definitions and Core materialization.

[Concrete record collection elements](struct-elements.md) preserve canonical collection identity while ordinary generic applications materialize before CFG. Array/slice types and cleanup shapes map to the same completed concrete element; specialization is shared across entries and callers.

The generic aggregate pipeline ends at the same concrete Core boundary as generic
function specialization:

```text
GenericStructSymbol / GenericStructFieldSymbol
	→ CheckedGenericStruct / GenericStructApplicationType
	→ CoreGenericStruct / CoreGenericStructField / CoreGenericStructApplicationType
	→ CoreGenericMonomorphizer
	→ ordinary CoreStruct / CoreStructField / recursive CoreFieldPlace
	→ CFG → SSA → NABI → LLVM
```

## Exact definitions and applications

GenericStructSymbol derives from Symbol. It does not derive from StructSymbol or
NativeInstanceSymbol, has no concrete StructType, and owns no receiver, layout or
ABI. Its ordered parameters are existing TypeParameterSymbols; their immutable
TypeParameterTypes carry GEN1_PLAIN_COPY. GenericStructFieldSymbol retains a weak
exact definition owner, parameterized semantic type, ordinal and provenance.
FieldSymbol factors declaration metadata so the existing CheckedFieldInitializer
can retain either ordinary or generic origins without a second initializer tree.

An application stores the exact definition and a snapshot of ordered argument
identities. The definition interns applications by exact argument comparisons.
Alias canonicalization already occurred in BuiltinTypes. There is no textual or
representation-based equivalence. Phantom arguments remain in every comparison.

CheckedGenericStructFieldPlace has the recursive CheckedPlace base, application,
exact origin field and substituted result type. Member names resolve at this
checked boundary only. A projected T remains the original lexical T identity,
including its existing GEN-CAP authority.

## Core ownership and substitution

CoreBuilder first creates every CoreGenericStruct and CoreTypeParameter, then
lowers fields and applications, allowing forward and mutually recursive
definitions. CoreGenericStructField and CoreGenericStructApplicationType refer to
exact Core definitions, with weak backlinks to avoid ownership cycles. No checked
symbol, checked field, syntax tree or LLVM object is retained.

Existing stage-neutral type parameters follow GEN-1's lifetime design. The shared
TypeSubstitution owns exact parameter bindings and argument substitution.
Application types implement its constructor hook and use their stage's canonical
application registry. Plain concrete types remain exact shared identities. No
substitution through T*, T[] or T[N] is supported. Mapping a pointer to a fully
concrete application is a bounded part of concrete aggregate conversion.

CoreGenericStructFieldPlace participates in the existing recursive Place tree.
CoreStorageFieldPlace factors the shared aggregate base and root lookup from
CoreFieldPlace. CoreStructInitialize retains its existing ordered recursive
storage statement tree and can target either kind of field projection above
concretization. There are no generic aggregate Values or copy nodes.

Generic projections are interned on demand by exact base and origin rather than
eagerly expanding potentially recursive generic definitions. Core verification
checks exact canonical projections, lexical parameters, eligible arguments,
substituted field types, recursive initializer completeness and local availability.

## One instantiation context, two recursion rules

CoreGenericMonomorphizer owns both function and struct registries. Function keys
and placeholder behavior remain unchanged. Struct keys use the separate exact
CoreGenericStructIdentity plus ordered concrete SemanticType identities. These
identity classes and separate registries prevent cross-kind collisions.

GenericStructInstance retains the immutable definition origin token, a weak
definition reference, concrete argument snapshot, deterministic ordinal, explicit
state, weak concrete CoreStruct reference, request count and exact weak requesters.
Requesters are root CoreFunctions, GenericFunctionInstances or
GenericStructInstances. Strings are labels, never requester deduplication keys.
An incoming struct requester records the exact dependency edge.

The context registers a DECLARED ordinary CoreStruct placeholder and its key
before resolving fields. It marks MATERIALIZING, visits fields in declaration
order, substitutes their types and recursively requests nested applications.
Each field becomes a fresh ordinary CoreStructField. The direct origin identity
map supplies that field to every projection of the instance. Its immutable
CoreGenericStructFieldIdentity token permits provenance retention after all
generic definitions and fields are released.

Re-entering a MATERIALIZING struct diagnoses the active application path and
throws; the failed instance does not become COMPLETE. This differs intentionally
from generic functions, whose registered IN_PROGRESS signatures support valid
recursive calls. No backend type or layout operation participates in either key.

## Concrete output and order

Ordinary callable concrete pointer signatures are visited first. Each ordinary
root then visits its ordered locals and body; generic function bodies follow the
existing FIFO instance worklist. Nested aggregate requests occur in field order.
First request assigns the aggregate instance ordinal. Ordinary structs keep their
declaration ordinals and materialized structs append after them. Hash tables are
used only for lookup. Root callables are consumed in place, retaining exact
Method/Property/accessor/cleanup targets.

The cloner substitutes local storage types and regenerates the ordinary complete
recursive field projection inventory. It maps each generic field origin directly
to its instance field, then reconstructs CoreStructInitialize using ordinary
CoreFieldPlace targets. Bundle<f64>.pair.first becomes two ordinary exact field
projections. No field name is searched during this operation.

The returned CoreProgram contains ordinary roots/functions/structs and empty
generic definition arrays. Release the consumed parameterized program before
continuing. CoreVerifier.verify_concrete checks completed metadata, key uniqueness,
ordinary field origin association and absence of unresolved generic aggregate
types, generic Places and type parameters in aggregate storage. CfgBuilder invokes
this verifier as its firewall.

CFG, SSA, NABI and LLVM use their existing concrete models without any generic
definition, application or field category. Scalarization retains scalar and whole
vector leaves. Address-taking creates only ordinary root storage. Struct* maps to
PTR, and layout follows ordinary backend field order and alignment policy. No
aggregate SSA Value, memcpy, heap, boxing, hidden arguments, descriptors,
dictionaries, witnesses or new NABI profile exists.

## Dumps and qualification

`--dump-semantics` shows generic definitions, parameters, field origins and
parameterized projections. `--dump-core` shows independent parameterized Core.
`--dump-instances` shows ordinary concrete structs/functions with origin inventory,
counts, requesters and concrete ordinals. Downstream dumps contain ordinary
concrete types and Places only. Source spelling and layout measurements are
descriptive evidence, never semantic authority.

Standalone tests destroy checked generic function and struct graphs before Core
materialization, Core generic definitions before CFG, concrete Core before SSA,
CFG before NABI, and SSA/ABI sidecars before retained LLVM verification. Tests cover
all 34 arguments, exact identities, nested dependencies, four cycle forms,
malformed-model firewalls, deterministic independent builds and ordinary layout
controls. See qualification and
[ADR 0059](../decisions/0059-generic-native-structs.md).

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
