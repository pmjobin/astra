# M16 native Class projections through typed COM views

A native Class channel can now satisfy a declared COM interface channel when the
Class is plain Shared and exports that exact interface, including a declared base
view. The foreign channel retains its IID and COM ownership; the native channel
retains its nominal Class, heap origin and C owner contract. Direction, nullability,
noescape, count, callback and scalar facts must still match. Unique Classes do not
acquire a COM lifetime through this conversion.

The semantic pass completes all root policies before resolving these relationships.
Core, CFG, SSA, Native and C ABI validators reconstruct their own root/interface
inventories. They require the exact protocol declaration and the selected native
root's supported view. Matching pointer widths or C signatures do not suffice.
Two selected interfaces cannot map one C++ override name to different native
members; this collision rejects before SDK emission.

The generated wrapper has a compiler-pinned private IUnknown-derived native-root
interface. Its IID and accessor identity derive from the exact normalized root
contract. A native Class input first queries this brand and acquires the opaque
native C owner through the typed accessor. It never infers a Class from a COM
pointer value or a guessed object layout. The acquired native owner protects the
Class during conversion and dispatch. An independent foreign implementation of
the public interface lacks this native brand and returns E_NOINTERFACE.

A native owned result is converted through its existing COM wrapper and the
required public interface query, then the temporary C owner is released. Borrowed
inputs use a temporary acquired native owner. Consuming inputs transfer that owner
through the native C slot and release the original COM owner at dispatch. Failed
preflight releases conversion temporaries. Output/owner aliases and repeated owner
slots reject before output clearing or transfer. Nullable native owner results
retain the declared positive null status, observed as S_FALSE by the COM client.
All views continue to share one authoritative native lifetime.

The independent Windows client exercises a native Class through borrowed input,
cloned owned result, consuming relay, nullable result and several public interface
views. It also supplies an independently implemented public interface with no
native brand and checks refusal before native field access. All four native/bridge
O0/O2 combinations plus O1 execute in win11. The detached proof replaces a root's
supported interface while keeping its native C API identical, and checks the
consumer's reconstructed projection authority after upstream stages are released.

This is intermediate integration. GObject/GIR and retained signals, target
personalities, opaque native-unit foreign metadata, frozen distinct API SDK
qualification and all final G0–G9 evidence remain required.
