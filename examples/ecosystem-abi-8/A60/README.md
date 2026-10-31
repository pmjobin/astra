> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# A60 — gir-client

Source: [`a60-gir-client.astra`](../a60-gir-client.astra).

Generate a typed client from installed GObject-2.0.gir plus AstraFixture-1.0.gir. Check runtime contract admission, invoke imported methods/property accessors and copy the imported UTF-8 snapshot. Write gir-report.txt with exactly the same bytes as stdout.

Provider: tools/gir/import.py, gir-profile.json, generated bindings.vapi/astra/c, installed GObject and real counter fixture. The foreign fixture namespace is AstraFixture 1.0 and
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
apps; the `apps["60"]` entry selects this app's exact output and O0/O2 hashes.
See [the suite guide](../README.md) for the shared source/provider invocation.

Negative counterpart: Using a GirUtf8 token as an AstraFixtureCounter is rejected; GIR corruptions and stale bridges have separate focused controls. Each has a unique `A60-unsafe.astra` in the
receipt directory and must report a source diagnostic without native execution.

Qualified current evidence: committed command/hash receipt.
Compiler SHA-256: `b1f16a2562d09328093243d1b6bab875a6b9578fde16e3c92ef4192a7f0d2180`.
Actual GObject/GLib provider 2.88.4, LLVM/Clang 22.1.8; fixture AstraFixture 1.0.

Exact stdout and report-file bytes:

```text
AstraFixture 1.0 / GObject 2.0
label=GIR café
value=23
```

| Level | Executable SHA-256 | Consumer object SHA-256 | Reachable target bytes |
| --- | --- | --- | --- |
| O0 | `e4302185cdc077572153b1406bf6049758e4828a895ffab9ceb947b902fb218c` | `ff8d204930615a4f59596911b367bf3661bc2a650da2b373dc35eb0ebb35d4b7` | 40,887 |
| O2 | `bf7f8058882dcf70b7ee0974a5429bd55fbd1ae51248d983d8ac3d0ba408e407` | `f73a5790a0dfcac5db8b42c4a8dbc553a05d48956bb4962f409d0851d4e3d42f` | 40,887 |

All runs report zero definite, indirect and possible losses and zero errors;
new Valgrind commands disable default suppressions, with zero suppressed errors.
Reachable GObject/GLib infrastructure is separate from released foreign/native
owner duties. Native-only apps have zero outstanding target allocations.

Exact qualified independent compilation/link commands (fresh directories are
created by the maintained recipe; these identify the recorded products):

```sh
<historical-private-path> -g -O0 --entry-object --vapi <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
/usr/bin/clang -no-pie <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -lgobject-2.0 -lglib-2.0 -o <historical-private-path>
<historical-private-path> -g -O2 --entry-object --vapi <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
/usr/bin/clang -no-pie <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -lgobject-2.0 -lglib-2.0 -o <historical-private-path>
```
