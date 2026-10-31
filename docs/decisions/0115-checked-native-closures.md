# 0115 — Exact checked native closure signatures

Status: implemented; qualification is recorded separately in the Surge-5 receipts.

`Closure<Env,Result,Args...>` and `Fn<Result,Args...>` retain their nonthrowing
contracts. The explicit checked form is
`CheckedClosure<Env,Error,Result,Args...>` and its constructor is
`checked_closure_bind(move environment, named_code)`. The target must declare
exactly the carried `throws Error` bound and borrow the exact heap Class Env as
its first parameter. Environment restrictions and the zero-to-four copied
scalar parameters/result remain the same as ordinary Closure. There is no
implicit widening, effect erasure, owned result, async migration or raw foreign
conversion.

`closure_invoke` borrows either kind of closure. Invoking a checked signature
requires an ancestor catch or compatible caller throws declaration. Its error
bound participates in the semantic and Core effect checks, independent of
whether a particular invocation actually throws. A caught failure leaves the
borrowed carrier alive; a failure that leaves its owning scope releases the
carrier/environment under the existing deterministic cleanup rules.

The checked carrier retains the existing exact native code, environment and
destructor identities. CFG represents invocation as an explicit effect that
produces the nominated root exception pointer, branches on null, routes failure
through existing checked cleanup and publishes the scalar value only in the
success successor. SSA independently checks the rooted error result, exact
signature, live owner loan, distinct error/success edges, reconstructed exception
bound and guarded success publication. The native closure ABI identity includes
the exact error name and must agree with the selected code's exception plan.

LLVM emits an actual indirect native call: the physical return is the root
exception pointer and the first physical parameter is the caller's private
scalar success slot, followed by Env and the copied arguments. The callee writes
that slot on success; the caller reads it only after the null-error edge. One
typed slot is allocated per call site in function entry and reused across loop
iterations, including O0. This
uses the existing checked native function ABI and fast calling convention.
Structural LLVM witnesses retain exact code, environment, success slot and
calling convention, in addition to ordinary ownership cleanup.

A checked native exception never traverses a C callback frame. The retained
callback API accepts only the ordinary nonthrowing closure signature. A native
adapter may own a CheckedClosure, catch its error during callback delivery,
store an owned diagnostic/result and return a foreign-safe scalar status. Native
code observes that state after C returns and may then raise a new checked error.
A35 (`examples/interop-async-5/checked-event-transformer.astra`) demonstrates this
protocol with a retained handler, a shared report and an owned Utf8Message.

The source controls and stage mutations are in
`tests/interop-async-5/checked-check.py` and `checked-proof.vala`. They cover exact
nonthrowing/checked identity, wrong error bounds and arguments, missing explicit
error handling, early scalar publication, owner loans, native effect erasure,
and LLVM slot/environment/code/convention corruption. Runtime fixtures exercise
direct and indirect success/error, repeated use after a catch, nested unique
captures and consuming checked unwind, including numeric and bool signatures.
