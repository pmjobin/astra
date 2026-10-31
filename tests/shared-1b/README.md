# Shared/Weak qualification

Use the real public compiler and external output directories:

```sh
python3 tests/shared-1b/qualify.py /path/to/build/astrac /path/to/runtime/shared
python3 tests/shared-1b/apps.py /path/to/build/astrac /path/to/runtime/shared-apps
meson test -C /path/to/build shared-1b-contracts --print-errorlogs
```

`qualify.py` checks two exact payload Class specializations, stable identity,
strong clone/move/return, multiple weak observers, live and expired upgrades,
owned fields, checked unwind, weak backedges and 10,000 legal interleavings.
It builds O0/O1/O2 executables and a public `-c` library object consumed by an
independently compiled C client. Fourteen source refusals require specific
diagnostics. Native allocator observers distinguish payload and control-block
frees and verify exactly-once destructors. A separate unique parent/child control
proves two ordinary object allocations, two frees and zero shared blocks; its
emitted LLVM must contain no shared block/count operations. Unsuppressed
Valgrind runs use the normal allocator rather than allocation interposition.

`apps.py` qualifies A25–A27 with exact event traces in all three optimization
modes and unsuppressed Valgrind. Each runner records complete commands, exits,
stdout/stderr, source hashes, compiler hash and product hashes; it writes a PASS
result only after every actual observation matches. Initial failure receipts
are retained separately during the campaign.

`contracts.vala` exercises independently owned contracts at their actual stages:

| Stage | Responsibility and mutation proof |
| --- | --- |
| Checked → Core | Acquisition requires the original exact unique heap source. A forged lexical allocation origin is refused. |
| Core | Exact payload, type, storage and cleanup authority; wrong native payload destructor identity is refused. Core does not duplicate the path liveness solver. |
| CFG | Exact acquisition/consumer pairing and independent moved/released ownership flow, including branch and checked cleanup; a wrong payload cleanup identity is refused. |
| SSA | Exact typed transitions, source-owner READ events, single direct payload-loan consumer and its live interval; missing READ, wrong payload and changed action are refused. |
| Native ABI | Detached payload/flavor/lifecycle plans must match source calls. Forged payload authority and omitted lifecycle plans are refused. |
| LLVM | Exact field, count, guarded branch, call and complete emitted sequence correspondence. Mutations omit increment publication/control-block free/count guards, duplicate a payload destructor, or publish a false expired upgrade. |

The mutated IR is verified and restored; it is never executed. These tests
qualify the documented finite single-threaded profile, with no cycle collector,
general shared container elements, async migration or retained C callback claim.
