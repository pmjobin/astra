# EFFECTS-25-R2 completion work

This continues the published PARTIAL checkpoint at
`271d1b80b3922da1466ea303b7deea9e941249d1` (tree
`d0f8d32dd17bccbc43736df629310293094ea356`). The user authorized an
amendment after engineering, preserving the current report as history. Its
SHA-256 remains
`8cc90df9c524cd8a22ca0e9ba166920cff9962cc92a493691de64121aad5dc5a`.
No new intake, repinning, ABI decision, or publication has occurred here.

## First actual error ELFs

The `recover-*` implementation retains the checked source owner through explicit
Flow, Core, CFG, SSA, and module-owned LLVM models. It currently admits private
direct integer/bool/void functions, root Error snapshots, payload-free derived
errors, checked-call splits, typed catches, and lexical error cleanup. Source
effects remain conditional in CheckedIndex. The ordinary native ABI guard for
checked functions is unchanged.

The initial working slice has four distinct source programs per **target**
profile: scalar success/error and void success/error. All eight Astra-produced
LLVM modules assemble, verify before and after optimization, link, execute with
the expected exit, and match independent C0 compilation of the same sources.
Unsuppressed Valgrind reports zero errors and live allocations. Each error run
performs two allocations and two frees; each successful run performs zero.
Ignoring a throw produces an incorrect exit, so success cannot impersonate the
tested error path.

The O0-built experimental compiler is
`build/effects25-r2-completion/v4-O0/astra-recover-O0`, SHA-256
`1b9ad8cbe4c3b98e368f3586df71d2d1e26e439227efad0a77beb7694ce78132`.
It emitted both target profiles; a separately O2-built compiler is not yet
qualified. Its cold build cost was 515.34 seconds wall, 510.92 seconds user,
0.97 seconds system, and 1,400,328 KiB peak RSS. The earlier successful stage
check and intentionally stopped v3 build are separate costs, not warm reuse.

Evidence is under `runtime/effects25-r2-completion/early-v4b-{O0,O2}/`;
generated LLVM, objects, and ELFs are in the corresponding build leaves. Paths
are relative to `~/Workspace/codex/work/astra/`. Recipes are
`tests/selfhost-effects/recover-build.py` and `recover-qualify.py`.

Independent GCC C and Clang C++ O0/O2 probes confirm root size/alignment 32/8,
offsets 0/8/16/24, descriptor offsets 0/8/16, origin layout, complete base tail
padding, and embedded-NUL UTF-8 snapshot storage. These probes receive **zero**
Astra ELF credit. Their evidence is `runtime/effects25-r2-completion/layout-v1/`.

## Typed messages and runtime continuation

The next implementation adds independently consumed conditional Typecore facts
for the source-declared message property and its lexical catch borrow. It keeps
the original CheckedIndex and pending obligations unchanged. LLVM verification
now also checks complete helper bodies, source parameter bindings, arithmetic,
instruction inventories, exact origin records and a closed function inventory.

The v5 O0-built compiler SHA-256 is
`7da7abbdc50c2a538dac70c3c2140d95ffed58c9d165f0d631d94f38615fec7c`.
It qualifies 15 distinct source programs per target profile, including 11 error
cases and four success cases. Typed derived/ancestor catches, ordered dispatch,
nested propagation, bare rethrow, replacement capture, outer handlers, empty
messages and embedded-NUL UTF-8 snapshots now execute. All compare with C0,
verify through LLVM and pass unsuppressed Valgrind. Evidence is
`early-v5b-O0/` and `early-v5d-O2/` in the continuation runtime.

Replacement performs four allocations/frees; bare rethrow performs two, with no
new Error allocation. The O0 empty-message representations differ: Astra
allocates its snapshot backing byte while C0 uses null backing. O2 can remove
the empty-error storage; the O0 twin retains its physical witness. Earlier
allocation-count assertions and their failed runs are retained separately.

The v5 cold build costs 594.14 seconds wall, 589.18 seconds user, 0.97 seconds
system and 1,424,112 KiB peak RSS. Focused Core checks are separate costs. The
native compiler itself remains O0-built for both target profiles.

## Independent controls and copyable record carriers

The v6 compiler qualified 17 semantic mutation categories and ten LLVM-valid
physical body alternatives at each target profile. Each negative begins with a
fresh verified positive twin and is rejected by the named independent consumer.
The skipped-object-free alternative returns 42 but independently fails
unsuppressed Valgrind with a 32-byte leak. The earlier harness assumption about
an unexecuted cleanup site is retained in `adversarial-v6a-O0/`; corrected runs
are `adversarial-v6b-{O0,O2}/`. These are focused controls, not complete input,
reservation, receiver or carrier qualification.

The v7 compiler SHA-256 is
`3f1a0bd64aa2b913ab998d46aa4078d95f8e9837bbace1b0c2129f60aa2384f2`.
Copyable records of integer/bool fields now retain declaration-bound construction,
local definitions, projections, checked returns and flattened source argument
groups. The physical verifier reconstructs the groups and validates aggregates,
source bindings and success-only storage independently. Original ordinary
compiler routes and the scalar-only historical ABI planner remain unchanged.

Eight distinct record programs pass per target profile, including result/error
paths, forwarding, flattened inputs, record copying and catch-local construction.
All 15 scalar/void cases are freshly repeated with v7. The combined 23 source
identities per target profile match independent C0, pass LLVM verification before
and after optimization and pass unsuppressed Valgrind. The 17 semantic and ten
LLVM-valid physical controls are also repeated at both target profiles.
Evidence leaves are `early-v7a-{O0,O2}/`, `early-v7scalar-{O0,O2}/`, and
`adversarial-v7a-{O0,O2}/`. All remain emitted by an O0-built compiler.

