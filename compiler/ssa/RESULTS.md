# SSA-11 qualification

The Astra-written SSA component passes the scoped O0/O2 qualification. It consumes
retained, independently verified CFG, constructs typed definitions and exact-edge
block arguments, and independently verifies dominance, nearest reaching versions,
operation/type/source identity and path-specific effect correspondence. Its
separate Astra consumer provides def-use, dominator and incoming-edge queries.
The representation and limits are documented in [CONTRACT.md](CONTRACT.md).

The native input closure is committed at
`9e477551c363075318140718a0b139b3f9d97bfc`. Final documentation and evidence commits do not change
the 81 Astra compilation inputs. Five separately identified C provider objects
complete each product. Qualified C0 remains SHA-256
`30865ad8a9d1652b63ad882f1e29031c76ac13204212f822b44235cb07df10de`.

Both profiles preserve all 47 original Core outcomes: 23 verified, 12 invalid and
12 deferred. All 14 CFG controls and the distinct historical break input construct
verified SSA, giving 38 inherited positives. Eighteen additional source witnesses
also pass. Their exact source hashes, identities and independent properties are
listed in [scope.json](../../tests/selfhost-ssa/scope.json). No inherited source
failure was relabelled. The scalar-control reference still returns 255, as before.

Per profile, all 22 Core and 26 CFG mutation categories remain intact, and 30
SSA-only categories reject after valid retained CFG. Complete backing-table
snapshots match before/recovery and differ during each mutation. Public projection
is blocked while the model is invalid. Synthetic graphs cover diamonds, parallel
edges, dead predecessors, backedges, cross edges and irreducible cycles; a separate
parallel-edge value fragment checks both inputs and rejects missing/duplicate edges.
Independent Python set worklists check produced graph/definition facts. Comparable
C0 incoming expressions are normalized by source symbols and exact edge predicates.
All 340 paired query/mutation outputs and diagnostics are byte-identical.

Unsuppressed Valgrind passes 17 native component checks per profile, covering
construction, consumer queries, cross-owner/function handles, retained sources,
mutants, invalid/deferred inputs and exhausted limits. Fifty-six admitted sources
run as actual C0-produced binaries per profile. The three fatal sources per profile
are classified separately; 53 normal binaries per profile pass memory checks.
Fresh allocation traces preserve inherited break/continue/return/record-leaf order
and the new argument/return/loan controls. The inherited destructor count/order
fixture also passes. Intentional infinite C0 programs time out separately.

Exact output, arena and work boundaries pass at both profiles. On the counter
witness the minima are 30,134 output bytes, 34 rows per arena cap and 18,968 work
units. One less fails closed. A retained-CFG-positive wide graph exhausts the
SSA-specific graph cap. Malformed/overflowing limits and forged success reject.
The deep-source failure remains an upstream checked-input rejection. The complete
73-source compiler/library selection still defers, with zero whole-program proofs.

All 1,044 source-bound predecessor proof observations replay unchanged, including
SEMADMIT's 82 original closures and nine new proofs, FLOWSEM, OWNFLOW, TYPECORE and
Binder. The source/span/path suite, current lexer/parser oracle pairs and LLVM
layout-cache lifetime regressions pass. Original C0 tests pass 8 dominance,
17 SSA and 56 standalone SSA cases. All 446 protected files, 6,622 donor tracked
files, local configuration and hooks retain their original bytes/modes.

Cold native compilation measured 506.93 s / 1,393,736 KiB peak RSS at O0 and
893.01 s / 1,400,956 KiB at O2. Their intervals overlap by 505.88 s; the union is
894.07 s, not their sum. Instrumented exact reuse measured 0.56 s / 162,224 KiB
and 0.55 s / 163,556 KiB respectively. Dependency setup, development checks,
queries, mutation tests, C0 references, memory work and publication have separate
receipts. These costs make no matched speed or size superiority claim.

Failed development checks and harness assumptions are retained in private
SSA-11 evidence. They include ownership API diagnostics, a local-name collision,
an oracle parsing error, C0 unused/edge-constrained phi normalization, the mutation
generator's corrected owned qualifier bit, and historical frontend corpus hashes
that preceded CFG-10's final source edits. Final observations use the corrected
source-bound products and fresh independent comparisons.

This is typed SSA and inspection, with explicit memory/ownership effects retained.
It is not an LLVM emitter or execution through the new SSA. General memory SSA,
broader semantic admission, interprocedural optimization, native ABI changes and
Stage 1 remain outside this milestone. The installed `pm-next` publisher produces
the canonical report; no donor edits, history rewrite, release or push are involved.
