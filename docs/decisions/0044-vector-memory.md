# 0044: Typed vector pointers and whole-vector memory

Status: accepted for ASTRA-VEC-MEM-1. Extends [0043](0043-typed-data-pointers.md).
Qualified execution target: default x86-64 Linux, as for VEC-1/F32-1.

## Decision

1. A currently supported numeric VectorType is a valid TypedPointerType pointee.
2. Scalar, native struct, and vector pointers use the same TypedPointerType.
3. Vector dereference uses the existing DereferencePlace at every IR stage.
4. A vector memory object contains one whole, exact VectorType value.
5. Loading a vector preserves one semantic value.
6. Loading produces one Astra SSA vector value.
7. A whole-vector store consumes one whole vector value.
8. Taking a vector local's address makes that local explicitly addressable.
9. Address-taken vectors cease ordinary whole-vector SSA promotion throughout
   their checked lifetime, including before a late or unreachable address-of.
10. Non-address-taken vectors remain fully promotable.
11. Direct and indirect accesses to one object remain coherent.
12. Multiple mutable vector pointers may alias one object.
13. Existing typed-pointer borrowing governs lifetime, not exclusivity.
14. Exact pointee identity includes element type and lane count.
15. `int<N>*` and `i32<N>*` are the same semantic type.
16. Signed and unsigned vector pointer types remain distinct.
17. `bool<N>*` remains unsupported. Logical bool lanes and LLVM `<N x i1>`
    boundary transport do not freeze scalar bool objects, mask memory layout,
    packed versus byte representation, or alignment.
18. Vector dereference is whole-vector only.
19. Vector lane extraction remains a value operation.
20. Vector lane assignment remains unsupported.
21. `(*p)[k]` loads one whole vector, then extracts a value.
22. `(*p)[k] = x` is invalid.
23. Lane mutation through memory uses whole-vector read/modify/write:
    `*p = insert(*p,k,x)`.
24. Vector memory adds no numeric semantics.
25. Integer vector memory preserves exact lane bit patterns and signedness.
26. F32 vector memory preserves exact binary32 lane values.
27. Plain load/store introduces no f32 arithmetic rounding point or fast math.
28. Vector load/store makes no source-language atomicity guarantee.
29. A backend may split or otherwise legalize a vector memory operation.
30. Physical scalarization does not create Astra semantic lane operations.
31. A non-null typed vector pointer denotes a live, suitably aligned object
    of its exact VectorType.
32. Numeric alignment belongs to the target/backend; it is not source-visible.
33. Current pointer construction guarantees alignment: addresses of initialized
    supported direct locals and compatible Astra-native pointer forwarding.
34. Arbitrary addresses and unaligned accesses remain unsupported.
35. Vector pointer arithmetic and indexing remain unsupported.
36. Native vector pointers use existing PTR channels and opaque LLVM `ptr`.
37. A vector pointee alone does not select NABI vector-v4.
38. Actual by-value vector parameters/results continue to select vector-v4.
39. C vector pointers, C vector ABI, and foreign vector-pointer syntax remain
    unsupported; no NABI version or CABI/VAPI capability is added.
40. Future arrays, slices, and vector streams must extend this foundation
    without weakening typed pointers' lifetime, identity, or alignment rules.

## Representation and consequences

The shared capability predicate admits numeric vectors with existing valid
shapes. Existing Core/CFG/SSA verifiers recursively validate their exact
canonical element and vector identities. General PointerTypeSyntax composes
VectorTypeSyntax with a star; existing scalar star tokens retain their format.
No VectorPointerType, vector-specific memory Place, lane Place, or separate
vector-memory instruction family is introduced.

LocalSymbol.address_taken flows through CoreLocalPlace and CfgLocalPlace to
SsaAddressableLocal/SsaLocalMemoryPlace. Initialize writes the normally
constructed vector once per declaration execution. Loads and stores remain
ordered effects. Pointer values can promote independently of their objects.
There is no competing promoted copy of addressable vector storage.

The backend's existing exact vector type mapper supplies `alloca <N x T>`,
`load <N x T>`, and `store <N x T>`. LLVM supplies alignment, audited against
configured target ABI layout; the frontend contains no payload-width-to-alignment
rule. Null guards reuse DPTR's trap and physical-final-block authority. Null
store RHS effects occur before the guard; no null path performs memory access.

Object byte order, lane byte offsets, packing, padding, numeric alignment,
`sizeof` and `alignof` are not exposed. Ordinary memory is neither volatile nor
atomic. No synchronization, concurrent visibility, or tearing contract is added.
One semantic operation need not be one machine instruction.

The flagship requires explicit RHS splats in vector comparisons to receive the
checked left vector's exact context. This extends existing literal context,
without implicit broadcasting or conversion. Extraction after dereference also
retains the established scalar integer literal context. Evaluation remains once,
left to right. No vector arithmetic, lane, DSP, dot, or MAC rule changes.

Parameters remain function-region borrows; results still require a future
return-lifetime contract. Direct-local-only address syntax is unchanged:
parameters, fields, dereferences, and lanes cannot be addressed. Pointer casts,
raw conversions, nested pointers, Resource*, bool memory, vector struct fields,
arrays/slices, unaligned, volatile, atomic, gather/scatter and foreign vector
memory remain outside this decision.

See [language](../language/vector-memory.md), [IR](../ir/vector-memory.md), and
qualification.