The v7 cold focused build costs 668.68 seconds wall, 663.42 seconds user,
0.94 seconds system and 1,394,264 KiB peak RSS. Its 29.74-second focused Core
check is separate. The combined compiler recipe is prepared for inherited
routes; integration and the 202-program replay are not yet qualified here.

## Owned storage and reservation continuation

The v8 O0-built compiler SHA-256 is
`14164a1496d4d6ff54f858240ad648ab6da2eae62c94b7dd38328f5ab6c2547b`.
It adds actual binder-owned local/parameter slots, separate armed bits, move
reservation and call-entry commits, explicit later-argument aborts, lexical
cleanup by validated scope/declaration order, and independent SSA slot/temporary
lifetime exploration. A null Class value can be armed. Success initialization
is separate from the nullable error return and is never inferred from TypeId.
The original CheckedIndex and pending obligations remain unchanged.

Class results here use the existing independently qualified fieldless Class
shape and its actual constructor specialization/borrowed receiver. No lexical
receiver root is invented. Checked Class results require a retained heap-factory
witness; a null-only checked factory is outside the native-v14-compatible domain.
The first independent C0-only nullable fixture was correctly refused for that
reason; the corrected heap-origin factory and its evidence are preserved.

Sixteen new owner programs per target profile cover buffer results, entered
callee success/error cleanup, later-argument reservation abort/commit, a retained
caller owner, protected/ordinary lexical scopes, implicit void cleanup, Class
factory success/error and nullable Class success. Together with the repeated
15 scalar/void and eight record cases there are **39 distinct source identities
and 39 distinct ELF hashes per target profile**. All match independent C0,
verify through LLVM and pass unsuppressed Valgrind. Evidence is in
`early-v8owned-*`, `early-v8scalar-*`, and `early-v8record-*`.
The 17 semantic and ten physical controls also repeat in `adversarial-v8a-*`.

`success-cell-v8b-{O0,O2}/` independently controls the caller's result cell for
scalar, buffer and nullable Class results against both Astra and C0 emitted
bodies. It proves the initialized canary remains unchanged on error, while
successful cells contain the complete expected carrier. These handwritten LLVM
caller adapters are **ABI probes with zero Astra program credit**. Original
emitted modules remain separate, byte-exact artifacts. The earlier harness
refusal over C0 dump mode's absent public main wrapper remains in `v8a`.
Independent GCC/Clang carrier assertions are in `layout-v7carriers/`.

The v8 cold focused build costs 848.95 seconds wall, 841.94 seconds user,
1.08 seconds system and 1,453,964 KiB peak RSS. Its focused Core check costs
31.13 seconds wall. The combined v8 Core check passes in 59.47 seconds with
359,988 KiB peak RSS. The earlier combined v7 `--check` passed through full LLVM
lowering/verification in 1,595.96 seconds, using 2,069,592 KiB peak RSS; it was
not a semantic-only check or a native executable build. These intervals overlap.

## Remaining boundary

This is an implementation checkpoint, not completion or a full gate PASS.
The native compiler itself remains O0-built for both target profiles.
Static checked receivers/generics, owner cleanup across loop exits, owned Error
locals/throw-move, additional source forms and unchanged original throwing
compiler-function execution remain unfinished. Record carriers currently contain
only scalar integer/bool fields; ordinary Class payloads are fieldless, and
error subclasses have no added payload fields.

The v9 focused compiler, SHA-256
`0d747eb2ed0f0a32d03a56f4fde43ed8c09c57c458671adc62056a4680657acf`,
qualifies 16 additional owner mutation categories and eight LLVM-valid owner
alternatives per target profile in `owner-adversarial-v9a-*`. The positive
reservation-abort twin passes execution, LLVM and unsuppressed Valgrind against
C0. Skipping its input-buffer cleanup preserves exit 42 but leaks eight bytes
and yields Valgrind exit 99 in a separate raw O0 falsifier. This falsifier is
not counted as O2 runtime evidence.

`abi-limit-v9a/` admits and LLVM-verifies 1,017 physical parameters, while 1,025
are explicitly deferred before LLVM signature construction; the existing output
sentinel remains intact. Independent C0 LLVM verifies both sources. The adapter
capacity remains 1,024. These boundary probes receive zero native program credit.
The v9 cold build costs 853.71 seconds wall, 846.96 seconds user, 1.09 seconds
system and 1,477,196 KiB peak RSS. Its successful Core check costs 30.95 seconds.
Earlier owner-mutator loan-check refusals remain in the build evidence.

The 202 inherited programs and frozen source cohorts have not yet been replayed
using a combined current compiler. Earlier R2 qualifications remain tied to
their original products. Full final costs, warm reuse and all gate results still
need consolidation before the installed report amendment is published.

`CheckedIndex.add_signature` predicate 26 remains independently deferred. No
receiver root, owner slot, `noalias`, verifier exemption, or larger resource
limit was introduced. Original EFFECTS-25/R1 PARTIAL archives, their payloads
and Git ancestry, the E25-A-v1 approval/proposal, 451 protected paths, 6,622 donor
files, and 1,044 historical proof hashes were reauthenticated. The read-only
donor, C0, public ABI, historical records, and prior build leaves are preserved.
There is no Stage 1, push, or release claim.
