# B2 frozen application witness

B2 passes the measured frozen application witness. This is not M18 or RC2 PASS.
Freeze 2 and seed 1879950433 were committed before requirements/measurement, and
production source, all 19 artifacts and 374 host dependencies stayed unchanged
through closure `runtime/native-current/m18-B2-closure-1.json`.

The image application is correct against an independent BFS oracle, while its
Astra implementation uses disjoint sets and generic component summaries. All
foreground labels, components/bounds/sums and per-row audits match exactly.
The 46-product O0/O1/O2 matrix covers original/renamed/field-order/helper forms,
native/local routes, producer-level mixes, workers 1/2/4, malformed refusals and
whole-product unsuppressed Memcheck. It records 426 outer commands and 146 paired
comparisons. Forty-eight additional executions cover hand-worked white/red/dark/
equal-threshold images and malformed high-bit headers.

The actual mechanisms differ across the boundary:

- Local linkage promotes both span owners beside the row audit retained in the
  incoming Vector. At 129 rows this removes 258 classification heap calls, keeps
  every audit/destructor and leaves component-map allocations unchanged.
- The opaque route conservatively retains span allocations. Supported scalar
  color-helper evidence permits nonadjacent Shared elimination in native and
  local linkage. No producer-body fallback is used to strengthen an unknown fact.
- The bounded 35-pixel traces execute 189→119 linked `cmpxchg` instructions in
  either linkage. Color work changes 140→70; weak controls in main remain 32,
  row destructor sites remain 15, and context/peak sites remain one each.
  Static sites change 25→22. The address controls relink exact qualified objects
  with `-no-pie`; they do not substitute a different algorithm.
- Native `.text` changes 24,785→24,657 bytes; local `.text` changes
  24,593→24,209. Full file sizes are neutral at 150,720/149,520 bytes respectively.
  All 160 raw alternating timing observations remain. For the maximum image at
  seed+31, local process medians are 23.59→23.91 ms despite the structural win.
  Native one-worker sequential medians are 21.22→21.11 ms. These measurements
  establish no universal speedup; the component-map merge often dominates.

Twelve emitted ASan/UBSan/TSan products pass, with 84 commands and six relocated
consumer traces showing no checkout or removed producer reads. Every emitted
consumer/library function and C provider is instrumented. Exact opaque objects
and static liburing are outside compiler instrumentation; full native products
separately pass unsuppressed Memcheck. Context payload/live/reserved conservation,
explicit ordinary row/graph storage and 1,860,696 bytes of static intermediate
storage are distinct from backing capacity, metadata and measured RSS.

Preserved failures are not rewritten. Initial semantic attempts used an unsupported
primitive owned-slots specialization, then reassigned a source parameter; the
admitted copied parent record/local cursor compile. The first io worker declaration
lacked its required root enum. Exact authoring source/receipts remain. The first
cost recipe incorrectly expected four atomics per clone/release instead of two:
its failed 160-sample/two-trace run and commit `7753e241` remain. Independent site
accounting explains the corrected 70-operation reduction; the successful replay
includes all four native/local traces under the original 32 MiB/20 CPU-second caps.

Evidence under `runtime/native-current/`:

| Receipt | SHA-256 |
|---|---|
| `m18-B2-closure-1.json` | `5b7193e3e50f6738833f33554d0e062963b5364c6213a26a6f90e2507de31b98` |
| `B2-qualification/B2-qualification-sqrmd0i7/checks.json` | `2e4dad76c3e00250f4daac855d1bb94e2b2b003826288cd3218e7aa7fdb75326` |
| `B2-costs/B2-costs-zli8tnf0/checks.json` | `ffe194ae431c3eacc6bf3fb063183cbf2737452c2beda793261d809eec503f5d` |
| `B2-instrument/B2-instrument-np8lq6dl/checks.json` | `c3f953b9c6722d73c9c712aec2c91ce47203dcaca50694e704154a818363b90d` |
| `B2-hand-controls-bcdohtb8/checks.json` | `62f18d52d1382a723b7f29432720ab989268ac9ef1f89230ea8402dd6e9a42db` |

This closes the original B2 challenge before later project/release-document edits.
Current regression runs omit the historical freeze option, snapshot actual current
inputs and receive no retroactive frozen credit. Any further production repair
requires honest freeze/challenge reconciliation; neither B1 nor B2 may be silently
relabelled or tuned into a fresh independent surprise.
