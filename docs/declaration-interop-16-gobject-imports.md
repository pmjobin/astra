# M16 typed GObject import prerequisites

GObjectImport declarations-v1 Classes normalize to the shared typed import model
with GOBJECT channels and actual foreign reference authority. The immutable root
records the C GType name, independent GIR namespace/version, checked physical
symbol prefix, explicit portable SDK header and constructing-thread context.
Namespace and C type spelling are separate facts, as with Gio and GFile.

The checked-out projection calls independently declared GLib functions: factories
return one owned nonfloating object with GError**, while methods return gboolean
and typed result/reference outputs with GError**. All scalar widths and gboolean32
convert to/from the native C99 helper ABI. Scalar input references are copied at
the GLib boundary; output/inout references use staged locals and publish on success.
The supplied SDK prototypes are compiled independently from the Native/C helpers.

Native checked errors map the declared negative code and exact
astra-foreign-domain-N quark to the native error factory. Contradictory success/error,
false without a GError, null factory results, wrong GType and floating-reference
results refuse without publishing an owner. Provisional objects and GErrors retire
once. No native exception unwinds through GLib.

An imported carrier holds one actual GObject reference. Borrow pins acquire actual
foreign references, not a second payload reference count. Releasing the owner's
reference marks its carrier retired; active noescape calls may finish and reenter,
and the carrier frees after the final active pin. Native C exports borrowing an
imported GObject use this same pin protocol. A wrong constructing thread refuses
before invoking foreign methods. The bridge does not sink floating references or
change the provider's object identity.

The independent provider executes i64/u32/f32/u64 operations, gboolean conversion,
a double property, checked results and staged scalar references. C clients exercise
provisional factory failure, null-without-error, wrong GType, floating reference,
wrong-thread borrowing and last external owner release during a nested import.
Every native/adapter O0/O2 combination plus O1 executes, with two Valgrind clients.
The detached SDK mutation keeps logical signatures and pointer widths equal while
changing the admitted SDK origin; each independent stage must reject it.

This is an intermediate checked-out import slice. Other GObject payload/record/
object/callback conversions, GIR round-trip, retained signals, explicit target
personalities and later M16 gates remain open. Legacy GObjectImport functions and
the older GIR profile are preserved; this does not claim general GTK imports.
