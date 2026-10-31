# 0043: General typed data pointers and scalar dereference Places

Status: accepted for ASTRA-DPTR-1.

Baseline: ASTRA-BIT-1, `92de911f9655fc06ce7057b6f0a07429e85915ea`.

## Context and decision

TPTR-1 and BORROW-1 established exact struct pointers, addressable local storage,
ordered memory Places, nullable native PTR transport, and lexical lifetime
proofs. Scalar memory needs those same authorities. DPTR-1 generalizes them;
numeric/vector value semantics, ownership, CFG/SSA algorithms, and physical
predecessor tracking retain their existing contracts.

1. Astra has one semantic constructor, `TypedPointerType(pointee)`, canonicalized
   by exact immutable pointee identity.
2. Existing `Struct*` uses this same constructor. `RawPointerType` now denotes
   only opaque `void*`; it is not `TypedPointerType(void)`.
3. Exact pointee identity is part of typed-pointer identity at every semantic IR
   stage. There is no downstream lookup of a pointee by source spelling.
4. `int*` and `i32*` are one type because `int` and `i32` are one type.
5. `i8*` and `u8*` are distinct, as are other differing pointees, including a
   struct and an integer of any width.
6. LLVM opaque `ptr` cannot erase these distinctions upstream. Physical erasure
   follows exact native argument validation.
7. Typed pointers are nullable. Contextual null and exact-type `==`/`!=` apply;
   truthiness and ordering do not.
8. Typed pointers are non-owning, trivially copied values with no cleanup duty.
9. Compiler-created typed pointers carry BORROW-1 lexical provenance. Checked
   region objects prove the same/ancestor outlives rule; immutable provenance
   snapshots accompany addresses and dereference Places after checking.
10. Multiple mutable pointers may alias the same live storage, including two
    parameters receiving `&x` in one call.
11. Typed pointers imply no exclusivity, `noalias`, or points-to proof.
12. Typed pointers imply no readonly access. A native parameter may mutate its
    pointee, and callers must observe that mutation.
13. Address-of exposes authoritative storage identity; it is not a copy or
    numeric conversion.
14. Taking a supported scalar local's address marks that local explicitly
    addressable, including stored and call-bound borrows.
15. An address-taken scalar local stays outside ordinary Astra scalar promotion
    for its whole checked lifetime, including before the first executed borrow.
16. Initialization, direct access, and pointer access use the same storage.
    Non-address-taken locals remain promotable, as do pointer values themselves.
17. Scalar dereference produces a Place. Vector lane extraction remains a value
    operation: `*p = x` is legal; `v[k] = x` is not.
18. Reading a dereference is `Place → Load → Value`, using existing load nodes.
19. Writing a dereference uses an existing Store. Evaluate its pointer base
    once, then the RHS, then the store (including its null guard), left-to-right.
20. Dereferencing null traps explicitly with the existing non-unwinding policy.
21. The null path reaches a non-returning trap before a physical load/store;
    only the non-null successor performs the access.
22. Direct whole-value dereference is a centralized capability, true for the
    integer types and f32 only. Exact pointee type determines each load/store.
23. Integer signedness changes interpretation, not storage width: i8/u8 use i8,
    i16/u16 use i16, and int/i32/u32 use i32 in LLVM.
24. Plain f32 loads/stores preserve binary32 value bits. They create no
    arithmetic rounding point or fast-math license, including for signed zero,
    subnormal values, infinity, and runtime NaN.
25. `bool*` stays unsupported: B1 transport has not established bool memory
    representation, width, or alignment.
26. `Resource*` stays unsupported: it would address an ownership-bearing handle
    slot and needs explicit slot mutation/ownership semantics.
27. Pointer-to-pointer stays unsupported, including `int**`, `Pair**`, `void**`,
    and address-of pointer locals.
28. `VectorType*` stays unsupported until VEC-MEM-1 reviews object alignment,
    physical vector memory, scalarization, and unaligned operations.
29. Typed pointers have no arithmetic, subtraction distance, indexing, or
    increment/decrement. `p[0]` is not an alias for `*p` in Astra.
30. Typed pointers have no source casts, pointer/integer conversions, or
    typed/void conversions. ICONV-1 remains integer-only.
31. Native typed-pointer parameters use existing `NativeScalarType.PTR`.
    Existing profile selection is unchanged; no DPTR channel/profile is added.
32. Typed-pointer results stay unsupported pending signature lifetime contracts.
    Whole-struct `*p` values also remain unsupported; `p->field` remains a field
    Place and preserves its existing evaluation order and dumps.
33. C typed-pointer boundaries stay unsupported in source imports, exports, and
    VAPI. Physical width does not define a portable C object contract.
34. No stable native layout, size, numeric alignment, pointer-width query,
    `sizeof`, or `alignof` is introduced. Nor are arrays, slices, volatile, or
    atomic memory.
35. A well-formed non-null `T*` denotes a suitably aligned live object of its
    exact pointee type.
36. Direct initialized local address construction and compatible native
    forwarding maintain that invariant statically. Parameters, fields,
    dereferences, temporaries, and vector lanes cannot newly be addressed.
37. Future unaligned, vector, array, or foreign-memory operations must explicitly
    extend this contract rather than weaken it. Vector memory should extend
    `TypedPointerType` and the memory Place hierarchy, not add a parallel system.

## Implementation consequences

`TypedPointerType` owns its immutable pointee; stages retain this authority
without retaining checked symbols. Core and CFG retain address-taken LocalPlaces
and dedicated DereferencePlaces. SSA generalizes `SsaAddressableStruct` into
`SsaAddressableLocal` and adds local/dereference variants to `SsaMemoryPlace`.
Struct field projections retain their descriptors and behavior. No scalar
shadow value competes with addressable memory.

LLVM entry allocas use target-appropriate backend alignment and exact scalar
types. Dereference lowering reuses `guard_nonnull` and the existing final
physical block authority used by struct accesses, division, and shifts. Direct
scalar dereference needs no GEP. LLVM may subsequently optimize storage only
when alias behavior is preserved.

See the [source guide](../language/typed-data-pointers.md),
[Place contract](../ir/dereference-places.md), and
qualification report.
