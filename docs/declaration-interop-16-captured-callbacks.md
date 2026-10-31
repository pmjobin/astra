# M16 captured native callback views

A borrowed synchronous `Callback<R,Args...>` can now receive an owned native
`Closure<Environment,R,Args...>` or an explicitly borrowed Closure parameter.
The signatures must match exactly: copied scalar or void result, copied scalar
parameters, nonthrowing, synchronous, non-Actor and nonthreaded. Existing Closure
arity rules remain intact; ordinary callback function addresses retain their
separately qualified callback arity. No historical negative is replaced.

The Closure keeps its unique owned environment and original cleanup contract.
The new view copies its exact native code/environment pair into call-scoped
callback storage. It does not acquire or transfer the environment. Null carrier
handling uses a guarded empty carrier before reading fields and preserves a null
callback. The Closure and callback layouts remain distinct LLVM types with
independent field-address/load/publication checks.

Checked/Core/CFG parameter views retain exact source and destination boundary
identities. Owned local projections use the existing unique borrow event. SSA
retains the original Closure operand and verifies its complete signature and
noescape use. Native ABI records each function/block/instruction/argument
projection with both physical signatures and exact environment authority. The
C ABI retains and independently validates that inventory. LLVM checks the exact
carrier field reads and projected pair. Detached mutations cover source type,
projection removal and an ordinary-valid change from environment field to code
field.

Argument evaluation cannot borrow a captured callback while transferring the
same Closure owner in another argument. A minimized negative exposed this gap;
admission and independent stages now reject that overlap. Callback values remain
excluded from fields, locals and results. The synchronous foreign NoEscape
promise remains an assumption about the provider, as for existing foreign calls.

The native matrix covers wide scalar, BOOL and void signatures, local capture,
borrowed forwarding and exact environment destruction at O0/O1/O2. The independent
GObject provider invokes a captured native callback and observes exact environment
retirement. Source-hidden leaf/middle native-library tests now receive a captured
environment from their consumer across all existing optimization combinations.

This is intermediate M16 qualification. Retained native signals, target-selected
personalities, foreign metadata in opaque native units, frozen SDK qualification
and final regression/Windows gates remain open.

The expanded compiler Valgrind witness exposed three eight-byte temporary-array
leaks in existing Closure cleanup lowering. Named local arrays now own the LLVM
API argument lists. A combined run also crossed GLib's quark-table growth boundary:
its 16 KiB initial pointer table becomes intentionally unreachable for lockless
lookup ([upstream implementation](https://github.com/GNOME/glib/blob/main/glib/gquark.c)).
The failed combined run is retained. Memory qualification runs the same 28 suites
in two fresh processes, with no suppressions, so compiler leaks remain visible
without crossing that unrelated global table growth boundary.
