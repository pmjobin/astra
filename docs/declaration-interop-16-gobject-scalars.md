# M16 declaration-derived GObject scalar prerequisites

The explicit declarations-v1 GObject policy now derives its constructors, methods
and properties from the selected native Class members. The native root remains a
plain Shared Class with one authoritative native lifetime. The adapter retains a
native C owner, a weak live-wrapper cache and a constructing-thread data contract.
Native methods execute compiled Astra code; the generated C handles transport,
GObject lifetime and GError publication.

The declaration has independent C and GObject prefixes and an exact type/namespace
identity. New namespace versions accept nonempty numeric major.minor values, such
as 2.3. The historical profile still requires 1.0. Scalar transport uses gint/guint,
gint64/guint64, gfloat/gdouble and explicit 32-bit gboolean. Internal C99 bool
arguments/results are converted rather than pointer-reinterpreted. Generated SDK
source asserts these physical widths.

Actual getter/setter declarations determine GParamSpec and GValue types, read/write
flags and stable property slots. IDs do not use source-member ordinals as array
indices. A setter observes the native value before and after successful dispatch,
and notifies only from committed state. Native checked failures preserve their
negative code and explicit domain in GError; no native exception crosses C.
Wrong-thread checked calls clear their result and report failure before data access.

Selected members can restrict their public surface with personalities="c" or
personalities="gobject". GObject-only operations retain a mechanical private C
bridge; its declarations require ASTRA_FOREIGN16_INTERNAL and are absent from the
ordinary public C header view. Native products do not gain a GObject link dependency
from adapter text generation. Target personality selection itself is still pending.

Each live GObject owns one native root reference; the native cache keeps a GWeakRef
to the wrapper. Repeated adaptations return the live wrapper. Disposal prevents new
data calls; finalization clears cache state before releasing the native owner.
Finalization requires the constructing thread. Direct default GObject construction
has no native backing; typed checked calls reject it safely. Explicit generated
factories create the required native instance with its declared parameters.

The independent C client uses separately authored prototypes and inspects actual
GParamSpec types, native arithmetic, checked errors, wrong-thread behavior, C/view
state sharing, stable wrapper identity and exact native destruction counts. Five
native/adapter optimization combinations cover every O0/O2 pair plus O1. Two native
clients run under Valgrind with no errors or lost blocks. The installed scanner and
compiler produce GIR/typelibs for version 2.3. Independent PyGObject clients execute
all five variants, including selected surfaces, notifications and checked exceptions.

The schema and detached suites check version/profile separation, copied contracts,
weak native-owner facts, property names and duplicate GType inventories after
upstream stages are released. The LLVM mutation keeps a valid module while removing
the internal C bool extension. Source controls also reject malformed versions,
unsupported ownership, symbol collisions and unqualified targets. These use the
[GObject property contract](https://docs.gtk.org/gobject/class.ParamSpec.html),
[explicit notification rules](https://docs.gtk.org/gobject/signal.Object.notify.html)
and [GI annotations](https://gi.readthedocs.io/en/latest/annotations/giannotations.html).

This is intermediate scalar integration. Counted text/bytes, copied boxed PODs,
native/foreign object channels, scalar references, typed callbacks, retained signals,
GIR round-trip imports, target personalities, opaque native units, the frozen SDK API
challenge and final G0–G9 qualification remain required. Emission rejects channels
whose GObject conversion plan is not yet implemented. This is not G4 completion.
