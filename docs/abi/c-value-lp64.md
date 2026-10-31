# C POD values on GNU x86-64 SysV LP64

`record_abi="value-lp64"` is the explicit import/export contract defined by
[ADR 0116](../decisions/0116-c-by-value-pod-records.md). It preserves source
record identity while adapting native copied leaves to the independently
planned C ABI. The C declaration is a real `struct R function(struct R)`.

The qualification on 2026-10-17 executed these layouts in both directions:

| Record | Source fields | Size / alignment | Field offsets | C transport |
| --- | --- | --- | --- | --- |
| `RecordInts` | `i64, i64` | 16 / 8 | 0, 8 | INTEGER, INTEGER |
| `RecordFloats` | `f64, f64` | 16 / 8 | 0, 8 | SSE, SSE |
| `RecordMixed` | `i64, f64` | 16 / 8 | 0, 8 | INTEGER, SSE |
| `RecordStack` | `i64, f64, i64` | 24 / 8 | 0, 8, 16 | MEMORY: stack `byval`, result `sret` |
| `RecordPadded` | `f32, f64` | 16 / 8 | 0, 8 | SSE float, SSE double; padding ignored |

GCC 16.2.1 and Clang 22.1.8 independently compile the C providers and clients.
The public Astra driver emits O0/O1/O2 executables and separate `-c` objects.
All four provider/client compiler pairings link each Astra object. Each client
checks 1,280 actual by-value parameter/result roundtrips and an independently
computed hash. An all-C reference executes the same equations. C static
assertions and layout programs check size, alignment and offsets; retained C
assembly and Clang IR expose the physical classification. No padding bytes are
compared and no struct pointer substitutes for a source struct value.

A36, `examples/interop-async-5/record-diagnostics.astra`, reports hash `1426`.
The independent C client reports hash `6562511336861592192`. The qualification
records 118 command checks, 51 hashed products and 24 clean unsuppressed
Valgrind executions. Its runtime receipt is
`runtime/native-current/record-debug/results.json` under the external project
work area, together with exact command/output/source/compiler hashes. These
counts describe this focused run, not the full compiler registry.

`record-loop.astra` performs one million MEMORY aggregate calls, including
nested result forwarding. Every optimization/provider variant completes with a
256 KiB process stack limit. All byval/sret staging allocations are reserved
once in the physical function entry and reused; the LLVM artifact verifier
checks allocation type, single extent, alignment and entry placement. This also
keeps async dispatch turns independent of source-loop allocation growth.

The five record proof cases exercise malformed Core arguments, CFG/SSA record
groups and fields, CABI layout/source identity, and LLVM byval/sret attributes
and native forwarding. Nine source controls reject omitted metadata, small
integer/coalesced layouts, nesting, pointer fields, excessive size/parameters,
borrowed values, unannotated exports and nominal mismatches. Run the registered
`interop-async-5-record` and `interop-async-5-record-proof` Meson tests against the
external build directory.

The finite profile also admits singleton `f32` and 64-bit unsigned/pointer-sized
numeric field spellings; the table identifies the independently exercised
layout families. Broader fields, shapes, register exhaustion, platforms and
foreign ownership contracts remain outside this qualification.
