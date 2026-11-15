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
The default kernel also compares packed owner states against the preserved
scalar checker, with current reservation metadata, generated graphs and word
boundary controls. Its reported 256-slot work count supports focused before/
after cost comparisons under the same 8M ceiling.
The executable also accepts `--owner-graph COUNTS BLOCKS CORE VALUES SLOTS
ENTRIES OWNER_SLOTS CONSUMERS CATCH_TRY REACHABLE REGIONS`, with eleven explicit
binary paths. The eight signed little-endian counts are block, Core node,
function, storage slot, SSA value and symbol counts, actual remaining work and
reservation count. The retained x86-64 row widths are 40, 80, 20, 24, 4, 4, 4,
4, 1 and 12 bytes respectively. It checks lengths, reconstructs the private
physical index, and compares the exact preceding Git-pinned packed entry with
the candidate under both an isolated 8M budget and the captured remaining
budget. Synthetic decoder controls include missing cleanup, malformed counts
and truncated transport. This remains helper replay evidence, with no complete
source, generation or compiler-memory acceptance.

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

### Current migrated compiler-systems examples

These are workload-cohort identities. Complete milestone qualification, including later compiler regression repairs, is recorded separately.

The migrated `module-config`, `file-digest64` and `systems-report` sources use the 27-C compiler. Their real no-argument entrypoints copy and validate every process argument through the existing private GNU/Linux x86-64 LP64 `compiler/driver/arguments.c` transport before checking argument count. Include `checked-arguments.astra` and the unchanged `arguments.o`; no new runtime or public ABI is introduced. A successful invocation takes an input path and an output path. Wrong argument count returns 64; malformed UTF-8 anywhere in argv, including argv0 or unused arguments, returns 2 before application work.

Use an authenticated compiler and the six authenticated provider objects from an existing build's `link.json`. The final qualification used these compiler identities:

| Host | Actual compiler source revision | Producer | SHA-256 |
| --- | --- | --- | --- |
| dev18 | `28f89b600115efe958f3f8d4724bb79aed0fc0f5` | C0 | `01d4b84cc7f6d0239327d1899e0257b7ff68225df0213ce0774031e378644a99` |
| dev19 | `38e3e3e181609e1513e86cbb22a28a5465cfd000` | Astra dev16 | `93615207f7fc09a4947f8eb759b19b98d984371df7bc065e16dd1d5e67c4bdc3` |

This Bash recipe uses explicit repository, compiler, provider and external output paths, the existing native driver, `cc`, and the pinned LLVM 23.1.4 verifier. It does not invoke C0 on migrated source. Set the four paths before running it; select the same qualified PATH/library environment recorded in the compiler build receipt.

