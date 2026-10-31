# ADR 0098: One named generic owner local from an incoming owner

Status: user-approved Q11E option A, 2026-10-15. Exact decision:
`A, fixtures yes.` The user approved the [source-backed design](../gen-own-2d-owner-local-design.md)
and its five enumerated historical fixture replacements before semantic changes.
ADRs 0094–0097 retain their historical scopes. Q11 remains OPEN.

A top-level synchronous nonthrowing native helper with one Ownable T parameter
and one incoming owned T may declare one explicitly typed owned T local,
initialized immediately by direct move of that incoming owner, outside loops.
Other formals and the result are copied bool/integer/f32/f64 scalars or void.
No additional local owner or Class storage is admitted in this finite helper.
The local may take completed Q11A loans and transfer at one direct site to a
qualified retaining terminal generic consumer. Otherwise its normal scope or
early return performs exact cleanup. Exits before the declaration retain the
incoming obligation. Moved/possibly moved sources and overlapping loans reject.

Resource and exact native Class actuals are supported, including independently
allocated heap and caller-backed/lexical instances of the same nominal Class.
The original pointer/handle is preserved; only responsibility changes slots.
Heap owners receive complete destructor/child cleanup and one final free;
caller-backed Class owners destroy without freeing caller storage; Resource
owners release their exact handle. Nullable incoming owners retain established
null-skipping cleanup. Generic source gains no null construction or test.

Reuse CheckedOwnedLocalDeclaration/CheckedOwnershipMove, CoreOwnershipTransfer,
the existing structured GenericOwnershipFlow and Q11C finite transfer summary.
Independent Core checks rebuild the incoming/local identity and exact cleanup,
then existing instance keys select heap versus caller-backed specialization.
CFG reconstructs the physical incoming transfer and applies its ownership flow.
Existing SSA owner events and current-pointer proof cover the local in all
three domains; native Class/heap correspondence remains independently checked.
Verifier metadata disappears in LLVM. No new native/public ABI, runtime origin
tag, destructor dictionary, reference count, Class copy or allocation is added.
Fatal traps remain non-unwinding; no new thrown/async path is implemented.

Plain T, copies, uninitialized/null slots, second locals/formals, rearm,
partial moves, local owned results, inline/result chains, generic construction,
loop/recursive ownership transfers, persistent loans, generic members/classes,
aggregate T, subtype adaptation and foreign/async/throwing helpers remain
excluded. The historical Q11D `generic-local` rejection still excludes a local
in an owned-result helper. The five approved older single-local negatives now
exercise a second local; their exit-1/no-executable gates remain intact.

See [the execution and mutation recipe](../../tests/gen-own-2d/README.md) and
measured qualification. Future owning collection,
member and text contracts require separate application-facing requirements and
authorization; this bounded decision does not close Q11.
