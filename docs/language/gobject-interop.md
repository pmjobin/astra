# Optional GObject and selected GIR

The current [declaration-driven profile](declaration-driven-interop.md) supports
typed native Class export/import, multiple property types, methods/signals,
selected GIR/typelib generation and Astra round-trip imports. Its optional typed
retained signal provider supports zero through four copied scalar parameters.
The original Resource and `int(int)` retained profile below remains compatible.

Select the explicit typed Resource VAPI/generated declarations and C adapters
when using GObject. Ordinary native Class/Shared/Weak identity and allocation do
not become GObject identities. Native-only executables acquire no new GLib or
GObject dependency. The original boundary is single threaded, GNU x86-64 LP64,
32-bit gint and installed matching GObject 2.0 headers/libraries.

`lib/astra/interop/gobject.c` admits trusted C-created pointers after real GType
checks. Each successful full-result/ref/weak-upgrade token owns one foreign ref;
a borrowed argument owns none. Tokens are bounded, monotonically unique and
never recycled. Multiple tokens can denote one referent: qdata supplies its
stable adapter identity without retaining an identity cache. Consuming native
helpers or ordinary Resource cleanup release exactly the acquired ref. Native
Class values cannot be passed as these handles. Raw pointer validity is the
trusted C provider's duty; arbitrary application pointer casts are not admitted.

The adapter supports exact checked integer and counted UTF-8 property access.
Borrowed C strings become copied ForeignUtf8 snapshots, then native owned UTF-8
when explicitly copied. Foreign weak tokens do not keep the referent alive and
upgrades can expire. Wrong types, property rights/ranges, invalid UTF-8/NUL,
null/disposed/stale tokens and duplicate release fail before unsafe C access.

`gobject-signals.c` supplies the existing retained native Closure architecture
with a real GSignal provider. The finite signal profile is `int(int)` without
cross-thread dispatch or C unwinding. A SignalSource itself holds a weak object
reference. Successful registration holds the object and connects the native
closure. Revoke disconnects; observe requires both no active callback and the
GClosure destroy notification. Retirement releases provider state before native
capture cleanup. Same-registration reentry/stopped dispatch returns -2, stale
native token returns -3. Checked native errors must be caught inside the callback.
A native capture can retain foreign refs and native Shared/Weak owners explicitly.
General callback signatures, cross-boundary cycle collection and native GObject
export are outside the initial profile.

The strict [GIR importer](../../tools/gir/README.md) reads installed
GObject-2.0.gir plus a selected versioned fixture and emits typed VAPI, native
consuming helpers, C bridges and a contract receipt. It verifies exact selected
annotations/transfers/versions, C header signatures and real runtime property/
signal/GType admission. Use `--verify` before compiling the generated declarations;
plain `--vapi` alone does not authenticate the manifest. Unknown selected shapes
fail with XML source coordinates. The finite integer/string/object profile is
not a general introspection engine, GTK binding or dynamic reflection system.

See ADRs [0129](../decisions/0129-optional-gobject-foreign-lifetime.md) and
[0130](../decisions/0130-selected-gir-contracts.md), and runnable
[A57–A60/A63](../../examples/ecosystem-abi-8/README.md).
