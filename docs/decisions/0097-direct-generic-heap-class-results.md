# ADR 0097: Direct generic heap Class results from an incoming owner

Status: user-approved Q11D, 2026-10-14.

The user approved the [current-source lifetime and ABI design](../gen-own-2c-heap-result-design.md)
before semantic changes, and separately approved its two enumerated historical
fixture replacements. This extends the finite Q11A/B/C contracts. Earlier
decisions and qualification evidence retain their historical scopes; Q11 remains
OPEN.

One named live exact native heap Class owner may enter a top-level synchronous,
nonthrowing generic helper with one owned Ownable T formal, copied concrete
scalar neighbors and an owned result of that exact T. Heap qualification requires
exactly one structural direct return of the incoming owner outside loops, with
no local owner or Class construction in that heap result helper. All
reachable normal exits must transfer ownership. Existing explicit and inferred
type arguments work; the result must acquire directly into a fresh named concrete
owned Class local, through existing var or owned Class grammar.

The original pointer and allocation responsibility pass from caller to formal,
to captured result, to the receiving local. Existing argument capture/commit and
return capture disarm former owners; their cleanup sees null. Only the current
owner performs complete Class destruction and one heap free. Exact derived
identities, empty/no-deinit Classes and Q08 children use existing cleanup. Fatal
traps remain nonunwinding.

Symbolic definitions stay allocation-neutral. Each actual supplies the result
origin from its matching exact incoming owner. Core independently rebuilds the
definition's direct-return proof, actual cleanup and fresh receiver. Retaining
and acyclic forwarding consumers keep their Q11C graph proof; an owned-result
helper cannot become a forwarding consumer terminal. Unsupported transfers,
second sites, loops and result recursion reject structurally, including dead
code. Resource and caller-backed Class results/recursion keep their existing
rules.

The existing definition/type/heap-formal key determines result domain; no new
canonical key is needed. Concrete heap specialization maps the same T formal and
result to the same exact heap Class cleanup, selects HEAP_OBJECT return provenance
and omits result candidate storage. Its established native result is
`(owner PTR, copied scalars...) -> PTR`. The lexical variant retains
`(candidate PTR, owner PTR, copied scalars...) -> PTR`. Their same-T instances
remain distinct in either request order.

Concrete Core verifies key/result/candidate agreement before CFG. CFG verifies
unique return capture, cleanup ordering and acquisition/liveness. SSA requires
the exact heap RETURN event and rejects cleanup of its escaped pointer; the
existing current-pointer proof also covers exact returned heap Class owners.
Independent incoming pointer/origin reconstruction prevents a consistently
forged null return or cleanup event from bypassing those checks. NABI validates
the exact Class/heap origin plan and candidate exclusivity against SSA.

No public/native ABI profile, backend representation, allocator tag, runtime
dictionary, destructor callback, refcount, object copy or syntax is introduced.
Heap result forwarding, inline consuming producers, generic owned locals,
multiple owning formals/results, mixed origins in one instance, implicit subtype
adaptation, generic members/classes, aggregates, foreign adapters, async/throws
helpers and broader allocator policy remain deferred.

See the [execution and mutation recipe](../../tests/gen-own-2c/README.md) and
qualification for actual evidence and limitations.
