> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# A59 — signal-recorder

Source: [`a59-signal-recorder.astra`](../a59-signal-recorder.astra).

Record two actual changed GSignal events in native owned UTF-8 storage shared with the closure. The first attempts a nested emit and records the defined -2 refusal. Disconnect, observe quiescence, destroy the capture, and prove no late delivery.

Provider: Counter/SignalSource, native Closure/Shared; gobject.c, retained.c, gobject-signals.c and counter.c. The foreign fixture namespace is AstraFixture 1.0 and
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
apps; the `apps["59"]` entry selects this app's exact output and O0/O2 hashes.
See [the suite guide](../README.md) for the shared source/provider invocation.

Negative counterpart: Registering an f64 callback in the int(int) retained profile is rejected. Each has a unique `A59-unsafe.astra` in the
receipt directory and must report a source diagnostic without native execution.

Qualified current evidence: committed command/hash receipt.
Compiler SHA-256: `b1f16a2562d09328093243d1b6bab875a6b9578fde16e3c92ef4192a7f0d2180`.
Actual GObject/GLib provider 2.88.4, LLVM/Clang 22.1.8; fixture AstraFixture 1.0.

Exact stdout:

```text
disconnected
recorder closed
event=3
nested=-2
event=5
foreign finalized=1
```

| Level | Executable SHA-256 | Consumer object SHA-256 | Reachable target bytes |
| --- | --- | --- | --- |
| O0 | `d54b7a49b5ddf170fc6e750b396470c295fc4b900b4f8c6416151a1a27f6137e` | `7e3c6d0721c9ff273815b040307b95504e5e29b090cc33f14d9f068a5f09bbce` | 40,951 |
| O2 | `13b75f7448c97395f74d07b6920b9206d024902763d36832fe9c0ee2f26e48ef` | `fe4e45ec4eaf3526aadd2b7a1245282460a4d81b4efcda323be3f8a0586a9e74` | 40,951 |
| O1 | `da7fd16d17285370af585a20d5c2075db7024f8b0f0f12ac2256338105ef6548` | `5cb4faf0f8a7f471a5c10495e62eb48fc8273d8f520b51a3f947fe59ec8d7425` | 40,951 |

All runs report zero definite, indirect and possible losses and zero errors;
new Valgrind commands disable default suppressions, with zero suppressed errors.
Reachable GObject/GLib infrastructure is separate from released foreign/native
owner duties. Native-only apps have zero outstanding target allocations.

Exact qualified independent compilation/link commands (fresh directories are
created by the maintained recipe; these identify the recorded products):

```sh
<historical-private-path> -g -O0 --entry-object --vapi <historical-private-path> --vapi <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
/usr/bin/clang -no-pie <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -lgobject-2.0 -lglib-2.0 -o <historical-private-path>
<historical-private-path> -g -O2 --entry-object --vapi <historical-private-path> --vapi <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
/usr/bin/clang -no-pie <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -lgobject-2.0 -lglib-2.0 -o <historical-private-path>
```
