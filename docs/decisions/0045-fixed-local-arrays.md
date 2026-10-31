# 0045: Fixed local arrays and indexed element Places

Status: accepted for ASTRA-ARRAY-1. Builds on [0044](0044-vector-memory.md).
Qualified execution target: default x86-64 Linux.

## Decision

1. Fixed arrays are contiguous storage aggregates.
2. Arrays are distinct from arithmetic vector values.
3. Arrays are distinct from typed pointers and never decay to pointers.
4. Arrays are distinct from future borrowed bounded slices.
5. Array length is compile-time type information.
6. Exact element identity and length define canonical ArrayType identity.
7. `int[N]` and `i32[N]` have identical ArrayType identity.
8. ARRAY-1 has no whole-array values, copying, equality or assignment.
9. Every array local is storage-backed from its declaration.
10. Whole arrays do not undergo Astra SSA promotion.
11. Individual accesses remain explicit Place operations.
12. Indexing a direct array local produces ArrayElementPlace.
13. ArrayElementPlace is writable exact element storage.
14. Vector lane extraction remains a non-writable Value.
15. Array indices may be dynamic scalar integers of any existing IntegerType.
16. Indices retain their exact mathematical integer meaning, independently of element type.
17. The valid index domain is `0 <= index < length`.
18. A negative dynamic index traps.
19. An index at or above the length traps, including large unsigned indices.
20. Invalid direct checked integer constants reject statically; general constant folding is not required.
21. No invalid source index reaches physical element GEP, load or store.
22. Each written index expression evaluates exactly once per access.
23. Assignment evaluates its LHS index before its RHS.
24. LHS bounds failure occurs before any RHS evaluation.
25. Array initialization is complete and ordered.
26. There is no implicit default initialization.
27. Initializer expressions execute left-to-right, with their values captured in that order.
28. Numeric vector elements are whole vector objects in storage.
29. Indexing an array of vectors produces a whole-vector Place.
30. Reading that Place produces one whole vector Value.
31. Writing that Place consumes one whole vector Value.
32. Arrays introduce no vector LanePlace, including through `blocks[i][k]`.
33. Bool object representation remains unfrozen; scalar bool and mask-vector arrays reject.
34. Pointer arrays are deferred pending aggregate borrow provenance and replacement/join rules.
35. Resource arrays are deferred pending aggregate ownership, initialization and cleanup rules.
36. Struct arrays are deferred pending complete aggregate element/value semantics.
37. No array ABI or array parameter/result is introduced.
38. No C array representation or VAPI array capability is promised.
39. LLVM array types and GEP are backend realizations, not upstream pointer arithmetic.
40. Future slices should borrow contiguous array element storage through deliberate lifetime rules, without C-style decay.

## Scope and representation

The grammar is `array-element-type "[" array-length "]"`, where the length is
one unsuffixed positive decimal integer literal. The current capability is
1..1024 inclusive. This bound limits accidental automatic storage while the
storage/resource model develops; it is not a permanent language maximum.
Supported elements are i8, u8, i16, u16, int/i32, u32, f32, and all twenty current
numeric vector shapes. Nested arrays, heap/dynamic arrays, computed lengths,
array address-of, element address-of, array pointers, pointer indexing/arithmetic,
length operators, unchecked indexing and iteration syntax remain outside scope.

The local becomes visible only after all N exact-typed initializers finish.
A trapping initializer follows existing non-unwinding termination semantics;
normal execution cannot observe a partially initialized array.

CoreArrayInitialize owns an ordered list of element Values, never an array
Value. CFG captures each initializer before starting the next and retains a
CfgArrayInitialize operation. SSA retains SsaArrayInitialize with one
SsaAddressableLocal. LLVM stores the captured values in ascending element order.
Delaying those stores until all expressions complete is observationally valid:
the local is unavailable throughout initialization and its address cannot escape.
This representation makes exact count and element typing directly verifiable.

Dynamic CFG/SSA bounds checks produce a validated integer index associated with
one exact storage object. The indexed Place consumes that result. Verifiers
require the check to precede and dominate its use; an ordinary integer result
cannot substitute for bounds authority. Direct valid integer constants need no
check instruction. Signedness and exact ArrayType length survive through SSA.

The backend compares in the original index width. It tests signed negativity
and the upper bound when N is representable in the index's positive domain;
otherwise that upper test is unnecessary. After validation it zero-extends the
nonnegative index to i64 and emits plain `getelementptr [N x T], ptr ..., 0, i`.
The existing actual-final-physical-block authority handles phi inputs after guards.
The GEP has no `inbounds` promise. LLVM's [GEP reference](https://llvm.org/docs/LangRef.html#getelementptr-instruction)
explains the additional contracts associated with that flag.

Array elements form one ascending contiguous sequence of exact T objects.
Target data layout supplies array and element alignment, including vectors;
no 16-byte frontend rule, byte stride, sizeof, numeric address or endianness
operation becomes source-visible. LLVM may scalarize storage downstream;
Astra retains one storage object and whole-vector element loads/stores.

## Alternatives and consequences

Per-element synthetic locals would discard stable aggregate storage identity.
Whole-array SSA values would invent copying and ABI semantics. Both conflict
with the storage foundation required by future slices. Extending existing
LocalPlace/SsaAddressableLocal with an indexed Place avoids those changes.

A guard attached only to the final Store would evaluate an effectful RHS too
early. An explicit ordered bounds operation solves this while preserving
ordinary Load/Store and the current CFG/SSA architecture. Vector extraction
still checks literal lane indices semantically; the shared bracket parser now
accepts expression indices so that arrays can use dynamic ordinals.

See [arrays](../language/arrays.md), [array Places](../ir/array-places.md), and
qualification.
