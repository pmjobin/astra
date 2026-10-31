> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# A64 — source-analyzer

Source: [`a64-source-analyzer.astra`](../a64-source-analyzer.astra).

Read a real source file, classify each byte through an independently compiled Analyzer8 module, and write exact letter/digit/tab/line counts to stdout and analysis.txt. Repeat after public formatting of both module sources, and read byte/category in GDB at a current source line.

Provider: analyzer-unit.astra, public -g, native module receipt, hosted file/text/argv providers. The foreign fixture namespace is AstraFixture 1.0 and
installed namespace GObject 2.0; the qualified provider version is recorded by
pkg-config in the receipt. The finite native profile is
`gnu-x86_64-lp64-scalar-pod-class/1`.

Run from the coordinator repository:

```sh
python3 tests/ecosystem-abi-8/apps-check.py \
  <historical-private-path> \
  <historical-private-path>
```

The maintained recipe records every exact provider command, producer
`astrac -g -O0/-O2 -c --module ... --emit-interface ... --native-export ...`,
separate consumer `astrac -g -O0/-O2 --entry-object ...`, subsequent Clang link,
expected/actual exits and stdout/files, source and product SHA-256, and
unsuppressed Valgrind observations under `apps-*/checks.json`. It runs all eight
apps; the `apps["64"]` entry selects this app's exact output and O0/O2 hashes.
See [the suite guide](../README.md) for the shared source/provider invocation.

Negative counterpart: Moving a borrowed analyzer node into an owned result is rejected; debug location corruption/restoration is separately exercised by debug-proof.vala. Each has a unique `A64-unsafe.astra` in the
receipt directory and must report a source diagnostic without native execution.

Qualified current evidence: committed command/hash receipt.
Compiler SHA-256: `b1f16a2562d09328093243d1b6bab875a6b9578fde16e3c92ef4192a7f0d2180`.
Actual GObject/GLib provider 2.88.4, LLVM/Clang 22.1.8; fixture AstraFixture 1.0.

Exact stdout and report-file bytes:

```text
letters=6
digits=3
tabs=1
lines=2
```

| Level | Executable SHA-256 | Consumer object SHA-256 | Reachable target bytes |
| --- | --- | --- | --- |
| O0 | `c237eb6d7af67fd2fd39c37c49890512e847eca268201aa9a83426b14df7dade` | `bd28eca1158ecaf3baed9f6ce03b79155931b545c1bad17b9369c17f808606be` | 0 |
| O2 | `ecb653bbdf700c521fbed28ff32137d3b52b704e4001ccf0fe4a99b618f8551c` | `0d00063eb71917ea97d1de4b4e3f10fe0dd284924fd64366721b3dbdc79fddd8` | 0 |
| O1 | `a980dddf8e07509d5d8e040fac1a74fcdd6c01f8e016d52ea7a2c31bedbdd011` | `6860b903d3e19ee486b46928985aab9ee3cbad49f487fd9124f962e89b0617cb` | 0 |

All runs report zero definite, indirect and possible losses and zero errors;
new Valgrind commands disable default suppressions, with zero suppressed errors.
Reachable GObject/GLib infrastructure is separate from released foreign/native
owner duties. Native-only apps have zero outstanding target allocations.

Exact qualified independent compilation/link commands (fresh directories are
created by the maintained recipe; these identify the recorded products):

```sh
<historical-private-path> -g -O0 -c --module Analyzer8 --emit-interface <historical-private-path> --native-export Analyzer8.classify <historical-private-path> -o <historical-private-path>
<historical-private-path> -g -O2 -c --module Analyzer8 --emit-interface <historical-private-path> --native-export Analyzer8.classify <historical-private-path> -o <historical-private-path>
<historical-private-path> -g -O0 --entry-object --import-module <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
/usr/bin/clang -no-pie <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
<historical-private-path> -g -O2 --entry-object --import-module <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
/usr/bin/clang -no-pie <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
```
