# ADR 0062: Native struct value boundaries

Status: accepted for ASTRA-STRUCT-ABI-1.

Small numerical records need ordinary parameter and result syntax. Astra already
has exact nominal struct storage, recursive copyability, and promotable field
Places. Native boundaries extend that leaf architecture. A mandatory pointer ABI
would force storage, introduce aliases, and hide the copy contract. A universal
aggregate Value would broaden the expression language and SSA unnecessarily.
We choose bounded producers and recursive native leaf channels.

1. Concrete copyable StructTypes may be native Astra parameters by value.
2. Concrete copyable StructTypes may be native Astra results by value.
3. Both contracts are COPY_VALUE, using copy semantics, without ownership transfer.
4. Caller and callee share no struct storage through this contract.
5. Mutating a callee's local copy cannot mutate caller struct storage.
6. Results have ordinary copyable value lifetime, without source storage identity.
7. Only recursively COPYABLE structs qualify, including future field policies.
8. `CopyabilityAuthority.of(type, fields)` from STRUCT-COPY-1 decides eligibility.
9. There is no second ABI copyability table.
10. Exact nominal StructType identity remains semantic authority.
11. Size, alignment, physical layout and target conventions cannot grant eligibility.
12. Native boundaries recursively flatten into copyable semantic leaf channels.
13. Flattening uses recursive field declaration order.
14. Scalar leaves reuse existing native scalar channels.
15. f32 uses F32.
16. f64 uses F64.
17. void* uses PTR and preserves pointer identity, without copying its pointee.
18. VectorType fields use existing native whole-vector channels.
19. Nested StructType fields recurse.
20. No physical STRUCT scalar channel is introduced.
21. No universal semantic StructValue is introduced for transport.
22. No aggregate Astra SSA Value is introduced.
23. A struct parameter has one ordinary parameter-owned local storage identity in Checked/Core.
24. Its leaves can remain completely scalarized.
25. Struct result construction and return can remain completely scalarized.
26. Physical decomposition/reconstruction does not require aggregate memory.
27. LLVM aggregate return values are allowed solely as backend ABI carriers.
28. These carriers are not Astra semantic, Core, CFG or SSA aggregate Values.
29. A single-leaf struct remains its exact nominal StructType.
30. Representation equivalence never collapses semantic types.
31. Same-layout A/B may share a physical signature but cannot interchange in source.
32. Parameter flattening performs no semantic rounding or conversion.
33. Result flattening performs no semantic rounding or conversion.
34. Floating field bits transport exactly under existing F32/F64 value semantics.
35. Vectors transport as whole values; no lane Places or scalar lane ABI is added.
36. Every parameter leaf initializes before any source body statement executes.
37. Parameter bindings remain immutable under ordinary Astra parameter policy.
38. Parameter fields and subobjects can be read and snapshotted.
39. By-value struct parameter storage is read-only in this milestone, recursively.
40. Returning an initialized local of the exact copyable result type is valid.
41. Returning an exact struct field/subobject snapshots its complete subtree.
42. Returning a struct parameter is valid.
43. Returning `*ptr` is valid wherever existing pointer legality permits the Place.
44. Return evaluation captures every leaf before cleanup and source lifetime end.
45. No memcpy/memmove semantic dependency exists.
46. No heap allocation or runtime aggregate helper is introduced.
47. Resource/Class-containing structs remain outside current legal/copyable field policy.
48. Concrete generic-origin structs obey the same boundary rules.
49. Parameterized generic aggregate types never reach NABI.
50. Generic Copy capability remains deferred.
51. GEN1_PLAIN_COPY's concrete type argument universe is unchanged.
52. C aggregate parameters/results remain a separate ABI milestone.
53. No GObject aggregate boundary is added.
54. The accepted monotonic NABI architecture gains aggregate-v7, subsuming v0–v6.
55. Generic semantics are materialized/monomorphized before physical ABI planning.

## Bounded contexts and sequencing

CheckedStructProducer and CoreStructProducer are dedicated nodes, not expression
Values. Their variants retain an exact Place snapshot or an exact native call.
An argument adapter is accepted only against an exact COPY_VALUE parameter.
A call result has four consumers: struct local initialization, struct assignment,
exact struct argument forwarding, and exact struct return forwarding. Discarding
one or embedding it in an arbitrary scalar/general aggregate expression rejects.
Properties retain PROP-1's explicit nonaggregate value matrix. Native struct/class
methods and class constructor parameters share the ordinary boundary machinery;
method receivers and object result-storage contracts do not change.

Argument evaluation is left-to-right, after receiver preparation. At each struct
argument's position the compiler evaluates/validates its Place, snapshots every
leaf, then proceeds to the next argument. Later argument mutation therefore cannot
change that earlier value. A call producer already supplies captured leaves.
Return snapshots finish before cleanup. Copy-result assignment validates its
destination before evaluating the result call and writes only after every result
leaf is available. Source storage remains usable after either operation.

Read-only parameter storage cannot be rebound, assigned through nested fields,
addressed with a mutable pointer, or used as a mutable struct method/property
receiver. `Pair local = value;` creates mutable local storage. This freezes the
otherwise ambiguous difference between immutable bindings and mutable aggregate
storage without adding reference-like behavior. Existing receiver and borrowed
ClassType mutation policies remain their separate contracts.

## Independent stages and physical realization

`StructLeafOrder` factors STRUCT-COPY's recursive declaration walk into a
stage-neutral authority. `CoreStructLeaves` resolves its ordinal paths back to
exact Core fields. Copy and boundaries use this one order. Each stage verifies
its own field graph with the existing CopyabilityAuthority; no Checked graph or
source-text recovery is required after Core construction.

CFG parameters and calls carry ordinary concrete leaf Values, with exact nominal
shape/group metadata. One call owns N ordinary result definitions. A resultless
bounded-consumption marker ties the full result set to one permitted consumer.
SSA keeps those ordinary leaf definitions and grouping, never an aggregate Value
or phi. Local result destinations promote normally; memory destinations use
ordinary recursive leaf stores. Branches merge corresponding leaf definitions.
Forwarding needs no aggregate storage round trip.

NativeStructValuePlan contains a copied source declaration identity, ordered
ordinal-path/channel pairs, and single-leaf or multiple-leaf carrier selection.
The completed NABI model contains no semantic graph. Any source signature with a
by-value struct selects aggregate-v7 for the program; body-only struct use and
Struct* parameters retain the previous profile selection. v0–v6 remain frozen.

LLVM receives flattened function parameters. A single-leaf result returns its
leaf type directly. Multiple leaves use an LLVM literal struct, constructed with
insertvalue and decomposed with extractvalue at call/return boundaries. There is
no default hidden parameter pointer, result-storage pointer, sret or byval.
There is no size-based switching to a C ABI. Backend register assignment and
spills are target decisions; x86-64 observations do not prescribe future SH-4
lowering. The NABI remains compiler-owned, without an external stability promise.

Padding is not semantic value state. Copying, passing and returning transport
field values, without promising preservation of padding bytes. Empty structs
remain illegal; no zero-channel ABI is invented. Floating arithmetic, contraction,
FMA/fast-math policy, ownership, CABI and VAPI remain unchanged. Generic Copy,
aggregate generic arguments, parameterized Box<T> boundaries, aggregate Move,
owned fields and C aggregate interoperability require separate decisions.

See [language](../language/struct-values.md), [IR](../ir/struct-values.md),
[native aggregate ABI](../abi/native-aggregates-v7.md), and
qualification.
