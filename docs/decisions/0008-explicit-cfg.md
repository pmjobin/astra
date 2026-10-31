# ADR 0008: Explicit control-flow graph

Status: accepted in ASTRA-CFG-1, on the accepted ASTRA-IR-1 foundation.

## Decision

1. Astra owns an explicit CFG representation independent of LLVM.
2. CFG construction consumes verified Core IR, never syntax. The boundary is
   `CfgBuilder.build(CoreProgram)`, which verifies its input before conversion.
3. Functions, parameters, basic blocks, values, and terminators acquire CFG-owned
   identity. Core nodes and semantic symbols are not downstream identity.
4. Every completed block has exactly one terminator. The block constructor
   requires it, and the property cannot be replaced through the public API.
5. Explicit source `return` becomes a `CfgReturn` terminator.
6. Reaching a structured function body's end becomes `CfgFunctionEnd` before
   completion validity is decided. It remains distinct from explicit return.
7. Reachability is graph analysis from the designated entry through terminator
   successors; source order and block ordinals do not imply edges.
8. Unreachable blocks are initially preserved, without unreachable-code warnings.
9. Definite-return validation belongs to the control-flow layer, where reachable
   paths are known. It is separate from Core and CFG structural verification.
10. CFG construction is normalization, not optimization. Computations, spelling,
    and post-return source statements survive without simplification.
11. CFG is independent of LLVM basic blocks, physical integer representation,
    storage, and ABI details.
12. Add successor-bearing terminators only when source syntax requires them.
    CFG-1 contains no placeholder unconditional/conditional branch kinds.

## Representation and construction choices

`CfgProgram` owns functions in source order. Functions own ordered parameters,
ordered blocks, and an explicit entry reference. Object identity determines
binding and containment; zero-based function, parameter, and block ordinals
provide stable dump IDs. Parameter and block ordinals are scoped to a function.
Names are copied source/debugging strings. There are no parent reference cycles.

Construction translates one function at a time. There are no function references
in the current value language, so a function identity map or preliminary global
declaration pass would serve no current consumer. A temporary object-identity
map translates each function's Core parameters to its exact CFG parameters.
The map is cleared between functions and destroyed with the builder.

The pending entry block is numbered zero. The only current Core statements are
returns, so each statement finishes a block immediately. The builder translates
its optional value and creates the block with that return terminator. A later
statement starts the next disconnected block. An empty body completes the
pending entry with `FunctionEnd`; a final explicit return needs no extra block.
This is equivalent to starting an unterminated entry and filling its terminator,
but publishing only completed blocks makes missing/double terminators impossible
through the normal constructor API. No mutable construction API is needed yet.

`CfgTerminator.successors()` is the sole edge authority. Both current kinds
return empty traversal snapshots. There is no independent stored edge list.
The verifier checks successor ownership as well as the absence of successors
for the current terminators. The iterative reachability worklist uses only the
designated entry and this interface, with an object-identity visited set.
Its result is separate from blocks and must be recomputed after graph edits.

Nested integer, parameter, prefix, and binary values retain the existing semantic
types/operators and exact source spans. They introduce no SSA temporaries or
storage operations. Completed CFG nodes have no Core, checked, symbol, syntax,
or token fields. Shared `SemanticType` and `SourceFile` authorities survive
independently through CFG references.

## Validation and stage policy

Structural defects raise deterministic `CfgError` internal errors. Missing value
returns and wrong parameter ownership are structural defects; a reachable
`FunctionEnd` in an `int` function is a structurally valid representation of an
invalid source program. `CfgFlowChecker` returns a normal source `Diagnostic`
at the function name for that case. Reachable void completion is valid.

Semantic analysis still answers whether individual declarations, expressions,
and returns are meaningful. Core still preserves ordered computation. Therefore
an empty `int` function remains valid for these earlier stages, and both
`--dump-semantics` and `--dump-core` succeed. `--check` now runs every implemented
validation stage through flow checking. `--dump-cfg` uses that complete pipeline
before emitting any output. Source errors exit 1; incorrect CLI usage exits 2.
Plain source compilation remains unimplemented.

## Evidence and scope

See the [CFG inventory, algorithms, and tests](../ir/cfg.md). Tests retain both
sequential returns, distinguish return from function end, exercise malformed CFG,
and use weak references to prove destruction of Core and earlier models before
verification, analysis, dumping, and huge-literal/source-location inspection.
A standalone Meson target compiles the completed CFG representation with only
source provenance, diagnostics, and semantic types/operators; no Core or backend
sources are available. Linkage tests cover both CFG executables and the driver.

No source syntax, semantic analysis, or Core implementation is redesigned.
There are no new dependencies, branch operations, unreachable-code diagnostics,
optimizations, SSA/dominance, Places, ownership operations, or physical lowering.
