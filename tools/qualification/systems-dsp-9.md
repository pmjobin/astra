> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# Systems and DSP Surge 9 qualification

Use the coordinator `<historical-private-path>` and the existing external
Meson directory `<historical-private-path>`. Confirm its
`meson-info/meson-info.json` names this source directory before rebuilding.
Keep `werror=true` and ordinary project hooks enabled.

```sh
CCACHE_DISABLE=1 meson setup --reconfigure <historical-private-path> .
CCACHE_DISABLE=1 meson compile -C <historical-private-path> -j 4 astrac astra-systems-dsp-proof astra-owned-state-proof astra-public-optimizer-contracts astra-native-module-proof astra-source-debug-proof astra-f64-semantic astra-vec-integer-oracle astra-vec-lane-oracle astra-dsp-oracle
PYTHONDONTWRITEBYTECODE=1 meson test -C <historical-private-path> --no-rebuild --num-processes 2 --print-errorlogs --logbase systems-dsp-9 systems-dsp-9-contracts systems-dsp-9-minimal systems-dsp-9-numeric systems-dsp-9-volatile systems-dsp-9-arena systems-dsp-9-portability
```

The tests run normal subprocesses and preserve commands, exits, stdout/stderr,
compiler/source/product hashes and failed earlier receipts in each external test
directory. They are qualification recipes, not process supervisors. The final
evidence freeze must recheck every receipt against current sources and compiler.

The minimal profile uses public `--runtime=none -c`, an identified assembly
entry, and explicit `ld.lld -static --no-undefined -e _start`. The observed
process is **Linux no-libc**. ELF dynamic entries, interpreter, undefined
symbols and relocations are inspected independently. The hosted counterpart
uses the ordinary C entry and libc. Startup is a boundary shim; Astra implements
the application algorithm.

The numeric oracle compiles independent C scalar reference operations with
contraction and fast math disabled. Each O0/O1/O2 build checks 2,048 f64 pairs
(8,192 resulting lanes across filter and division) and 2,048 integer pairs.
Non-NaN floating results, including signed zero and subnormals, compare by bits;
NaNs compare by classification. No NaN payload identity is promised.
The O2 assembly must contain packed double multiply/add/divide instructions.
The i64/u64 saturation operations may lower to equivalent baseline sequences;
PCM16 additionally exercises packed signed saturation.

The volatile fixture allocates actual anonymous host mappings through explicit
linker wrappers around the native buffer allocator. A parent traces its own
child with x86 data watchpoints at four mapped addresses and verifies all nine
accesses, values and order. O0/O1/O2 LLVM and machine disassembly are retained.
The trace is an actual host-memory witness. Physical devices, interrupts,
atomics, DMA ordering and cache coherency require separate qualification.

Typed arena storage is a published finite encoded-record profile. ByteArena
checks complete u32/u64 little-endian fields before accessing bytes. PacketArena
admits two `{u32 tag; u32 payload;}` records and two exact unique Resource owners
in compiler-managed fields. Initial backing and receiver allocation use the
host allocator; placement and resource admission allocate no packet heap block.
The supplied Resource provider opens real file descriptors in a static table.
There are no exported arena pointers or loans, native-layout casts, generic
allocator substitution, or recoverable underlying host-OOM claims.

A71 uses independent native producer/interface/consumer objects, including
mixed O0/O2 combinations. A separate public `aarch64-none-elf` object-only
profile admits 32-bit integer kernels and is checked with ELF and LLVM tools.
No AArch64 executor, SH-4 backend or no-OS execution is inferred from an object.

Historical LAZY Q4 remains HELD/INCOMPLETE, and previous milestone scopes keep
their prior statuses. The final selected historical regression list and actual
results belong in the current evidence document.

Run the complete maintained 40-name selection and compact the qualified
receipts with the ordinary tools below:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import json, os, subprocess
from pathlib import Path
names = json.loads(Path('tests/systems-dsp-9/integration-tests.json').read_text())
raise SystemExit(subprocess.call([
	'meson', 'test', '-C', '<historical-private-path>',
	'--no-rebuild', '--num-processes', '4', '--print-errorlogs',
	'--logbase', 'systems-dsp-9-qualified', *names],
	env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')))
PY
PYTHONDONTWRITEBYTECODE=1 python3 tests/systems-dsp-9/evidence.py <historical-private-path> <historical-private-path> docs/systems-dsp-9-evidence.json
```

The compactor requires the current task's native intake plus successful build
and integration command receipts in the external runtime directory. It checks
the compiler and each focused product/source identity, the selected Meson
statuses, strict build routing/options and original protected user files.
