# ADR 0070: Local generic call inference

Status: Accepted for ASTRA-GEN-INFER-1.

## Decision

A call without an explicit type-argument list may infer the complete ordered
list from already-typed arguments corresponding directly to a callee's `T` or
legal `owned T` parameter. Ordinary name resolution first selects one exact
generic definition. There is no overload search.

`GenericCallInference` records the exact callee TypeParameterSymbol, canonical
candidate semantic identity, argument index and span. Repeated observations must
have identical identities. The first conflicting argument is diagnosed in source
argument order, with the first observation's location. Missing parameters require
an explicit type argument. BuiltinTypes and existing nominal/lexical interning are
the canonicalization authority; neither spelling nor machine representation is
an equality rule.

SemanticAnalyzer types participating expressions without a callee target type.
Declared names already carry their checked identities. It reuses checked
expressions through the ordinary argument checker, preserving concrete parameter
contexts and source argument order. The existing GenericArgumentTypes and
GenericCapabilityAuthority validate the completed list. Explicit applications
continue through those same authorities and retain their literal contextualization
and full-list arity diagnostics. No capability generates a candidate.

The existing forward numeric-context probe can consume an inferred call's known
result, for example in `1.0 + identity(1.0d)`. It checks that call locally once,
caches the checked result and stages its effects until expression checking reaches
the call in source order. This preserves explicit/inferred expression equivalence
without feeding the surrounding numeric expectation into generic inference.

The resulting CheckedGenericCall/CheckedGenericCallStatement is exactly the
existing representation, with an ordered semantic type list. No inference
provenance is retained. Core lowering, substitution, canonical specialization,
recursive placeholders, deduplication, CFG, SSA and ABI lowering remain unchanged.

## Exact outer identities: resolved §75 review

Inside a generic definition, inference may select an exact existing outer
TypeParameterSymbol's TypeParameterType when the equivalent explicit application
is already legal. Thus `identity(x)` inside `outer<T>(T x)` means precisely
`identity<T>(x)`. Same-named symbols from different definitions remain distinct.
`same(a:A,b:B)` conflicts even if every current root instantiates A and B as int.

This explicitly supersedes the original GEN-INFER-1 §§72–74 concrete-only
restriction following the user's affirmative §75 review. It is symbolic identity
propagation through the existing generic representation, not a general
unification engine. The accepted baseline already retains these arguments in
Checked/Core and substitutes them before concrete instance requests. No new
parameterized call node, downstream inference operation, or constraint solver is
needed. Capabilities must be established at definition checking, including unused
definitions. Ownable propagation still requires `move`.

## Ownership and checking effects

Inspecting a named move source resolves and validates the existing owner binding
without recording a move. Ordinary resolved argument checking constructs the
transfer. Generic definition checking uses temporary structured ownership proof
fragments for argument expressions and the inferred call. Only a fully validated
call composes them into the enclosing proof, in argument order. Short-circuit
choices retain their existing structure. Failed inference, capabilities or another
argument discard the proof. The semantic-only SemanticOwnershipFlow subclass
composes proof fragments and remaps owner identities; the shared proof evaluator
is unchanged. Concrete ownership remains the existing Checked transfer and
independently verified downstream flow.

The accepted baseline rejects direct owned-result calls as owned arguments,
including Resource and Class results. Inference preserves this boundary. A direct
producer may initialize a named owner, followed by `relay(move owner)`. Generic
borrowing, generic owned locals and generic owned buffers remain deferred.

## Alternatives and boundaries

A solver using result/assignment/expected type context would obscure the locally
visible type choice and change literal semantics. It is excluded. So are common
numeric types, conversions, subtyping, structural matching, partial explicit
lists, defaults, overloads and generic constructor/method expansion.

Rechecking argument expressions after inference could select a different literal
type or record a move twice. Retaining temporary checked expressions avoids both;
the cache and observations die before Checked leaves semantic checking. Named
storage of unsupported argument types can supply an exact rejection candidate
without creating a whole-struct load, borrowed alias or ownership transfer.

Inference is local across source files: source paths are diagnostic provenance,
never part of observations' type equality or the global specialization key.
There is no runtime metadata, dictionary, witness, allocation, dispatch, reflection,
ABI profile, monomorphization policy or production dependency for this feature.

See [language rules](../language/generic-inference.md) and
qualification.
