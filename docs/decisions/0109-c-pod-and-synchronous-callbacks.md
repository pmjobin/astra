# Natural scalar POD pointers and named synchronous C callbacks

The first aggregate C boundary passes an explicitly borrowed native Struct pointer.
`[CCode(record_abi="natural-lp64")]` admits one through 32 numeric scalar fields
in source order. The supported target is GNU Linux x86-64 LP64. The independently
computed CABI plan records exact names, scalar identities, offsets, extent and
alignment; LLVM verifies its actual storage against that plan and target. C/GCC
and Clang witnesses independently establish `sizeof`, `_Alignof`, `offsetof` and
field/value transport. A pointer boundary avoids inventing a by-value aggregate
register/result classification from native scalar widths.

The callback subset uses `callback="qualified_function"` and
`callback_abi="i32-context-i32-sync"` on an import whose logical signature is
`int provider(borrowed Context* context, int value)`. The C signature inserts one
function pointer before the context: `int32_t provider(int32_t (*)(void*,int32_t),
Context*,int32_t)`. The nominated native function must have the exact same
context/value types and return I32; it is concrete, direct, synchronous and
nonthrowing. A generated internal C-convention thunk forwards both arguments to
that exact native function using its native convention. A raw pointer is never
reinterpreted as an owning object or a callable merely because its width matches.

This is an explicit trusted provider obligation: it invokes only during the
import, keeps no callback/context/derived alias, does not destroy or replace the
record's storage, and does not throw/unwind through C. The normal source pointer
provenance keeps the lexical context live across the call. The declaration names
the callback statically; arbitrary first-class retained closures are outside this
slice. Native Class callable environments are a separate facility.

Bool, pointers inside records, nested/generic/owning records, empty records,
packed/over-aligned layouts, unions, bitfields, variadics, aggregate by-value
parameters/results and ownership-consuming foreign pointers remain unsupported.
The declaration must agree with the independently compiled C provider; this
compiler does not parse C headers or prove a dishonest C implementation safe.
Foreign calls retain their existing observable effects and optimized `nobuiltin`
controls. Ordinary programs acquire no callback allocation or extra dependency.

The executable sources and deliberate rejected mutations live under
`tests/language-runtime-3/cabi-*`; the campaign validation document records the
actual qualification result and its limits.
