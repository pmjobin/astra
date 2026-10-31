# Native Class exports carrying foreign handles

A native `declarations-v1` Class can expose borrowed and owned parameters/results
whose types are declared imported C Classes. It can retain an imported owner in a
normal owned Resource field. The common schema records the exact provider root
and lifetime; Core/CFG/SSA reconstruct that authority from their actual handle
declarations, while the native ABI verifies Resource cleanup independently.

The public C boundary uses the provider's opaque handle type. A borrowed input is
that pointer; a consuming input is a pointer to its owner slot; an owned result
uses a private pointer output before publication. The adapter transports the
provider pointer directly. It never reads a foreign object as a native Class or
allocates a second native ownership wrapper around the provider object.

Borrowed Shared providers acquire a temporary reference through their declared
`<prefix>_acquire` and release it through the exact provider cleanup. Acquisition
failure stops before native execution. Provider pins and native Class holds share
one reverse acquisition-order retirement list. This supports a Shared owner input
aliasing a borrowed view while the native method consumes that input. Unique
borrowed providers retain the foreign caller's call-scoped lifetime obligation;
an owned unique input aliasing another owned input or borrowed view rejects before
owner transfer. Native Class wrappers retain their existing context and lifetime
rules.

All owned slots must be distinct from other owned slots and result places.
Validation and staging precede consumption. A pre-call failure leaves the C
owner slot intact; entry into the actual native call clears it and transfers the
duty to ordinary Astra code. Native fields, parameter cleanup, checked exception
unwinding and owner returns use their existing Resource rules.

Owned foreign results retain their provider identity and allocation domain.
Invalid produced counts or conversion failures retire a provisional result
through its exact provider cleanup before error publication. Successful results
publish the existing owner duty after pins retire, without adding another reference
or wrapper. Nullable object results support the declared positive empty status.
Unique provider cleanup requires status zero, a consumed owner slot and a cleared
error record; violating that total-retirement obligation traps.

The independent/generated-header C witness calls actual Astra methods that store,
read, consume, relay and create imported objects. It covers all four native
Container/provider Item unique/shared combinations at O0/O1/O2; exact Shared pin
counts; refused acquisition; constructor partial failure; native root and wrapper
allocation failures; owned result rollback; nullable views/results; and safe alias
rejections. Whole-executable Valgrind uses no suppressions. Detached mutations
substitute equal-width nominal provider types, omit provider authority and change
LLVM pin/retirement behavior without executing corrupted code.

Imported properties and weak operations, callbacks, declaration-derived COM/GObject,
opaque SDK composition and the full acceptance matrix remain active M16 work.
