# EFFECTS-25 engineering checkpoint

The static producer/local/move type chain is repaired. Recoverable effects are
still unsupported in the self-hosted executable pipeline. This checkpoint is
**PARTIAL**, not an effects implementation PASS.

The owner explicitly selected **APPROVE THE BOUNDED DESIGN E25-A-v1** in the
native session. The approved proposal is
`docs/selfhost-effects-25-abi-proposal.md`, SHA-256
`d77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e`.
Its original approval-required text is preserved as the decision artifact;
approval is recorded separately in `runtime/effects25/abi-approval.json`.
There is no outstanding ABI permission request. The proposed transport has
not been implemented or qualified in the self-hosted compiler.

## Exact cause

Initial HEAD was `a19425f2cd0932fb0c93629abcd1ed63b98aa5bf`, tree
`9ef8178508f411c474c247a8bb0718075f5d6f08`. Installed unchanged pm-next accepted
the exact EFFECTS-25 submission SHA-256
`7be68ba88a6891dacb4a6a3e0bc4c6226722d43739358d1144fbc419e3f939ca`.
The 13,447,308-byte GENREF-24 report SHA-256
`45575de25c8f62ad8d9c30480be353eedde28bca75c96713fa8c777166e51a37`
was verified and preserved before any publication.

All four independent consumers initially return `CHECKED_CONSUMER 1 25` at
O0 and O2. Exact source populations remain 79/85/92/92 files and
174297/188293/206465/208328 nodes. The first failing generic call predicate is
reason 13, `generic_type_matches` on `index.graphs.append(move graph)`.

| Population | Producer symbol | Local symbol / declaration node | Initializer node | Exact Class TypeId / nominal | Moved argument node | Append bytes |
|---|---:|---|---:|---|---:|---|
| original | 560 | 9037 / 49868 | 49867 | 197 / 181 | 49912 | 23489–23520 |
| LLVM23-base | 566 | 9340 / 52044 | 52043 | 198 / 182 | 52088 | 23687–23718 |
| Class15-current | 626 | 10230 / 69348 | 69347 | 202 / 186 | 69392 | 24314–24345 |
| live-initial | 630 | 10298 / 70795 | 70794 | 202 / 186 | 70839 | 24893–24924 |

The declared callable already has a nonzero exact nominal result, owning result
flag 4, declared Error TypeId and signature flags 68 (= owned 4 | throws 64).
The first missing type operation is the early unsupported-call guard in
`checked_call`, before callable descriptor/result and argument checking. Its
`(8 | 16 | 64)` test matches flag 64; this native throwing function cannot
satisfy the separate scalar C-import/export predicate. The guard visits children,
records deferral 17 and returns `no_type()`. The inferred declaration copies
that zero. The moved argument reads the local's zero, sets owning flag 4 and
retains obligation 19. The generic verifier correctly refuses that argument.

Read-only baseline instrumentation preceded the repair. The actual original
producer declarations, function/source IDs, signature/error/result descriptors,
local and move uses and lexical/concrete append correspondence are retained in
`trace-baseline-v1` and `trace-static-v2`. Independent C0 whole-file syntax
parses bind the exact `flow_graph` and `flow_index` methods to their owned
results and `throws Error` declarations in `source-oracle-v2`. C0's dump emits
throws metadata immediately before its function record; both records are
retained and hashed. Whole-method syntax is not whole-method native execution.

## Static repair and remaining source frontier

`checked_pending_effect_result` retains only the result edge of a complete,
matching private synchronous declaration signature. It checks owner-local IDs,
callable/error families, exact declaration/signature/flags, direct dispatch,
argument count and result validity. Async, foreign and signal channels stay
outside this observation. No identifier spelling selects a result TypeId.

The call keeps deferral 17 and its exact signature error bound. An inferred
local inherits that deferral and owning qualifier. These are conditional
success facts; they do not establish an initialized owner on failure. The moved
use keeps obligation 19. No generic, borrow, ownership, cleanup, Core, CFG, SSA,
LLVM or layout-cache verifier is weakened.

All four repaired local and move TypeIds equal the declaration-derived nominal
result. The separate unchanged generic verifier returns zero. This removes the
missing-type predicate without establishing ownership/effect admission. The
original earlier calls 40833/42968/46736/47584 must still retain type 1, flags 0
and obligation 19 in the matched final ledgers.

