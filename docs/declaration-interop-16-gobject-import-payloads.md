# M16 imported GObject callbacks and counted payloads

Typed call-only callback imports now derive GLib thunks and exact userdata from the
normalized callback signature. Copied scalar parameters and scalar/void results
convert between gboolean32 and the native C99 helper transport. Nullable callbacks
pass a null code/data pair. Actual native Astra function bodies run synchronously;
a direct imported-C function name is not substituted for a native callback body.

Counted byte/UTF-8 inputs become call-scoped GBytes views over the already staged
native transport. NUL inputs use the explicit terminated text projection. Owned
GBytes and GLib string results remain under scoped GLib cleanup while the bridge
validates their count and creates an independent native-helper allocation. The exact
bytes/text release function frees that allocation. NUL results retain their terminal
byte, including empty strings; counted text retains embedded NUL and the native
UTF-8 checker rejects malformed data before publication.

Bounded output arrays use pointer and capacity slots at the GLib call. Intrinsic
capacities and separately declared named capacities have distinct argument positions.
The SDK may not replace caller storage or alter its capacity under this caller-owned
profile. The bridge checks those facts before publishing any owned result or scalar
references. Native staging also verifies produced counts and commits only initialized
bytes after success. Provisional factory objects remain scoped until all validation
has finished and transfer once into a carrier.

The independent provider tests BOOL32/nullable/void callbacks, GBytes snapshots,
provisional owned-byte failures, absent owners, invalid UTF-8, embedded NUL, owned
terminated/empty strings, intrinsic and named output capacities, foreign checked
failure, excess produced count, replaced output pointer and changed capacity.
Custom GBytes release callbacks count actual foreign allocation retirement. Strict
C compilation caught a duplicated named-capacity argument independently of the
emitter. The first generated indentation warning and that prototype failure remain
in runtime receipts and are not counted as passes.

Every native/adapter O0/O2 pair plus O1 executes and two native clients run under
Valgrind. Record and object import conversions, GIR round-trip, retained signals,
target personalities, opaque foreign units and later M16 gates remain open.
