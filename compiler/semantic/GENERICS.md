# Generic specialization resources

The private native profile retains specialization maps in their owning
`CheckedIndex`. A key consists of the original Binder `SymbolId`, the exact
enclosing `TypeId`, and the ordered argument `TypeId`/channel-flag pairs. These
IDs belong to that index's Binder and TypeTable. Type interning includes nominal
declarations, lexical parameter owners, structural edges, extents and qualifiers.
Lookup uses full equality, without hashing or text/layout equivalence. Unsupported
foreign, throwing, asynchronous and qualified argument policies still fail before
lookup. LLVM target/layout and callable channels remain separately bound by the
native ABI plan and backend name; no LLVM pointer is cached here.

The resource limits are distinct and unchanged:

| Boundary | Unit and ceiling |
| --- | --- |
| Instance table | 256 distinct declaration/substitution keys |
| Node correspondence maps | 8,000,000 reserved integer slots, including zeros |
| Symbol correspondence maps | 8,000,000 reserved integer slots, including zeros |
| Syntax copier | Original-node identity, depth at most 128, existing arena check against 262,144 nodes |
| SSA | Its separate 8,000,000-step execution budget |

Previously each instance reserved maps covering every original node, symbol and
scope in the entire input. GENRESOURCE-20 reproduced all four frozen first stops
and measured 38–45 completed instances reserving 7.84–7.92 million node slots;
only 1,621–1,978 entries were nonzero. Exact-key reuse already worked. The failed
boundary was allocated correspondence storage, not 256 necessary instances,
syntax depth or SSA work.

Each instance now reserves conservative contiguous windows for its declaration.
Node spans select a storage envelope; original node IDs remain keys. Symbol and
scope windows cover original bindings whose nodes fall in that envelope. Lookup
outside a window means the same absent correspondence as an old zero slot. A
copy outside the envelope fails before writing a map. Spans never decide type
identity, replacement bindings, ownership, ABI or semantic acceptance.

The independent consumer checks arithmetic bounds before indexing, disjoint
reservations, zero sentinels, total slot accounting, exact origin-to-concrete
bindings and the copied declaration root. It reconstructs every copied syntax
edge and retained reference, followed by existing type/channel/constraint checks.
An undersized or aliased map cannot hide a missing child or skip a verifier.
All generated maps and their original source/token/span correspondence live until
the owning checked program is retired. The module-owned LLVM23 layout-cache
lifetime remains separate.

An active-origin guard rejects recursive signature expansion. A completed table
entry (`state = 2`) denotes a materialized declaration and signature, not proof of
its executable body. Bodies still pass checked semantics, Flow, Core, CFG, SSA,
ABI and retained LLVM checks before output. Failed materialization is not added
to the instance table. Finite runtime generic recursion may still be withheld by
the existing effect policy; this change grants no recursive language contract.
Distinct necessary work beyond a fixed ceiling remains deferred.

`checked_build_profile_trace` enables an optional diagnostic consumer. Normal
entrypoints leave it disabled. The trace emits at most 4,096 request/event IDs,
their requester edges, full local argument IDs, reuse/scheduling/completion and
resource/cycle failures. `tests/selfhost-genresource/query.astra` additionally
emits the exact TypeTable and Binder identities and map occupancy. Trace data is
observational and grants no acceptance authority. Raw receipts belong in the
external `genresource20` runtime; retained source snapshots bind long builds to
their actual input bytes.
