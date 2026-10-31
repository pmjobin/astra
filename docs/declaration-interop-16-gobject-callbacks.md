# M16 GObject synchronous callbacks and scalar references

Declared GObject methods now carry synchronous scalar/void callbacks with exact
userdata and nullable call-only scope. Public callbacks use gboolean transport;
the mechanical thunk converts to/from the internal C99 bool callback without
changing application behavior. Generated callback type identifiers follow GI's
type namespace rules, and GIR records the actual closure parameter and call scope.

Scalar output and in/out references use staged native locals. Inputs are captured
before output initialization, and reference changes publish only after success.
Input-only scalar references use a copied scalar in the public GObject ABI and a
private noescape reference for the native call. This is a distinct physical plan:
GI's scalar input marshalling must not be described by a C pointer prototype.
The normalized GObject identity records inref=value and outref=pointer.

The independent C and PyGObject clients execute BOOL32 callbacks, nullable callbacks,
void/double callbacks, i64 input references, double in/out references and u32 output
references. Native input mutation stays private; checked failure leaves in/out data
unchanged and clears scalar outputs. Every native/adapter O0/O2 pair plus O1 executes;
two native clients run under Valgrind. The recipe checks emitted GIR callback scope,
closure index, exact input C type and output/inout directions before GI execution.

The first scanner attempt rejected callback identifiers containing an underscore
before their digest. Naming was corrected with warnings still fatal. A later valid
GI caller exposed an input-reference ABI mismatch: GIR marshalled an integer while
the C prototype expected its address. The retained backtrace locates that call;
callbacks themselves completed successfully. The corrected copied-input projection
passes the same GI call and its checked-error control. The original diagnostics
remain in the task runtime and are not counted as passes.

This covers synchronous borrowed callbacks only. Retained signal closures, captured
native Closure conversion, the remaining GObject payload/object channels, GIR
round-trip imports and later M16 gates remain required.
