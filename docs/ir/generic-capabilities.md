# Generic capability IR

Capability legality is frozen during generic-definition checking. Concrete roots
cannot grant missing authority. `GenericCapabilityNamespace` owns one exact
`GenericCapabilitySymbol` per built-in name per compilation; type/value/member
namespaces never participate. Each `GenericCapabilityRequirement` retains its
exact weak `TypeParameterSymbol`, exact capability symbol and SourceSpan.
`GenericFunctionSymbol` and `CheckedGenericFunction` retain the complete ordered
requirement list. Each type parameter also retains its ordered requirements.

The immutable `GenericCapabilitySet` on `TypeParameterType` stores a copied ordered
list of stage-neutral `GenericCapabilityIdentity` values and exact membership.
`GenericCapability.GEN1_PLAIN_COPY` is unchanged. There is no implication closure.
`GenericCapabilityAuthority.capabilities_of` owns the only concrete matrix;
`satisfies` uses that matrix for concrete types and declared set membership for
parameter types. Neither Core nor the monomorphizer duplicates the matrix.

`CheckedGenericCapabilityOperation` retains `GenericOperationKind`, exact
TypeParameterType, authorizing GenericCapabilitySymbol, left/right operands,
result and span. The bounded kind maps Eq/Ordered/Numeric/Bitwise/Shift to their
exact families. BIT_NOT has no RHS; shifts retain the concrete integer count
operand/type; comparisons return scalar bool. Every other binary RHS has the
same exact T. Existing concrete checked operator nodes are unchanged.

## Core lifetime and verification

`GenericCapabilityIdentity` is also the immutable Core capability identity:
semantic-to-Core mapping copies the enum identity, with no checked symbol backlink.
`CoreGenericCapabilityRequirement` holds exact weak CoreTypeParameter, identity
and independent provenance. Core parameters/functions own their requirement lists.
The existing immutable type token carries only stage-neutral authority.

`CoreGenericCapabilityOperation` owns the exact CoreTypeParameter descriptor,
operator kind, authorizing identity, operands, result and provenance.
Checked/Core generic calls snapshot already-resolved target requirement records,
retaining argument bindings through their explicit ordered type arguments. This
is compile-time evidence; no witness operand exists. Core verifies the retained
requirement records against the target, then validates every actual argument.

The verifier rejects foreign parameter references, invalid capability identities,
duplicates, inconsistent requirement ordering/membership, missing target evidence,
unauthorized operator families, wrong result shapes, cross-T/U operands, and
generic shift counts. Generic-to-generic satisfaction uses explicit membership,
never concrete-universe enumeration. Unused definitions are also verified.

Stage lifetime tests release the checked graph, including its symbols and
requirements, then verify Core and specialize it. After specialization they
release the generic Core graph and verify/build concrete CFG, SSA, NABI and LLVM
with their upstream graphs released at each boundary. Standalone Core and
monomorphizer targets compile without the parser, checked model or analyzer.

## Specialization and firewall

`CoreGenericMonomorphizer.request` checks all concrete requirements before looking
up/creating a registry bucket or placeholder. The canonical key and existing
placeholder-before-body recursion remain unchanged. No capability evidence is
added to instance keys, ABI parameters or runtime data. No extra instance-level
evidence record is needed for these canonical built-ins.

The cloner substitutes operation.parameter.semantic_type and clones operands in
source order. `CoreGenericOperationResolver.concretize` verifies concrete
satisfaction, retained operator authority and shape, then selects existing
`CoreBinaryValue`, `CorePrefixValue` or `CoreIntegerShiftValue`. It never invokes
SemanticAnalyzer or rechecks source. Signedness, wrapping, divide/trap behavior,
IEEE rounding/comparisons and shift guards come from those ordinary authorities.

`CoreVerifier.verify_concrete`, called by CfgBuilder, rejects unresolved capability
operations even when their result is concrete bool. CFG/SSA/NABI/LLVM contain no
capability types or nodes. Concrete instance NABI uses existing v0-v6 profiles;
definitions have no NABI. No runtime witness, dictionary, descriptor, boxing,
capability helper or new backend operation exists. CABI and VAPI remain unchanged.

Old unconstrained syntax/semantic/Core/instance dumps preserve their previous
format. New dumps append ordered `(requires #ordinal T Capability)` records and
explicit `(generic-op kind (capability Capability) ...)` values. Concrete dumps
show the accepted ordinary operations after specialization.

See [generic IR](generics.md), [language](../language/generic-capabilities.md),
[ADR 0057](../decisions/0057-explicit-generic-capabilities.md), and
qualification.

## Ownable transport authority

Ownable extends the existing GenericCapabilityIdentity/Symbol namespace and sole
GenericCapabilityAuthority matrix. The immutable parameter requirement set
selects GenericTransportMode.OWNABLE, while every old parameter remains PLAIN_COPY.
The legacy GEN1_PLAIN_COPY accessor never grants copy authority to an Ownable T.
Exact membership authorizes owned contracts and transfer, with no capability
implication or runtime witness. See [generic ownership IR](generic-ownership.md).
