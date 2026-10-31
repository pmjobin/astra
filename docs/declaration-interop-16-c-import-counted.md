# Counted byte and text inputs in C imports

Declaration-derived imports now accept nonretained `borrowed u8[]` inputs, bounded
out/inout byte views and native string inputs. Imports and exports use the same
frontend channel normalizer. This slice adds parameter transport; owned byte/text
results remain subsequent work.

A byte view carries its actual native pointer/i32-length pair. The C signature
has a pointer and an intrinsic length/capacity, or resolves an explicit `length`
or `capacity` to the declared i32 input parameter. The supplied count must equal
the native view length. Negative counts, mismatches and missing nonempty storage
raise checked infrastructure errors before provider invocation.

Every counted parameter gets independent bounded scratch storage. Input and
inout data are copied before the provider runs. A zero-length view gets a nonnull
one-byte allocation, allowing empty native views to satisfy mandatory C pointer
contracts. Allocation failure retires every earlier scratch allocation. Mutable
buffers publish only their initialized produced prefix; bytes beyond that prefix
remain unchanged. Explicit produced counts use an actual i32 out reference, or
`produced="result"` uses the native i32 result. The bridge validates every produced
count against its capacity before publishing any mutable bytes or scalar outputs.
Provider state changes are not rolled back.

Native strings use counted UTF-8 by default, preserving embedded NUL. An explicit
`encoding="utf8-nul"` checks for embedded NUL and creates a terminated snapshot;
the sentinel is excluded from its logical length. Named text lengths must agree
with the actual native byte length. C provider writes to input scratch never
change the original native string or byte view.

Successful factories retain a provisional opaque owner through produced-count
validation. Bad counts retire that owner before constructing the native exception.
A missing mandatory owner or provider failure also retires all temporary buffers;
failed owner outputs never escape. The independent provider observes retirement
before native error construction. Two allocation fault points exercise rollback
before provider entry, without changing native algorithm allocation behavior.

The independent/generated-header C matrix covers unique/shared O0/O1/O2, aliased
byte views, prefix publication, negative/excess counts, explicit capacities and
lengths, counted/NUL text, empty buffers, constructor failure and provisional owner
cleanup. Eight whole-executable Valgrind runs cover these paths. Six source negatives
and detached element/count/capacity/cleanup mutations qualify the same transport.
This is intermediate M16 evidence; the remaining import channels, callbacks,
COM/GObject personalities, opaque SDK challenge and final qualification stay active.
