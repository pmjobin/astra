# ADR 0025: Native local structs and field Places

Status: accepted for ASTRA-STRUCT-1.

Astra needs aggregate storage authority before it needs computed aggregate
values, layout, or aggregate ABI channels. The existing Place/value distinction
and scalar promotion machinery support this step directly.

1. A top-level struct declaration introduces one Astra-owned nominal type identity.
2. These structs are native Astra types; they do not denote C structs.
3. Each struct local is authoritative aggregate storage, represented by an ordinary local Place with StructType.
4. A field Place projects one exact aggregate base Place. A detached scalar copy never becomes authoritative field storage.
5. Field identity is a compiler-owned object, independent of its spelling, source offset, declaration ordinal, and any future physical offset.
6. Fields are scalar leaves: `int`, `bool`, or nullable unmanaged `void*`.
7. `void` fields are invalid.
8. Struct-valued fields, including recursive fields, are unsupported. Empty structs are rejected without inventing zero-size or size-one layout.
9. Struct locals require complete explicit named initialization; there are no defaults or uninitialized fields.
10. A local becomes visible only after its entire initializer finishes. Its symbol is absent from every initializer expression's scope.
11. Every field must appear exactly once; unknown, repeated, omitted, and incorrectly typed fields are diagnosed deterministically.
12. Initializer expressions evaluate in written source order, preserving calls, short circuit, and traps.
13. Written initializer order may differ from field declaration order. Field ordinals follow declaration order from zero.
14. Field reads lower to explicit scalar Loads from FieldPlaces.
15. Field assignments evaluate their RHS, then Store into the exact FieldPlace.
16. Aggregate base storage is not directly loadable as a computed whole value.
17. Whole-struct assignment, copying, and equality are unsupported. A brace initializer is contextual local-declaration syntax, not a general expression.
18. Struct function parameters and results are unsupported, including native, C import/export, and VAPI function channels.
19. Size, alignment, padding, offsets, and native/C layout remain unspecified and uncomputed.
20. Scalar leaf FieldPlaces promote independently through the existing scalar SSA algorithm.
21. Struct base Places are storage authorities, never SSA values or promotion candidates.
22. Scalarization erases the current storage operations without defining or freezing future aggregate representation.
23. LLVM needs no struct type, aggregate instruction, aggregate alloca, or field offset for STRUCT-1.
24. NABI and CABI retain their existing scalar/pointer contracts and profiles. VAPI gains no struct declarations or metadata.
25. Future typed pointers and address-of must consume exact FieldPlace authority instead of reconstructing fields from names or LLVM offsets.

All struct identities are collected before resolving any field types, function
signatures, or bodies. Type-name authority is separate from callable and value
namespaces. A function may share a struct's name. Checked declarations retain
symbols and scalar expressions, never syntax as type identity.

`StructSymbol` owns its canonical `StructType` and ordered `StructFieldSymbol`s.
The type carries only nominal identity and a display name, with no symbol
backlink. Fields weakly reference their containing symbol. Core and CFG retain
that safe shared type authority and translate descriptors/fields into their own
objects through temporary exact maps. A program owns descriptors; a function
owns aggregate bases and canonical projections. A projection strongly retains
its base and field, while neither base nor field retains the projection. Field
to descriptor backlinks use expiring WeakRef. There is no ownership cycle.

Core represents one declaration as a contiguous sequence of scalar Initialize
operations in written order. Every field is initialized exactly once within the
same structured block; the aggregate base receives no aggregate Value. Complete
field initialization establishes the base's initialized state. Core also rejects
field Loads/Stores before the complete sequence is available. CFG preserves
ordered Initialize operations while ordinary expression lowering may split an
initializer across blocks. It does not add aggregate definite-assignment analysis.

Promotion order is scalar source locals in local ordinal order, then fields by
containing local ordinal and declaration field ordinal, then compiler temporaries.
SSA carries only scalar values and copied debug provenance (`p.x`, local ordinal,
field ordinal). It retains no StructType, descriptor, aggregate base, projection,
or upstream symbol. Existing no-struct dumps remain unchanged.

Distinct fields of a local and the same field of different locals are disjoint
storage projections in this milestone. No address-of, struct pointer, union,
overlap, or whole-aggregate operation can introduce an alias. Future addressability,
aggregate copies, unions, and ownership must revisit this proof and promotion
eligibility. This decision does not preselect their representation or ABI.

No architectural review trigger was needed: ordinary scalar Initialize/Load/Store,
initialization-dominated promotion, branch/loop block arguments, and existing LLVM
lowering suffice. See [language rules](../language/structs.md),
[field Places](../ir/field-places.md), and qualification.
