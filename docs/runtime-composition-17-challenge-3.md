# M17 frozen challenge 3: triple-range sequence alignment

Selected after freeze 3 commit `b53fd2fa3f4327f2665fc866702d132d726726e4`, before authoring or compiling
this variant. Selection UTC: `2026-10-28T20:49:24.955526+00:00`. Reproduction seed: `2575218845`.
Compiler SHA-256: `af1bf5731330f6cdd54b51dd6ef8cd6689f8d418a4381b2c8a34571de851354f`.

A query selects three file ranges: a reference and two comparison sequences. Read
all three through real io_uring. Native workers calculate two longest common
subsequence (LCS) profiles using in-place dynamic programming over actual selected
context byte buffers. Return the two LCS lengths and independent checksums/extent
metadata in a new three-level closed generic envelope. Retain the actual two final
DP rows in selected-context cache entries, including sampled profile values in
responses. Cache hits must avoid file reads and worker recomputation. The
independent Python oracle uses a bit-parallel LCS algorithm and validates complete
responses and retained row samples; it does not share the Source algorithm.

This changes the request/range structure, algorithm, working and persistent buffer
layout, copied record nesting and native SDK from B2's paired histogram/quantiles
and byte-pair distance service. Failed freezes 1 and 2 remain failed. Their repaired
fixtures and complete B2 service remain regressions only.

Author a new real custom allocator through the frozen callback contract. Each
instance owns a dynamically allocated aligned arena, synchronized sorted extent
ledger and private allocation guards. Use first-fit gaps with reuse after exact
releases, bounded slots, overflow/alignment/quota checks and disposal after the
final backing lease. Allocation authority lives in per-instance callback state;
telemetry may not act as a global allocator lookup. This differs from B2's
individually allocated guarded blocks. Exercise several instances, including
cached results that outlive their original controller handles.

Use scoped caller-backed validation, selected persistent inputs/results/cache
backing and actual selected worker frames. Exercise at least three simultaneous
TCP clients, UDP progress, both numeric endpoint families, changed queue/cache
sizes, quotas and worker counts. Observe real useful worker overlap, file progress,
cache reuse, checked library/provider errors and live cross-executor cancellation.
Prove exact frame, context, ticket, buffer, descriptor and thread retirement with
normal and instrumented runs, preserving all failures.

Split model/processing and setup into opaque native units with producer
implementation absent during consumers' compilation. Run every O0/O2
producer/middle/consumer combination (eight) and O1, plus ordinary O0/O1/O2.
Qualify the public application, independent complete protocol/results, context
origin/guard/quota controls, generated-code ASan/UBSan, race tools and unsuppressed
product Valgrind with explicit coverage and bounds.

No compiler, shared runtime/library, A or other frozen source change earns freeze-3
success. Verify all frozen identities before builds. A valid public-contract failure
must be retained, repaired generally and followed by refreshed evidence and another
explicit freeze/new structural variant. No B3 success has been claimed.
