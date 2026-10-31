# Generic record async results

Awaited record values now follow ordinary Core type projection and concrete
materialization. Core, CFG, SSA and native frame planning retain the declared
canonical type identity across those representations. The native task result
mapper recognizes generic record storage. It no longer mistakes a materialized
record for a different result because its compiler object has changed.

The new source witness returns a two-argument generic record containing a nested
record, suspends, delivers complete fields, catches a checked failure and retries.
The first result remains an independent copy. O0/O1/O2 and three unsuppressed
Valgrind runs pass: each memory run records 12 allocations, 12 frees, 1,421 bytes,
zero retained blocks and zero errors. A concrete counterpart and a renamed,
reordered nested-record variant pass all three optimization levels with debug
info and six further memory runs.

A new source negative keeps a same-layout result of another nominal type invalid.
The independent native frame proof destroys CFG before checking SSA and rejects a
forged result contract with the same printed name and unchanged physical leaves.
Existing proof bodies and historical negative expectations remain unchanged.

Compiler `c8533d99a787e29fe1e7a1ec45a8e2d05e3536a73bcc656654007ca62642a31b`
passes 110 source programs (1,871 checks, 330 memory runs), 200 negatives
(1,600 checks), 789 opaque-unit checks (177 memory runs), the expression matrix
(168 checks, 24 memory runs), both equivalence variants (18 checks, six memory
runs), and all 207 structural verifier proofs. Exact source and receipt identities
are in the accompanying JSON. The added Meson equivalence recipe brings the
registered inventory to 9,375. This is focused qualification; final G7 is pending.

The separate generic-record producer now passes source/frame checking but its
native async export remains refused. The next work is a typed producer cold-task
factory with immutable runtime, success, error, capture and frame metadata, exact
resume/destroy contracts and observed cross-unit cancellation/retirement. The
application, remaining generality work and final qualification/report remain open.
No completed native async boundary or milestone PASS is claimed here.
