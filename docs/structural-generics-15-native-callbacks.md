# Native callback declaration contracts

The compiler now exports two separate sets of direct Fn input ordinals:
`readonly_inputs` conditions the producer's readonly summary, while
`callback_inputs` states the callback requirements for any valid invocation.
For example, ordinary `apply(value, callback)` may mutate through its callback
outside a protected scope. Map lookup requires an observing callback because it
passes a live stored owner to the query. A dependent library preserves that
requirement without receiving the Map implementation.

Each phase reconstructs its call graph and input substitutions independently.
Imported declarations supply immutable producer contracts; empty declaration
bodies establish no effects. Native ABI validation recomputes the summaries,
and detached verification checks their original snapshots. Canonical masks,
the typed signature and the existing object symbol fingerprints reject missing,
malformed or altered metadata before emission. The development ABI remains
compiler pinned and requires rebuilding all units.

Scoped iteration and `with` protection survive lowering. The latter uses the
existing possible owner/child alias rules. CFG and SSA reject erasure of their
original protection markers. Call traversal also follows ownership producers,
task creation, awaiting and async operation wrappers. Analysis frontier closures
are created separately from probe closures to avoid a Vala closure-storage
reference cycle; retirement controls cover all four phases.

The new unit witness compiles the actual `lib/astra/collections/map.astra`
declaration into the leaf producer, hides task-owned producer source copies,
imports its selected closed methods into a middle library, then compiles a
client importing only that middle interface. It queries copied generic results,
checks a missing key and repeated observation, permits independent ordinary
mutation, and checks exact resource retirement. The recipe checks all eight mixed O0/O2 graphs
and O1 smoke with unsuppressed Valgrind. Mutating protected callbacks and
altered metadata fail. No fixture names participate in compiler admission.

Stored Fn fields and higher-order invocation-dependent effect transport are
still outside this callback declaration profile. Plain native Fn values cannot
silently erase callback preconditions; the binder rejects that transport.
Existing Fn signature restrictions also reject nested Fn parameter signatures.
