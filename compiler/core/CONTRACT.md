# Checked Core, version 1

`CoreProgram` owns `FlowIndex -> CheckedIndex -> BindingIndex -> SyntaxProgram ->
SourceSet`. Types, symbols, signatures, tokens and spans retain those exact owners.
Core IDs also require their stage owner and function. There is no serialized-input
ABI. The structural projection is `astra-core/1`, an internal downstream contract.

Values and authoritative places have different tables. Places preserve slot roots,
recursive nominal field parents, declaration identities, type and qualifiers.
Ordered child edges evaluate once, left to right; kind 7 evaluates its right child
conditionally. Structured while nodes own break/continue targets. Buffer allocation
is a producer with the existing fatal-failure contract, without trap unwinding.
Records remain typed trees and source-bound copy/move/borrow producers.

The supported profile is complete admitted free-function programs with scalar
values, direct calls, concrete records, scalar buffer producers and structured
blocks/if/while/break/continue/return. Unsupported forms defer the entire program.
There is no subset-selection API or whole-compiler admission claim.

Exit plans preserve inside-out lexical scopes, reverse storage acquisition order,
and reverse record-leaf declaration order. Actions test the runtime owner arm and
disarm exactly once; Flow's joined owner state is evidence, not a runtime value.
Call loans retain exact source and commit endpoints. This is responsibility for
ordinary returns and scope exits; custom destructors, release/replacement, foreign
calls, exceptions, unknown member effects and other unsupported policies defer.
Ordinary mutable borrows imply no exclusivity. Nullness is separate from ownership.

The separate verifier must validate the complete model before reads, traversal or
projection. It reconstructs source structure, types, field trees, call contracts,
loan endpoints and cleanup plans from the retained authoritative stages. Builder
status and printed text are never safety authority. Invalid input, invalid Core,
resource exhaustion and semantic/profile deferral are distinct failures. Limits
bound tables, recursion and verifier work; failed queries print no partial Core.
