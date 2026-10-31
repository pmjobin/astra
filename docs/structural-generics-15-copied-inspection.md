# Copied record inspection results

Indexed inspection calls now accept a copied record whose recursively derived
leaves are numeric scalars or bool. Source and Core use their own field graphs;
CFG and SSA check their concrete record graphs. Applied generic records use the
canonical struct-storage classification. Existing ownership, noescape,
receiver-alias and read-only effect checks continue to apply.

Read-only inspectors can construct copied local records and initialize their
fields. Writes must remain rooted in copied local storage; borrowed record
parameters and observed Class storage remain protected. Three independent
proofs destroy the preceding representation and insert a write to the observed
Class after complete local record construction. Core, CFG and SSA each reject
that write through their own effect checker.

The registered `copied-record-slot-inspection.astra` uses two closed marker types
and distinct nominal generic record layouts. A second registered witness,
`parenthesized-owner-results.astra`, preserves explicit owning-call acquisition
through ordinary expression parentheses for Resource, heap Class and
caller-backed Class inputs.

Compiler `bb4ced026bc0f3253368257153b5f090e0263e6936a6ea9de47a0489694b6d94`
passes all 107 current structural source programs (1,820 checks and 321
unsuppressed memory runs), 639 opaque unit checks (141 memory runs), all 195
negative cases (1,560 checks), and 191 structural proofs. Exact receipts and
qualified source hashes are in `structural-generics-15-copied-inspection.json`.
This is focused increment evidence; the affected registry and final G7 have not
been rerun for this compiler. Historical expectations remain unchanged.

The original copied-record inspector failure is retained in
`copied-record-inspector-before.json`. Intermediate failures exposed local
record initialization and applied-type classification; the final witnesses pass
O0/O1/O2 with unsuppressed Valgrind. The first Core write mutant accidentally
interrupted contiguous record initialization; its retained failure supplied no
effect-checking credit. The corrected mutant preserves complete initialization
and reaches the intended effect rejection.

The full nonconsuming Map callback probe now reaches the actual remaining
read-only indirect-call restriction. Supporting it requires reconstructing the
actual code targets through argument/alias flow and checking their effects.
The separate code-origin prototype is not compiled into this qualified binary;
it does not yet establish Map lookup, opaque callback contracts or G1 completion.
