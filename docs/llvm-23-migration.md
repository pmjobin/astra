# LLVM 23 migration

The GNU/Linux x86-64 development profile now uses LLVM **23.1.4**. The migration
starts at `10eb2c60e46a5b36cde39aaf41b117bf1f5c1261`, following the truthful
CLASSSTORAGE-15 environment checkpoint. [ADR 0169](decisions/0169-llvm-23-migration.md)
records the dependency decision and its limits.

## Implementation

Meson and both C API shims require LLVM major 23. The standalone emitter's
recipe requires the exercised patch version and obtains the actual shared
library and link name from `llvm-config`; it verifies every imported symbol.
The selected library resolves to `/usr/lib64/libLLVM.so.23.1`, SHA-256
`3149b73c3118dee2d2829a210b422ca89a4aa0064b57e77936ede12bdcfe750d`.

The final production compiler has SHA-256
`e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b`.
Its 647 source/generated-C inputs and 15 runtime libraries are recorded in
`production-final-product.json`. The standalone emitter's seed compiler remains
at SHA-256 `3924060f7d03ef4cfc1d1991adf3e69e21795e6fd0a11623ef0318e9cf98c32b`
in the original build leaf. Its source snapshot differs only in the obsolete
LLVM 22 diagnostic label removed for the final production build; build paths
also affect debug bytes. Neither executable is overwritten to conceal this.
The rebuilt standalone emitter has SHA-256
`bb3e3ba75bc3e19c1cd7749e9ec24d44dff74200d06f81cf3f388c7496449f75`.
Its implementation is compiled at O0; its application outputs are independently
tested at O0 and O2. `environment-qualified.json` reports READY with no dependency
drift and all seven formatter tool identities matching. This is environment
readiness, not Class-storage acceptance.

Both backends distinguish unconditional opcode 70 and conditional opcode 71.
The independent physical checker still reconstructs conditions, edges, cleanup
guards and targets. A direct C API regression checks successor/operand order,
successor swapping and restoration, both branch forms and module verification.
The old branch-reversal mutation now selects the actual conditional opcode.

LLVM 23 exposed noncanonical inputs to `LLVMConstInt`: the old emitter supplied
64-bit sign-extended payloads for narrower types. The independent checker rejected
a wrapping literal; subsequent clean execution found the same precondition in
all-ones bitwise operands. A single producer boundary now limits every input
to its physical width. The numeric consumer separately reconstructs expected
destination-width bits. Observed LLVM values remain checked without masking.
There is no change to Astra wrapping, conversion or ownership policy.

The guarded formatter records current compiler, clang-format, Python, Meson and
Node identities. A lexical enum-indentation adapter preserves the existing TAB
and alignment columns under clang-format 23. It changes no tokens; adversarial
tests check columns, payloads and idempotence. The twelve affected existing enum
sources retain their original bytes. Only touched source is eligible for apply.

## Current evidence

Detailed commands, stdout/stderr, GNU time records, source identities and failed
attempts are retained under
`~/Workspace/codex/work/astra/runtime/llvm23-migration/`. Builds are isolated under
the corresponding `build/llvm23-migration/` directory. No host package or global
loader setting was changed.

The focused production checks include:

| Check | Observed result |
| --- | --- |
| LLVM backend | 88 subtests passed |
| Direct branch API and compiler/smoke linkage | Passed; exactly one selected LLVM library |
| Numeric and allocation contracts | 6 + 6 subtests passed |
| Context and lifetime contracts | 131 subtests passed |
| Owning enums | 11 subtests passed |
| CLI/module/golden/diagnostic selection | 65 tests passed; retained goldens unchanged |
| Object lifetime, ownership, generic owner slots/buffers, lazy runtime | Passed |
| Module/context layout-cache lifetime | O0/O2 controls and retained-cache negatives passed |
| C ABI floating-point exchange | 52 executions, 91 determinism checks, 39 machine audits passed |
| Public formatter | 405 checks over 74 sources passed |
| Formatter guards and representative language lanes | 14 guards and all selected lanes passed |
| Inherited standalone native corpus | 52 unchanged source identities per profile; O0/O2 passed |
| Original source statuses | 80 retained: 56 accepted, 12 invalid, 12 deferred |
| Core / CFG / SSA mutations | 22 / 26 / 30 categories rejected with restored controls |
| Generics mutations | 19 typed/binder/Flow + 6 physical categories rejected per profile |
| LLVM and native ABI mutations | 21 + 17 categories rejected per profile |
| Parser-valid source negatives | 15 rejected per profile |
| Explicit numerical conversions | 3 normal + 8 SIGILL edges per profile; guard mutation 38 rejected |

