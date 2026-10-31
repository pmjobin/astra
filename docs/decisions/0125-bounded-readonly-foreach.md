# ADR 0125: bounded readonly Bag traversal

`foreach (var item in diagnostics) { ... }` accepts a named exact generic Bag
owner or existing borrowed Bag parameter in synchronous concrete native code.
The binder is a temporary inspection view. It can be used only as an exact
borrowed Class argument to a direct nonthrowing scalar/void free function. It
cannot be copied, moved, returned, stored, projected directly or captured.
Existing fixed arrays and slices retain their existing explicit indexed loops;
this slice chooses the exact Bag source, without a general iterator protocol.

The collection has a scoped loan through the entire body, including nested
loops. Consuming, releasing, reserving, appending, taking, replacing, or passing
an overlapping collection alias to an uncertain helper rejects. Inspection
helpers are checked transitively against a conservative readonly subset:
scalar/text reads and local computation, branches and loops, direct bounded
native calls, and foreign scalar/text observations. Field writes, ownership
effects, allocation, pointer/handle foreign exposure, virtual calls and lazy
getter initialization reject. This effect check applies to indexed inspections
inside foreach too. Historical indexed inspections outside foreach retain
their prior contracts. Unknown effect shapes reject.

Semantic analysis creates a lexical hidden I32 index initialized once to zero,
an exact `index < len(backing)` condition, and a distinct `index + 1` step.
Checked and Core models retain independent iteration authority binding the loop
target, storage and hidden index. Core reconstructs the guard, initializer and
step and prevents writes to the index in the body. The existing for-loop CFG
then supplies cleanup, continue, break, return and checked-failure behavior.
Each element access uses the existing checked occupied-slot operation and exact
call-scoped loan. There is no element copy, new backend operation or ABI change.

An independent CFG mutation test exposed missing unique-definition enforcement
for existing slot-loan captures. The CFG verifier now rejects duplicate captures
before lowering to SSA. Existing slot-loan invalidation and exact consumer
checks remain in effect. A temporary CoreBuilder expression also exposed a Vala
generated-C lifetime issue; a strong local now retains the backing field place
through CoreSlotsValue construction.

Qualification uses public optimized programs with lifetime event traces,
unsuppressed Valgrind, source refusals with source locations, and independent
Checked/Core/CFG/SSA mutation and restore tests. A50 renders owned diagnostics
through the same readonly view, including empty and early-exit inputs. The
application corpus and final campaign integration are tracked separately.
