# M17 frozen challenge 2: paired-range distribution cache

Selected after freeze 2 commit `ebb482fb29e83348238a1b60c4d9d96f6d51a48a`,
before authoring or compiling this variant. Selection UTC: `2026-10-28T19:42:34.873396+00:00`.
Reproduction seed: `2290007590`. Compiler SHA-256:
`a2a66da64524b825803e9c2a2c03bbfce7da0e9d5f1f87254aba3d8fd4678017`.

This is a new structural variant of the indexed query service, not a repaired
passing claim for B1. Freeze 1 and its original single-span/autocorrelation model
remain failed and retained.

Each B2 request selects two file spans. The service reads both through io_uring,
computes a joint byte histogram, quantiles and a cross-range absolute-difference
score on native workers, caches the typed distribution, and returns a nested
generic result envelope. The cache retains actual histogram backing selected
from its allocator context. Repeated paired queries must use a cached result and
avoid both file reads and worker recomputation. The bounded pairwise score is a
real analysis; the independent oracle computes it from histograms by a different
algorithm. This differs from A's incoming single stream/transform/file writes and
from B1's single range/scalar statistics/correlation layout.

Exercise at least three simultaneous TCP clients, changed record nesting and
closed generic shapes, different paired-range ordering, queue/cache/buffer
capacities, and numeric IPv4/IPv6 endpoints. UDP reports cache/progress. A local
scoped key/checking context must remain within its borrowed backing. Persistent
entries, actual histogram payloads and selected worker frames must retain their
original contexts through results, checked errors, cancellation and joined shutdown.

Author a new per-instance quota allocator through the public custom-provider API.
It must carry real user state, synchronize its callbacks, track actual allocations
and exact releases, enforce its quota/slots, and dispose only after the final
lease. Use multiple independent instances, including cache/result backing that
outlives its original allocator handle. This provider belongs to B2, outside the
frozen shared runtime. Configuration remains the launching application's choice.

Use opaque native model/processing and setup libraries with implementation absent
at consumer compilation. Verify all eight O0/O2 producer/middle/consumer mixes plus
O1, actual query/results across the boundary, checked provider errors and live
cross-executor cancellation. Qualify ordinary O0/O1/O2, independent complete
protocol/results, real IO/worker progress, bounded queues/memory and exact context,
frame, descriptor, buffer and thread conservation with appropriate safety tools.

No production/shared-runtime/A change earns freeze-2 success. Retain a valid
contract failure, repair generally, refresh evidence, freeze again and author
another structural variant if needed. No B2 success has been claimed.
