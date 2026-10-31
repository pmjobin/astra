# ADR 0053: Owned native object results

Status: accepted for ASTRA-OBJ-RET-1. Builds on accepted OBJ-OWN-1
`02e76fda0b570438b96e65decda8283712c0256f` and ADRs 0049–0052.

## Decision

1. Ordinary native functions and struct/class methods may return `owned ClassType`.
2. This is the existing `ResultOwnershipContract.OWNED_TRANSFER` contract on an exact ClassType, not a new type or ClassType variant.
3. Owned object results are nullable.
4. Their ordinary physical result is one PTR.
5. Fresh construction uses caller-provided candidate ObjectStorage.
6. The caller knows the exact result ClassType and reserves its exact backend layout and alignment, including distinct empty-object identity.
7. Caller-provided storage is compiler-private ABI machinery.
8. It is not a source pointer parameter, and source parameter ordinals do not change.
9. `return C.init(arguments);` initializes result storage directly.
10. Returning a fresh object copies no object bytes.
11. ObjectStorage is never relocated.
12. Fresh identity is exactly the identity of the supplied result storage.
13. No heap allocation is implied.
14. No `new` syntax is introduced.
15. `return null;` is legal.
16. Null activates no cleanup for candidate storage.
17. `return move parameter;` may forward an incoming owned object parameter.
18. Parameter forwarding preserves its original ObjectStorage identity.
19. `return inner(...);` may forward an exact owned-object result, threading the same result candidate.
20. A callee-local owned object cannot be returned by moving its binding.
21. Its physical ObjectStorage dies with the callee frame; copying or relocation cannot repair this within the contract.
22. Exact known storage provenance therefore determines object-result legality.
23. A fixed ClassType local cannot supply an ownership result.
24. A borrowed reference, including `this`, cannot supply an ownership result.
25. An owned-result acquisition creates one visible owned binding in the caller.
26. Caller responsibility activates only after the result call returns successfully.
27. Return transfer reuses OWNBOUND's Checked/Core ownership return, CFG capture and SSA ownership return machinery.
28. Return move disarms its source before lexical cleanup.
29. The result expression evaluates before all remaining lexical cleanup.
30. The callee never deinitializes its transferred result.
31. A null owner has no lifecycle responsibility.
32. Constructor traps remain non-unwinding.
33. Trapping construction produces no caller-visible owner and no result destructor.
34. There is no runtime result descriptor.
35. There is no runtime storage-kind tag.
36. There is no object header.
37. A null or forwarded result may leave the candidate physically unused.
38. Unused candidate bytes have no semantic ObjectStorage lifetime.
39. NABI uses its existing PTR channels.
40. No new NABI profile is needed for an object result.
41. One hidden result-storage PTR is a physical implementation detail, ordered before the receiver, if present, and all explicit parameter components.
42. The ordinary result remains PTR so fresh, nullable and forwarded ownership use the same signature.
43. CABI/VAPI object results remain unsupported.
44. Future heap allocation must interoperate with this ownership-result contract rather than replace it.

## Representation and alternatives

Each stage owns an exact result-storage input separate from its lexical storage
array. Caller allocations have a compile-time `result_candidate` marker; that
marker produces no runtime state. Candidate storage is attached to the producing
call, while the acquired owner receives the returned pointer. Cleanup follows that
pointer without comparing it with the candidate or allocating an active flag.

The alternative of returning a local construction would leave a dangling pointer.
Copying or relocating it would change storage identity. Heap allocation and a
source-visible storage parameter are unnecessary: the existing NABI signature
model accepts an independent hidden PTR plus a direct PTR result. Its physical
plan remains independent of semantic types and LLVM.

Exact legal provenance is RESULT_STORAGE, OWNED_PARAMETER_STORAGE,
FORWARDED_OWNED_RESULT or NULL. CALLEE_LOCAL_STORAGE and BORROWED_STORAGE reject.
Locals acquired from results are conservatively local: their producer could have
used the candidate. Acquiring and then returning such a local is not equivalent
to direct forwarding. A forwarding call cannot pass a local owner of its result
class to a callee that might return that same storage. No general region inference
or lifetime-polymorphic signature is introduced.

Fresh return construction is recognized only as the complete return expression
of an owned ClassType function. Existing lexical constructor initialization remains
valid. Brace returns are deferred: the existing brace grammar is tied to lexical
local declarations, and extending it is unnecessary for direct emplacement.
Classes requiring fresh results therefore declare an explicit `init`, including
empty classes. Classes without deinit work normally.

No result temporaries, direct `consume(factory())`, local owner moves, object
rearm/release, persistent owner aliases, object-reference fields, inheritance,
interfaces, properties, custom allocators or storage arenas are introduced.

## Qualification

See [object result language](../language/object-results.md),
[IR and physical lowering](../ir/object-results.md), and the
qualification and delivery report.
