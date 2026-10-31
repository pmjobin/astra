# Native signals and typed retained closures

M16 remains active. This slice adds the approved contextual declaration
`[Foreign] signal void updated(...);` and `emit updated(args);` statement.
Only the defining plain Shared Class emits through its exact `this` receiver.
The signal is synchronous, nonthrowing, void-returning and selected only for
GObject. Existing functions named `emit` retain their syntax and behavior.

An immutable signal binding carries the root policy and resolved member index
through Checked, Core, CFG, SSA, Native and CABI. Each verifier reconstructs the
stage's actual receiver, callable signature and member authority. Intrinsic
bodies permit only the exact copied-record acquisition prologue and return.
The LLVM operation reads the native root's verified foreign carrier cache and
calls a typed external emission bridge. It does not pass a native object as an
opaque foreign handle. Detached LLVM checks retain the exact cache address,
forwarded arguments, C99 bool extension and operation sequence. Native-only
personality selection emits no GObject signal reference.

Generated GTypes register typed void signals. Scalar values use their actual
GValue types. Counted text and bytes become independent GBytes snapshots, so
embedded NUL survives and a foreign handler may retain a reference. Scalar PODs
become copied boxed records with the existing independent gboolean32 layout.
The bridge holds the emitting native root and live wrapper through delivery.
Standard GObject connections retain their GClosure/userdata; self-disconnection
invalidates the connection immediately and defers its destruction until the
active callback unwinds. The constructing-thread profile remains explicit.

The authored witness has three different signals, including a native-created
object that has no pre-existing foreign wrapper. The generated projection helper
checks its constructing thread, acquires the exact cached or new carrier, and
holds the carrier and GObject view throughout delivery. The foreign handler can
retain the object after its native local owner retires. An independent C client checks
committed native state, typed values, self-disconnection, delayed userdata
destruction and releasing its final C/GObject owners inside the handler. It
retains text, byte and boxed-record copies after emission and native retirement.
The actual GIR scanner and typelib compiler feed an independent PyGObject client
which checks all three signals, retained copies and native retirement. Producers are
compiled at O0/O1/O2 into opaque native units, their source copies are removed,
and adapters are then generated from declarations and existing objects.

The companion JSON records exact compiler/source identities, registry outcomes,
memory scope and earlier failed attempts. Reproduce the host witness with:

```sh
python3 tests/declaration-interop-16/signals.py \
  /absolute/path/to/astrac /absolute/path/outside/checkout
```

The strict GIR importer requires explicit synchronous scope, GClosure ownership
and finalized destruction facts. It generates typed import declarations, an owned
signal-source Resource in VAPI, and an exact GClosure marshaller. The selected
scalar signal is exercised by a native Astra consumer against the scanned opaque
SDK at O0/O1/O2, with unsuppressed memory checks at O0 and O2. Twelve well-formed
GIR mutations reject before products are written. A nominal carrier bridge states
which imported GObject Class is required; it does not reinterpret the native
carrier as an SDK GObject pointer.

`retained_signal_register(handler, mode)`, `retained_signal_revoke(handler)` and
`retained_signal_observe(handler)` operate on nonthrowing void Closures with zero
to four copied scalar inputs (i32/u32/i64/u64/f32/f64/bool). Four is the existing
native Closure argument bound. The physical callback uses C99 bool; generated
GValue conversion maps GObject gboolean explicitly. The older retained and thread
operations retain their original i32(int) contracts. Selected non-GObject
personalities reject these signal operations before emission. Native retained
record, text and object handlers are currently rejected; this bound is distinct
from the exported C/GI signal domain above.

The optional `lib/astra/interop/gobject-signals-16.c` runtime checks the actual
signal's argument order, GTypes, void result and RUN_LAST convention. Connections
hold one source GObject reference and are confined to their constructing thread.
Revocation stops new delivery immediately; invalidation and finalization separately
record foreign retirement. An active callback cannot retire its environment, and
recursive delivery is refused. Observe acknowledges only stopped, inactive,
foreign-finalized connections. Native Closure destruction releases its environment
only after the provider's retirement acknowledgment. Stale connection tokens are
looked up without dereferencing freed connection storage. Tests cover source-owner
release, duplicate registration, wrong-thread calls, self-disconnection, recursive
emission and environment destruction after callback return.

Native/CABI inventories freeze the original operation, normalized callback and
retirement facts. Detached tests mutate bool width, action and plan presence;
physical tests also remove the exact bool extension from otherwise valid LLVM.
The nominal imported-carrier bridge has separate detached stage tests.

GClosure lifecycle follows the installed GLib contract for
[invalidation](https://docs.gtk.org/gobject/method.Closure.invalidate.html),
[finalization notification](https://docs.gtk.org/gobject/method.Closure.add_finalize_notifier.html)
and [typed marshalling](https://docs.gtk.org/gobject/callback.ClosureMarshal.html).
The compiler uses no arbitrary-signature libffi callback transport.

The companion retained-signal ledger distinguishes the failed memory attempt from
its corrected rerun. Required remaining channel composition, the frozen second-API
challenge and final G0–G9 qualification remain unfinished. This integration slice
does not claim complete M16 acceptance.
