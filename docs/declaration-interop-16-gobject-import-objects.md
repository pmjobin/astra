# M16 real GObject object channels

Imported GObject members now accept borrowed or transferred typed foreign objects
and return owned/nullable typed objects. Each channel resolves to its own immutable
GType/header contract; forward references to another imported root are supported.
Every nominal carrier and helper is declared before member generation. Actual SDK
prototypes check the GLib pointer types independently of native opaque handles.

Borrowed inputs pin actual GObject references. Full inputs validate all channels,
reject conflicting ownership slots, then extract exactly one foreign reference and
clear the native owner slot before the SDK call. Carrier retirement still waits for
active borrows. A full result stays under scoped foreign unref until checked status,
all output validations and exact GType adoption succeed. Failed, wrong-type and
provisional results publish no native owner and retire once. Nullable success keeps
null. Imported views preserve the provider's actual object identity and reference
count, with separate carriers for distinct acquired references.

The context guard compares its immutable constructing-thread token before reading
mutable retirement/pin state. Existing wrong-thread and last-external-owner nested
use probes continue to run. Safe alias controls compare slot addresses before any
output clear or owner transfer; the independent C caller observes its owner intact.

The independent provider introduces a second real final GObject type with its own
native state and finalizer. Astra executes typed construction, reads, borrowed input,
duplicate, nullable lookup, owned result, consumed success and consumed checked
failure. Real foreign finalizer counters include provisional object failure and
wrong GType refusal. All native/adapter O0/O2 combinations plus O1 execute, with
two native clients under Valgrind. These methods are provider code, not generated
application algorithms.

POD import conversion, GIR round-trip, retained native signals, captured Closure
conversion, explicit target personalities, opaque foreign native units and the
remaining M16 gates are still required. No final M16 report is published here.