Flow still reports unsupported-effect 6 on the initializer/caller. Its Class
origin analysis deliberately treats throwing factory calls as unsupported,
retaining Class-origin obligation 12 at the consumer. Other whole-source graphs
also report `BAD_GRAPH`; the read-only diagnostic view preserves the exact
predicate stop rather than relaxing that boundary. The first original stop is
Flow graph 55, `CheckedIndex.add_signature` (symbol 2053), predicate 26 in the
diagnostic view: operation 24 fails `flow_owner_capture_verified`. Its
`this.signatures` operand has slot zero; the other operand, `grown`, has slot 6.
The unspecialized lexical member has no admitted receiver-owned root for that
field. This is a separate source/storage authority failure, not evidence that
the repaired `FlowGraph` nominal type is wrong. Whole-source admission,
complete `flow_graph`/`flow_index` execution and the new recoverable-effect
Typecore→Flow→Core→CFG→SSA→LLVM pipeline remain unqualified.

Disjoint Parcel/Ripple and generic Bag source controls retain conditional owned
results. Mismatched nominal and undefined-result controls reject. An unhandled
effect and a borrowed move remain refused by the complete pipeline; this static
repair does not claim to diagnose all effect/owner errors at Typecore.

## Independent design evidence and limits

Unchanged C0 is SHA-256
`e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b`,
LLVM 23.1.4. Three existing C0 witnesses execute at both O0/O2 with verified
LLVM and zero unsuppressed Valgrind errors/live allocations. Twelve new C0
source programs additionally cover propagation, catches, rethrow, replacement,
owning buffer/Class success and error, reservation abort and nested cleanup.
They are C0 oracles; they contribute zero new qualified Astra effect programs.

GCC and Clang at O0/O2 independently agree with C0 LLVM's root error layout:
size 32/alignment 8; descriptor/origin/snapshot/count at 0/8/16/24; descriptor
size 24/alignment 8. Six different C++ layout alternatives per tool/profile
are distinguished. These are design measurements, not physical mutations of a
new self-hosted error emitter. Existing nonthrowing and public C ABIs remain
unchanged. Finally syntax remains a C0 parser refusal.

The full original-cohort C0 semantic check exceeded its 240-second deadline.
The time wrapper initially left its compiler child running; the exact child was
identified and terminated, and its actual CPU/RSS observation is retained. Task
harness deadlines now terminate the complete owned process group; a descendant
termination probe verifies that behavior. No compiler resource ceiling was
increased. The other three full-cohort C0 semantic checks were not started.

The two inherited eight-million-step SSA stress deferrals, wide-u64/f32 Valgrind
disagreement and complete Utf8Message factory coverage remain historical
deferrals. MEMBERCALL-22 stays PARTIAL; CALLPLACE-23 and GENREF-24 stay PASS.
The original 80 source-status rows, 1044 historically attributed proof outputs,
451 protected paths and 6622 read-only donor files retain their identities.

The campaign requires further implementation and independent qualification of
E25-A-v1: explicit error successors/propagation, successful-result dominance,
handler/error-owner liveness, exactly-once cleanup, source/SSA/LLVM correspondence,
12+ new Astra executables including 8+ actual error paths, and new semantic and
physical mutations. Approval alone supplies none of those proofs. Full compiler
native admission, self-compilation and Stage 1 remain unqualified.

## Native baseline and costs

Both final compiler profiles freshly recompile and execute all 202 inherited
native source identities. All 202 raw LLVM outputs per profile remain byte-exact
to GENREF-24. Source identities and distinct ELF byte identities are counted
separately: 202 distinct ELF images at O0 and 182 at O2. Fifteen inherited
normal-return programs per profile pass fresh unsuppressed Valgrind with zero
errors, live allocations or suppressions. The original 80 statuses still classify as 56 admitted, 12 rejected
and 12 deferred. The module-owned layout-cache lifetime and 28 inherited
Generic/Core/CFG/SSA model controls pass; they are not new effect mutants.

Cold O0 costs 1292.01 s wall, 1279.67 s user and 1997504 KiB peak RSS. Cold O2
costs 2008.85 s wall, 1990.97 s user and 2010776 KiB peak RSS. These builds overlap
and include additional read-only diagnostics; no matched-workload speedup is
claimed. Exact warm reuse has separate receipts. The baseline observer costs
483.67 s wall; the first static candidate fails C0's borrowing check in 1.95 s;
the corrected observer costs 486.59 s. Candidate/failed/source-timeout and test
command observations retain their own attribution in the lossless evidence.
