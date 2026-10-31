> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# Surge 12 application witnesses

These are twelve distinct current-Astra witnesses, plus focused companions.
The source contains the application logic; startup serializes returned bytes
or the program uses the fixed checked UART operation. No launcher invents
application output.

| ID | Source | Selected route and oracle |
| --- | --- | --- |
| A97 | [Serial checksum](a97-serial-checksum.astra) | No-OS O0/O1/O2; checksum 042, changed Source loop 056; omitted DATA/BSS negatives |
| A98 | [Static initialization and lexical cleanup](a98-static-cleanup.astra) | No-OS O0/O1/O2; DATA/BSS probes, fixed stack array, `ABba:42` cleanup trace |
| A99 | [Volatile EDU and atomic ordering](a99-device-order.astra) | No-OS EDU device, UART, all selected atomic orders; missing device/signature/width/order controls |
| A100 | [Breakpoint return](a100-trap-return.astra) | No-OS real vector 3, source handler, preserved machine state, IRETQ; invalid handler and panic controls |
| A101 | [Region owners](a101-region-owners.astra), [guest](a101-region-guest.astra) | Host O0/O1/O2: 28 heterogeneous owner allocations; guest O0/O1/O2: 16 pairs, reverse destruction and checksum 288 |
| A102 | [Pool reuse](a102-pool-reuse.astra) | Host O0/O1/O2: exhausted nullable admission, 19 allocations/releases, stale generation and wrong-origin controls |
| A103 | [Heap/custom/static/caller identity](a103-policy-identity.astra) | Host O0/O1/O2: 128/256-byte alignment, exact destructor/release pairing, finite static slot; Shared payload companion |
| A104 | [Two bounded Bags](a104-bounded-bags.astra) | Host O0/O1/O2: Diagnostic/Utf8Message specializations, growth, take/replace and failed reserve without publication |
| A105 | [Nested record rollback](a105-record-rollback.astra) | Host O0/O1/O2: policy-owned child/parent, move/extraction, checked prefix rollback; owning-record storage companion |
| A106 | [Retained closure pool](a106-retained-pool.astra) | Host O0/O1/O2: two live environments/carriers, revoke/observe/dispatch and return cleanup after quiescence |
| A107 | [Natural C layout](a107-c-layout.astra) | Host O0/O1/O2 with independent GCC and Clang providers; size 40, alignment 8, offsets 0/8/16/20/24/32 |
| A108 | [Static numerical stream](a108-static-stream.astra) | No-OS O0/O1/O2, f32 input/f64 strict recurrence, C and exact-rational references; bounds panic |

The tests retain exact commands, exits, stdout/stderr and source/product/tool
hashes outside the repository. Host programs use public `astrac` compile/link
routes. The sanitizer recipe applies ASan to the actual emitted Astra bodies
and ASan/UBSan to the authored C runtime/oracles; system libraries and guest
memory are outside sanitizer coverage. Valgrind runs separately with default
suppressions disabled. Static-domain suballocations also need the compiler's
layout/ownership/bounds and runtime range/origin checks.

Use the coordinator's one existing out-of-source build:

```sh
astra_build=<historical-private-path>
CCACHE_DISABLE=1 PYTHONDONTWRITEBYTECODE=1 meson compile -C "$astra_build" -j4 astrac astra-allocation-proof
PYTHONDONTWRITEBYTECODE=1 python3 tests/freestanding-allocation-12/guest.py "$astra_build/astrac" "$astra_build/tests/freestanding-allocation-12/guest"
PYTHONDONTWRITEBYTECODE=1 python3 tests/freestanding-allocation-12/devices.py "$astra_build/astrac" "$astra_build/tests/freestanding-allocation-12/devices"
PYTHONDONTWRITEBYTECODE=1 python3 tests/freestanding-allocation-12/policies.py "$astra_build/astrac" "$astra_build/tests/freestanding-allocation-12/policies"
PYTHONDONTWRITEBYTECODE=1 python3 tests/freestanding-allocation-12/owners.py "$astra_build/astrac" "$astra_build/tests/freestanding-allocation-12/owners"
```

Other focused recipes are `refusals.py`, `modules.py`, `substrate.py`, and
`sanitizers.py`. The detached Vala proof mutates and restores Checked, Core,
CFG, SSA, native and LLVM allocation/POD authorities, dropping upstream graphs.
The [explicit selection](../../tests/freestanding-allocation-12/regression-selection.txt)
contains 156 registrations, rather than a complete registry campaign:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/freestanding-allocation-12/regressions.py "$astra_build" <historical-private-path>
```

The build recipe derives exact dependencies through read-only Meson
introspection, runs ordinary Ninja with four jobs, then ordinary Meson tests
with two processes and no implicit rebuild. It verifies the build's source
routing. No supervisor, global lock, downloads or repository build products
are involved. The emulator commands have a 15-second watchdog and require both
the exact serial trace and the expected debug-exit status.

See the [language contract](../../docs/language/allocation-policies.md) and
working ledger. Scope is
the approved emulator and finite owner/layout families. Dynamic short-lived
domains, arbitrary foreign allocators, threaded allocation/Shared, general
async frame policies, physical boards, SH-4 and self-hosting remain separate.
