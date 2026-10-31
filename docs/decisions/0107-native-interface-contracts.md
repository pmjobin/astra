# 0107 — Finite native interface contracts

Native interfaces reuse the existing opt-in Class hierarchy dispatch channel.
`interface Measure { int read(int input); }` declares a nominal, fieldless,
nonconstructible contract. `class Add : Measure` supplies an explicit `override`
for every operation and calls the empty contract initializer with `: base()`.
The implementing object remains the unique Class allocation; a borrowed
`Measure` parameter retains its original receiver address and lifetime.

The initial contract admits copied `int`/`i32` parameters and result only,
without throwing, generic, owning, asynchronous or foreign method channels.
Implementations return one copied expression using parameters, constants,
receiver fields and ordinary scalar arithmetic. Calls and mutations reject;
this makes the read-only promise checkable without a new effect-inference
system. Ordinary methods outside an interface retain their existing effects.

The contract consumes the existing one-parent inheritance slot. It supports
multiple concrete implementations and further concrete subclasses, but no
multiple interfaces, interface inheritance, dynamic casts or reflection.
Interface values cannot be constructed, returned with ownership, or accepted
by an ownership-consuming parameter. Call-scoped borrowing uses the existing
owner and lexical-lifetime checks; no persistent owner alias is introduced.

The internal requirement definition has an inert synthesized scalar body and
an empty base initializer. Source cannot construct the contract and every
concrete vtable must replace all requirements, so the synthesized operation
body has no source-observable execution path. The marker remains on the nominal
type through Core/CFG/SSA and is copied into independent native metadata.
Concrete slot completeness, abstract identity and physical selector ranks are
validated before LLVM execution. Two declarations with the same signature
remain separate slots. Classes outside a participating hierarchy retain their
header-free layout and incur no new allocation, refcount or global registry.

Qualification lives in `tests/language-runtime-3/dispatch-verify.py` and
`dispatch-tests.vala`: public optimization routes, separately compiled C
allocation/destructor observations, receiver identity across a legal owner move,
same-signature selectors, namespace identity and deliberate IR metadata
mutations. The campaign validation report records the actual executed results.
