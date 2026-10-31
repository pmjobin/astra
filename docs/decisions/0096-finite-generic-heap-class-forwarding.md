# ADR 0096: Finite generic heap Class forwarding without an owned result

Status: user-approved `Q11C-HEAP-FORWARD-NORESULT`, 2026-10-14.

The user approved the [source-grounded forwarding and lifetime design](../gen-own-2b-heap-forward-design.md)
before semantic implementation, then separately approved its seven enumerated
historical fixture replacements. This extends ADR 0095's direct heap consumer
boundary. ADR 0060, 0094 and 0095 retain their historical scopes and evidence.
Q11 remains OPEN.

One named live exact native heap Class owner may enter a top-level synchronous,
nonthrowing generic helper with one owned Ownable T, concrete copied scalar
neighbors and a scalar/void result. Callers remain synchronous. The body retains
its incoming owner or has one structural forwarding site to a qualified generic
owned-T callee. Conditional nonforwarding paths retain cleanup responsibility.
Existing explicit/inferred T resolution, nominal identity, move state and Q11A
call-bounded loan rules remain authoritative.

Semantic checking records exact generic transfer destinations and formal
ordinals in its existing temporary ownership event tree. Core independently
rebuilds that information from verified Core calls and source owners. Both
qualify finalized helper graphs by a least fixed point: retaining eligible sinks
qualify first, and a shaped helper with one exact edge qualifies only when its
destination formal already qualifies. Cycles have no terminal proof. There is
no new hop-count limit. Unsupported transfers, multiple structural sites and
loop forwarding reject, including unreachable forms. This scope gate does not
replace the existing path-state ownership solver.

Shared symbolic formals stay allocation-neutral. The existing Q11B immutable
definition/type/heap-formal key applies at every hop. The specializer already
selects an inner domain from the mapped source owner's cleanup; it carries the
original pointer, exact Class responsibility and heap origin into the next
signature/acquisition. Concrete Core also rejects injected subtype adaptation
at generic heap boundaries by comparing the exact source nominal identity;
ordinary concrete Class transfer rules retain their existing authority.
Concrete Core reconstructs and verifies its own finite
graph, while CFG capture/commit/live-state, SSA current-pointer/origin and native
PTR/object-origin correspondence retain their independent checks.

Only the current owner retires the object on normal exit. A forwarded slot is
disarmed; a retained branch uses existing complete Class destruction and heap
free. Exact derived chains, empty/no-deinit objects and Q08 children reuse their
established lowering. No production backend/ABI, runtime allocator tag,
generic dictionary/callback, refcount, object copy or owned-result candidate is
introduced. Fatal traps remain non-unwinding.

Heap generic owned results, owning T locals, multiple owned formals, aggregate T,
subtype adaptation, persistent loans, generic members/classes, foreign ownership
adapters, async/throwing contexts, recursive ownership, multiple sites, loop
forwarding and special allocator policies remain deferred. Existing Resource
and lexical forwarding/results/recursion keep their established rules.

See the [independent controls and executable recipe](../../tests/gen-own-2b/README.md)
and measured qualification for evidence and limits.
