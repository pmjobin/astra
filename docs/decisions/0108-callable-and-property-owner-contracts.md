# 0108 — Explicit callable environments and receiver property loans

Status: accepted finite implementation; full CALLABLE-1A remains partial.

A direct Class local or borrowed Class parameter with a typed `invoke` method
can be called as `value(arguments)`. The compiler resolves the exact method and
uses its existing receiver, parameter, result, dispatch and checked-effect
contracts. A lexical zero-field callable needs no heap environment. A heap
callable owns captured Classes or Resources through ordinary explicit `owned`
fields; moving, forwarding, early return and checked unwinding retain the same
unique destruction authority. No new implicit capture, copying or foreign
retention rule is introduced. A borrowed environment is a call-scoped borrowed
Class parameter, not a heap closure containing an unproved stack address.

This is a callable-object facility. Bare function-address values, signature
inference and anonymous closures are missing; the finite spelling does not
establish full first-class function-value support.

`property borrowed T view` explicitly projects one private owned Class or
Resource field. Its getter must be the single statement `return this.field;`.
The generated accessor retains its exact identity and returns a pointer without
cleanup authority. The caller may only use the result as an exact borrowed
argument or null test in the same expression block. Core, CFG and SSA independently
validate the projection and refuse storing the result or invalidating the
receiver while its loan is live. Native correspondence retains the borrowed
getter marker; LLVM retains the exact private field address and call bindings.

The optional `set(owned T value)` consumes a named replacement owner or null.
Evaluate and validate a checked producer first: failure leaves the old owner in
place, and ordinary unwinding destroys an acquired temporary. Replacement then
uses the existing field retirement contract. Destructors remain nonthrowing;
checked setters, direct producer assignment, stored receiver-backed aliases and
owning lazy caches are not established by this decision.

Runnable source and mutation proofs live under `tests/language-runtime-3`.
Historical lazy qualification remains unchanged.
