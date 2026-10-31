# 0057 — Explicit generic capabilities and definition-time operators

Status: accepted for ASTRA-GEN-CAP-1.
Baseline: ASTRA-GEN-1, `0bff0c63742648e6db757314c6312ba203efb09a`.

## Decision

Generic capabilities are semantic compile-time authority. A generic definition
is checked once against its declared requirements, even when unused. Eventual
concrete instantiations cannot supply missing operations or forwarding evidence.
No enumeration of the concrete type universe participates in parametric checking.

1. Requirements attach to exact `TypeParameterSymbol` identities and retain source
   provenance. Capability names resolve in a separate compiler-owned namespace to
   exact `GenericCapabilitySymbol` identities.
2. `GEN1_PLAIN_COPY` remains the implicit baseline. Existing unconstrained GEN-1
   source rules and dumps remain unchanged. Source `Copy` and `Move` do not exist.
3. The additive built-ins are exactly `Eq`, `Ordered`, `Numeric`, `Bitwise`, `Shift`.
   There is no implication graph: Ordered does not grant Eq; Numeric grants
   neither Ordered nor Eq. Requirements preserve source order; membership uses
   exact identity sets.
4. Each generic call validates all requirements, including phantom parameters.
   Concrete arguments consult the single compiler-owned capability matrix.
   Type-parameter arguments satisfy only their explicitly declared requirements.
   Missing evidence rejects during definition checking, including recursive calls.
5. Capabilities authorize exact operator families and uniform input/result shapes.
   They never authorize arbitrary member access, ownership, casts, null, literals
   contextualized to T, addressing, dereferencing or indexing.
6. `Eq` grants `T == T` and `T != T`, returning scalar bool. `Ordered` grants
   `T < T`, `<=`, `>`, `>=`, returning scalar bool. `Numeric` grants only binary
   `T + T`, `-`, `*`, `/`, returning T. Unary minus and remainder are excluded.
   `Bitwise` grants `&`, `|`, `^`, `~`, returning T. `Shift` grants `T << count`
   and `T >> count`, returning T, with an ordinary concrete scalar integer count.
7. T and U remain distinct even with identical requirements or future arguments.
8. Semantic and parameterized Core IR represent capability operations explicitly,
   retaining the operator family, exact type parameter, authorizing capability,
   operands, result and provenance. They are never disguised as concrete operations.
9. Core retains immutable stage-neutral capability identities, independent
   requirement records and exact parameter descriptors. It retains no checked
   symbols or analyzer. Its verifier checks requirements, operations, call evidence
   and exact shapes after the checked graph has been destroyed.
10. Monomorphization substitutes exact types and resolves capability operations to
    the existing concrete Core binary, prefix and integer-shift forms. It verifies
    retained capability authority. This is semantic substitution, never source
    re-typechecking or operation discovery from an instance.
11. Capability operations disappear before CFG. CFG, SSA, NABI and LLVM remain
    generic-unaware; the concrete Core entry verifier enforces the boundary.
12. Concrete operation semantics belong to the substituted type. Numeric promises
    availability and shape, not identical mathematical laws or overflow/trap rules.
    Integers keep wrapping arithmetic, divide-zero traps and signed division edge
    semantics; f32/f64 keep strict IEEE rounding, NaNs, signed zero and floating
    division by zero. No fast math or FMA contraction is introduced.
13. Equality preserves pointer identity and floating NaN/zero semantics. Ordering
    preserves signed/unsigned and IEEE ordered comparisons. Bitwise/Shift reuse
    accepted BIT semantics, including concrete width, valid count domain,
    invalid-count trap, arithmetic/logical right shift and fixed-width left shift.
14. No runtime witness, type descriptor, dictionary, boxing, dispatch helper or
    hidden ABI channel exists. There is no new NABI profile; only v0-v6 apply.
    CABI and VAPI gain no generic capability support.
15. Instance keys remain definition identity plus ordered exact concrete types.
    Requirements are frozen by the definition; canonical satisfaction supplies no
    alternate witness. Unsatisfied arguments reject before an instance placeholder
    or inventory entry is created. Existing placeholder recursion is retained.
16. The matrix is frozen: bool and void* have Eq; the six integer scalars have all
    five capabilities; f32/f64 have Eq, Ordered, Numeric. All numeric vectors and
    boolean masks have no named capabilities, but retain GEN1_PLAIN_COPY eligibility.
17. Vector equality returns `bool<N>`, conflicting with Eq's scalar bool result.
    Vector arithmetic has differing operator sets across element families. Both
    remain deferred; no associated type, output type, constant or result-shape
    mechanism is introduced, and no future vector-capability names are frozen.
18. Generic ownership, owned/borrowed T, explicit Copy/Move, generic aggregate or
    member declarations, type constructors, inference, const generics,
    specialization and representation sharing remain separate work.
19. No user-defined capabilities, interface-as-capability relationship, capability
    inheritance, associated items, interfaces or dynamic dispatch are frozen.
    Future interfaces/capabilities must extend the exact requirement identities
    and explicit generic checking model rather than replace them. Witness semantics
    remain undecided future work.

## Consequences

The concrete matrix lives in `GenericCapabilityAuthority.capabilities_of`.
`GenericCapabilityIdentity` is the stage-neutral Core capability identity as well
as the identity of each semantic built-in symbol; no parallel identity table is
necessary. `GenericCapabilitySet` preserves order and exact membership without
retaining symbols. Where clauses are contextual syntax after a generic function's
parameter list, with at most one clause per parameter. Repeated capability names
and clauses reject; clauses may follow any type-parameter order.

The existing generic-call result-context lookup required one correctness fix:
when a result is a directly substituted concrete scalar, neighboring literals
receive that scalar's ordinary context. This does not infer type arguments or
contextualize literals to T.

See [language](../language/generic-capabilities.md),
[IR](../ir/generic-capabilities.md), and qualification.
