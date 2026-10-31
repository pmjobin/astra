# Semantic generic-function IR

GEN-1 specializes structured Core before any CFG exists. The pipeline is:

```text
GenericFunctionSymbol + TypeParameterSymbols
  → CheckedGenericFunction / CheckedGenericCall
  → CoreGenericFunction + CoreTypeParameters / CoreGenericCall
  → CoreGenericMonomorphizer
  → ordinary concrete CoreFunction + GenericFunctionInstance origin metadata
  → CFG → SSA → NABI → LLVM
```

Checked and Core program `generic_functions` arrays are distinct from ordinary
`functions`. All signatures precede body checking/lowering, allowing forward,
direct-recursive and mutually recursive generic calls. The source body is checked
once. Signature substitution checks each call without copying/rechecking its body.

TypeParameterSymbol owns a unique immutable TypeParameterType. Its transport
mode is PLAIN_COPY with GEN1_PLAIN_COPY unless it explicitly requires Ownable;
that requirement selects OWNABLE without implicit copy authority. This token has no upstream backlink. CoreTypeParameter
is an independent stage descriptor mapped from the checked symbol; it owns the
same exact stage-neutral type token, following accepted nominal type authority.
The token is Core's type-parameter representation without a parallel type universe.

CheckedGenericCall and CoreGenericCall retain the exact definition target,
ordered exact type arguments, ordinary value arguments and substituted result.
The statement form permits discarding an ordinary result. Existing concrete
owned/borrowed call arguments retain their exact parameter/cleanup contracts.
A generic target without its typed generic-call representation and ordered type
arguments fails verification, regardless of source spelling.

## Substitution and registry

TypeSubstitution maps exact type-parameter tokens, never strings. Direct parameter
occurrences and GEN-STRUCT-1 aggregate applications substitute through this shared
authority. Concrete types, non-generic functions, methods,
properties/accessors, fields and cleanups remain exact shared identities.

One CoreGenericMonomorphizer owns a compilation-wide registry indexed by exact
CoreGenericIdentity. Ordered argument identities compare directly inside each
bucket. Aliases already have canonical identity: int/i32 share one key. Sign and
vector element identity remain significant independently of physical ABI/LLVM
representation. Phantom arguments remain in the key.

The first request creates and registers a concrete function signature placeholder
and IN_PROGRESS instance metadata. Ordinary source/call traversal and a FIFO
worklist then clone bodies. Recursive requests reuse registered signatures;
completed bodies mark COMPLETE. Hash-table traversal and pointer values never
choose output order. The worklist handles cross-concrete calls and arbitrary
finite recursive instance graphs.

CoreInstanceCloner maps fresh parameters, locals/Places, field projections, blocks,
loop targets, object storage, owned slots and result storage. It recreates all
statement/value nodes and copies immutable vector selector snapshots through
their normal constructors. It preserves global targets instead of resolving names.
Generic calls substitute their type arguments and bind to the registered concrete
function; owned/borrowed argument descriptors remap to its exact concrete parameter.

GenericFunctionInstance retains an immutable CoreGenericIdentity origin token,
weak exact origin definition, concrete argument snapshot, deterministic ordinal,
state, request count and exact weak callers. Origin and caller weak references
avoid recursion cycles; the token retains identity after definition destruction.
Instance Core names are `astra.gen.D.I`; LLVM uses existing internal `astra.fn.N`
ordinal naming. Internal physical symbols are not a public/source-addressable ABI.

The pass consumes ordinary Core bodies in place to retain all global target
identities. Its result owns ordinary roots and concrete instances, with an empty
generic-definition array. Release the consumed parameterized program before
continuing. Specialization requires no checked graph, syntax or LLVM dependency.

## Verification and stage lifetime

CoreVerifier verifies parameterized definitions, exact lexical parameter scope,
allowed operations, substituted signatures, type-argument eligibility and ordinary
concrete body invariants. Substitution never legalizes an operation rejected by
this verifier or source checking. Final instance verification checks concrete
signatures/Places/calls, completed metadata, canonical key uniqueness and order.

CfgBuilder calls CoreVerifier.verify_concrete. It rejects any generic definition,
unresolved generic call or type parameter. Existing CFG/SSA verifiers and
NABI/LLVM input verification reject unknown/unresolved types without introducing
generic representations into those stages. No generic node, profile, hidden
parameter or runtime helper is added downstream.

Qualification destroys checked generic symbols before Core specialization, then
Core generic definitions/type parameters before CFG, concrete Core before SSA,
CFG before NABI, and SSA/ABI sidecars before retained LLVM artifact verification
and object emission. Independent Core/monomorphizer binaries do not link the
parser, checked semantic analyzer or LLVM.

`--dump-core` prints verified parameterized Core. `--dump-instances` prints
verified concrete Core with origin keys, counts and callers. Existing downstream
dumps remain concrete. Determinism checks compare fresh compilations, including
semantic/Core dumps, inventories and emitted symbol ordering.

NABI remains v0-v6. Substituted signatures choose existing channels; the accepted
program-wide effective profile subsumes the individual requirements. No profile
is assigned to a parameterized definition. See [ADR 0056](../decisions/0056-semantic-generic-functions.md)
and qualification.

## Explicit generic capabilities

GEN-CAP-1 adds exact ordered capability requirements and explicit capability
operations to checked and parameterized Core definitions. Generic calls snapshot
target requirements; Core verifies concrete matrix satisfaction or exact declared
parameter membership. The resolver selects existing concrete Core operations after
substitution. Keys and recursion placeholders are unchanged, and failure precedes
placeholder creation. See [capability IR](generic-capabilities.md).

## Generic native structs

CoreGenericMonomorphizer now also owns exact generic struct instance keys and demand-driven recursive materialization. TypeSubstitution handles CoreGenericStructApplicationType through the same binding authority. Function recursion still reuses IN_PROGRESS signatures; struct MATERIALIZING re-entry rejects an infinite by-value layout. Both registries reach one deterministic fixed point before CFG. Existing function keys are unchanged. See [generic aggregate IR](generic-structs.md).

## Parameterized ownership

[Generic ownership](generic-ownership.md) uses the same parameter identities,
capability requirements, exact substitutions, canonical instance keys and FIFO
specialization. OWNABLE parameters do not carry GEN1_PLAIN_COPY. Structured
ownership state is proved during semantic checking and independently verified in
Core, before any instance is materialized. Core ownership contracts specialize to
ordinary Resource/Class contracts before CFG; no source rechecking occurs.

## Call-site inference boundary

GEN-INFER-1 finishes in semantic checking. Checked generic calls contain the same
ordered exact semantic arguments whether inferred or written. An inferred outer
TypeParameterType uses the existing parameterized Core call and TypeSubstitution;
only concrete arguments enter GenericFunctionInstance keys. No inference variables,
equations, solver or authoritative inference provenance enter Core. Monomorphization,
CFG, SSA, NABI, CABI and LLVM require no inference implementation. See
[ADR 0070](../decisions/0070-generic-call-inference.md).

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
