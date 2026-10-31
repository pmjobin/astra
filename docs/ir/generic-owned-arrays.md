# Generic array ownership before concrete Core

GenericSliceObligations records COPY, STORAGE, ZERO and DESTRUCTION separately by
exact lexical TypeParameterType identity. Semantic checking and the independent Core
verifier require the complete current BUFFER contract and validate its signature
origin. Concrete admission continues through the existing copyability and element
authorities with each stage's own field graph. Allocation cannot use a mere copy
premise or an obligation attached to another same-spelled token.

| Operation | Parameterized contract | Concrete realization |
| --- | --- | --- |
| Incoming/local owner | SliceType<T>, exact owner slot, lexical scope and buffer cleanup | Existing complete SliceType<E> owner group |
| Allocation | OwnedBufferAllocate, int count, scoped complete element proof | Existing checked zero-initializing allocation |
| Temporary borrow | Exact owner identity and bounded borrow consumer | Existing buffer read/view and provenance |
| Move/return | One compatible owner or paired direct result producer | Base/count capture and whole-group disarm |
| Replacement/rearm | Stable destination cleanup and incoming producer/source | Incoming production, old cleanup, complete publication |
| [Owner exchange](owned-buffer-exchange.md) | Two live slots with the same lexical element and cleanup identity | Ordered destination captures, then complete descriptor permutation |
| Scope exit/release | Existing ownership possibility set and lexical order | Concrete conditional cleanup authority |

CoreCleanupContract.is_symbolic_buffer distinguishes unresolved element responsibility
from direct Ownable T and concrete cleanup. Its logical BufferValueShape has only
immutable type leaves; it has no target byte layout, C symbol or callback. Materialization
filters symbolic cleanup inventories, interns the exact concrete slice, independently
validates the complete element shape, and maps every owner/producer cleanup use to the
concrete contract. Concrete slices and applications retain their existing memoization.
The result contains no generic definition, proof or symbolic cleanup.

The shared structured proof records READ, MOVE, RELEASE and ACQUIRE in source order.
Choices and loop fixed points use OWNED/MOVED/RELEASED possibility sets. Acquisitions
reset rearmed slots; parameter identity remains separate from its mutable local slot.
Direct call borrows get a completion read after later arguments; completed inner calls
and copied elements do not leave a live view. Indexed places retain their owner through
index/RHS completion. Semantic inference fragments commit only on successful calls;
the Core verifier independently rebuilds the proof from its own model.

The cloner maps owner slots, local ordinals, acquired record parameters, storage cleanup
ranks, fields, optional receiver provenance, moves, releases, rearm and result producers.
No source-name reconstruction or body recheck occurs. An allocation or buffer-call node
has exactly one owning consumer. Invalid or half-disarmed groups remain subject to
concrete CFG/SSA checks; Core does not invent physical offsets.

Instance keys remain private immutable snapshots of definition plus ordered canonical
element arguments. No ownership qualifiers, addresses, counts, metadata or byte sizes
enter them. Existing 1,024 instance and 256 application/dependency bounds remain.

Numeric owners use buffer-v8 and record owners struct-elements-v11. Borrowed plans stay
separate even where raw PTR/I32 channels match. Backend-only return carriers are pairs;
there is no Astra aggregate SSA owner, hidden pointer, sret/byval or dictionary. Native
plans independently own element shape, role and group information and are checked for
correspondence before semantic/SSA graphs die. Retained artifacts own no compiler graph.
