# Declaration-derived C byte channels

This is an intermediate part of ADR 0166. Full M16 qualification is pending.
The explicit `declarations-v1` C Class profile now accepts selected native
`borrowed u8[]` parameters. A parameter without further transport annotations
has an input `const uint8_t *` and a signed `int32_t` length in the C signature.

`[ForeignChannel(parameter="input", length="count")]` reuses the actual copied
`int count` parameter instead of adding a second length. Mutable byte channels
select `direction="out"` or `"inout"` and `produced="result"`; their native
method returns an `int` produced count. Their intrinsic C count is capacity.
Explicit capacity can similarly refer to an actual copied input parameter.
The schema also models separate produced output parameters; lowering of those
parameters remains pending.

Selected native `owned u8[]` results transfer a data/count pair through mandatory
output slots. The SDK's `<prefix>_bytes_release` consumes those slots, clears
them, and retires exactly that allocation domain. An empty successful owned
result has a nonnull one-byte allocation and length zero. Native empty storage
is retired during this conversion. A snapshot remains usable after its native
root retires. Missing output pointers refuse before invoking native code.

All counts must be nonnegative. A null byte pointer is accepted only for an
explicitly nullable channel whose count is zero. Mandatory result pointers,
receiver context and all byte pointer/count pairs validate before the native
method runs. The wrapper snapshots input and inout bytes, and zero-initializes
output scratch storage. Input and output may overlap: native reads use the
snapshot. Multiple overlapping mutable channels commit in declaration order.
The foreign caller remains responsible for valid storage throughout the call.

After native execution, every mutable channel requires a produced count in
`[0, capacity]`. Only those initialized bytes publish on success. Failure leaves
caller byte storage unchanged and clears the scalar produced result. This
guarantee concerns foreign outputs; it does not roll back native object state.
Each nonempty byte channel costs one temporary allocation. Admission or scratch
allocation failure does not invoke the native method. All scratch storage is
retired on success and failure.

Each active shared call pins its native root through conversion and cleanup.
Unique owners retain explicit ownership: an active-call depth prevents a callback
from consuming its active receiver, without introducing reference counting.
Nested calls remain subject to the native language's own borrowing restrictions.
Before native destruction starts, the wrapper's root link becomes null. Calls
from synchronous destruction observers refuse before accessing native state.
This does not yet qualify the later typed callback or signal channels.

The current caller-owned error record is `{ int32_t domain; int32_t code; }`.
Adapter failures use domain zero and the exact signed status as code: pointer
`0x80004003`, invalid count `0x80070057`, allocation `0x8007000e`, wrong thread
`0x8001010e`, invalid produced count `0x8000ffff`, active unique consumption
`0x80010001`. Ordinary success is zero. This record allocates no memory. Mapping
declared native errors and nonfailure statuses remains pending.

The byte integration recipe uses independent C prototypes and generated SDK
headers for unique/shared O0/O1/O2. It exercises non-ASCII byte values, nullable
empty storage, aliased input/output, inout mutation, unchanged input snapshots,
negative counts, short output, partial native output, first/second scratch
allocation failure, wrong context, unique consumption refusal and shared
last-release reentry. Eight unsuppressed Valgrind runs cover the complete
executables. Detached-stage tests substitute wider-element slices with identical
PTR/I32 physical widths and require rejection before execution.
