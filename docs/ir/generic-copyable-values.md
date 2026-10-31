# Parametric plain-copy transport

`CopyabilityAuthority.value_copy` shares the ordinary recursive walk with `of`.
It additionally requires nonempty value storage and accepts an explicit scoped
premise callback for symbolic leaves. Semantic and Core callers supply exact
field resolution and lexical parameter ownership. Ownable leaves fail even if a
forged callback tries to assert a plain-copy premise. No layout/LLVM query or
second generic-record whitelist participates. All visited/proof state is local
to a walk; materialization caches belong to one compilation.

`GEN1_PLAIN_COPY` keeps its internal spelling and expands its documented domain.
Generic operator requirements use the unchanged separate capability authority.
Type application substitution retains exact definitions, ordered arguments and
field origins. Before final registry lookup, constructed arguments canonicalize
through the existing application/materialized identity mapping. Keys never use
physical representation. Placeholder-before-body ordering preserves recursion;
budgets bound growing instance requests and symbolic copy proofs.

| Checked/parameterized operation | Primitive/vector specialization | Record specialization |
| --- | --- | --- |
| T parameter acquisition | Existing parameter value | Independent read-only local plus CoreAcquireStructParameter |
| T local initialization | CoreInitialize | CoreStructCopy or CoreStructResultStore |
| Same-T assignment | CoreStore | Bounded snapshot copy/result store |
| Known Box<T> field initialization | Existing typed field entry | CoreStructInitialize with bounded producer |
| Known T field load/write | Exact substituted projection | Exact mapped storage projection and copy consumer |
| T argument | Existing scalar/vector argument | CoreStructArgument with complete snapshot/call result |
| Generic T call result | CoreCallValue | CoreStructCallResult at a bounded consumer |
| T return | CoreReturn | CoreStructReturn |
| Whole Box<T> transport | Existing concrete struct operations | Existing concrete struct operations |
| Discarded generic T result | Existing call statement | Fresh bounded unused result storage, subsequently scalarized |

The discarded-result row preserves a checked-once operation already legal in a
plain-T body/call statement; specialization cannot retroactively make it illegal.
It does not expose an aggregate expression or change ordinary native source
result-discard rules. Owned producers are distinct and retain explicit moves.

Parameterized Core reuses its typed parameter/load/call nodes as bounded symbolic
transport at established consumers. They retain exact symbolic types and origins.
The cloner permits only checked parameter, Place-load and generic-call sources
when reifying a record source. A record otherwise entering ordinary `CoreValue`
materialization fails. Existing struct nodes carry whole known applications;
typed field initializer entries can carry one producer or nested children.

Entry acquisition keeps owned parameter slots first, then record parameters in
declaration order, before body execution. Record-specialized locals and canonical
projections are regenerated before verification. Concrete scalar/vector bindings
retain their established behavior. Exact field-origin maps, rather than source
name lookup, resolve application fields. Mutable semantic graphs, source bodies
and type universes may be released before parameterized Core specializes.

Inference observations can cache either an expression or a bounded producer,
along with the existing transactional ownership proof. Direct type observation
does not load a record or execute an index/producer. Cached checks replay the
proof once in source order and feed the actual consumer once. Invalid calls
cannot commit a fragment. Neither inference nor scoped semantic premises reaches
concrete Core.

A producer field initializer snapshots/obtains the complete source, writes that
field's recursive leaves, then lowers the next written entry. A fixed record-array
initializer preserves its accepted complete-entry publication: nested producer
leaves are captured in written order and consumed by that entry's exact ordered
field list. CFG independently checks the complete, unique same-block consumer,
including nested field producer results. Duplicate/missing leaves and substituted
nominal or parameter identities reject.

After substitution, `verify_concrete` rejects all type parameters, unresolved
applications, generic calls/operators and malformed producer/parameter contracts.
Only existing concrete struct lowering reaches CFG. SSA has scalar/vector leaves,
normal phis and explicit storage where source addressability requires it. Native
plans independently own exact nominal shapes and carriers after SSA is destroyed.
Aggregate-v7 applies to ordinary struct boundaries; STRUCT-ELEM v11 and other
features still determine the effective program profile. No new profile, C ABI,
sret/byval/input pointer, runtime box, dictionary or aggregate Astra SSA is added.

The [standalone tests](../../tests/gen-copy-1/gen-copy-core.vala),
[pipeline tests](../../tests/gen-copy-1/pipeline.vala) and
[LLVM consumer](../../tests/gen-copy-1/llvm.vala) retain next-stage artifacts after
predecessor destruction and exercise forged admission, field, parameter, instance,
producer and physical-plan identities. See validation
for raw comparisons, lifetime/memory runs and precise qualifications.

[Generic slices](generic-slices.md) reuse these bounded value consumers for
parameterized indexed Places; concrete materialization still completes before CFG.
