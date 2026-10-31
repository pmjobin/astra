# ADR 0095: Finite generic heap Class consumption

Status: user-approved `Q11B-HEAP-CLASS-CONSUMER`, 2026-10-14.

The user approved the [source-backed design and lifetime argument](../gen-own-2a-heap-design.md)
before production changes. This extends the existing generic ownership authority
for one direct consuming use, while preserving ADR 0060 and ADR 0094's historical
decisions and qualification scopes. Q11 remains OPEN.

Allow a named exact native heap Class owner to move into one owned Ownable T
formal of a synchronous, nonthrowing, top-level native generic consumer.
Other parameters are concrete copied bool/integer/f32/f64 scalars; the result
is copied scalar or void. Callers are synchronous. Existing explicit type
arguments and supported owner-name inference retain their rules.

The body must retain its incoming T responsibility until normal retirement.
It may call the accepted borrow-only T helpers and return early, but heap
instantiation cannot move/forward/recurse with that owner, return an owned T,
or declare a generic owner local. Definition-time ownership flow is unchanged;
eligibility inspects its owner events structurally, including unreachable moves.
Source requests are validated after all bodies, and Core rebuilds that proof
independently. Resource and lexical/caller-backed Class forwarding remain legal.

Keep shared symbolic formals allocation-neutral. Each direct Class actual carries
its existing concrete cleanup origin. A function instance's canonical identity
adds the heap consuming-parameter ordinal to definition/type identity. The same
T can therefore select separate lexical and heap bodies in either discovery
order. Borrow-only instances acquire no cleanup and share their existing key.

Specialization sets the concrete incoming parameter's existing heap origin and
maps symbolic retirement to its exact existing Class heap cleanup. Core verifies
the canonical domain and source/acquisition boundary; CFG and SSA retain their
concrete liveness/cleanup authorities. Native PTR and object-origin plans are
unchanged. Actual heap destruction and deallocation reuse existing lowering,
including absent deinit, empty Classes and exact derived destructor chains.
No result candidate is introduced for scalar/void consumers. No backend change,
object copy, allocation-domain runtime flag, generic dictionary or callback is
introduced. Fatal traps remain non-unwinding.

Heap generic results/forwarding/ownership-carrying recursion, generic owner
locals, multiple owned T formals for heap instantiation, generic members/classes,
aggregate T, implicit subtype adaptation, inline producers, async/throwing
consumers, foreign ownership adapters and persistent loans stay deferred.
Existing nullable lexical/Resource behavior supplies no heap instance origin.

The user separately approved replacing only Q11A's now-stale direct heap
rejection case with an actual heap-forwarding rejection. Direct heap consumption
is independently exercised by the [new native/memory suite](../../tests/gen-own-2a/README.md).
See qualification for actual results and limits.
