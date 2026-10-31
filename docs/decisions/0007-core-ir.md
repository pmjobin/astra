# ADR 0007: Typed semantic Core IR

Status: accepted in ASTRA-IR-1, on the ASTRA-SEM-1 foundation.

## Decision

1. Core IR consumes the checked semantic model, never raw syntax. The explicit
   conversion boundary is `CoreBuilder.build(CheckedProgram)`.
2. Core IR uses Astra's existing `SemanticType` identity. It does not create a
   parallel type universe or choose the physical representation of `int`.
3. Functions, parameters, and values have Core-owned object identities. Checked
   symbols are temporary builder-map keys, not identities retained by Core.
4. Core retains source provenance through `SourceSpan` and `SourceFile`, without
   retaining syntax as semantic authority. Exact integer spelling remains in
   the source bytes; names are copied debugging/source spellings.
5. Core remains independent of LLVM and physical ABI representation. A future
   physical lowering stage may consume Core; Core must not depend on a backend.
6. Core is structured in this milestone. A function owns an ordered `CoreBlock`
   of statements; `CoreReturn` is a structured return operation.
7. CFG construction is a distinct downstream normalization stage. IR-1 introduces
   no basic blocks, edges, terminator abstraction, SSA, or reachability analysis.
8. Core verification checks internal compiler invariants. Its failures are
   internal errors, not ordinary source-language diagnostics. Deliberately
   malformed Core can be rejected without process assertions or aborts.
9. Core values are computed semantic values, not automatically Places or
   addressable storage. This milestone establishes no storage/ownership model.
10. Checked-to-Core construction does not optimize, even where simplification
    appears obvious. Unary `+`, literal arithmetic, association, and every
    sequential return survive construction.

## Rationale and implemented choices

Syntax records what the programmer wrote. The checked model records resolved
language meaning. Core records typed semantic computation for compiler
transformation and later lowering. The currently small computation subset gives
checked and Core trees similar shapes, but their identities and consumers differ:
Core parameter values refer directly to Core parameters, and Core has no token,
syntax-node, checked-node, or semantic-symbol fields. Parentheses have already
normalized away and do not reappear.

The builder first creates all function signatures, parameters, and empty body
containers, then translates bodies. Object-identity hash maps translate
`FunctionSymbol` to `CoreFunction` and `ParameterSymbol` to `CoreParameter`;
ordered arrays determine traversal, never hash-table iteration. This establishes
identities before bodies without nullable function bodies or partially defined
parameter references. The maps are destroyed on return from construction.

Parameter ownership is containment in exactly one function's parameter array.
The verifier builds a temporary ownership map to reject repeated declaration
slots and references into another function. A parameter-to-function strong
reference would add a reference-counting cycle without serving this subset, so
none is introduced. A parameter value derives its type from its parameter.

`PrefixOperator` and `BinaryOperator` move unchanged from `checked-nodes.vala` to
the semantic-owned `operators.vala`. Both layers share their language identities;
only semantic analysis translates token kinds. Core does not inspect source
spelling to resolve types, names, or operators.

Semantic types and source files survive through ordinary strong references from
Core nodes and spans. Core does not retain even the checked program's
`BuiltinTypes` container. A weak-reference regression proves frontend objects
are destroyed before Core verification, dumping, parameter use, and literal
source-location lookup; the retained type and source are then freed with Core.

The verifier traverses declarations first, then statement/value trees in source
order. It throws `CoreError.INVALID_IR` with deterministic structural paths.
Unsupported checked nodes or broken declaration mappings raise
`CoreError.INVALID_CHECKED_MODEL` during construction. The dumper verifies the
complete program before formatting and returns a complete string, preventing
partial output on invariant failure.

## Scope

See the [implemented Core model and operation inventory](../ir/core-ir.md).
This decision proves conversion of one checked program and its canonical type
identities. It does not settle multi-file linking, final whole-program structure,
future call identity, transformation APIs, or the representation of CFG/SSA.

There are no new source constructs, physical integer width/range or overflow
decisions, constant evaluation, Places, ownership operations, optimizations,
LLVM objects, or ABI classifications. Core and its tests use only the existing
host dependencies. LLVM linkage/symbol firewall tests also cover the Core test
executable. No backend or Vala/LLVM-v2 implementation source is incorporated.
