# GENERICS-14 native generic specialization

This milestone qualifies a bounded native generic pipeline. Whole-compiler
admission, Stage 1 and release packaging remain deferred. The final publisher
receipt supplies the final Git commit/tree and canonical report identity.
The installed pm-next intake accepted the exact 31,299-byte submission with
SHA-256 `5e6ae0758b69df5e05028b03ffdd87433d8e2fbbe06ed5b0d6b93810210acbf0`.
Its base is commit `5cd200f8210482835f1ff80182a59fb1532801ba`, tree
`acddbd3da33c771b956082e27d68a1bc98a53cfe`. The predecessor report is preserved
under its SHA-256 `f1215775b351bdec9ba0267c90f023ba8044b75abfa75631ea653a7edf4bb8b1`.
The live start was clean. All 451 protected inputs matched their recorded
hashes; all 6,622 read-only donor files matched the predecessor byte/mode map.

## Implemented architecture

The original syntax, tokens, spans, binder symbols and references remain the
source authority. Target-agnostic `GenericInstance` rows name a declaration,
ordered concrete TypeIds, an optional enclosing Class instance and separate
syntax/symbol/scope maps. Maps live in a bounded typed arena. A requested
instance creates concrete declaration/body syntax and binder identities; it
does not rewrite source text, call C0 to instantiate, or use a fixture table.
Explicit arguments and inference use canonical type edges. Closed nominal
records obtain distinct concrete nominal declarations, including nested
records with identical physical shapes. Copy and owner facts come from the
concrete fields and the existing checked/Flow contracts.

The separately implemented consumer reconstructs substitutions, source syntax,
binding references, signatures, constraints and method receiver selection. It
runs before Flow admission and again at admission verification. Existing
Core/CFG/SSA verifiers remain independent. Backend keys encode declaration
source identity and canonical types, including enclosing/method arguments;
the qualified native ABI plan binds those bodies to actual machine layout.
General C ABI exports are not introduced.

The owner approved the bounded private receiver proposal in
`selfhost-generics-14-abi-proposal.md` through the native session. Empty native
Classes have real allocations and scoped once-only retirement. A specialized
direct method has a hidden borrowed Class pointer before source parameters.
The original call remains intact; a checked normalized argument view retains
receiver-first evaluation and the existing loan/consumption checks. The ABI
plan records the receiver channel explicitly and grants no alias attributes.
Field-bearing Classes, inheritance, virtual/indirect dispatch and custom
Class destruction remain outside this bounded implementation.

## Qualified execution matrix

Final v6 products execute all 39 inherited programs and 13 additional distinct
generic programs at each O0 and O2: 52 identities per profile, 104 qualifying
native executions. The same source tuples qualify at both profiles. All new
programs pass independent C0 compilation/execution, checked/Flow/Core/CFG/SSA
admission, raw and optimized LLVM verification, ordinary linked ELF execution
and unsuppressed Valgrind checks. Applications link the Astra emitter's object;
C0 application objects supply only the separate oracle.

| New family | Frozen program identities | Count per profile |
| --- | --- | --- |
| Explicit/inferred functions | explicit-int, inferred-int, explicit-bool, explicit-f32, ordered-arguments | 5 |
| Nominal/nested records | record-identity, record-nested, record-nominal | 3 |
| Bounded instance methods | method-concrete, method-outer | 2 |
| Owner arguments/results and cleanup | owner-buffer, owner-early | 2 |
| Provider/consumer across four files | cross-unit | 1 |

Six are unchanged repository programs from `tests/gen-infer/fixtures/`;
seven were authored and frozen separately after real C0 acceptance. Their
original native refusals and exact source hashes remain in frozen v3.
The standalone Astra consumer admits all 13 and independently exercises the
19 typed/binder/owner/receiver/Flow mutations. Four further integration controls
at each profile are uncounted: combined mechanisms, Class local move, an
unchanged capabilities fixture and reversed provider/consumer ordering. The
last retains exact canonical keys/private symbols and one shared instance.

Each final native product rejects 19 substantive semantic/model corruptions
and six physical receiver/layout/allocation/cleanup/buffer-stride corruptions,
with valid twins and exact restore checks. Fifteen parser-valid source
negatives are independently rejected by C0 and Astra. Seven further policy
controls preserve the specific C0 acceptance/refusal and Astra deferral;
the foreign-generic parser refusal is not counted as a semantic negative.

The 39 inherited source identities, native/C0 ABI plans, raw/optimized IR,
objects, executables and memory observations are byte-exact against the
predecessor at both profiles. The closure retains all 80 original statuses,
Core22/CFG26/SSA30 mutations, LLVM21 and ABI17 plus the separate numeric guard,
strict numeric, allocation failure, lifetime, literal and bidirectional C ABI
controls. The original 66 compiler comparisons and 405 formatter cases remain
historical, with their report/evidence identities preserved; they are not
claimed as freshly rerun campaigns.

