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

## Remaining boundary

This is an implementation checkpoint, not completion or a full gate PASS.
The initial message-reading failure (`RECOVER_FLOW 1`, before output) is
retained in `early-v4a-O0`; it is resolved by the conditional typed-borrow facts
above. The first minimal witnesses remain tied to their original sources.

Owned input reservations, owned buffer/Class results, owner locals and loop
cleanup, admitted static receivers/generics, full source integration, the
required owner/input coverage, and unchanged throwing compiler-function execution
are unfinished. The current record path permits only copyable scalar fields.
The 202 inherited programs and frozen source cohorts have not yet been replayed
using a combined current compiler. Earlier R2 qualifications remain tied to
their original products. Draft owner models receive no execution credit.

`CheckedIndex.add_signature` predicate 26 remains independently deferred. No
receiver root, owner slot, `noalias`, verifier exemption, or larger resource
limit was introduced. Original EFFECTS-25/R1 PARTIAL archives, their payloads
and Git ancestry, the E25-A-v1 approval/proposal, 451 protected paths, 6,622 donor
files, and 1,044 historical proof hashes were reauthenticated. The read-only
donor, C0, public ABI, historical records, and prior build leaves are preserved.
There is no Stage 1, push, or release claim.
