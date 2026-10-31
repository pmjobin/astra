# 0046 — Bounded borrowed slices

Status: accepted for ASTRA-SLICE-1, on the accepted ARRAY-1 storage model.

## Decision

1. `T[]` denotes a borrowed slice type.
2. `T[N]` remains a fixed array type.
3. SliceType identity depends only on exact element type; `int[] == i32[]`.
4. Runtime length does not participate in type identity.
5. A slice is a first-class local value.
6. A fixed array is not a first-class whole value.
7. Arrays never implicitly decay to slices.
8. Slice construction is explicit: `slice(array)` or `slice(array,start,count)`.
9. Slices are non-owning; copying copies the view, not its storage.
10. Slices carry lexical borrow provenance from their backing array.
11. Borrowing uses the existing BORROW/DPTR ancestor/same-region model.
12. Multiple mutable slices may alias, including overlapping subranges.
13. Borrowing provides lifetime safety, not exclusivity.
14. A slice has no null state, equality operation, or truthiness.
15. An empty slice is valid.
16. SLICE-1 length is an exact non-negative `int`.
17. Every constructor proves length <= ARRAY-1's current 1024-element bound;
    every resulting length therefore fits int exactly.
18. `len(slice)` returns int and evaluates its slice operand exactly once.
19. `len(array_local)` returns int and needs no runtime evaluation.
20. Slice indexing accepts every scalar IntegerType.
21. An index denotes its exact mathematical integer value, without conversion.
22. A valid index satisfies `0 <= index < runtime_length`.
23. Every invalid index traps, including every index into an empty slice.
24. No invalid index reaches physical address calculation, load, or store.
25. Slice indexing yields SliceElementPlace.
26. SliceElementPlace is writable, using existing Load/Store operations.
27. Supported elements are ARRAY-1's scalar integers/f32 and numeric vectors.
28. Vector slice elements are whole vector objects.
29. `view[i][lane]` loads the whole vector, then extracts a lane Value.
30. No LanePlace is introduced; vector lane assignment remains invalid.
31. Full-array construction borrows the entire direct fixed-array local.
32. Subrange construction validates start/count before a usable view exists.
33. Start/count measure element objects, never bytes or vector lanes.
34. Zero-length subranges are valid.
35. `slice(array,N,0)` is valid.
36. A zero-length view has no dereferenceable element.
37. Its physical data pointer may be null; this does not create source nullability.
38. Slice locals require initialization and permit exact-type copies/rebinding
    while stored-borrow lifetime constraints hold.
39. Slice locals may be SSA-promoted as one semantic SliceValue.
40. Physical lowering may realize that value with multiple machine components.
41. Exact slice identity and base/length pairing survive until physical lowering.
42. SLICE-1 freezes no NABI/CABI slice representation or profile.
43. There is no exposed pointer extraction, `.data`, or pointer conversion.
44. Address-of slice elements is unsupported.
45. Future native boundaries must extend SliceType, rather than redefine slices
    as raw pointer/count conventions.

## Bounds and effects

Start and count each accept any scalar IntegerType, independently. Evaluate
start, then count, exactly once each; only then validate the range. Even an
invalid start cannot suppress count's effects. Require `start >= 0`, `count >= 0`,
`start <= N`, and `count <= N - start`. Subtraction follows the start proof;
no overflow-prone `start + count` check is used. Direct checked integer constants
that prove an invalid range receive a static diagnostic. General folding is
not required.

Reads evaluate the slice expression, then index, validate, then load. Writes
evaluate the slice expression, then index, validate, then RHS, then store.
Bounds failure suppresses RHS effects. Base and extent come from the same
captured view. A constant index still requires the runtime length check.
Short-circuit guards can skip an access; eager boolean operations cannot.

## Representation and alternatives

BuiltinTypes interns SliceType by exact element identity, separately from
ArrayType, TypedPointerType and VectorType. Immutable types and provenance
snapshots have no syntax, symbol, region-tree, ABI or backend backlink.
Checked constructors use the array's region; stored slice reads conservatively
advertise their own local's region after legality is established. No runtime
lifetime metadata, move, release, rearm, or cleanup belongs to SliceType.
Bare lexical blocks use the same region/scope machinery as if/while bodies.

CoreSliceFromArrayValue and CfgSliceFromArrayValue retain one semantic view;
SsaSliceConstructInstruction produces one SliceType result. Ordinary slice-local
promotion yields one block argument at a branch/loop merge. Separate source
pointer and length locals were rejected because they would lose this pairing.
The indexed place remains distinct from ArrayElementPlace because its base and
runtime bound come from a value rather than fixed local storage.

LLVM uses one first-class `{ ptr, i32 }` aggregate locally. This fits existing
SSA value binding and phi construction without coordinated component maps or
any ABI changes. Full views insert the element-zero address and N. Subranges
validate first; nonempty views compute a plain element GEP, while empty views
select a null base on a path containing no element GEP. An internal pointer phi
joins these paths, then the base and length form one aggregate. Slice length
uses extractvalue. Element accesses check the captured extent before plain GEP
and exact scalar/vector load/store. The existing final-physical-block authority
supplies phi predecessors after all guard and empty-view splits.

All current IntegerTypes fit losslessly in signed i64. LLVM sign-extends signed
operands and zero-extends unsigned operands into that mathematical domain for
bounds comparisons. After validation, count narrows losslessly to i32 and valid
indices normalize for addressing. These are physical operations, not ICONV.
Alignment and stride come from backing array layout. No inbounds GEP, slice
runtime library, allocation, or production dependency is introduced.

## Deferred

Native slice parameters/results, NABI/CABI/VAPI slices, pointer-backed views,
raw pointer plus length, pointer arithmetic/indexing, slice subslicing,
readonly/nullable/unsafe slices, ownership, equality, properties, aggregate
slice fields/elements, nested slices, slice pointers, computed-place address
borrowing, unchecked indices, general aggregate values and usize are deferred.
Bool/mask, pointer, Resource and struct element storage remains unsupported.

The int length policy is bounded to current constructors, not a universal size
policy. A future source exceeding INT_MAX requires explicit size-type review.
Future ABI, foreign-memory, readonly and computed-address proposals must preserve
exact element identity, bounded extent, coherent value flow and lexical authority.