All 1,044 original proof observations match their exact exit/stdout hashes
using six freshly source-bound Binder/Typecore/Flow products at O0/O2. The
first replay used the older Flow query interface and stopped at observation
50; that routing error and its raw output are retained. Rebuilding the proper
Flowsem query and checking its exact guard output precede the complete replay.

## Whole-source observations and style

| Consumer / observed source | Files including generated backing | Original parsed nodes | Typed observations | Unvisited/structural zero use |
| --- | --- | --- | --- | --- |
| Initial / initial | 79 | 174,297 | 66,322 | 34,455 |
| Current / exact initial | 79 | 174,297 | 1,333 | 172,964 |
| Current / current | 85 | 188,240 | 1,370 | 186,870 |

The initial consumer also records 73,520 nodes with explicit type deferrals.
Every initial original node identity is preserved under both consumers. Full
ledgers retain file/function/node/span/reason/source hashes, declarations and
the actual generated Utf8MessageFactory source backing. All input sources have
byte-exact snapshots. The current consumer stops at `Bag<FlowGraph>` in
`compiler/semantic/flow-model.astra:342`: its native subset cannot discharge
the generalized `ExactHeapClass` constraint. The raw checked constraint error
is preserved; general Class storage is named **DEFERRED**, not classified as
invalid C0 source. Later nodes retain zero recorded use and the program error.
The decrease in typed observations is an early-stop effect, not progress or
acceptance. The separate 13 executed source identities demonstrate progress.

The final guarded read-only style check passes 4,662 sources with zero changes.
Current eligible source bytes match that receipt plus a fresh single-path
guard for the final transport recipe. Formatting applies were
limited to task-touched eligible paths; the qualified style, restricted
unbraced controls, all 451 protected byte/mode identities and the five excluded
Windows scripts remain unchanged. There was no repeat of the 3,033-file rewrite
or a release-sized historical registry.

Early trials remain in `runtime/generics14/`: the older independent C0 rejects
approved unbraced syntax, so new witnesses use the qualified current C0;
C0 rejects owned fields in generic records, a by-value parameter mutation and
an inferred unresolved generic local. Revised witnesses were separately frozen
before implementation. C0 also exposed a record-projection temporary without
a reaching definition in a loop condition in the verifier implementation;
materializing that descriptor before the loop retains the same checks and
passes C0. No C0 verifier or ownership restriction was relaxed. A missing
construction commit identity, missing floating buffer element layout and the
independent check's incorrect LLVM insertvalue opcode were corrected and
requalified. Obsolete interrupted builds and all earlier failed attempts stay
visible; acceptance is a composite result, not an uninterrupted first run.

The exact C0 oracle for the 13 new programs and source style is
`908f8db9e524cf94b7651f36e9bf0ff32c98ef64cb7eacd737c3b5f680064b45`.
The inherited 39 retain their original independent C0
`30865ad8a9d1652b63ad882f1e29031c76ac13204212f822b44235cb07df10de`:
current C0 rejects some historical owned-struct-field grammar. These tools
have distinct, source-bound roles. Neither is substituted for Astra emission.

C0 O2 elides the unused empty-Class allocations in the two method witnesses;
its actual main disassembly and empty traces are retained. The approved Astra
convention deliberately emits real one-byte allocations and once-only frees
at both profiles. Those native events satisfy authored object-count contracts.
Buffer owner traces match C0 exactly; all observed memory error/lost-byte
counts are zero, with raw unsuppressed receipts and reachable-library counts
retained. The earlier overly strict Class trace comparison remains a failed
development observation, not a rewritten success.

## Measured build cost

| Final component | Cold wall seconds | User/system seconds | Peak RSS KiB | Exact warm wall seconds |
| --- | --- | --- | --- | --- |
| O0 | 753.75 | 747.95 / 1.02 | 1,563,040 | 1.07 |
| O2 | 1,260.95 | 1,251.60 / 1.08 | 1,569,732 | 1.00 |

These are actual GNU-time command observations with exact source/tool/flags
sidecars, compared with the reported predecessor 647.55/1,129.04 seconds cold
and 1.03/1.09 seconds warm. Source sizes and workloads differ. The cost ledger
retains failed/retried builds, measured command sums, the union of overlapping
monotonic intervals, CPU observations and largest individual process RSS.
Neither sum is total session time or simultaneous memory peak. API token and
dollar charges are not exposed. No compiler speedup claim follows.

## Deferrals retained

C0-rejected owning generic-record fields and owning-record reassignment remain
unsupported. General generic Class containers, virtual dispatch, advanced
constraints/ownership, broad foreign pointers and C aggregate ABI, callbacks,
async/exception policy and whole-compiler admission remain unqualified. Class
value/owner/aggregate ABI channels beyond the approved hidden borrowed receiver
are explicitly DEFERRED, including the C0-admitted Class relay policy control.
The prior wide-u64-to-f32 Valgrind numerical discrepancy remains **DEFERRED**
with its original failed exit and raw identity; native numeric expectations
are unchanged. No release, Stage 1, donor write, global tooling change,
history rewrite or public push is part of this task.
