> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# Retained Content Adaptive Downscaling workload

**APP-CAD-1 is BLOCKED_COMPILER.** The historical application L and compatibility
port P reproduce the original acceptance. I stops at the required native-array
allocation-failure boundary. This directory does not contain a completed
idiomatic downscaler. See the report.

The authority is CAD `f415381f92daecfa683838206dffa5ea78d78477`, with historical
compiler `a1fadc5c052e82ae464268787f617252998c24be`. The current compiler is frozen
at `4c59bf432a48bea7bf2bf262c296aa0c868ffec3`. [pins.json](pins.json) and
[cad-members.json](cad-members.json) identify exact commits, trees, blobs, modes,
report records and local image hashes. No later PIXEL source is imported.

Run commands from the Astra repository root. Every output argument below must
name a fresh directory under `build/app-cad-1/`. None of these commands downloads
inputs, installs packages, changes another checkout or regenerates expectations.

## Full local qualification

The original Git objects, full oracle, all eight local-only source/reference
images, and existing CAD dependencies are mandatory. On this machine they were
found read-only in the sibling `aster-scale` repository and its
`test-data/reference` directory. Other machines should supply their verified
local locations explicitly.

```sh
python3 -B workloads/cad/qualify.py \
	--compiler-repository "$PWD" \
	--cad-repository <historical-private-path> \
	--assets <historical-private-path> \
	--output "$PWD/build/app-cad-1/reconstruction" --jobs 8
```

The command first runs the mandatory input preflight, extracts immutable Git
snapshots with complete blob/mode checks, reconstructs L and its 6,726 compiler
tests, runs all 13 original CAD entries, builds the frozen current compiler and
its 9,067 tests, materializes P, runs the same CAD entries, checks all 37 original
hash/iteration controls, and compares retained native artifacts. It then runs the
I allocation-boundary probe. Exit **3** records BLOCKED_COMPILER; exit **2** records
BLOCKED_INPUT. An unresolved build, test or parity failure returns 1 with raw logs
and an INCOMPLETE record requiring investigation. There is no application PASS
shortcut. This is a substantial local qualification, not a smoke test.

The delivered investigation ran these component commands in separate recorded
roots; the composed command above was checked through its constituent operations,
not run as an additional duplicate full campaign. It intentionally reconstructs
the baseline compiler, while the final repository candidate suite is a separate
validation obligation.

Preflight alone, with or without extraction:

```sh
python3 -B workloads/cad/prepare.py \
	--cad-repository <historical-private-path> \
	--assets <historical-private-path> \
	--output "$PWD/build/app-cad-1/inputs" --extract
python3 -B workloads/cad/materialize.py \
	--reference "$PWD/build/app-cad-1/inputs/sources/cad" \
	--manifest "$PWD/build/app-cad-1/inputs/cad-members.json" \
	--output "$PWD/build/app-cad-1/compatibility-source"
```

The import recipe reads Git objects rather than the live worktree. It applies
[the complete compatibility patch](compat/port.patch) and adds only the bounded
argument adapter and public entry. The manifest maps every resulting source back
to the frozen authority. Keep the generated archives/manifests when moving a run;
an unrecorded live checkout is not a reproduction source.

## Public regression and smoke

The ordinary compiler test needs only the existing compiler/C/libm toolchain:

```sh
CCACHE_DISABLE=1 meson test -C build app-cad-original-numerical-foundation --print-errorlogs
```

It compiles the exact original numerical source and native assertions using actual
multi-source compilation. It needs neither local images nor NumPy, Pillow or
libpng development files. It qualifies that original unit group only.

For an already built P executable, this deterministic smoke uses Python's standard
library to write the exact constant-image pixels from the original synthetic case:

```sh
python3 -B workloads/cad/smoke.py \
	--program "$PWD/build/app-cad-1/reconstruction/P-cad/astra-cad" \
	--output "$PWD/build/app-cad-1/public-smoke"
```

The smoke checks the existing 15-iteration control and PNG output SHA-256
`749b331e85b16a049f15dab5d85b1ec3590cbde32f9cf608a520034110338083`.
Its generated input has the same pixels; the standard-library PNG encoding need
not equal Pillow's original input encoding. This does not replace the local corpus.

A source-only smoke build needs the pinned CAD Git objects and existing libpng/C
dependencies, but no private image or oracle package. Import exactly the textual
authority, then let `materialize.py` verify every file against the committed
manifest before applying the compatibility patch:

