# CALLPLACE-23: receiver Place method calls

This is a new source-bound milestone after MEMBERCALL-22. The historical
MEMBERCALL-22 report remains **PARTIAL**. Its exact report and the SLOTSWAP-21
report are preserved externally by hash; no earlier qualification is relabeled.

The implementation resolves a unique visible method from the receiver's exact
nominal Class type, including projected receivers and instantiated Class
environments. A normalized executable call retains the original receiver AST
as its first, borrowed argument. It does not reconstruct or duplicate that
expression. The independent generic consumer checks the receiver identity,
argument order, signature, origin and enclosing type. Binding completion records
lexical authority without granting a physical ABI or storage qualification.

Concrete methods with no type parameters use ordinary exact signature checking.
They do not infer nonexistent generic arguments. Genuine generic methods still
infer or check their type arguments, and an unavailable inner result remains
unavailable. The existing private borrowed Class pointer ABI, ownership checks,
cleanup, module-owned LLVM layout cache and separate stage verifiers are retained.

The original `FlowGraph.slot_for`, `room` and `add` method bodies and the original
`checked_target` helper are exercised in bounded nonthrowing drivers. These views
retain the relevant actual bodies and nominal records; they are not executions
of their original complete callers. An independent Class family supplies nested
record results, mutation/evaluation order, aliases, owner movement and cleanup
witnesses. Separate programs cover concrete and genuinely generic methods in an
instantiated Class, field-array record storage, early return and namespace calls.

The larger original-method views exposed an existing SSA builder cost: ascending
fixed-point visitation propagated facts against CFG construction order and spent
the unchanged eight-million-step allowance. The builder now visits blocks in
reverse order. The monotone intersection and budget charging are unchanged.
The independent path-exclusion dominance verifier is byte-identical to the base.
This change requires actual successful stage and mutation evidence; a build alone
does not qualify the resulting calls.

Qualification recipes live in `tests/selfhost-callplace/`. Builds and observations
use explicit paths under `~/Workspace/codex/work/astra/{build,runtime}/callplace23`.
`build.py` extends the existing LLVM build recipe with the Astra-written mutation
consumer. `qualify.py` requires source admission, separate Core/CFG/generic
consumption, independent C0 execution and ABI layout measurements, LLVM
verification, native ELF execution and unsuppressed Valgrind. `inherited.py`
freshly emits, verifies, links and executes every inherited source identity with
its exact historical link recipe and independently established expected behavior.

`mutations.py` drives 28 new actual model mutations: generic origin/environment,
state, arity, hidden borrow channel, receiver/result type, normalized argument
identity, Core source/signature/operand/cleanup, CFG edge/borrow and SSA use/result
contracts. Each restores its valid twin. `physical.py` checks seven new LLVM-valid
alternatives with LLVM's verifier, source assertions, the independent private
receiver ABI and unsuppressed Valgrind. These post-emission alternatives are
external physical checks, not claimed inputs to Astra's retained-module audit.
`lifetime.py` checks allocation and retirement order against independently measured
record/Class sizes. The tiny C effect observer writes a byte; no compiler
algorithm is implemented in that observer or other C support.

The failure-order witness preserves an inner `A` effect before a later bounds
trap and proves the outer `B` effect did not occur. This fatal-trap observation
does not establish recoverable exception handling or normal-return cleanup for
the aborted process. Parse-valid nominal, arity, generic and ownership negatives
also preserve the output destination when native emission refuses them.

The four frozen source populations retain their exact source/node/span identities
and original resource bounds. Partial lexical type-use progress and independent
whole-module refusal are recorded separately. A published nonzero lexical type
does not discharge a pending borrow/ownership obligation or qualify a whole call
plan. No whole original compiler module, complete caller or Stage 1 is claimed.

The final O0 observer reran all four cohorts using the same source/node/span
populations. Counts below are source uses with a nonzero type and no per-use
deferral; they are partial facts, not whole-module verification:

| Frozen cohort | Before | After | New such facts in the same file after the old stop span |
|---|---:|---:|---:|
| original | 52,257 | 96,817 | 547 |
| LLVM23-base | 54,255 | 104,172 | 552 |
| Class15-current | 59,268 | 117,410 | 821 |
| live-initial | 59,815 | 118,780 | 1,105 |

