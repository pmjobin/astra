> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# Surge 11 qualification

Use the existing coordinator-routed source/build directory and normal native
permissions. Revalidate `meson-info/meson-info.json` before another worktree uses
that build. Keep source in Git and products/logs in the external build/runtime.

The explicit [137-name selection](../../tests/numerical-optimization-11/regression-selection.txt)
contains 119 inherited and 18 numerical registrations. Its 54 dependencies were
rebuilt with fatal warnings enabled. It is not the full 9,302-entry registry.
Standalone CFG/SSA/native models build without predecessor builders; native
vector plans and primitive permissions have no semantic-model dependency.

```sh
CCACHE_DISABLE=1 PYTHONDONTWRITEBYTECODE=1 meson setup --reconfigure <historical-private-path> <historical-private-path> -Dwerror=true -Dlinux_async=false
```

Build the selected dependencies from ordinary Meson introspection, then invoke
Ninja and Meson directly:

```python
from pathlib import Path
import json
import subprocess

root = Path('<historical-private-path>')
build = Path('<historical-private-path>')
names = (root/'tests/numerical-optimization-11/regression-selection.txt').read_text().splitlines()
tests = {row['name']:row for row in json.loads((build/'meson-info/intro-tests.json').read_text())}
targets = {row['id']:row for row in json.loads((build/'meson-info/intro-targets.json').read_text())}
ids = {target for name in names for target in tests[name]['depends']}
paths = sorted({str(Path(path).relative_to(build)) for target in ids for path in targets[target]['filename']})
subprocess.run(['ninja','-C',str(build),'-j4',*paths],check=True)
subprocess.run(['meson','test','-C',str(build),'--no-rebuild','--num-processes','2',
	'--print-errorlogs','--logbase','surge-11-final',*names],check=True)
```

Application recipes freeze source/compiler identities, compare independent C
results, retain output bytes and run Valgrind. A92 has 7,435 observations per O
level plus an executed FMA audit using explicit `+avx,+fma`, separate from the
generic public target. Native/scalar memory paths have the same range/alignment
checks. Nineteen new detached TAP tests cover policy, memory, effects, placement,
lazy, exact-call and Shared authority after upstream graphs are released.

Run supplementary recipes after builds/tests finish, avoiding measurement
contention. Each accepts compiler and external output paths. Below, `compiler`
means the routed `build/astrac`, `output` a distinct external directory per
recipe, and `components` the external `build/tests/numerical-optimization-11`.

| Recipe | Arguments after script | Evidence |
| --- | --- | --- |
| `ablation.py` | compiler output [historical-compiler] | Four same-source O2 pairs; compile/size/IR/machine/runtime/counter evidence |
| `simd-cost.py` | compiler output | Independent vector/scalar-source PCM; exact bytes and actual vectorization |
| `sanitizers.py` | compiler output | ASan on emitted Astra LLVM, ASan/UBSan on C oracles |
| `memory-audit.py` | compiler output components | Twelve current O2 programs, default suppressions disabled, zero errors/suppressed contexts/heap bytes |
| `packet-checked.py` | compiler output | 425 caught failures independently counted in C; retained allocation and exact teardown |

Scripts are in `tests/numerical-optimization-11/`; invoke them with
`PYTHONDONTWRITEBYTECODE=1 python3`. The historical compiler is the preserved
pinned-source build, SHA-256
`4fcf207efdeb0e25f9eeaac3afad4fbabc43c05bcb98ffe7c6522cf9cc17f48f`.
Omit that argument when unavailable; do not invent a baseline from current code.
A91 uses new syntax and has no substituted-source historical comparison.

Ablations change only `ASTRA_TEST_OPTIMIZATIONS=off|on`, keeping O2, source, target
and C oracle fixed. Each has three compile samples, a first observed run, two
warmups, eleven fixed-seed interleaved run pairs and seven hardware-counter
pairs. Host frequency, affinity and kernel settings are unchanged. A89/A91/A95
are machine-identical neutral results; A93/A94 improve allocation/instruction
costs. No isolated-pass or universal speedup is inferred. LLVM also vectorizes
the scalar PCM source; it is not a scalar-ISA promise.

Sanitizer IR uses the exact public target triple/data layout. Native arithmetic
and system libraries are not UBSan-instrumented. The allocation-count interposer
is disabled only in sanitizer products. The separate Valgrind audit explicitly
disables default suppressions and checks complete heap release.

With the existing private liburing 2.15 provider, run unchanged real timer/payload
continuity without installing anything or changing `linux_async=false`:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/interop-async-5/timer-check.py <historical-private-path> <historical-private-path>
```

The read-only evidence verifier checks this campaign's saved build/test receipts,
source/product identities, protected files, hooks, refs and stash. It runs no
engineering; runtime filenames identify this campaign. Its compact JSON files
are committed and included by the standard publisher:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/numerical-optimization-11/campaign-evidence.py <historical-private-path> <historical-private-path> docs/numerical-optimization-11-evidence.json
```

The earlier foundation verifier/JSON retains its original historical scope.
See final validation and the
Bible/question map.