```sh
set -euo pipefail
mkdir -p build/app-cad-1
mkdir build/app-cad-1/public-reference build/app-cad-1/public-tmp
git -C <historical-private-path> -c tar.umask=0022 archive f415381f92daecfa683838206dffa5ea78d78477 | tar -xf - -C build/app-cad-1/public-reference
python3 -B workloads/cad/materialize.py --reference "$PWD/build/app-cad-1/public-reference" --manifest "$PWD/workloads/cad/cad-members.json" --output "$PWD/build/app-cad-1/public-source"
CCACHE_DISABLE=1 CC=/usr/bin/gcc TMPDIR="$PWD/build/app-cad-1/public-tmp" meson setup build/app-cad-1/public-build build/app-cad-1/public-source -Dwerror=true -Ddebug=false -Dastra_compiler="$PWD/build/astrac" -Dargs_provider="$PWD/build/lib/astra/args-posix.o"
CCACHE_DISABLE=1 TMPDIR="$PWD/build/app-cad-1/public-tmp" meson compile -C build/app-cad-1/public-build -j4
python3 -B workloads/cad/smoke.py --program "$PWD/build/app-cad-1/public-build/astra-cad" --output "$PWD/build/app-cad-1/public-source-smoke"
```

This explicit smoke route cannot qualify the private corpus. Run the mandatory
full qualification command above for application acceptance; running only the
source-only smoke must never be reported as that acceptance.

## Staged and relocated P consumer

The recorded independent installation was configured with prefix
`build/app-cad-1/configured-prefix`, datadir `share` and libdir `lib64`, then staged
with `meson install --no-rebuild --destdir build/app-cad-1/installed/stage` and moved
to `build/app-cad-1/installed/relocated-prefix`. Both prefix locations are outside
the isolated compiler source snapshots. The complete installed manifest records
28 files and their origin hashes.

The retained usable consumer is `build/app-cad-1/installed/application/astra-cad`.
Its build selected the relocated `bin/astrac` and
`lib64/astra/x86_64-linux/args-posix.o` explicitly. P needs no Astra library source
beyond its original application sources; it still uses the original C/libm
wrappers. There is no transitive autolinking. The local `installed/commands.json`
records every command/cwd/environment and all 24 source permutations. All nine
canonical stages use stable relative `src/*.astra` labels without string scrubbing.
This is installed P evidence, not the incomplete installed I obligation.

## Native-state blocker without images

```sh
python3 -B workloads/cad/allocation_probe.py \
	--compiler "$PWD/build/astrac" \
	--args-provider "$PWD/build/lib/astra/args-posix.o" \
	--output "$PWD/build/app-cad-1/allocation-reproduction"
```

This compiles the actual nine-f64 Kernel shape and a scalar minimization. Under
the original 64 MiB address-space limit, both native allocations trap, whereas
the original application requires exit 2 and `failure 3`. A small first/last
record-copy control succeeds; a bounds-control trap demonstrates why translating
all SIGILL signals into allocation errors would be ambiguous. These fatal probes
disable core files and make no cleanup claim. The command returns 3 when it
reproduces the recorded blocker, not 0 for application acceptance.

## Separate observation and timing

[memory.py](memory.py) runs eight normally returning scenarios per route under
unsuppressed Valgrind, and repeats them with [observe.c](observe.c). Build the
observer with `gcc -std=c11 -O2 -Wall -Wextra -Werror -fPIC -shared
workloads/cad/observe.c -ldl -o build/app-cad-1/observer.so`, then supply
`--build`, `--synthetic-inputs`, `--observer` and a fresh `--output`.
The synthetic inputs must come from the original completed Synthetic suite.
Observer allocations and whole-process memory measurements are separate records.

[measure.py](measure.py) uses the fixed [timing plan](timing-plan.json). Supply
`--l-compiler`, `--p-compiler`, `--l-source`, `--p-source`, `--l-build`, `--p-build`,
`--args-provider`, `--synthetic-inputs` and a fresh `--output`. Run it only after
all builds, qualification suites and heavy evidence operations finish. It retains
seven balanced repetitions, commands, raw samples, output identities, medians and
spread. I is explicitly absent. The two-clock numerical observer covers
initialization through output-sample conversion, excluding PNG read/write and
cleanup. It is a separate binary; uninstrumented CLI samples remain separate.
The public driver exposes Astra compilation plus linking as one measured command;
C adapter translation is timed independently.

## Ownership and distribution

The 55-file CAD authority has no standalone license or copyright notices. The
user-authorized textual excerpts retain their original comments; their exact
origin mapping is in [reference/origins.json](reference/origins.json). This
campaign does not assign them the compiler's license. New harness/adapter files
carry their own notices. The full exact application import remains local and
reproducible from the pinned objects. Images, rejected research variants, later
PIXEL code and binary datasets are not vendored or published.
