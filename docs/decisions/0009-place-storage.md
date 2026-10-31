# ADR 0009: Places and local storage

Status: accepted in ASTRA-PLACE-1, on the accepted ASTRA-CFG-1 foundation.

## Decision

1. Computed values and authoritative storage are distinct compiler concepts.
2. A Place represents storage authority. Its identity is not a source name.
3. Reading mutable local storage is an explicit load from a Place to a value.
4. Mutation is an explicit store of a computed value to a Place.
5. Initializing fresh storage is distinct from replacing its stored value.
   `Initialize` and `Store` remain separate operations through Core and CFG,
   until a downstream stage can prove the distinction irrelevant.
6. Every downstream representation owns its Place identities. Temporary exact
   object maps translate `LocalSymbol → CoreLocalPlace → CfgLocalPlace`;
   completed representations do not retain upstream declaration authority or
   reconstruct binding from strings, ordinals, or provenance.
7. Places are independent of LLVM pointers and allocas.
8. Addressability, physical location, and target realization are downstream
   concerns. This decision does not require every future Place to occupy memory.
9. Only local Places exist now. Field, index, dereference, ref/out, and foreign
   storage projections remain future work.
10. Future ownership semantics consume the established Place/storage authority;
    they do not redefine it. Current `int` values have no ownership operations.

## Current source and semantic policy

The grammar adds `type-name identifier = expression;` and
`identifier = expression;`. Assignment is a statement with no result value.
Uninitialized locals, assignment expressions/chaining, compound assignment,
expression statements, and nested block statements are not supported.

Every local has type `int` and a mandatory initializer. `void` and unknown local
types are semantic errors. Initializer and assignment types must exactly match
the local type; there are no conversions. All current valid expressions are
`int`, so the mismatch guards cannot be reached through valid source declarations.

Locals inhabit the single current function-body value scope. The analyzer checks
statements in source order: resolve the declared type, check name availability,
check the initializer without the new local, require its exact type, then create
and publish the `LocalSymbol`. Ordinals are zero-based declaration positions.
An earlier use or self-reference receives the existing deterministic unknown-name
diagnostic. Local names must be unique and must not duplicate parameters.
Nested-block shadowing policy remains undecided because nested blocks do not exist.

Assignments bind only to previously published `LocalSymbol` objects. Parameters
retain their existing value semantics, and assignment to them is explicitly
unsupported in PLACE-1. This does not freeze permanent parameter immutability.
Known function/type names receive a non-assignable diagnostic; absent targets
receive an unknown-target diagnostic. Local/parameter value lookup takes priority
over separate function/type namespaces.

## Representation and verification

`CheckedFunction` owns ordered locals; checked declarations, assignments, and
local references retain exact symbols. Core functions own local Places, and a
checked local reference becomes `CoreLoadValue`. Core statements preserve
initialization, ordinary stores, and returns in source order, including after
return. The verifier checks ownership, types, ordinals, exactly one initialization
per local, and initialization before loads/stores in this structured order. This
is a linear structural check, not CFG dominance or definite-assignment dataflow.

CFG functions own distinct local Places. Blocks contain ordered
`CfgInitialize`/`CfgStore` instructions followed by exactly one separate,
constructor-required `CfgReturn` or `CfgFunctionEnd` terminator. Instructions
cannot represent terminators. Only terminators provide successors; adding storage
does not change reachability or function completion. Post-return instructions
survive in disconnected blocks. CFG verification checks exact declaration
ownership, types, ordinals, and one initialization per local across all blocks.
It does not infer initialization flow from block order or introduce dataflow.

The implementation extends the existing stage-owned declaration arrays and
temporary identity maps. Publishing a completed block with its instruction array
preserves CFG-1's mandatory single terminator without a mutable terminator API.
No physical fields, new dependencies, SSA, branches, ownership operations, or
optimizations are introduced.

## Evidence

See the [storage inventory and examples](../ir/place-storage.md), identity tests
with deliberately disagreeing source spelling, malformed foreign-place/type
tests, and local lifetime regressions in `tests/core/places.vala` and
`tests/cfg/places.vala`. Weak references prove earlier symbols/nodes actually die.
Both Core and CFG have standalone structural executables and LLVM linkage
firewalls. The local literal fixtures preserve 1,003 exact digits through every
existing dump mode.
