# SSA-11 qualification plan

Declared before implementation. Preserve the 47 Core outcomes by original names,
the 14 CFG controls and `coreir9-break-control` (38 CFG positives). The original
Core/CFG mutation runners remain unchanged. New source expectations live in
`corpus.py`; synthetic graphs cover parallel edges, a cross-edge counterexample,
an unreachable predecessor and irreducible cycles independently of source grammar.

The representation retains CFG/Core/Flow/source authority. One SSA instruction
refines each CFG instruction in the same block; edges preserve exact polarity,
meaning and ordering. This correspondence preserves conditional cleanup, call
commit, moves, loan endpoints, fatal operations and memory places. It is checked
separately from scalar SSA. No owner/resource is merged as a copyable scalar.

Only primitive, unqualified, root scalar places with no address/loan/move use
are promoted. Record fields, buffers, borrowed storage and other memory remain
explicit. Every CFG value producer receives a new SSA definition; short-circuit
assignments receive distinct values and exact-edge block arguments. Promoted
stores define versions. Entry parameters remain typed definitions. Live joins
may contain redundant block arguments; minimal SSA is not a requirement.

Builder dominance uses descending predecessor intersection; the verifier uses
entry reachability with a candidate block removed. Builder reaching versions use
a forward fixed point; the verifier walks backwards to the nearest definition on
every path. Independent Python checks use graph sets and source-authored facts.

Predeclared SSA mutation families: wrong incoming value; missing/extra incoming;
duplicate definition; wrong incoming edge; cross-owner/function value; changed
type; use before definition; non-dominating use; stale scalar version; forged
idom/frontier; missing loop backedge; move-as-copy; loan past cleanup; reordered
call operands/effects; dropped/double release; wrong block; wrong source span or
literal spelling; forged success; invented noalias; resource exhaustion. Each
must leave retained CFG valid, reach the SSA verifier, block public projection,
restore all touched tables and compare complete before/recovery identities.

Bounded O0/O2 component builds use the existing exact-product recipe. Qualification
batches sources through those products, uses current C0 SSA/native oracles, and
runs unsuppressed Valgrind. Failed attempts remain in private runtime evidence.
No LLVM emission, new native execution backend or Stage-1 claim is in scope.
