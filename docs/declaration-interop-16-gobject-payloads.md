# M16 GObject payloads and boxed records

Declared counted byte and UTF-8 inputs project to borrowed GBytes. Exact lengths
are checked against i32 representability and any named native length; counted
UTF-8 keeps embedded NUL and rejects malformed sequences through the native
boundary. Owned results copy into an independent GBytes or GLib string and retire
the original allocation through the exact native release symbol. Explicit NUL
conversion rejects embedded NUL instead of truncating it.

Bounded mutable byte arrays project to an in/out pointer slot and a capacity slot.
The storage remains caller-owned. Capacity is unchanged; native staging publishes
only validated initialized bytes after success. GI requires both slots when
marshalling in/out arrays; even a GIR input-only length annotation did not make
PyGObject pass the length by value. The retained GDB argument trace records that
failure. Named explicit capacities and intrinsic capacities follow the same plan.

Scalar PODs use a separate Linux GLib boxed layout with gboolean32 fields, natural
alignment and checked offsets. Generated copy/free/new operations register the
boxed GType. Inputs and outputs convert each field to/from the native C99 layout;
producer algorithms stay in the linked native object. The GObject source includes
the mechanical C record forwarders required by that object. A closed generic POD
uses the same path. Scanner/typelib consumers see actual record fields and ownership.

Independent C and PyGObject clients exercise exact counts, owned snapshots, embedded
NUL, invalid UTF-8, explicit/intrinsic output capacities, rollback, nullable input,
mixed scalar records, closed generic records and independent boxed copies. All
native/adapter O0/O2 pairs plus O1 execute, and two C clients run under Valgrind.
The recipe checks exact GIR array direction, capacity slots and full result transfer.
The first raw in/out buffer ABI and the subsequent capacity mismatch remain failed
attempts in the runtime; neither is counted as qualification.

The mapping follows the [GI annotation contracts](https://gi.readthedocs.io/en/latest/annotations/giannotations.html).
Object handles, retained signals, GIR imports, target personalities, foreign native
units, the frozen SDK challenge and the remaining M16 gates are still pending.