```bash
set -euo pipefail
: "${ASTRA_REPO:?absolute repository path}"
: "${ASTRA_HOST:?absolute authenticated 27-C astrac-O2 path}"
: "${ASTRA_PROVIDER_DIR:?absolute directory containing authenticated provider objects}"
: "${ASTRA_EXAMPLE_BUILD:?absolute output directory outside the repository}"
mkdir -p "$ASTRA_EXAMPLE_BUILD"
astra_example_common=(
  "$ASTRA_REPO/examples/application-runtime/support.astra"
  "$ASTRA_REPO/lib/astra/base/errors.astra"
  "$ASTRA_REPO/lib/astra/base/diagnostics.astra"
  "$ASTRA_REPO/lib/astra/text/utf8-message.astra"
  "$ASTRA_REPO/lib/astra/text/utf8-byte-builder.astra"
  "$ASTRA_REPO/lib/astra/text/scalar-format.astra"
  "$ASTRA_REPO/lib/astra/hosted/text-ops.astra"
  "$ASTRA_REPO/lib/astra/collections/bag.astra"
  "$ASTRA_REPO/lib/astra/hosted/files.astra"
  "$ASTRA_REPO/lib/astra/hosted/text.astra"
  "$ASTRA_REPO/examples/compiler-systems/checked-arguments.astra"
)
astra_example_providers=(
  "$ASTRA_PROVIDER_DIR/args-posix.o"
  "$ASTRA_PROVIDER_DIR/files-posix.o"
  "$ASTRA_PROVIDER_DIR/text-posix.o"
  "$ASTRA_PROVIDER_DIR/text-ops-posix.o"
  "$ASTRA_PROVIDER_DIR/diagnostics-trap.o"
  "$ASTRA_PROVIDER_DIR/arguments.o"
)
build_astra_example() {
  local astra_example_name="$1"
  shift
  local astra_example_mode
  for astra_example_mode in O0 O2; do
    "$ASTRA_HOST" -c "-$astra_example_mode" \
      -o "$ASTRA_EXAMPLE_BUILD/$astra_example_name-$astra_example_mode.o" \
      "$@" "${astra_example_common[@]}"
    cc -no-pie "$ASTRA_EXAMPLE_BUILD/$astra_example_name-$astra_example_mode.o" \
      "${astra_example_providers[@]}" \
      -o "$ASTRA_EXAMPLE_BUILD/$astra_example_name-$astra_example_mode"
    readelf -h "$ASTRA_EXAMPLE_BUILD/$astra_example_name-$astra_example_mode"
  done
  "$ASTRA_HOST" --emit-llvm -o "$ASTRA_EXAMPLE_BUILD/$astra_example_name.ll" \
    "$@" "${astra_example_common[@]}"
  opt -passes=verify -disable-output "$ASTRA_EXAMPLE_BUILD/$astra_example_name.ll"
}
build_astra_example module-config \
  "$ASTRA_REPO/examples/compiler-systems/module-config.astra" \
  "$ASTRA_REPO/examples/compiler-systems/module-config-parser.astra" \
  "$ASTRA_REPO/examples/compiler-systems/module-config-model.astra" \
  "$ASTRA_REPO/examples/compiler-systems/module-config-format.astra"
build_astra_example file-digest64 \
  "$ASTRA_REPO/examples/compiler-systems/file-digest64.astra"
build_astra_example systems-report \
  "$ASTRA_REPO/examples/compiler-systems/systems-report.astra" \
  "$ASTRA_REPO/examples/compiler-systems/systems-report-math.astra"
```

For the recorded qualification, `ASTRA_PROVIDER_DIR` was the unchanged dev16 provider directory. Its six SHA-256 identities are below. `llvm-capi.o` and the LLVM library are needed by the compiler product, not by these example executables.

| Provider object | SHA-256 |
| --- | --- |
| `args-posix.o` | `387994b9f3a084bab6e8ddbf67646c429c37559e01604ca3e98db22d6a9cf985` |
| `files-posix.o` | `566f338cdb1b9c85e1b34c7e17e34ed42af95124d518e47bcacd95fdee450ce3` |
| `text-posix.o` | `74a7c8adc3187f37bd55bc97b5f740f5052f760ffe7f8b5373461d1d779e62a9` |
| `text-ops-posix.o` | `d3c248afac37d384a3c4b391fea6a250011c14128de00134323cb2ee5f1b71ad` |
| `diagnostics-trap.o` | `7c0fcb2a2e952aeaf45e17e2e832e8e9c98056d90f987840a72bbe009f3209d7` |
| `arguments.o` | `1b79596b599abf0568908f9b65693454af41b82685299d6604abbcca61b87cd7` |

The immutable legacy argv-main sources remain the C0 before-oracles. The historical `compiler-systems-2` recipe uses its historical public C0 driver and emitter interfaces; it is not evidence that C0 accepts the migrated syntax. Current before/after CLI proofs record actual sources, producer hashes, provider hashes, O0/O2 ELF/LLVM, exact output and exit status, I/O faults, Unicode paths, malformed argv, and strict returning target memory separately from this build recipe.
