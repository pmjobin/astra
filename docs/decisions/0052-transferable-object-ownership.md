# ADR 0052: Transferable lexical object ownership

Status: accepted for ASTRA-OBJ-OWN-1.

## Context and choice

OBJ-1 references copy and rebind. OBJ-LIFE-1 therefore attaches fixed destruction
to ObjectStorage, independently of the constructing reference's current value.
Retrofitting those references into move-only owners would invalidate accepted
programs. OBJ-OWN-1 instead makes transfer an explicit binding and call contract.

OWNBOUND already separates semantic capture from physical call commit. Its owner
slots, possibility-state analysis and lexical cleanup order can carry exact native
class cleanup authority alongside foreign Resource cleanup. A second ownership
solver, a distinct object storage representation and heap allocation are unnecessary.

## Frozen decisions

1. `owned ClassType` is an ownership contract, never a new semantic type.
2. A transferable lexical object binding is explicitly declared `owned`.
3. Fresh owned construction creates one ordinary exact ObjectStorage.
4. Its physical storage remains lexical and caller-allocated.
5. Consuming ownership needs no heap allocation.
6. The fresh binding initially holds the unique cleanup responsibility.
7. Unqualified construction remains fixed lexical and nontransferable.
8. Ordinary ClassType references cannot move as owners.
9. Object owners transfer only through explicit `move`.
10. Transfer carries responsibility for the exact same ObjectStorage.
11. Transfer never copies ObjectStorage.
12. Transfer never relocates ObjectStorage.
13. Semantic move invalidates the source owner immediately.
14. Physical source normalization to null is preferred and used.
15. MOVED is distinct from a legitimate nullable ClassType value.
16. Owned ClassType parameters may be null.
17. A null owned parameter owns no ObjectStorage.
18. A nonnull owned parameter receives exactly one ObjectStorage responsibility.
19. Owned parameters clean up on normal exit unless forwarded.
20. Object cleanup invokes the exact class DestructorSymbol when present.
21. A class without deinit still carries semantic lifetime responsibility.
22. Forwarding uses `move`.
23. Ownership does not imply readonly; field and method mutation remains permitted.
24. Ownership implies unique transferable responsibility.
25. Persistent ordinary aliases from owners are unsupported in this milestone.
26. Temporary borrowed/noescape calls are permitted.
27. Temporary method receiver use is permitted.
28. Temporary field access is permitted.
29. Passing an owner to `borrowed Counter` never consumes it.
30. Temporary borrowing ends with the expression/call, before later statements.
31. A same-call borrow may precede a move into that same call.
32. Later source use rejects after semantic capture, before physical commit.
33. Capture follows existing CALL/OWNBOUND left-to-right evaluation order.
34. Physical disarming commits immediately before invocation, after all arguments.
35. A pre-call argument trap does not commit transfer.
36. A trap after invocation does not unwind cleanup.
37. Consequently a transferred object may not deinitialize on a callee trap.
38. This matches the existing non-unwinding Resource ownership rule.
39. There is no runtime ownership stack.
40. There is no ownership bit in an object header.
41. There is no reference count.
42. There is no garbage collector.
43. Owned ClassType parameters physically use existing NativeScalarType.PTR.
44. There is no NativeObjectOwnerType or NativeOwnedObject type.
45. There is no new NABI profile.
46. Owned object and Resource parameters coexist with distinct cleanup domains.
47. Borrowed slices coexist through existing slice-v5 expansion.
48. Vector parameters coexist through existing vector-v4 channels.
49. All object results, including owned results, remain unsupported.
50. Later heap/escaping ownership must extend this exact responsibility model.

## Construction, cleanup and control flow

An owned local must be a complete fresh `C.init(...)` construction, or complete
brace construction when C has no explicit init. References, aliases, null and
`move other` are not local initializers. There is no ordinary owner assignment,
release or rearm. Exact ClassType identity forbids cross-class transfers.

An owned parameter has an immutable source binding and a promotable compiler
owner slot. It enters the same OWNED possibility state as Resource parameters,
including for null. OWNED/MOVED joins use the existing ownership fixed point;
MAYBE_OWNED is the established dump spelling for OWNED | MOVED. Reads and moves
require definitely OWNED. Conditional physical pointers merge with null for cleanup.

One cleanup list ranks fixed ObjectStorage and transferable owner slots. Root
locals clean before root parameters; parameters clean in reverse declaration
order. Return expressions finish before these actions. A constructor consuming
another object cleans its owned inputs before completing. Its destination storage
is distinct and becomes live only on successful construction.

The physical caller stack slot can outlive the object's semantic lifetime. The
callee cannot return that pointer or store it in fields, arrays or slices. No
allocator, deallocator, object copy, runtime active flag or lifetime intrinsic is
needed. Native destructor calls use existing fastcc and receive the original
pointer. Ownership supplies no `noalias`, `nonnull`, `readonly`, `byval` or `sret`.

## Temporary-view correctness

A borrow into an enclosing call cannot survive a nested consuming call that
already destroys its referent: `f(c, sink(move c))` rejects. By contrast,
`f(c, move c)` supplies the temporary view and responsibility to the same call.
The existing owned-borrow event and pending-call identities distinguish these
cases without a new object transfer engine.

Two additional concrete hazards require checking a temporary view at its actual
use. `c.field = sink(move c)` would store through a dead captured base. A callee
receiving `borrowed C view, owned C owner` may receive the same object; after
forwarding owner, reading view or a local copy of view could access a dead object.
The shared OwnershipFlow conservatively checks such input-derived views against
same-ClassType owned parameters. Existing borrowed-copy provenance is summarized
conservatively across assignments; a definitely separate fresh construction has
no such dependency. A same-call forward of both views remains valid. Method
receivers cannot consume themselves directly or through nested argument calls;
a borrowed receiver that may alias a consumed input is also checked at invocation.

This introduces no stored borrow from an owner, borrow-scope syntax or NLL. It may
reject an input-derived view that the caller knows points elsewhere: source type
alone cannot prove that separation. More precise stored-borrow/provenance proofs
are future work. The conservative check prevents the new same-call allowance
from weakening existing noescape lifetime guarantees.

## Deferred work

Object results need storage relocation, a caller-provided destination, an arena,
or heap ownership. Local owner destinations additionally need scope/provenance
and cleanup-rank transfer rules. Stored borrows need explicit lifetime proofs.
Early destruction/rearm, owned or reference fields, arrays/slices of object
references, heap allocation, inheritance, interfaces, properties and C/GObject
ownership remain outside this milestone.
