# NATIVEABI-13-R1 qualification

The owner approved live base `b589e48ec94131de3b330f6377076ddbdac88c62`
after the historical email rewrite. Its tree is the packet's exact
`46f72a3381161aac36f158c5b5a5ccd0d551e9af`. The original R1 ZIP remains
50811 bytes, SHA-256
`da04dc996707e0111beaf804587eb27c85c4351b6db0f2388b67037da3771ff8`.
The installed, unchanged intake accepted the separately identified approved-base
ZIP, SHA-256
`92daf50efd0cf6a0d147490f636c76cf2a5ec62034c8311a52fd1761df8b9737`.
The reconciliation and exact predecessor report are preserved in the external
`runtime/nativeabi13-r1/` leaf. No history modification is part of this task.

Before lowering changes, `corpus.py` declares twelve distinct new source
programs: four FP, four independently compiled C boundaries, and four native
aggregate/memory cases, including two observable buffer replacements. The
twenty-four LLVM-12 inputs and expectations remain byte-exact. The inherited
`existing-nested` input is an additional unchanged FP-record witness. A proposed
input is never counted until C0 accepts it, the native stages independently
verify it, and its newly emitted body executes against the declared oracle.

Expected exit is zero and ordinary output is empty. C export cases use the
independent C witness as entrypoint; other application main functions are Astra.
C bit comparisons use memcpy and include signed zero, subnormal, infinity,
quiet NaN payload and maximum finite transport. Arithmetic has strict defaults.
The pointer witness transports a static unmanaged C pointer; it provides no
claim of compiler-proven foreign noescape behavior.

Preflight found C boundaries deferred before SSA, admitted buffer replacement
deferred by LLVM, and owning-record reassignment rejected by C0. That last
case remains outside the executable selection. The current parser also rejects
the user's edited unbraced model. Any required admission or grammar extension
has the separately recorded owner approval. The owner approved both bounded
semantic admission and restricted single-statement parsing on 3 November 2026.
Neither approval permits new ownership or floating-point language semantics.

The public version-2 formatter pilot passes 405 checks over 74 existing source
files. A separate paired original/new pilot compares normalized syntax trees,
O0/O2 executions and exact unsuppressed Valgrind cleanup traces, including
continue/break paths, with declaration/nested-control refusal tests. Both user
model variants converge to identical formatted bytes. Initial pilot failures
and rebuild costs remain in runtime receipts. This is formatter qualification;
the broad formatting pass and the native ABI campaign remain outstanding.

G0–G10 and F0–F5 remain mandatory. Full eligible-source formatting must follow
a qualified syntax/AST/lifetime pilot and remain in its own mechanical commit.
No build, partial execution set, or subset of gates constitutes milestone PASS.

The initial O0 component freshly passes all original 24 executions plus nine
additions, with independent C0 comparisons and unsuppressed normal Valgrind.
The C export bit witness also links and executes with both GCC and Clang.
The three import-bearing additions pass source admission but stop at Core's
existing nonempty-body invariant. Their failed receipts are retained. This is
an intermediate implementation checkpoint, with O2, imports, independent new
faults, source-formatting equivalence and final publication still outstanding.

The next source closure passes the original 24 at both profiles, and ten
additions at O2 (including separate C I32 edge calls). Its independent negative
pilot exposed a missing strict-FP check on an export wrapper; this failed trial
is retained. C imports now pass Core but expose CFG's executable fallthrough
rule on declaration-only records. Both require explicit refinement checks.
The borrowed-noescape declaration is a trusted foreign assertion, independently
witnessed with static C storage; it never grants LLVM capture/alias attributes.

Three tracked test inputs referenced by the inherited 1044-query proof ledger
are explicitly protected before the broad format pass: nested/deep struct-copy
fixtures and the destructor witness. This preserves all original 446 exclusions
and adds three source-bound exclusions, without omitting implementation code.
