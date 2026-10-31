# One source program

DIAG-1 caller completion inspects owned SourceFile bytes through the original
argument spans and called-name token. Parenthesized syntax retains its boundary,
so no rewritten expression is used as a source oracle. Generated TextBytes own
their payload independently of spans, syntax, semantic symbols and SourceSets;
declaration contracts erase at the semantic-to-Core boundary. Generic definition
provenance is captured before specialization, while explicit forwarding is an
ordinary value flow. See [caller information](../language/caller-information.md).

CONST-1 adds a separate canonical constant declaration queue. It preserves old
function/type queues and ordinals. Constants join value lookup, support cross-file
forward dependencies and finish evaluation before bodies lower to executable Core.
Their names and source paths provide provenance, never runtime identity. See
[constant evaluation](constant-evaluation.md).

`Source.SourceSet` owns ordered `SourceFile` objects. Each object provides stable
compilation-local identity, normalized user-facing path, original bytes and a
per-file line-start index. Identity is provenance, not a semantic type.
`Syntax.SyntaxProgram` composes `CompilationUnitSyntax[]`; the existing compilation
unit is the per-file SourceUnit equivalent. Its function/type arrays reference
original syntax nodes and retain their exact SourceSpan. It has no cross-file
covering span: the first unit supplies only a fallback program diagnostic anchor.

The driver validates and orders input names before I/O, reads each separately,
then calls `SyntaxProgram.parse`. That method calls `Parser.parse(file)` once per
SourceFile, stopping at the first diagnostic in canonical order. It preserves
UTF-8/NUL rules and independent line numbering. The standalone constructor also
composes already-parsed units and rejects duplicate normalized input identities.

`SemanticAnalyzer.analyze_program` uses the existing global analyzer tables. The
single-file `analyze` wrapper delegates with one unit. Its collection sequence is:

1. Load unchanged VAPI handles and collect all native nominal/generic names.
2. Resolve field types, reject layout cycles and collect every member signature.
3. Collect every free-function signature and merge existing foreign declarations.
4. Collect constant symbols and all initializer dependencies, then evaluate the
   cycle-checked graph into memoized exact scalar values.
5. Check free functions, methods, lifecycle members and accessors using exact
   globally registered targets and established deterministic per-kind queues.

Source path byte order (`strcmp`, not locale collation) and within-file declaration
order stabilize each queue. Generic/struct/class category precedence remains the
accepted baseline authority. Thus no single-file ordinal or canonical downstream
dump needs a wrapper. Invalid source sets select the same failure under all input
permutations. Cross-file duplicate diagnostics include the previous name span.

There is one CheckedProgram. Its spans retain SourceFile objects independently of
syntax. CoreBuilder maps exact semantic identities to independent Core identities;
all later builders follow existing mappings and verification. No backend depends
on SourceSet or SyntaxProgram, and no stage looks up declarations by path. The
generic registry keys remain exact definition/type-argument identities. Caller
paths do not participate. NABI/CABI remain source-independent physical plans.

The driver releases SyntaxProgram after checking and Checked after Core building.
Existing provenance spans own SourceFile byte/line metadata until their final use;
no source set retains them globally and no file retains a parse tree. Weak-reference
tests with three to five units destroy syntax, Checked, Core, CFG, SSA and ABI
predecessors and verify the next independent stage. The final LLVM artifact survives
destruction of every source object.

One LLVM lowering and one native emission process the complete function universe.
Target requirements aggregate over that program once. A buffer allocation anywhere
selects the existing hosted allocator qualification; merely splitting scalar code
does not. There is no per-source object, Astra link phase, runtime filename table,
module initialization or new runtime symbol.

See [ADR 0069](../decisions/0069-multi-source-compilation.md),
[language](../language/source-files.md), and validation.
