> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# Surge 12 qualification

Use the coordinator's existing external build and native permissions. Before
reuse, verify that Meson introspection routes it to this checkout. Preserve
peer work, user files, hooks, refs and stash. No dependency download or system
configuration change is part of these recipes.

```sh
astra_build=<historical-private-path>
astra_stage=<historical-private-path>
CCACHE_DISABLE=1 PYTHONDONTWRITEBYTECODE=1 meson setup --reconfigure "$astra_build" <historical-private-path> -Dwerror=true -Dlinux_async=false
PYTHONDONTWRITEBYTECODE=1 python3 tests/freestanding-allocation-12/regressions.py "$astra_build" "$astra_stage/regressions"
```

The explicit 156-registration selection includes all 137 Surge 11 selections,
the impacted object allocation/field/container families, ten new suites and
default-allocation LLVM/execution controls. The recipe derives the required
targets using ordinary Meson introspection, builds with Ninja `-j4`, then runs
Meson with two test processes and `--no-rebuild`. It checks build routing and
compiler identity. This is a risk selection, not the full historical registry.

The two TAP suites independently corrupt and restore device and allocation/POD
authority after upstream graphs are dropped. The eight Python component
recipes in `tests/freestanding-allocation-12/` take `compiler output` arguments.
They retain complete commands, stdout/stderr, expected exits and hashed files
in that external output directory. Recipes archive previous attempts.

Guest recipes invoke QEMU 10.2.2, `pc-i440fx-10.2`, TCG `qemu64`, 64 MiB and
the explicit SeaBIOS image. Each boot has a 15-second watchdog and checks both
serial bytes and the debug-exit status. Startup, linker, memory primitives,
allocator substrate and application sources are repository inputs. Every guest
ELF must have an empty undefined-symbol inventory. Host sanitizer products
instrument actual emitted Astra with ASan and authored C with ASan/UBSan;
static suballocations retain their explicit range/ownership checks. Separate
Valgrind commands disable default suppressions. Guest memory is qualified by
layout, counters, guards and executed negative paths, rather than host tools.

After the compiler and component products are stable, run the unchanged host
continuity controls and the measured size/cost inventory:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/interop-async-5/timer-check.py "$astra_build/astrac" "$astra_build/tests/freestanding-allocation-12/timer-continuity"
PYTHONDONTWRITEBYTECODE=1 python3 tests/numerical-optimization-11/packet-checked.py "$astra_build/astrac" "$astra_build/tests/freestanding-allocation-12/packet-checked"
PYTHONDONTWRITEBYTECODE=1 python3 tests/freestanding-allocation-12/metrics.py "$astra_build" "$astra_stage/metrics"
```

The timer uses the installed private liburing 2.15 prefix, with no changes to
the default `linux_async=false` build. The checked-throwing A93 supplement must
retain its 425 caught failures and 48,850 heap allocation calls with optimizer
placement enabled and disabled. ROM/RAM/stack figures come from actual linked
ELF sections and flat images. Callgrind counts the full hosted A101 process at
each public O level, including the independent C observer and process startup;
it does not establish an allocator speedup or guest cycle count.

After committing the exact qualified source, the read-only collector validates
the current receipts, compiler and product hashes, complete selection,
target/tool identities, and original conservation inventory. It writes a
compact committed JSON suitable for the standard report's per-file cap:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/qualification/freestanding-allocation-12-evidence.py --build "$astra_build" --stage "$astra_stage" --output docs/freestanding-allocation-12-evidence.json
```

Large output is represented by exact byte length/SHA-256 and excerpts; short
output remains exact. Full raw receipts stay at their recorded external paths.
The final documentation commit descends from the source checkpoint named in
that evidence. No held historical milestone, physical board, other target,
general threading, SH-4 or self-hosting qualification follows from this run.
