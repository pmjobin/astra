# 0129 — Optional typed GObject references and signal sources

Status: implemented and qualified in the bounded Surge 8 profile.

`lib/astra/interop/gobject.c` is an explicitly compiled/linked foreign adapter.
It uses existing nominal foreign Resource handles and cleanup contracts. A token
is an adapter reference duty, never a native Class, Shared value, GType or raw
GObject address. Only trusted C adapters admit an actual transfer-full GObject
with its expected runtime GType. Admission checks inheritance; failure consumes
the incoming reference. Ref creates one new duty, unref consumes one, and native
borrows cannot escape their owner under existing Resource verification.

The single-threaded LP64 profile has 256 live adapter handles and monotonically
assigned, never-reused token identities. Every operation checks registry membership
and handle kind before using an object. Repeated borrowed views keep the same
token; separate strong references preserve referent identity. A per-object qdata
identity has no owning backreference or cache. Foreign weak handles use GWeakRef;
they retain no strong object and upgrades acquire an explicit new reference.
These identities are private to this linked adapter context, not global native
type or wrapper interning. Arbitrary external raw-pointer admission is not a
source operation.

Properties check the exact runtime property name, GType, access flags and integer
range. Counted UTF-8 input is copied to a terminated C string; embedded NUL and
invalid UTF-8 reject. String reads make an owned foreign snapshot, independent of
later object mutation; byte/length operations do not expose borrowed C strings.
The selected Counter fixture additionally refuses operations after disposal.
Arbitrary GObject disposal semantics and cross-thread calls remain unqualified.

`gobject-signals.c` explicitly selects the retained registrar's optional version-1
event-provider extension. Mode zero keeps its original ordinary protocol.
A weak SignalSource records an actual checked `int(int)` GSignal. Successful
registration acquires a strong GObject reference and connects the existing exact
C-convention native closure thunk through `g_signal_connect_data`. It never
reinterprets a function pointer, native Class or closure environment.

Revoke disconnects; observe requires both zero native callback activity and the
GClosure destroy notification. Retirement then releases the connection and its
object reference before native capture destruction. A closing guard rejects
recursive retirement during object finalization. Native owner movement/cleanup
retains the existing closure attachment authority and checked errors must be
caught in a nonthrowing native adapter before returning to C.

Synchronous nested GObject emission is safe: the same active registration returns
the existing reentry refusal `-2`; it does not invoke its native closure again.
Revoked direct dispatch returns `-2`, retired/stale dispatch `-3`, and disconnected
GObject emission has no handler result. There is no background dispatch or
cross-thread, dynamic-unload, arbitrary signal-signature or native-export policy.

Initial public O0/O1/O2 and independent C controls live under
`tests/ecosystem-abi-8`. They cover identity/ref/weak/property failures, bounded
capacity, stale tokens, real reentrant emission, disconnect inside a handler,
quiescence, exit orders and checked-error/weak native captures. Unsuppressed
Valgrind covers whole target programs; ASan/UBSan cover the C provider/fixtures.
Native-only debug controls independently inspect ELF dependencies for absence
of GLib/GObject. None of these checks imply completion of the other Surge 8 gates.
