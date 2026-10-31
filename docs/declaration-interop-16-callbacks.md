# M16 typed synchronous callback carriers

This intermediate implementation adds `borrowed Callback<R, A...>` to native
functions and selected declarations-v1 C Class members. A Callback is a call-only
view of code and opaque context. It is distinct from the copied native `Fn` code
pointer and from an owning `Closure` environment. It cannot initialize a local,
field or property, escape as a result, be consumed as an owner, or enter an async
function. Forwarding preserves the exact signature and borrowed scope. Existing visible
user-defined `Callback` nominal types retain normal resolution; the builtin does
not replace historical Class definitions.

Callback signatures admit i32/u32/i64/u64/f32/f64/bool arguments and a scalar or
void result, including zero arguments and signatures wider than the old Fn
four-argument bound. The current callback argument bound is 256. Captured native
Closure conversion and retained GObject signal closures are still pending.

The C ABI expands each Callback into a typed function pointer followed by its
`void *` user data. Callback code receives the original user data first. C99 bool
extension belongs to the C declarations and calls; native code uses the existing
native calling convention. Private native views contain exactly code and context.
Imports generate a C thunk that loads this native pair; exports build a private
view whose thunk calls the original C function and data. The view and its context
box have call lifetime and do not allocate an independently owned environment.
Explicit nullable channels preserve null code and support an Astra null test;
mandatory null callbacks fail before invoking native code or publishing outputs.

Native callback arguments also cross independently compiled leaf/component/consumer
units. The producer sources are removed before subsequent compilation. All eight
O0/O2 combinations and an O1 graph exercise the unchanged typed code/context
carrier. This is a native callable prerequisite, not the pending foreign-metadata
unit schema extension.

The new executable fixtures use independent C prototypes as well as generated
headers, unique/shared receivers, O0/O1/O2 native objects, scalar and void results,
mixed natural-layout POD arguments through target C forwarders, checked failures,
active-receiver destruction refusal, and nullable calls. The import roundtrip
passes a C callback through an Astra exported member, a foreign provider, the
native thunk, and back to the original C callback with two distinct data records.
Counters check exact calls and cleanup. These results do not qualify COM,
GObject signals, the final frozen API challenge, or native Windows.

Detached Core/CFG/SSA/native tests reject replacement with an equal-width raw Fn.
C ABI tests reject omission of the physical user-data slot. Ordinary-valid LLVM
mutants swap same-typed code/context addresses, replace user data, change calling
conventions, and remove C bool attributes. Each mutant passes ordinary LLVM
verification before the Astra artifact verifier rejects it. The combined contract
proof and actual foreign clients run under Valgrind without suppressions; the
slice ledger records their exact identities and outcomes.
