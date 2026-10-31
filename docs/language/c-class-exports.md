# Opaque native Class exports

For typed constructors, methods, properties, unique/shared owners, checked errors,
counted data, records and opaque native units, select `profile="declarations-v1"`
and follow the [declaration-driven guide](declaration-driven-interop.md).
The bounded property profile below remains compatible.

The legacy selected `[CExport]` Class profile creates a separate stable C wrapper over
one native intrusive `[Shared]` root. The native reference counts remain the
lifetime authority. A C wrapper address is an interface identity, and the opaque
`root_identity` token is a comparison value with no authority to inspect layout.
Ordinary native Classes acquire no foreign cache or runtime dependency.

```astra
[CExport(name="counter", property="value")]
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

Use `astrac --emit-class-header counter.astra` to obtain the verified C11/C++
header on stdout, and `astrac -O2 -c counter.astra -o counter.o` for the native
object. Compile `share/astra/interop/foreign-14.c` from the installed prefix with
the external C toolchain and link it explicitly. This provider supplies a
nonrecycled constructing-thread identity; it owns no object reference counts.
Linux `[Shared,Monitor]` composition additionally requires the existing explicit
`monitors-13.c` provider. Attribute order does not change the contract.

The initial profile requires an independent concrete nonpolymorphic heap root,
nonthrowing `init(int)` and a selected nonthrowing read/write `int` property.
Payload fields are copied integers. Inheritance, generic export declarations,
custom allocation, lazy caches and native-module serialization are refused.
Other ordinary native methods and native-only construction remain available.

The generated protocol has explicit `create`, `acquire`, `release`, `get`, `set`,
`root_identity`, `weak`, `weak_clone`, `weak_upgrade` and `weak_release` functions.
Create and successful weak upgrade return one owning strong reference; acquire
adds one and release consumes one. Weak wrappers each own one native weak count.
Last strong release destroys the payload once, synchronously retires a selected
foreign personality and frees its C wrapper. Native storage persists until the
last weak reference expires. A failed weak upgrade never accesses a retired C
wrapper. A caller must hold the appropriate strong or weak owner during a call.

Data calls return 32-bit HRESULT-compatible statuses. Get clears a valid out
slot before failure, rejects null out with `E_POINTER` (`0x80004003`), and rejects
a foreign thread with `RPC_E_WRONG_THREAD` (`0x8001010e`). Set uses the same
thread check. Strong/weak lifetime operations are atomic and can run on a foreign
thread with a backed owner. Data affinity is independent of Monitor locking.
Count results are bounded to 32 bits with an explicit overflow trap.

The compiler-private personality hooks are emitted behind
`ASTRA_FOREIGN14_INTERNAL`. They attach one borrowed personality and synchronous
retirement callback to the native root; they are not a second ownership scheme.
The callback runs after payload teardown and before native weak-sentinel
retirement. It must return normally. No callback may access the dead payload.

The immutable foreign policy is copied through checked semantics, Core, CFG,
SSA and Native ABI. A typed C ABI adapter binds exact native constructor and
property ordinals, public symbols, signatures and ownership roles. Each stage
checks its admitted identity; physical lowering checks the corresponding LLVM
calls, fields, guards, calling convention and retirement operations. Header
emission occurs only after the physical verifier succeeds. Inspection commands
show the selected policy and ABI roles.

`tests/interop-tooling-14/c-class.py` independently compiles C clients and runs
O0/O1/O2 lifetimes, live/expired weak references, thread refusal, native-only
roots and partial-allocation failure cleanup. It also checks Monitor composition,
attribute order, inspection and source refusals. Unsuppressed Valgrind checks
normal and failed construction at O0/O2. The separate contract proof mutates
stage policies, native accessor identities, C ABI plans and LLVM calls/guards,
requires refusal, restores them and verifies upstream graphs are released.
This C bridge alone does not establish COM or GObject qualification.