The original call nodes 40833, 42968, 46736 and 47584 now each publish type 1
(`int`), flags 0, with borrow/ownership obligation 19 still pending. All four
whole-module observations remain `STATUS 2 0`; their separate admission probes
report `CHECKED_CONSUMER 1 7`: structural validation passes, independent generic
reference verification fails. There is no replacement checked-error diagnostic.
These remaining stops are recorded independently of the unchanged throwing
caller effect boundary. The successfully executed nonthrowing views do not
discharge either original whole-module obligation.

Both original complete callers, `admit_record_value` and
`class_storage_slot_flow`, remain **DEFERRED**: their complete bytes/ASTs and
`throws Error` declarations are unchanged. Independent pure/throws twins retain
the existing native `UNSUPPORTED_EFFECT 6` refusal at the throwing function's
actual span. Recoverable error transport, error edges and unwind cleanup need a
separately authorized effect/ABI milestone. No such ABI was introduced here.

Failed and cancelled builds and draft input versions remain in the evidence with
their actual costs. Unsupported draft forms include an empty generic Class with
an owned child, a direct effectful record-result indexed store and a raw null
pointer call argument. None is counted as a successful native program. Existing
source statuses, protected files, donor files, historical proof outputs, hooks,
configuration and installed workflow are checked independently before publishing.

Final measured counts, timings, exact HEAD/tree and gate outcomes are recorded
by `audit.py` in `final-audit.json` after the qualification completes. `handoff.py`
reconstructs and verifies lossless evidence before handing an indexed attachment
set to the unchanged installed `$pm-next` publisher. Generated products and
temporary proof output remain outside Git.

The final qualification executed 172 inherited plus 15 new source identities at
each of O0 and O2 (187/profile). All 172 inherited raw LLVM outputs/profile are
byte-identical to their predecessors. All 15 new native and independent C0
executables/profile agree with explicit expected exits and pass unsuppressed
Valgrind with no errors or lost allocations. Separate Core, CFG and generic-plan
consumption also passes for every new program. There are 28 new model rejections,
seven LLVM-valid independently rejected physical alternatives and ten parse-valid
source refusals/profile. The ownership-alias declaration negative remains native
deferred rather than receiving a new ownership-error classification.

The two-profile continuity replay preserves exactly 56 admitted, 12 rejected and
12 deferred original source statuses, along with the module layout-lifetime
controls. Historical outputs retain their original attribution. Preservation
checks cover 451 protected files, 6,622 donor files and 1,044 historical proof
outputs; these counts do not represent fresh qualification of those old proofs.

| Final cold compiler build | Wall seconds | User CPU seconds | System CPU seconds | Peak RSS KiB |
|---|---:|---:|---:|---:|
| O0 | 1,160.322 | 1,151.53 | 1.25 | 1,795,700 |
| O2 | 1,824.232 | 1,810.43 | 1.27 | 1,807,644 |

These builds overlapped. Earlier failed, cancelled and successful intermediate
builds have their own exact command/input/cost records in the report; none is
substituted for final execution. Nested parent/child measurements also overlap
and must not be summed as an exclusive performance benchmark. The final results
use `compiler-v7-{O0,O2}`, `qualified-v3-{O0,O2}`, `inherited-v2-{O0,O2}` and the
separate versioned mutation/effect/cohort ledgers. Source cohort comparisons are
`cohorts-v2.json`; earlier cohort observations remain attributed to their earlier
product hashes.

The first complete lossless package reconstructed correctly but exceeded the
unchanged report cap (31,043,996 bytes). It remains preserved externally with its
verification receipt. Content-defined chunking also exceeded the cap (35,009,728
bytes); sorting the original chunks produced 29,901,652 bytes and still failed.
Both experiments remain preserved with their actual outcomes. The final package
column-encodes the recorded native `NODE` rows with exact path dictionaries and
integer deltas, preserving all prefix/suffix bytes. A separate restorer recreates
every original stdout byte and verifies its recorded SHA-256 before the existing
source-ledger restorer runs. These are reversible evidence representations, not
new executions or semantic observations. The chunk transport's independent byte
verifier remains byte-identical to the reviewed version. No compiler/resource
contract, installed workflow or required evidence is removed.

Made by Ria and Pim. 💙🖤
