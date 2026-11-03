# LLVM-12 native qualification

The Astra-written backend passes the bounded native engineering qualification
on GNU/Linux x86-64 with LLVM 22.1.8. It consumes retained independently verified
SSA, checks source/edge/value correspondence, verifies real LLVM modules, emits
ELF relocatable objects and executes newly generated application functions.
Its API, private ABI, lifetime rules and limits are in [CONTRACT.md](CONTRACT.md).

The final compiled input closure is committed at `942273a`. Later findings and
receipt-tool commits do not alter the native compilation inputs. Qualified C0
remains SHA-256 `30865ad8a9d1652b63ad882f1e29031c76ac13204212f822b44235cb07df10de`.
C0 builds the component and independent reference executables; it does not
supply the application functions emitted by this backend.

Both O0 and O2 freshly execute the same 24 frozen, distinct source programs:
six numeric, four branch/short-circuit, four loop/PHI, four direct-call, four
ownership and two storage/control cases. Each matches predeclared exit/output
expectations and a separately generated C0 executable. The inherited scalar
control still returns 255. Five allocation/cleanup traces, including both call
order variants and the ownership loop, match hand-derived byte counts and C0.
The loop observes five repetitions of allocate 8, allocate 12, free 12, free 8
bytes in both profiles. Normal executions and LLVM construction/error/lifecycle
checks pass unsuppressed Valgrind with zero errors and zero lost bytes.
Reachable LLVM/library allocations are reported separately in the raw receipts.

One additional complemented-literal regression passes at both profiles and is
not counted among the frozen 24. The pre-fix emitter actually returned 1 on this
source while the qualified C0 reference returned the independently expected 0.
The correction respects the exact retained +, - or ~ token and each integer
width. Three inherited intentional SIGILL controls execute independently in
both profiles; no ordinary leak or fatal-unwinding claim is made for them.

Each profile rejects 21 actual LLVM module mutations after valid upstream SSA,
covering 20 families if signed/unsigned no-wrap attributes are grouped together.
They include exact PHI values/edges, predicates/extensions/constants, wrapping
flags, GEP flags, branches, returns/ABI, argument order, alias premises,
omitted/duplicate/wrong-owner cleanup, wrong storage, target/layout, forged
verification and removal of the owning-store observation marker. Before/mutant/
restored IR hashes are retained. Restoration creates a fresh owner with byte-
identical IR; complete retained SSA backing snapshots remain byte-identical.
Wrong source owners, disposed artifacts, exhausted/malformed profiles and output
failures reject without a public object; pre-existing destination bytes survive.

All 80 inherited source statuses are freshly preserved: 56 SSA positives, 12
invalid and 12 deferred, with byte-compatible admission/Core/CFG/SSA output.
The Core22, CFG26 and SSA30 mutation families and independent graph oracles pass
again at both profiles. Of the 56 SSA positives, 55 reach verified LLVM IR;
`existing-nested` explicitly defers because its record contains f64. Other
unexecuted positives are labelled IR-verified rather than native-qualified.
The separate predecessor replay freshly matches all 1,044 source-bound proof/
query observations, retaining the original 82 closures and nine added proofs.

Independent llvm-as/opt invocations parse and verify captured IR. readelf, nm
and objdump identify x86-64 ELF objects, newly generated function bodies, and
only approved libc dependencies. Every selected case records source/function
spans, admission and SSA identities, raw/optimized IR/object/executable hashes,
target/layout, runtime libraries, ABI version, link line and memory results.

Development failures remain recorded. They exposed the current C0 C-ABI vector
limitations, a borrowed-record address mismatch, an unavailable LLVM setter,
LLVM 22's implicit GEP flags, the folded-prefix bug and O2 allocation elimination.
Owning initialization/parameter storage now carries an independently checked
volatile implementation marker, keeping required heap observations through the
standard O2 pipeline without adding alias/overflow assumptions. Obsolete builds
whose inputs changed were refused by the identity guard. No process exit or
build success was counted as native acceptance.

Final cold component builds took 512.687s O0 and 929.674s O2, with a 929.674s
overlap union. Peak RSS was 1,435,680 and 1,444,536 KiB respectively; measured CPU
was 508.05+1.04s and 921.61+1.08s user+system. Final exact warm reuse took 1.12s
and 1.02s. The complete ledger includes failed/development/check attempts; their
costs are not hidden behind final-build figures. API token/currency cost was not
exposed by the session. SSA-11 timings remain historical, not a claimed speedup.

The 446 protected repository identities, 6,622 donor files, project config,
hooks and installed skill are preserved. Global Codex config byte differences
were observed before and during this task, without task writes; both identities
are retained and the model/reasoning/sandbox/approval settings still match.
The exact SSA-11 report is preserved by content hash before canonical replacement.

The focused Meson test and component target are registered; qualification uses
the same portable recipe directly with the exact qualified C0. The release
registry, other targets, public pushes and releases were not run. The former
73-source compiler selection remains deferred with zero whole-program proofs.
This is not Stage 1 or general language/backend qualification. The installed
pm-next publisher supplies the final report's submission, HEAD and tree binding.
