> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# A62 — module-ownership

Source: [`a62-module-ownership.astra`](../a62-module-ownership.astra).

Acquire a heap-owned native Ticket from an independent producer. Borrow it through the native module channel, move it into a consumer completion scope, and observe exactly one producer destructor and matching code.

Provider: work-unit.astra, Work8.Ticket/create_ticket/ticket_code; app-support.c observes lifetime without allocating or releasing native objects. The foreign fixture namespace is AstraFixture 1.0 and
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
apps; the `apps["62"]` entry selects this app's exact output and O0/O2 hashes.
See [the suite guide](../README.md) for the shared source/provider invocation.

Negative counterpart: Borrow-to-owner escape and altered heap-result interface identity are rejected; restoration passes. Each has a unique `A62-unsafe.astra` in the
receipt directory and must report a source diagnostic without native execution.

Qualified current evidence: committed command/hash receipt.
Compiler SHA-256: `b1f16a2562d09328093243d1b6bab875a6b9578fde16e3c92ef4192a7f0d2180`.
Actual GObject/GLib provider 2.88.4, LLVM/Clang 22.1.8; fixture AstraFixture 1.0.

Exact stdout:

```text
completed=73
destructors=1
allocator=native
```

| Level | Executable SHA-256 | Consumer object SHA-256 | Reachable target bytes |
| --- | --- | --- | --- |
| O0 | `4969235fa30775f339d2da7d5512e9076a2e986c9e2efa249b991126c24767df` | `0293d0b0e58a4046e351321d6c345bdc208dfe52db9c54b1812e9ef44ef5d180` | 0 |
| O2 | `24dab694b7d28e712d6e2fb8c560835e9dfe66ae3c744eaf563d3cd888a7a463` | `14118b008dc7448c283f69bf8f633a5e3c35a3cab6b9909e4992c4d5f467be19` | 0 |

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
<historical-private-path> -g -O0 --entry-object --import-module <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
/usr/bin/clang -no-pie <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
<historical-private-path> -g -O2 --entry-object --import-module <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
/usr/bin/clang -no-pie <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
/usr/bin/clang -fsanitize=address -fno-sanitize-recover=all -no-pie <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
/usr/bin/clang -fsanitize=undefined -fno-sanitize-recover=all -no-pie <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> <historical-private-path> -o <historical-private-path>
```
