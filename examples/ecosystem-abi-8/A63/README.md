> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# A63 — plugin-pipeline

Source: [`a63-plugin-pipeline.astra`](../a63-plugin-pipeline.astra).

Connect an actual GObject event source to a native capture that owns an independent-library Ticket, foreign reference and native shared log. Each event calls the imported native transform and borrowed Ticket method. Quiescence precedes capture destruction; both native and foreign duties finish once.

Provider: Independent Work8 object/interface, actual GObject signal provider, native Closure/Shared and owned UTF-8 builder. The foreign fixture namespace is AstraFixture 1.0 and
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
apps; the `apps["63"]` entry selects this app's exact output and O0/O2 hashes.
See [the suite guide](../README.md) for the shared source/provider invocation.

Negative counterpart: Dispatch through a released closure is rejected by ownership checking. Each has a unique `A63-unsafe.astra` in the
receipt directory and must report a source diagnostic without native execution.

Qualified current evidence: committed command/hash receipt.
Compiler SHA-256: `b1f16a2562d09328093243d1b6bab875a6b9578fde16e3c92ef4192a7f0d2180`.
Actual GObject/GLib provider 2.88.4, LLVM/Clang 22.1.8; fixture AstraFixture 1.0.

Exact stdout:

```text
pipeline closed
mapped=46
mapped=50
ticket released=1
foreign finalized=1
```

| Level | Executable SHA-256 | Consumer object SHA-256 | Reachable target bytes |
| --- | --- | --- | --- |
| O0 | `a4e3a347ac7e0e2dd5880d04fdeae9dac40b21e0c53d0e2123323f9be194e361` | `271c44396c48b82e5ac45d96637df73d98be4373e4b1ddc8a55c0cbe5c2975c6` | 40,951 |
| O2 | `6ccfa4ce787850c5d060de92fd8a4aacf36f5e76377ca7ecbfe9d1bea403b7ad` | `bbcb75824672edfb9dddebf378f3947ef6d804a9657ae618d419d951dbda57ab` | 40,951 |

All runs report zero definite, indirect and possible losses and zero errors;
new Valgrind commands disable default suppressions, with zero suppressed errors.
Reachable GObject/GLib infrastructure is separate from released foreign/native
owner duties. Native-only apps have zero outstanding target allocations.
Clang ASan/UBSan additionally execute this app with instrumented C providers
and allocator interception; Astra LLVM instructions and installed GLib are not
sanitizer-instrumented.

Exact qualified independent compilation/link commands (fresh directories are
created by the maintained recipe; these identify the recorded products):

```sh
<historical-private-path> -g -O0 -c --module Work8 --emit-interface <historical-private-path> --native-export Work8.Sample --native-export Work8.combine --native-export Work8.scaled_mean --native-export Work8.double_value --native-export Work8.Ticket --native-export Work8.create_ticket --native-export Work8.ticket_code <historical-private-path> -o <historical-private-path>
<historical-private-path> -g -O2 -c --module Work8 --emit-interface <historical-private-path> --native-export Work8.Sample --native-export Work8.combine --native-export Work8.scaled_mean --native-export Work8.double_value --native-export Work8.Ticket --native-export Work8.create_ticket --native-export Work8.ticket_code <historical-private-path> -o <historical-private-path>
<historical-private-path> -g -O0 --entry-object --vapi <historical-private-path> --vapi <historical-private-path> --import-module <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
/usr/bin/clang -no-pie <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -lgobject-2.0 -lglib-2.0 -o <historical-private-path>
<historical-private-path> -g -O2 --entry-object --vapi <historical-private-path> --vapi <historical-private-path> --import-module <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
/usr/bin/clang -no-pie <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -lgobject-2.0 -lglib-2.0 -o <historical-private-path>
/usr/bin/clang -fsanitize=address -fno-sanitize-recover=all -no-pie <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -lgobject-2.0 -lglib-2.0 -o <historical-private-path>
/usr/bin/clang -fsanitize=undefined -fno-sanitize-recover=all -no-pie <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -lgobject-2.0 -lglib-2.0 -o <historical-private-path>
```
