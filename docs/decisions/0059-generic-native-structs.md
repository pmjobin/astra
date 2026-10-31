# ADR 0059: Generic native structs and concrete aggregate monomorphization

Status: accepted for ASTRA-GEN-STRUCT-1.
Baseline: `2102ad774feadd540083ece57bf3df6b2f18f130`, ASTRA-STRUCT-AGG-1,
whose decision is ADR 0058.

## Context

STRUCT-AGG-1 supplies concrete recursive native storage, nested direct-storage
initialization, all supported vector fields, leaf promotion and selective root
addressability. GEN-1 supplies exact type parameters and Core function
specialization. Generic aggregate construction belongs above these concrete
storage and backend mechanisms.

## Decision

1. Generic structs are semantic/static type constructors.
2. Each definition owns exact compiler-generated identity.
3. Parameters reuse TypeParameterSymbol and TypeParameterType.
4. There is no second generic parameter system.
5. GEN1_PLAIN_COPY remains the baseline parameter authority.
6. Struct declarations have no where clauses in this milestone.
7. A generic definition has no physical layout, size, alignment, LLVM type or ABI.
8. Each concrete instance has exact nominal identity.
9. The instance key is exact definition identity plus ordered canonical semantic arguments.
10. Spelling is not an instance key component.
11. Field layout is not an instance key component.
12. Size and alignment are not instance key components.
13. LLVM representation is not an instance key component.
14. int/i32 canonicalization precedes lookup.
15. Pair<int,f64> and Pair<i32,f64> share one instance.
16. Pair<i8,f64> and Pair<u8,f64> remain distinct.
17. Different definitions remain distinct even with identical fields/layouts.
18. Phantom parameters remain part of semantic identity.
19. Concrete instances are demand-driven.
20. Unused valid definitions create no concrete struct.
21. Instances are globally deduplicated within one compilation.
22. Generic field declarations have exact origin identity.
23. Each instance receives fresh exact ordinary CoreStructField identities.
24. Concrete fields retain immutable origin association to generic fields.
25. Specialization maps field origins directly and never re-resolves field text.
26. Instances reuse STRUCT-AGG recursive Places.
27. Instances reuse STRUCT-AGG recursive direct-storage initializer trees.
28. Instances reuse ordinary scalarization.
29. Instances reuse selective root addressability.
30. Instances reuse ordinary concrete backend layout.
31. No aggregate SSA Value is introduced.
32. No whole-struct copy semantics are introduced.
33. No by-value aggregate native ABI is introduced.
34. Fully concrete generic Struct* uses TypedPointerType and existing Struct* policy.
35. Parameterized Pair<T,U>* remains deferred.
36. A field may directly have type T.
37. A field may have an already accepted concrete native struct field type.
38. A field may have a parameterized generic struct application type.
39. Nested applications accept current type parameters and eligible concrete arguments.
40. Concrete generic structs are not GEN1_PLAIN_COPY arguments.
41. Box<Pair<int,int>> remains unsupported.
42. This deliberately defers aggregate capability authority.
43. Recursive by-value generic layouts are illegal.
44. Direct recursive layouts are illegal.
45. Mutual recursive layouts are illegal.
46. Permuting arguments does not legalize a concrete materialization cycle.
47. Arguments collapsing onto an active instance also form an illegal cycle.
48. Generic aggregate cycle detection occurs during Core materialization.
49. Function specialization and aggregate materialization have distinct placeholder semantics.
50. Re-entering an in-progress function placeholder is valid recursion.
51. Re-entering a MATERIALIZING struct through a by-value field rejects infinite layout.
52. Generic aggregate materialization finishes before CFG.
53. CFG, SSA, NABI and LLVM remain unaware of generic aggregate representations.
54. No runtime type descriptor is introduced.
55. No hidden type-argument fields are introduced.
56. No witness or dictionary is introduced.
57. No boxing is introduced.
58. No heap allocation is introduced.
59. No new NABI type/profile is introduced; the accepted set remains v0-v6.
60. Future generic ownership, classes, methods and interfaces must extend this exact aggregate identity system.

## Pipeline and ownership

GenericStructSymbol is a Symbol, not a StructSymbol or NativeInstanceSymbol.
CheckedGenericStruct owns its checked definition. GenericStructApplicationType
retains ordered argument identities and a weak exact definition reference.
CoreBuilder maps these to independent CoreGenericStruct, CoreGenericStructField,
CoreTypeParameter and CoreGenericStructApplicationType objects before releasing
the checked graph. Stage-neutral TypeParameterType tokens follow GEN-1's accepted
lifetime policy and have no upstream backlinks.

CoreGenericMonomorphizer owns separate exact function and struct registries in one
compilation context. TypeSubstitution remains the sole binding authority;
application types participate through its constructor substitution hook. No
substitution through T*, T[] or T[N] is added. Converting a pointer to an already
concrete aggregate application is part of aggregate materialization.

The struct state machine is DECLARED → MATERIALIZING → COMPLETE. Registration
precedes field traversal. Recursive requests diagnose the active application path;
a failed instance never becomes COMPLETE or reaches downstream construction.
The completed output contains ordinary CoreStructs with ordinary field identities.
Immutable origin tokens survive without retaining generic definition bodies.

CoreStorageFieldPlace factors the recursive base/root operation used by ordinary
CoreFieldPlace and temporary CoreGenericStructFieldPlace. The existing
CoreStructInitialize tree accepts either projection above materialization. The
materializer replaces generic projections with exact ordinary CoreFieldPlaces and
reuses the same statement tree. CFG still accepts only ordinary concrete fields;
there is no parallel generic initializer or Place hierarchy downstream.

## Determinism and consequences

Ordinary struct declaration ordinals remain unchanged. Materialized structs append
in first exact request order. Traversal first resolves ordinary callable pointer
signatures, then each root's locals and body in existing deterministic order, then
generic function bodies in the existing FIFO order. Nested fields are visited in
declaration order. Hash tables serve lookup only. Request counts and exact weak
requester identities distinguish root callables, function instances and aggregate
instances. Requester labels are descriptive only.

Generic origin never forces memory. Vector fields remain whole-vector leaves.
Address-taking affects the selected root only; ordinary recursive GEP/load/store
handles addressed instances and nullable concrete Struct* parameters. Layout
comparisons against ordinary controls are qualification evidence, never key or
capability authority.

See [language](../language/generic-structs.md), [IR](../ir/generic-structs.md),
and qualification.
