# Expressive language development checks

Use the existing production build recipe in
`tests/selfhost-ownership-syntax-27b/build.py` with an explicit producer path,
SHA-256, producer kind, optimization mode, build leaf and runtime leaf. The
recipe freezes committed compiler/library inputs and records their Git blobs,
tools, providers and actual compilation commands. A build receipt alone grants
no feature, complete-source, memory or generation acceptance. Attribute each
product to its actual frozen revision and producer; final same-source Stage3
convergence remains reserved for 27-D.

`component.py` builds focused production-source consumers with `--layer syntax`,
`binding`, `types`, `semantic` or `ssa`. Select an explicit consumer when needed,
such as `--layer syntax --consumer tests/selfhost-expressive-language-27c/formatter.astra`.
Supply `--compiler`, `--compiler-sha256`, `--c0`, `--c0-sha256`, `--producer-kind`,
`--mode`, `--link`, `--build` and `--runtime`. `--link` names a validated existing
production build's link manifest; the focused recipe selects its five platform
providers. It runs C0 source preflight, actual compilation, native assertions
and strict returning memory. The semantic consumer's `--source`/`--flow` and
SSA consumer's `--source` paths allow actual specimen checks without rebuilding
the component. Their results remain scoped to the selected passes.

`owner-kernel.py --llvm-cursor` selects the exact production aggregate cursor and
primitive checks with real LLVM arguments, constants and rejected corruptions.
It requires the explicit C0 identity and production link manifest, runs both
optimization modes and strict returning memory, and grants only cursor evidence.
Without that option the existing owner/dominator kernel selection remains active.
Its resulting executable also accepts `--graph BLOCKS.i32le ENTRIES.i32le` for
an explicitly identified diagnostic capture: ten little-endian signed 32-bit
RecoverBlock fields per block, followed by a separate entry-ID file. It reports
the production dominator work cost under the unchanged 8M ceiling. This graph
replay establishes neither source acceptance nor complete SSA/owner safety.

`named.py` exercises actual targets through `--feature named`, `match`, `range`,
`format` or `collection`. It requires the same explicit producer/C0 identities,
link manifest and output leaves. `--case NAME` selects focused cases; the range
lane includes the lazy specimens. Each normal case runs its independently
expanded C0 reference, actual O0/O2 ELF targets, returning target and compiler
Valgrind, and LLVM verification. Allocator observers check designated storage
contracts. `--oracle-only` establishes expanded-reference evidence only and
never qualifies new syntax or semantics.
`--feature range --freestanding-only` selects unused ranges, scalar range loops
and exact fixed collection. It retains import/ELF inspections, links a syscall
entry without libc or allocator, runs O0/O2 and strict returning memory, and
checks that owning array collection fails that link without its allocator.

`physical.py` reuses the existing 27-B process-local LLVM mutation driver.
Select `--feature existing`, `range`, `lazy`, `collection`, `format` or `enum`,
with explicit compiler SHA/build/runtime arguments and optional `--case NAME`.
Each group first checks unchanged controls. Every corruption must be accepted
by LLVM's returning structural verifier, then rejected by the independent
physical consumer without replacing the output sentinel. Corrupted targets are
not executed. This supplies no strict memory or complete milestone credit.

The native formatter consumer exposes `--format FILE`, `--dump-syntax FILE` and
`--version`, in addition to its default focused regressions. Its separately
piloted exact executable may be selected through the existing guarded
`tools/format/source.py --astrac PATH` entry point. The historical C0 formatter
pin stays recorded. See `docs/selfhost-expressive-language-27c.md` for exact
qualified hashes, corpus/refusal/memory results, and the explicitly unavailable
C0 factory-format reference. Preserve external receipts and earlier failures;
do not substitute historical or expanded results for current native proof.

All generated products belong under `~/Workspace/codex/work/astra/build/` and
temporary inputs/receipts under its `runtime/`. No recipe here changes intake,
publishes a release, upgrades a failed gate, or predeclares post-delivery G7.
