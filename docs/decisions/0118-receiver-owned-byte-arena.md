# 0118 — Explicit receiver-owned byte arena with checked admission

Status: implemented selected library storage policy. Q13/Q25 remain open beyond
this byte-only scope. Select `memory/byte-arena.astra` and `base/errors.astra`.

`byte_arena(capacity, max_blocks)` returns a unique heap ByteArena. Negative
capacities are checked ArenaError results. Acquisition of the arena's five
backing arrays and Class still follows existing fatal native allocation policy;
this is not recoverable host OOM or a change to `new`.

`allocate(count, alignment)` selects contiguous storage inside the receiver's
fixed backing. Permitted alignment values are 1, 2, 4, 8 and 16, constraining byte
**offsets**. Byte storage has byte alignment; no typed pointer casting or typed
record allocation is authorized by these offsets. Zero-count allocations use a
metadata slot. Invalid extents/alignment, insufficient remaining capacity,
metadata exhaustion and ID exhaustion throw ArenaError before publishing any
state. Subtraction checks precede additions to avoid I32 wraparound.

The result is an integer ID relative to that exact receiver, not a globally
unique or unforgeable capability. IDs are monotonically increasing and never
reused by that receiver. `read/write/offset/length` validate a currently live ID;
byte indexing is checked against its extent. An ID used with a different arena
names that other arena's allocation namespace. IDs contain no address or loan.
Private arrays are never returned or passed across a retaining boundary, and no
API exports native storage. Thus a copied ID can outlive its receiver without
retaining a dangling pointer; it cannot access bytes without a live receiver.

`release_last(id)` requires the most recent allocation and restores its prior
cursor, including alignment padding. Reused storage is zeroed before admission;
old IDs stay invalid. Logical release does not call the host allocator. Reverse
Class field cleanup releases the physical backing arrays exactly once, including
checked exits and owner moves. The public `find` helper exposes only a scalar
metadata index because private methods are outside the current grammar; all
backing arrays remain private.

This is an ordinary Astra library built from existing checked methods, fields,
array bounds, owner moves and cleanup authorities. It adds no parallel compiler
ownership annotation or C allocator shim. It cannot allocate Class objects,
closures, Bag slots, async frames or kernel payloads. Borrowed receiver escape,
private storage exposure and post-move receiver access remain rejected by the
existing stages. Physical allocation accounting and public O0/O1/O2 admission,
failure/retry, stale-ID and scope cleanup witnesses are retained in the tests.
