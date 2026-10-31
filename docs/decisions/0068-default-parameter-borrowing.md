# ADR 0068: default native parameter borrowing

Status: accepted for ASTRA-PARAM-BORROW-1, including the two explicitly approved
semantic compatibility breaks below.

## Decision and doctrine

Non-consuming bounded use should look ordinary. Ownership acquisition,
transfer, persistence and escape should look explicit.

For exact native nominal Resource (`HandleType`), ClassType and SliceType
parameters, plain `T name` and `borrowed T name` both select the existing
`PointerParameterContract.BORROWED_NOESCAPE`. `owned T name` continues to select
`OWNED_TRANSFER`; named owners transfer through explicit `move`.

```astra
void inspect(Resource resource) { /* bounded use */ }
void install(owned Resource resource) { /* owns cleanup */ }
```

The borrow contract preserves the existing domain's nullability, mutation,
aliasing and escape rules. It receives no cleanup, ownership, reference count,
copy or move. Class borrows refer to the same ObjectStorage. Two borrowed
parameters may alias; borrowing implies neither readonly nor noalias.

This applies to free functions, struct/class methods and constructors through
their shared native signature collector. No static-method syntax exists in the
accepted baseline; this decision does not add one or change `this`/properties.
Resource identities continue to come from VAPI handle declarations; native
`resource {}` declarations are not introduced.

## Intentional compatibility changes

The baseline audit at `31ca2a92312f1483072975696fb08be3369f6b23` found that plain
Resource parameters were UNMANAGED, nullable, freely escapable values without
cleanup. `Resource identity(Resource r) { return r; }` was explicitly documented
and tested. Project policy intentionally supersedes this input contract:
`r` now borrows, and the existing noescape rule rejects that return or local
capture. Resource result syntax and unmanaged results/locals are unchanged.
No `unmanaged`, `unowned` or `unsafe` Resource parameter qualifier replaces the
old native parameter capability. Foreign/VAPI contracts remain unchanged.

Plain ClassType parameters previously rejected; they now use the same accepted
contract as explicitly borrowed Class parameters. Plain slices already borrowed
under BUFFER-1 and retain that behavior.

The baseline also deliberately accepted same-owner Class `f(c, move c)` with
`(borrowed C, owned C)` parameters. This is intentionally superseded: a borrow
must remain valid throughout the call, while the other parameter receives a
capability that can invalidate its referent. Argument order cannot establish
that lifetime guarantee. Resource and buffer calls already reject this pattern.
The old OBJ-OWN alias fixture is now a negative; a separate two-borrow alias
fixture retains the mutation/no-noalias witness.

## Authority and alternatives

Resolve defaults from exact semantic domains during signature collection,
before semantic parameter identity and Core construction. Explicit syntax and
implicit syntax create the same existing ParameterSymbol contract. Borrowing
is not a semantic type and adds no provenance-dependent legality. No
ImplicitBorrowType, Checked/Core operation, ABI channel or backend case exists.
Downstream stages cannot determine whether the source spelled `borrowed`.

Keep the existing CFG ownership fixed point, borrow values, move captures and
through-invocation reads. Remove the Class exceptions that waived owner liveness
when that same invocation received a pending transfer. Existing conservative
input-borrow provenance also rejects forwarding a potentially aliasing Class
view and incoming owner together. Fresh independent objects remain independent.
No runtime pointer equality, token, exclusivity proof or lifetime metadata is
needed. Completed borrow calls still permit later moves, and Resource/buffer
release and replacement retain their existing rules.

Preserving native unmanaged Resource parameters would defeat the safe ordinary
spelling. Adding an unmanaged qualifier would prematurely design an escape
mechanism with no established workload. A second implicit-borrow tracker would
risk diverging from the accepted explicit semantics. All three alternatives are
rejected in favor of one contract and one lifetime authority.

## Boundaries

Scalars, vectors and masks remain values. Copyable concrete structs retain
STRUCT-ABI COPY_VALUE and independent read-only parameter storage. Raw void*
and supported typed-pointer semantics stay unchanged. GEN-1 PLAIN_COPY and
GEN-OWN owned T remain distinct; plain or borrowed T under Ownable still reject.
Concrete Resource/Class parameters inside otherwise generic functions use the
same concrete defaults.

No CABI, VAPI, CEXPORT, result, field, receiver or property default changes.
No new NABI profile, runtime dependency, object header, refcount or weak
reference is introduced. Bounded borrowing guarantees a live referent for the
permitted region; it is not expiration-aware weak ownership. Generic borrowed
T, stored borrows, interfaces, shared/weak ownership, const and multi-file
compilation remain separate design decisions.

[Language rules](../language/parameter-borrowing.md) and
qualification and supersessions give the
source matrix, evidence and exact baseline changes.
