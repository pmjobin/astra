# M17 frozen challenge 4: weighted range alignment

Selected after freeze4 commit `c6b8fb36cbed189c68df71d78c9a8f1896001e4a`, before authoring or compiling
this variant. Selection UTC: `2026-10-29T00:52:43.116453+00:00`. Reproduction seed: `1776966140`.
Compiler SHA-256: `541a3483d0750cf3b713747a5c1a90c96625a5141c66159bf069d1a89c70133c`.

Build a weighted edit-distance range/cache service in ordinary Astra. A request
contains three file ranges and independent positive insertion, deletion and
substitution costs. Read all three ranges through real io_uring, then calculate
the two weighted edit-distance frontiers on actual native workers. Retain the
complete final frontiers in selected-context cache backing. Cache identity includes
all three costs; returned scores and sampled frontier values must agree with an
independent Python shortest-path oracle over the edit graph. The oracle must not
share the source algorithm generator or scalar in-place row implementation.

This is a new structural variant after B3's historical triple-range LCS service:
new runtime-weighted request and cache keys, a different recurrence, a four-level
closed generic response envelope, an independent second selected-context owning
buffer in each cached result, extracted processing helpers, new symbols and changed
request/response widths. The extra owning buffer supplies a checked response
witness and remains live for cache hits after the worker's original context handle
retires. Source data, range sizes, queue/cache capacities, worker configuration and
endpoint family vary while preserving declared nominal/effect contracts.

Author a new per-instance buddy allocator through the frozen public external
context contract. Allocate aligned dynamic arenas, split power-of-two extents and
coalesce exact buddy pairs after release. Use a synchronized bitmap/tree and exact
origin ledger, 64 bytes of allocation guards, explicit logical quotas, overflow/
alignment checks and disposal only after the final lease. Per-instance callback
state supplies authority. This differs from B3's sorted-ledger first-fit arena;
no allocator name/type/address special case may be added to production.

Exercise at least three simultaneous TCP clients, UDP progress and both numeric
endpoint families. Observe useful two-worker overlap, real ring completions, cache
reuse and exact selected task-frame/input/result allocation. Retain provider quota,
guard, wrong-origin and disposal controls. Qualify checked library errors and real
cross-executor cancellation, including worker-active and submitted-I/O paths, with
exact joined task/context/ticket/buffer/descriptor/thread retirement.

Split model/processing and setup into opaque native units. Keep producer copies
absent during consumer compilation, trace imports and execute all eight O0/O2
producer/middle/consumer combinations plus O1. Run the application at O0/O1/O2,
unsuppressed product Valgrind and emitted ASan/UBSan and thread instrumentation,
with an independent complete wire/file oracle. Keep actual costs and conservation
observations bounded and report their coverage precisely.

All new challenge sources and recipes belong in the separate
`tests/runtime-composition-17/frozen-4/` directory. Existing registered inputs and
every frozen compiler/runtime/library/A/application file remain unchanged. Add
registry entries only after active existing registry partitions retire and retain
the exact old definitions alongside the explicit new delta. No production edit
earns freeze4 credit. Preserve any valid public-contract failure, repair it generally,
refresh affected evidence and create another freeze/structural variant if necessary.

The broader current registry, nine consent-dependent historical registrations,
affected Windows permission/execution, final measurements and canonical delivery
remain required. Selecting this challenge is not G7 PASS or milestone completion.
