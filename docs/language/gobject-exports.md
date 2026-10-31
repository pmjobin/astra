# Selected native GObject exports

`[GObjectExport]` creates a real final GType over one native intrusive Shared
root. It composes with the [opaque C bridge](c-class-exports.md); the separate
GObject never interprets the native Class layout. The selected profile is
hosted Linux x64, one read/write integer property named `value`, and synchronous
`changed(int)` plus `notify::value` signals for GObject-facing changes.

```astra
[GObjectExport(type="Astra14Counter", namespace="Astra14", version="1.0")]
[CExport(name="astra14_counter", property="value")]
[Shared]
class Counter {
	private int data;
	init(int value) { this.data = value; }
	property int value {
		get { return this.data; }
		set(int value) { this.data = value; }
	}
}
```

Type and namespace are explicit ASCII GType identifiers, the type extends its
namespace, the C prefix is the snake-case type name, and the initial typelib
version is `1.0`. The selected native root restrictions are those of CExport.
COMExport composition, unsupported targets, other property shapes and mismatched
names are refused. Ordinary native Classes acquire no GObject dependency.

The admitted `[Shared,Monitor]` root uses the same foreign headers and adapter.
Link its explicit `monitors-13.c` provider as well. Native synchronous property
operations retain their Monitor discipline; foreign data affinity still requires
the constructing thread. This grants neither cross-thread data access nor a
foreign Singleton factory/shutdown contract.

`--emit-gobject-header` and `--emit-gobject-source` emit the verified SDK header
and C11 implementation on stdout after native/C ABI/LLVM verification. Compile
the Astra object, generated C and `foreign-14.c` with explicit GObject SDK flags.
Use the real `g-ir-scanner` and `g-ir-compiler` on that library/header to generate
GIR and typelib files. The complete portable recipe, including independent C
and installed Python GI consumers, is
`tests/interop-tooling-14/gobject-export/build.py`. No GIR XML is fabricated.

For prefix `astra14_counter`, `new(int, GError **)` returns one non-floating
GObject owner. `as_gobject(native_handle, GError **)` returns an acquired GObject
view of a backed C owner; it is excluded from introspection. Each GObject lifetime
owns exactly one native strong reference. Additional `g_object_ref()` or
non-floating `g_object_ref_sink()` calls change only GObject's own count. C owners
and native weak owners keep their existing explicit lifetime semantics.

The native root caches a separate holder with a `GWeakRef`, avoiding an owning
cycle. Adaptation acquires the same live GObject view atomically. Disposal blocks
new adaptation until that view finalizes; if a C owner survives finalization, a
new view can subsequently retain the same native payload. A retiring weak view
is refused with a retryable disposed/busy error. GLib clears GWeakRefs before
disposal and defines their atomic acquisition/invalidation behavior; see its
[GWeakRef contract](https://docs.gtk.org/gobject/struct.WeakRef.html).

Direct `g_object_new(GType, ...)` construction also creates a real native root,
initially with `init(0)` before property application. The explicit `new(value)`
factory runs `init(value)`. Adapting an existing C root creates no temporary
native payload. Class initialization finishes before a construction-local seed
is published, and instance initialization consumes that seed immediately.

Get/set/adaptation check the native constructing thread. `try_get_value` clears
out on failure and `try_set_value` refuses before changing data or signaling.
GError codes are 1 for invalid arguments, 2 for wrong thread, 3 for disposed or
retiring views, and 4 for recoverable native/control/cache allocation failure.
Property accessors quietly return zero or refuse a write on error; explicit
try methods expose GError to C and introspection callers. Standard GLib object
allocation retains GLib's fatal out-of-memory convention. No native reactive
graph is implied: native/C changes are visible on the next read; GObject-facing
changes emit the selected signals when the value actually changes.
Every assignment reaches the native setter, including an input equal to the
previous value. Notifications use a subsequent native getter result so clamping
and other setter behavior remain visible accurately. An unchanged committed
value emits no signal. O0/O2 native setter witnesses cover both cases.

Every data call temporarily retains the GObject and uses its recursive gate.
Synchronous signal callbacks can release the caller's last owner or dispose the
view. Disposal disconnects callbacks and blocks further data access; finalization
retires the native owner only after active calls return. Lifetime ref/unref may
run on foreign threads with backed owners. The weak cache uses atomic publication
state so a foreign last-unref cannot race an unsafe raw wrapper resurrection.
Last native strong release destroys the payload once, then clears/frees the weak
holder and C control. Native allocation metadata remains until its last weak
owner retires.

The immutable policy carries GType/namespace/version, native ownership, weak
cache, floating convention and affinity through every stage and C ABI adapter.
Mutation proofs reject missing ownership, unsafe caches, changed floating
semantics, missing affinity, substituted GTypes and Windows target relabeling,
then restore valid lowering. Header and source emission leave original files
unchanged.

Real O0/O1/O2 libraries passed independent installed C clients, scanner-generated
GIR/typelib and installed Python GI clients. Checks include C/GObject/native
identity and data coherence, ref/sink behavior, weak expiry, view recreation,
direct GType construction, callback owner drop, disposal quiescence, thread
refusal, 128 weak-cache retirement races per run, root/control/cache allocation
failures and exact native destruction. Unsuppressed Valgrind checks pass at
O0/O2. The pure native Shared control binary has no GObject/GLib/LLVM/libffi
dependencies. These component results do not replace final Surge 14 campaign
qualification.
