> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# A61 — module-statistics

Source: [`a61-module-statistics.astra`](../a61-module-statistics.astra).

Compile Work8 separately, then import its scalar/POD native signatures from unit.asti. Combine two samples and format their total/count/scaled mean into owned native output.

Provider: work-unit.astra exports Work8.Sample/combine/scaled_mean plus the shared bounded work profile; app-support.c. The foreign fixture namespace is AstraFixture 1.0 and
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
apps; the `apps["61"]` entry selects this app's exact output and O0/O2 hashes.
See [the suite guide](../README.md) for the shared source/provider invocation.

Negative counterpart: Passing int in place of the exported nominal POD is rejected before lowering. Each has a unique `A61-unsafe.astra` in the
receipt directory and must report a source diagnostic without native execution.

Qualified current evidence: committed command/hash receipt.
Compiler SHA-256: `b1f16a2562d09328093243d1b6bab875a6b9578fde16e3c92ef4192a7f0d2180`.
Actual GObject/GLib provider 2.88.4, LLVM/Clang 22.1.8; fixture AstraFixture 1.0.

Exact stdout:

```text
samples=2
total=42
mean-hundredths=2100
```

| Level | Executable SHA-256 | Consumer object SHA-256 | Reachable target bytes |
| --- | --- | --- | --- |
| O0 | `27e1f4a928b6e41cbb22e873e7fe75dcbdecc62ad4d4a54c1a67734fe15adb38` | `8ae75557bd6f9414c8dd198d3c26dd2d384df090fe30303fef0f9064997338f3` | 0 |
| O2 | `584518f87c44202b4160e439512f9816cf6a66e92e70f9c0b1846de323a752b6` | `2de5572f757ffa036c094898daa27f6c14461c945aad28a118b7b9202b537d5a` | 0 |

All runs report zero definite, indirect and possible losses and zero errors;
new Valgrind commands disable default suppressions, with zero suppressed errors.
Reachable GObject/GLib infrastructure is separate from released foreign/native
owner duties. Native-only apps have zero outstanding target allocations.

Exact qualified independent compilation/link commands (fresh directories are
created by the maintained recipe; these identify the recorded products):

```sh
<historical-private-path> -g -O0 -c --module Work8 --emit-interface <historical-private-path> --native-export Work8.Sample --native-export Work8.combine --native-export Work8.scaled_mean --native-export Work8.double_value --native-export Work8.Ticket --native-export Work8.create_ticket --native-export Work8.ticket_code <historical-private-path> -o <historical-private-path>
<historical-private-path> -g -O2 -c --module Work8 --emit-interface <historical-private-path> --native-export Work8.Sample --native-export Work8.combine --native-export Work8.scaled_mean --native-export Work8.double_value --native-export Work8.Ticket --native-export Work8.create_ticket --native-export Work8.ticket_code <historical-private-path> -o <historical-private-path>
<historical-private-path> -g -O0 --entry-object --import-module <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
/usr/bin/clang -no-pie <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
<historical-private-path> -g -O2 --entry-object --import-module <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
/usr/bin/clang -no-pie <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
```
