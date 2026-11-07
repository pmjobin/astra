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

## Remaining boundary

This is an implementation checkpoint, not completion or a full gate PASS.
The message-reading version of the error witness is rejected by the Flow
consumer (`RECOVER_FLOW 1`, before output); its failed attempt is retained in
`early-v4a-O0`. The working minimal witnesses use direct catch returns. Catch
message projection still needs the independent checked/borrow contract.

The initial physical consumer checks declaration groups, error splits,
success-only loads/stores, handler targets, phi incoming owners, destruction
calls, and layouts. Complete instruction/body correspondence, independent
adversarial controls, and helper-body verification remain required. No mutation
credit is claimed for this checkpoint.

Owned input reservations, owned buffer/Class and record results, ordinary local
and loop cleanup, admitted static receivers/generics, full source integration,
the 12-program/eight-error minimum, and unchanged throwing compiler-function
execution are unfinished. The 202 inherited programs and frozen source cohorts
have not yet been replayed using a combined current compiler. Earlier R2
qualifications remain tied to their original products.

`CheckedIndex.add_signature` predicate 26 remains independently deferred. No
receiver root, owner slot, `noalias`, verifier exemption, or larger resource
limit was introduced. Original EFFECTS-25/R1 PARTIAL archives, their payloads
and Git ancestry, the E25-A-v1 approval/proposal, 451 protected paths, 6,622 donor
files, and 1,044 historical proof hashes were reauthenticated. The read-only
donor, C0, public ABI, historical records, and prior build leaves are preserved.
There is no Stage 1, push, or release claim.
