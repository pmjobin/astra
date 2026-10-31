# 0024: Opaque nullable raw pointers

Status: accepted for ASTRA-PTR-1.

Astra needs to transport real C handles through native functions and local
control flow without assigning pointee layout, lifetime, or ownership semantics.
The existing semantic type, Place, SSA, and independent ABI boundaries can express
this without making a host pointer or LLVM type language authority.

1. `void*` is an Astra semantic value type, distinct from `void`, `int`, and `bool`.
2. PTR-1 supports exactly the `void*` pointee form. Typed, deep, and function pointers are unsupported.
3. Every current raw pointer is nullable; there is no non-null raw pointer type.
4. `null` is the unique null raw-pointer value. It directly has canonical `void*` type; it is never an Astra integer zero.
5. A raw pointer carries no ownership of its pointee.
6. Copying it acquires, releases, or duplicates nothing.
7. Destroying it performs no pointee cleanup. Compiler object destruction concerns compiler models, never foreign storage.
8. Raw pointers cannot currently be dereferenced or indexed.
9. Astra cannot create one from its own storage through address-of, ref/out, or capture.
10. No conversion to or from integers, cast syntax, or pointer arithmetic exists.
11. `==` and `!=` compare address identity only, including null; both operands must have the exact same semantic type.
12. Pointer ordering is undefined in the language and relational expressions reject.
13. Pointer truthiness is unsupported. Conditions and logical operands remain bool-only.
14. Native transport uses the distinct `NativeScalarType.PTR` channel, with direct parameters/results and no hidden channels.
15. C `void*` transport uses the distinct `CAbiScalarType.PTR` channel for imports and exports.
16. Native PTR and C PTR are separate ABI-domain identities even when both map to LLVM `ptr`; exports keep an explicit external/ccc wrapper around the internal/fastcc implementation.
17. Semantic pointer identity is independent of machine pointer width.
18. Backend target/data layout determines pointer width. No semantic width, layout, integer carrier, or host typedef is introduced.
19. Current raw-pointer locals remain scalar-promotable: their values can denote foreign addresses, but their own Place addresses cannot escape.
20. Future address-of, ref/out, dereference, capture, or ownership work must explicitly reconsider aliasing and promotion eligibility.
21. Nullable `void*` does not freeze future typed-pointer nullability. Future types may generalize null conversion; PTR-1 introduces no contextual conversion machinery.
22. VAPI metadata enriches the existing C declaration path. Aliases and opaque header names stay orthogonal to pointer semantics and never authorize header parsing or define layout.

Each analysis owns one `RawPointerType` whose pointee is that universe's canonical
void type. Core/CFG/SSA retain semantic types and source provenance independently
of frontend lifetimes, with explicit null values and ordinary pointer-typed
parameters, Places, and definitions. The alternative of treating `void` as a
pointer would conflate an absent result with a value. Using an integer carrier
would incorrectly introduce width and conversion semantics. Neither is needed.

Native signatures containing PTR select `scalar-ptr-v1`; pointer-free native
signatures keep `scalar-v0`. C import/export signatures independently select
their C profile by the same rule. Pointer-valued body locals do not select a
native profile. Both scalar-v0 contracts remain frozen and reject PTR channels.

LLVM realizes both channels as opaque default-address-space `ptr`, null with
`LLVMConstPointerNull`, equality with pointer `icmp eq/ne`, and block arguments
with `phi ptr`. No pointer/integer conversions or `nonnull`, `noalias`,
`dereferenceable`, `align`, `nocapture`, `readonly`, or `writeonly` guarantees are
inferred. Foreign calls remain conservatively effectful.

Static-lifetime C test handles demonstrate real identities and nullable
roundtrips without allocation, free, or any Astra access to pointees. A handle
may dangle if foreign code invalidates it; transport establishes no lifetime
validation or dereference safety. No ownership, allocation, aggregates, strings,
callbacks, variadics, C bool, header parsing, GIR, or GObject support is added.
