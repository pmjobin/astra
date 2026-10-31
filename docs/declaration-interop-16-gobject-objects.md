# M16 native Class object projections and properties

Declared GObject channels for native Shared Classes use the exact declared GType
and native root inventory. Runtime registration uses a final GType and dispatch
checks exact instance type. An audit found that G_DECLARE_FINAL_TYPE alone did not
set the runtime flag; independent C/GI assertions now check the actual registered
types, and G_DEFINE_FINAL_TYPE enforces the declared restriction. Input checks acquire a native owner through the wrapper's
checked context gate; no object pointer is reinterpreted as a native payload.
Temporary owners pin borrowed arguments through the complete native call. Full
input transfer consumes the incoming foreign reference and passes an acquired
native owner into the ordinary native consuming boundary. Full results acquire the
cached live GObject view and retire the temporary native C owner. Nullable results
preserve null and their GIR metadata. Views retain one authoritative native lifetime.

Independent C/GI callers exercise forward-declared distinct object types, clone
identity, consuming relay, nullable lookup, wrong GType, disposed input and release
of the last external argument reference during a nested native operation. The call
continues through its native owner pin, and destruction occurs after unwind.

Text properties use exact counted UTF-8 GBytes. Object properties use an exact
GParamSpec object type and transfer-full GValue publication. A declarations-v1
selected direct owning getter uses the ordinary native owned-result cleanup and
storage-origin solver. The native child snapshot is real Astra code. Ordinary
unselected owned-property restrictions and existing lazy-cache semantics remain.
Core/CFG/SSA validate the getter's resolved foreign member and exact ownership;
Native/CABI retain the same object origin. The retained detached mutant replaces
an admitted child GObject root with a valid C-only root and independently checks
that each downstream consumer rejects it. Another mutation substitutes the owning
getter's parent result origin.

The C and PyGObject clients observe all five property types, exact embedded NUL,
shared child identity and a returned child surviving parent destruction. Final
retirement is observed after the surviving foreign reference is dropped. All
native/bridge O0/O2 combinations plus O1 and two native Valgrind clients execute.
The strict GIR recipe checks typed object results, owned/null transfer and exact
GParamSpec discovery; GUI or broader GTK support is not claimed.

Real imported foreign GObjects/GIR round-trip, retained signals, target-selected
personalities, opaque foreign native units, the frozen SDK challenge and later
G0-G9 remain required. This slice does not close G4 or publish a final report.
