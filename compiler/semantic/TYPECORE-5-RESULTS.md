# TYPECORE-5 current qualification

This is a scoped checked-type/signature and finite scalar-checker qualification,
not Stage 1 or a replacement for Vala C0. The native implementation consumes the
retained Binder graph. Logical type identity, written qualifiers and deferred
proof obligations remain distinct. The report binds these findings to exact Git
HEAD/tree, product hashes, fixtures and raw receipts.

The final corpus has 121 independently annotated cases: 67 accepted C0 programs,
51 rejected programs, and three positive partial-layer observations whose full
C0 programs fail later storage/nonnull/ownership obligations. Initial fixtures
were frozen before implementation; subsequent expansions, diagnostic annotation
repairs and regression fixtures retain their separate frozen attempts. All 121
execute at O0/O2 with identical native observations. Every rejection has accepted
C0 syntax and exact C0/author-annotated first-error byte coordinates. Native
message wording is not asserted byte-identical to C0; both raw diagnostics remain.

The checked consumer exercises canonical scalar/wrapper identity, exact nominal
and scoped parameter identity, closed generic substitution, primitive widths and
signs, callable channels, declaration order, returns/locals/calls, scalar operators,
conditions, contextual null, readonly/private metadata and written async/throws
flags. Wrong owner/ID, source identity, retained spans, partial construction,
constructor depth/exhaustion, repeated error destruction, two checked-model
mutants and a hidden AST-span mutant are executed controls. Three independently
corrupted observations are rejected by the fixture assertions.

The mixed current-project input has 12,224 declarations and 80,495 references.
It produces 1,146 type records, 1,388 signatures and 30,360 typed use records;
records carrying a deferred obligation are not complete semantic proofs.
The common primitive source projection matches 1,594 C0 type observations.
Structural/template materializations, dependent deferrals and synthetic source
identities have explicit separate denominators in the report.

For the same original Binder references, 1,137 direct-field selections and 1,713
contextual initializer selectors become bound. Original bound targets and byte
spans remain unchanged. The competing inferred callable case separately proves
reason-7 completion. This does not close entire language-wide categories: implicit
receivers, properties/inheritance, match payloads, intrinsics and slot operations
remain represented by their original reasons. All remaining reason counts and
representative spans are retained in the current-source summary.

Memory qualification includes 20 unsuppressed runs of the new O0/O2 consumers and
four additional lifetime/multi-source stress runs, with zero Valgrind errors and
no definitely/indirectly/possibly lost bytes. The maintained Binder suite passes
85 cases at O0/O2 and 32 unsuppressed Valgrind runs. Fresh focused source, lexer,
parser and native LLVM layout-lifetime continuity passes. No inherited release
sweep, Windows/VM run, installation or release qualification is implied.

Final native compilation measured 241.56 seconds / 1,169,696 KiB peak RSS at O0
and 484.19 seconds / 1,176,500 KiB at O2. These command wall times overlap other
builds and cannot be summed as campaign duration. The final corpus runner took
17.47 seconds excluding compilation (exact dependency/product reuse). Complete
command/RSS receipts include builds, C0 observations, memory checks, failed
attempts and repairs. No cold-cache or whole-compiler speedup claim is made.

Failures were retained and repaired: safe child borrowing and constructor rules;
diagnostic/projection differences; an invalid readonly-int metadata fixture;
and a real local-constant Binder omission which exposed a zero-ID assertion in
partial checking. Local constants now enter scope after initialization and the
checker guards incomplete declaration rows. Their minimized source and native
assertion trace are preserved. Historical Binder-4 remains scoped historical
qualification; its report and all source/project ancestry are preserved.

Reference phase controls matter: C0 tooling/dumps can expose depth-130 signatures,
while full `--check` refuses materialization beyond depth 128. Tooling-index can
also return declarations for a double-release source which the full pipeline
correctly rejects. The recipe retains these distinctions, rather than treating
a checked-model observation as executable acceptance. Native constructor depth
128 is tested independently of a 4,096-leading-zero valid literal spelling.

The remaining work is explicit in `typecore-port.json`: nonnull flow (18),
ownership/loans (19), complete aggregate construction (20), constant extents (11),
receiver/property/inheritance selection (12), foreign/async/throwing/generic calls
(17), broader checked statements/expressions and general generic storage proofs.
Some declaration policy, Resource/context/runtime admission, full checked IR,
Core/CFG/SSA, native ABI and LLVM remain Vala. These are follow-on semantics,
not evidence of a complete self-hosted compiler.
