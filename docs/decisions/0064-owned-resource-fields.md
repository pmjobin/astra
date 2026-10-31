# ADR 0064: owned Resource fields and native class RAII

Status: implemented for ASTRA-OWN-FIELD-1.

## Context

The accepted baseline is ASTRA-CABI-FP-1,
`07d76c50d0816ee1a14409b518bf183915934f9b`. Nominal Resources already have
an exact nullable handle representation and direct release authority. Storing
that responsibility in a native class does not relocate Astra object storage.
Class owners, by contrast, can refer to caller, ancestor or result storage.
Resource-bearing structs would change the accepted copyable value model.
Neither storage-provenance policy nor aggregate Move belongs in this milestone.

## Frozen decisions

1. Native classes may declare explicit `owned R field;` for an exact nominal Resource.
2. Ownership is a declaration and transfer contract separate from Resource type identity.
3. No OwnedType, wrapper type or new TypeKind is created.
4. Plain Resource fields remain unsupported.
5. Owned ClassType fields remain unsupported pending a storage-provenance solution.
6. Native structs gain no owned fields or Resource fields.
7. Generic structs gain no owned fields or Resource fields.
8. Generic `owned T` fields remain unsupported; generic classes are not introduced.
9. Every owned field has one exact release authority from its nominal Resource declaration, including VAPI declarations.
10. All owned fields must initialize exactly once on each normal constructor completion path. Classes with owned fields require explicit `init`; brace acquisition is not added.
11. Initialization transfers responsibility into the destination field.
12. A moved constructor parameter is no longer responsible for cleanup.
13. Initialization never loads or cleans the uninitialized destination.
14. An initialized owned field can be replaced throughout the live object lifetime.
15. Replacement evaluates and captures the incoming owner before loading or cleaning the old field.
16. A trap in incoming evaluation performs no old-field cleanup or store for that replacement; explicit side effects inside the producer remain effective. Traps do not unwind.
17. Receiver validation precedes incoming evaluation and ownership consumption.
18. Replacement releases the old non-null owner exactly once before storing the incoming handle.
19. A named incoming owner becomes MOVED at successful transfer and is not subsequently cleaned by that binding.
20. A direct exact owned Resource result can initialize or replace a field without an intermediate owner local.
21. Non-consuming field use uses temporary Resource borrowing, including existing null comparisons.
22. A borrow never duplicates release responsibility and cannot be stored or returned. Potentially overlapping access to the containing object during a field borrow is rejected conservatively.
23. Moving ownership out of a field is deferred, including self-move and field-to-field move.
24. Explicit release of a field is deferred, including in deinit.
25. A successfully initialized field remains an initialized ownership slot for the rest of the live object lifetime.
26. A slot may contain a concrete Resource domain's legally obtained null owner.
27. Null cleanup performs no release call, under existing Resource semantics.
28. No runtime active flag is necessary.
29. Field lifetime is subordinate to the containing object's lifetime.
30. Containing-object owner transfer transfers responsibility for eventual field cleanup transitively.
31. Object moves do not individually move field handles.
32. Object result construction and forwarding preserve exact ObjectStorage and handle bits.
33. User deinit runs while owned fields are live and mutable. Ordinary replacement is legal directly, through methods, and through already-legal setters.
34. Automatic cleanup runs after normal user-deinit completion and cleans the CURRENT final field contents. A class without user deinit still receives this cleanup.
35. Automatic field cleanup follows reverse declaration order, ignoring non-owning fields.
36. Reverse order is deterministic language semantics, not a backend optimization choice.
37. A user-deinit trap runs no subsequent automatic cleanup. Prior completed replacements remain effective; there is no rollback.
38. Constructor traps do not unwind previously initialized fields or constructor locals; partial-construction unwinding is not introduced.
39. No heap allocation is introduced.
40. No object-header bit is introduced.
41. No field-active bitmap exists.
42. No generic destructor callback exists.
43. No runtime ownership table exists.
44. Release targets remain exact direct semantic identities; there is no runtime dispatch or handle-equality guard.
45. Each field occupies the existing Resource-handle physical representation in native class ObjectStorage.
46. No NABI type or profile is added.
47. Object parameter and result-storage ABIs are unchanged.
48. CABI/VAPI class-layout export or import is not added, and struct ABI policies remain unchanged.
49. Existing Ownable generic functions continue to dispose, relay and recursively forward the containing class without field-by-field work.
50. Future owned class and aggregate owner fields must extend these RAII rules without weakening storage provenance or silently changing copyable structs.

## Replacement and destruction

Replacement orders receiver validation, incoming evaluation/capture, source
consumption, old-handle load and conditional release, then new-handle store.
There is no source-visible empty slot. The incoming owner is captured once.
No ordinary Astra code runs between old cleanup and the store; Resource release
contracts remain the existing foreign boundary, without native object callbacks.

The accepted §76 clarification preserves the baseline mutable live receiver:

```text
live object
  user deinit body: borrow/use/replace through ordinary member paths
  normal return
  automatic cleanup of final contents, in reverse declaration order
object lifetime ends
```

If deinit replaces A with B, A releases during replacement and B releases after
normal deinit return. A→B→C releases A, B, then C. A trap after A→B releases A
but does not run B's automatic cleanup. Move-out and release-to-empty remain
illegal throughout these phases. No destructor-specific prohibition, call-graph
restriction, ownership state, or runtime mechanism is added.

## Temporary borrow overlap

The first runtime implementation exposed a concrete stale-handle hazard:
`mutate(context, context.resource)` could replace the field before using its
borrowed argument. The same hazard exists when a later argument evaluates a
mutating call. The implementation conservatively rejects passing a field borrow
alongside a receiver/argument of its containing ClassType, and passing such an
object capability to a later nested call while the field borrow is pending.
Different references of the same ClassType may alias; no noalias assumption is
made. A later direct scalar field read and multiple field borrows remain legal.
Nested calls that finish a borrow before subsequent object access are legal.
This restriction applies uniformly, including in deinit. It is temporary borrow
validation, not a destructor effect system or a runtime borrow flag.

## Representation

The shared FieldSymbol retains `owned_cleanup`, its exact HandleType, ordinal,
source spans and OWNED_FIELD role. CheckedOwnedFieldTransfer distinguishes init
from replacement. CheckedOwnedFieldBorrow retains the exact field Place and
borrowed parameter (or null-test context).

Core owns independent field/cleanup identities, CoreOwnedFieldTransfer,
CoreOwnedFieldBorrow, and the CoreDestructor's ordered CoreOwnedFieldCleanup
epilogue. A missing user destructor gets a compiler-synthesized exact native
destructor. Core verifies contracts, initialization, use, and cleanup order.
CFG expands transfers into concrete Resource capture, cleanup and store actions.
SSA has ordinary handles, memory and direct cleanup calls. LLVM has no field
ownership policy; ABI and physical pointer lowering are reused.

See [language rules](../language/owned-resource-fields.md),
[IR](../ir/owned-resource-fields.md), and qualification.
