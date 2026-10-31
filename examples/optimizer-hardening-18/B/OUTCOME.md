# B1 preserved outcome

B1 is **not a passing frozen optimization witness**. Its independently specified
transaction journal is correct in the measured profiles, but the frozen compiler
derives zero storage, Shared-elision or exact-dispatch claims for this application.
Do not relabel its correct execution as satisfying the M18 optimization requirement.

Original requirements, seed 1666689098 and freeze 1 remain unchanged. The useful
state/undo/history algorithm and all failures remain available. Production source,
19 artifacts and 374 actual host dependencies matched the freeze throughout.
No unsafe accepted program or production identity drift was found.

Current evidence beneath `runtime/native-current/`:

- `B1-qualification/B1-qualification-jxbm57od/checks.json`: correctness PASS,
  46 products, 402 outer commands and 146 paired comparisons; original/renamed/
  field-order/helper forms, O0/O1/O2, native/local and producer-level mixes,
  exact independent outputs, workers 1/2/4, malformed/no-publication controls
  and unsuppressed whole-product Memcheck.
- `B1-instrument/B1-instrument-s_s_1g7m/checks.json`: 12 emitted ASan/UBSan/TSan
  products, 84 commands, six relocated consumer traces without checkout or removed
  producer reads. Every emitted consumer/library function and C provider is
  instrumented; exact native leaf/middle objects and static liburing are excluded.
  Two failed SDK-copy attempts remain failed: first a sibling header was missing,
  then the public included `task-core17.c` source. The complete public provider
  include closure passes; no application, oracle, deadline or memory rule changed.
- `B1-costs/B1-costs-iyd5g882/checks.json`: 140 raw serial alternating observations,
  whole-process RSS and explicit context backing/metadata, under recorded host
  load. At 8,193 records/seed+31 every profile has 26,258 measured kernel heap
  calls with either facts setting. The bounded seven-record address controls
  execute 66 linked `cmpxchg` instructions with either setting (29 static sites).
  Relinking with `-no-pie` changes only the trace address control; the exact
  qualified products provide timings/RSS. Mixed timing differences earn no gain.
- `m18-B1-closure-1.json` binds the above receipts and the final freeze check.

The current transaction function combines context-backed byte formals, generic
Maps/undo/history, checked errors and nested opaque helper calls. Existing proof
domains conservatively withhold authority for that composition. The dynamic
interface policies and weak controls also retain their required observations.
The mandatory per-value and nonadjacent mechanisms already witnessed by A are
not thereby exercised by B1. Keep this program as a broad current regression.

The next challenge must be genuinely different, selected only after another
committed production/host freeze. It must not be B1 with its statement graph
rearranged after querying which shape the optimizer recognizes. No compiler or
runtime edit has been made to turn B1 into a success.
