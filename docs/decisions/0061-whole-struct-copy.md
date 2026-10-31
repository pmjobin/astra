# ADR 0061: Whole native struct copy

Status: accepted for ASTRA-STRUCT-COPY-1.

Native structs already have recursively promotable/addressable storage leaves.
Whole copy extends that Place architecture; converting storage into an aggregate
Value would couple this feature to representation and ABI decisions it does not
need. The chosen operation is `StructCopy(destination: Place<S>, source: Place<S>)`.

1. Concrete native structs may be copied in dedicated whole-storage contexts.
2. Copy introduces no general StructValue, AggregateValue or TupleValue.
3. Its source is exact initialized StructType storage, retained as a Place.
4. Its destination is exact mutable StructType storage, retained as a Place.
5. Both types must be the same exact nominal StructType.
6. Equal physical layout never establishes assignment compatibility.
7. Copyability is semantic, independent of LLVM layout, size and alignment.
8. Current bool and exact integer scalar types are copyable.
9. F32/F64 are copyable with exact representation/value preservation.
10. Raw void* is copyable.
11. All accepted numeric and mask VectorTypes are copyable whole leaves.
12. StructType is copyable if and only if every exact field type is recursively copyable.
13. Concrete generic struct instances obey that same rule.
14. Generic origin is irrelevant to copyability.
15. ClassType is not made copyable by this rule.
16. Resources and nominal handles are not made copyable.
17. Arrays and slices are not newly made copyable.
18. Typed-pointer field policy remains unchanged; such fields stay unsupported.
19. By-value struct cycles remain illegal; the shared authority additionally rejects in-progress cycles.
20. Copy initialization initializes fresh destination local storage exactly once.
21. Copy assignment requires complete, already initialized destination storage.
22. The source remains initialized and usable; copy causes no ownership transition.
23. All source leaves are semantically snapshotted before any destination mutation.
24. This rule applies to self-copy, aliases and future overlapping storage forms.
25. Snapshots need no runtime aggregate temporary.
26. Snapshots need no memcpy or memmove.
27. Every source leaf read precedes every destination leaf write.
28. Leaves are visited recursively in declaration order, independent of brace initializer order.
29. Nested StructType fields recurse through exact field identities.
30. VectorType fields are single whole-vector leaves.
31. No LanePlace or writable lane semantics is introduced.
32. Floating leaves copy without conversion, arithmetic or additional rounding.
33. Pointer leaves preserve exact pointer identity.
34. Whole copy preserves eligible scalarization.
35. Copy alone never makes either root addressable.
36. Memory-backed roots use ordinary recursive Place address lowering.
37. Scalarized leaves use existing concrete scalar/vector Values.
38. No whole-aggregate SSA Value or aggregate phi is introduced.
39. No whole-aggregate native ABI channel is introduced.
40. Native by-value struct parameters and results remain unsupported.
41. C aggregate ABI remains unsupported; VAPI is unchanged.
42. Struct-valued properties remain unsupported; accessor bodies can copy concrete storage.
43. Struct equality and ordering remain unsupported.
44. Ordinary local copy does not admit structs into GEN1_PLAIN_COPY generic arguments.
45. No source Copy or Move capability is introduced.
46. Future generic Copy must reuse this exact stage-neutral recursive copyability authority.
47. Future aggregate Move must be distinct from Copy and Ownable; `move struct` stays unsupported.
48. No heap allocation, copy runtime helper, descriptor or reflection is introduced.

Destination evaluation and null validation precede source evaluation and
validation. All source loads then precede the first store. A source trap cannot
partially update destination storage. Explicit Place validation performs no leaf
read and produces no Value; it uses the existing null/address lowering. Repeated
ordinary leaf address checks may optimize away. No noalias assumption is valid.

`CopyabilityAuthority.of(type, fields)` owns the single recursive semantic rule.
The field resolver supplies exact types from the caller's own graph. Checked
copy retains its proof result, Places, exact type and provenance. Core rederives
copyability and checks legality independently; it does not trust that result.
The existing frontend represents fully concrete generic applications before
materialization. Those exact, non-parameterized identities use the same copy
statement and substituted field rule; materialization produces ordinary
StructTypes before CFG. Parameterized `Box<T>` copy is rejected even in unused
functions. No early specialization or generic copy node is required.

CoreStructLeaves performs the deterministic concrete field walk. Core→CFG
captures both Places, emits ordinary Evaluate/Load leaf snapshots, and only then
Initialize/Store leaves. SSA receives ordinary leaf operations. All graphs and
field descriptors remain stage-owned and independently verifiable.

Aggregate ABI, source Copy/Move, aggregate generic arguments, owned/borrowed
fields, cloning and user-defined copy hooks are separate future decisions.
Current overwrite assignment is justified by the recursive absence of lifecycle
fields; it does not prescribe overwrite behavior for future owning aggregates.
