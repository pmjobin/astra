# Building and testing Astra

The production compiler currently builds from Vala in `bootstrap/`. The Astra
source and lexer ports live in `compiler/`; they are component implementations,
not a self-hosted full compiler. Use explicit source and output paths.

## Dependencies and build

The hosted development profile uses system Vala, Meson 1.11+, Ninja, a C11 compiler,
GLib/GObject and LLVM 22 development files. The LLVM boundary uses the selected
`llvm-config` and the narrow C API; discovery and linkage checks are authored in
`bootstrap/backend/llvm/meson.build`. Python drives integration tests. LLVM command
line tools, GCC/Clang, ELF inspection tools and Valgrind are used by their respective
test profiles. GIR/GObject, debugger, editor and platform profiles have additional
explicit prerequisites.

From the repository root, choose a new task-owned external build directory:

```sh
astra_build="$HOME/Workspace/codex/work/astra/build/developer"
astra_runtime="$HOME/Workspace/codex/work/astra/runtime/developer"
CC=/usr/bin/gcc CCACHE_DISABLE=1 meson setup "$astra_build" "$PWD" \
  -Dbuildtype=debugoptimized -Dwerror=false \
  -Dqualification_runtime="$astra_runtime"
meson compile -C "$astra_build" astrac -j 4
"$astra_build/astrac" --version
```

`astrac` always enables fatal Vala warnings, strict generated C and C warnings as
errors. Detached test helpers use their existing warning policy; selecting
`-Dwerror=false` for them does not relax production. `stage0_optimization` controls
the compiler's own C optimization; it does not change public `-O0/-O1/-O2` behavior.
`numeric_oracle_optimization` separately controls exhaustive numeric helpers.
Keep assertions enabled. Routine component work should name its required targets;
the default build includes hundreds of independent white-box programs.

## Use and installation

```sh
"$astra_build/astrac" --check /absolute/answer.astra
"$astra_build/astrac" -O2 /absolute/answer.astra -o "$astra_runtime/answer"
"$astra_runtime/answer"
meson install -C "$astra_build" --no-rebuild --destdir "$astra_runtime/install"
```

Create the runtime directory before writing products. Installation requires all
installable targets to have been built. The supported two-build distribution
recipe in `tools/release/developer-build.py` discovers those prerequisites and
checks relocated installs; see its README. Installation stages into the explicit
DESTDIR. The source layout is `lib/astra` for Astra, `lib/runtime` for C/headers and
`lib/bindings` for foreign declarations. Installed API paths remain stable beneath
`share/astra`. Supply required sources, `--vapi` declarations and `--link-object`
providers explicitly. VAPI parsing never invokes a C compiler or parses headers.
The [installed guide](tools/developer-release.md) includes package and editor use.

## Test selection and evidence

```sh
meson test -C "$astra_build" --list
meson compile -C "$astra_build" astrac
meson test -C "$astra_build" --no-rebuild selfhost-foundation-source selfhost-lexer
meson test -C "$astra_build" --no-rebuild --print-errorlogs TEST_NAME
```

Build a selected test's dependencies before using `--no-rebuild`. Meson owns test
process isolation, expected exits, TAP interpretation, deadlines and serial tests.
A successful build or exit alone does not establish all expected cases passed.
Inspect actual case plans, refusals, traces and results. Preserve failed attempts.
The generic execution/installed-client runners use the test-only stage collector;
their registered Meson dependencies build it automatically. Direct invocations
accept an explicit collector path after their normal compiler/build and output
arguments. It materializes each dump at its original boundary; independent models,
public CLI controls and fresh-process determinism remain separate.

Standalone Core, semantic, NABI, CFG and SSA cohorts share compilation only within
an identical model closure. Their dispatcher selects one original family in a fresh
process. LLVM-free linkage checks still inspect every affected boundary. No
universal compiler test library replaces those independent closures.

The auxiliary generic `memory.py` recipes take current build, independent baseline
build and output paths. The struct-element recipe also needs the baseline
`astra-struct-elements-pipeline` and `astra-struct-elements-llvm` products built
from their matching source/recipe. Explicit host GLib controls require exact
baseline loss counts, stacks and observations; they do not suppress additional
errors or relax zero-loss checks for other normal cases.

API B/B3, Sequence and Braid default to current regression. Current runs bind actual
compiler, sources, recipes and host dependencies without historical freeze JSONs.
An explicitly selected historical replay requires genuine evidence and matching
identities; unavailable evidence is a failure. Current outcomes carry no historical
challenge credit. Sequence/Braid keep independent peers, hidden-producer SDKs,
lifetime/cancellation and tool instrumentation checks.

The default build excludes optional native Linux providers. Enable the existing
profiles with `-Dlinux_async=true` (matching liburing >=2.15 via `PKG_CONFIG_PATH`)
and `-Dhosted_concurrency=true` when their prerequisites are available. This makes
additional tests visible; record the configured catalog. Foreign/VM/editor and
separate-peer qualification require their declared environments and authorization.
An unavailable profile is not a passing test.

For cost comparisons, fix logical cases and variants first. Use separate fresh
build directories and disabled or initially empty compiler caches. Measure setup,
cold selected-product builds and warm execution separately; compilation performed
by a test remains part of that test. Report process counts and peak memory alongside
wall time, and do not substitute historical timings from another machine.

## Contribution and continuity

Use [CODING_STYLE.md](../CODING_STYLE.md) and `tools/format/source.py`; update
`format/scope.json` explicitly for authored source changes. Protected fixture bytes,
independent numerical/lifetime oracles, verifier separation and module-owned LLVM
layout-cache lifetime remain contracts. Run the complete affected host dependency
closure once changes stabilize. Reconcile changed registrations and conditional
profiles instead of asserting a permanent historical count.

Keep code, portable recipes and concise maintained documentation in Git. Store
build products under the project's external `build/` area and detailed receipts
under its `runtime/` area. [Git recovery](history/active-tree.md) identifies retired
milestone reports; those old qualifications do not qualify a new checkout.