The clean standalone replay checks actual IR parsing/verification, ELF objects,
native and C0 runtime outcomes, C ABI observations and unsuppressed Valgrind
runs. Normal-program and emitter lifecycle memory observations remain separate
from fatal witnesses; fatal exits do not establish normal leak freedom. All
52 source-hash tuples match the original GENERICS-14 receipts at both profiles.
The O0 numeric profile reproduces two numerical exit-1 observations for native/C0
wide-u64-to-f32 execution under Valgrind; the new O2 instrumented runs exit zero.
Memory observations and numerical conformance remain separate. The O2 result
does not retire the historical numerical DEFERRED receipt.

The first lazy-runtime attempt lacked its explicit async provider object; its
log remains, and the retry passed after building that registered prerequisite.
Initial standalone emitter attempts and their real failures also remain.
A temporary process-local integer API adapter was used to diagnose the original
binary. Those development-only runs carry no qualification credit; the final
replay uses the rebuilt binary with no `LD_PRELOAD`.

## Measured build costs

GNU `time -v` receipts record these actual operations with `CCACHE_DISABLE=1`:

| Operation | Wall time | Maximum RSS, KiB |
| --- | --- | --- |
| Fresh final production compiler, six Ninja jobs | 114.30 s | 2,431,472 |
| Fresh final standalone emitter, implementation O0 | 776.89 s | 1,562,812 |
| Warm production compiler, no work required | 0.86 s | 245,668 |
| Warm emitter, exact source/tool/product reuse | 1.10 s | 199,120 |

These are command measurements, not a whole-session total or a speedup against
LLVM 22. RSS is GNU time's command/child high-water observation, not summed
concurrent memory. Failed attempts and earlier successful intermediates have
separate receipts and are not included in these selected-operation costs.
The emitter warm run retains six explicit exact-reuse receipts, including its
unchanged product hash. Production warm output says `ninja: no work to do`.

## Reproduction and continuity

Choose fresh external directories and disable compiler caches. The main setup
uses `-Dstage0_optimization=2 -Doptimization=0`; compiler implementation
optimization and generated application optimization are separate settings.
Build the selected dependencies before `meson test --no-rebuild`.

`tools/qualification/llvm23-native-replay.py` replays the inherited corpus with
an explicitly hashed independent compiler, fresh output leaves and the original
frozen selections. It invokes the existing LLVM, native ABI and generics runners,
asserts 24 + 15 + 13 distinct identities per profile, and compares source hashes
across O0/O2. Reference applications come from the production compiler; tested
application objects come from the Astra emitter. C companions remain ABI oracles.
The three selection directories beneath the external work area are:

```
runtime/nativeabi13-r1/frozen
runtime/nativeabi13-r1/selection-39
runtime/generics14/frozen-v3
```

For the retained measured binaries, use fresh output leaves:

```sh
migration_work="$HOME/Workspace/codex/work/astra"
python3 -B tools/qualification/llvm23-native-replay.py \
  --compiler "$migration_work/build/llvm23-migration/production-final/astrac" \
  --compiler-sha256 e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b \
  --component "$migration_work/build/llvm23-migration/native-component-v4/astra-llvm-O0" \
  --build "$migration_work/build/llvm23-migration/replay-again" \
  --runtime "$migration_work/runtime/llvm23-migration/replay-again" \
  --legacy "$migration_work/runtime/nativeabi13-r1/frozen" \
  --additional "$migration_work/runtime/nativeabi13-r1/selection-39" \
  --generics "$migration_work/runtime/generics14/frozen-v3"
```

The replay requires `--compiler-sha256`. Historical default hashes in
the original runners remain intact. The emitter's dependency sidecar binds its
source, compiler, tools and libraries; warm reuse requires exact equality.

Preservation checks retain all **451 protected files**, all **6,622 tracked donor
files**, donor HEAD/status, local configuration and hooks. The original **1,044
proof outputs** and raw evidence transport remain hash-verified historical
evidence. Historical ledger inputs that changed during this migration are
identified by their original Git blobs; current source is not called unchanged.
This migration does not rerun all 1,044 historical proof queries.

The CLASSSTORAGE-15 report stays byte-exact at SHA-256
`4251e394e062d00193b487deeef49e2000b9f55e1487bb7454c2e823464b74b2`.
It continues to describe its original checkpoint and missing LLVM 22 library.
This separate dependency migration does not repin that submission, qualify new
Class-storage programs, implement a public Class ABI, or claim whole-compiler
admission, Stage 1, a release or a full registry run. The historical
wide-u64-to-f32 Valgrind numerical exit 1 remains **DEFERRED** with its original
raw receipts. No history, donor content or prior build was replaced.
