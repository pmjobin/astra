# Constant evaluation boundary

CONST-1 adds four compiler authorities: shared declaration syntax,
`ConstantSymbol`/`ConstantValue`, semantic dependency/subset checking, and
`ConstantEvaluator` with `ConstantFloat`. They terminate before executable Core.

`ConstantDeclarationSyntax` appears in unit or statement position. Explicit types
use ordinary TypeNameSyntax subclasses. ArrayTypeSyntax holds a parsed expression
for its extent; empty brackets continue through SliceTypeSyntax. Neither parser
nor lexer performs lookup. SyntaxProgram adds a separate constant queue without
renumbering existing function/type queues.

A ConstantSymbol owns its exact declaration, source spans, optional lexical region
(null means program scope), state and final value. It has no LocalSymbol, Place or
storage ordinal. ValueScope lookup selects exact symbols; CheckedConstantReference
retains that identity and type instead of masquerading as fresh literal syntax.
Ordinary numeric-context inspection can observe the fixed type, exactly as it can
for a typed runtime binding. Generic inference uses the existing checked argument
path and unchanged specialization keys.

Top-level collection occurs after existing type/callable signature collection and
before bodies. The complete constant queue is installed in one scope. A closed
syntax walk checks subset eligibility, resolves references, and collects edges
for **both** boolean operands. Edges retain indices and source spans, avoiding
owning symbol cycles. Explicit DFS frames and collected/visiting/completed states
make arbitrary finite dependency graph depth independent of the host stack.
Completed symbols are evaluated once. Source-order roots and written-order edges
make diagnostics deterministic; hash tables are lookup-only. Invalid graphs fail
the compilation and never escape as a checked program. No process-global state is
used. Expression recursion retains the parser's deterministic 256-depth protection.

Local constant initializers are checked before insertion into the current scope.
They share the same closed-subset walk and ordinary expression checker used for
top-level constants and array bounds. Ordinary operators and conversion capability
authorities remain the only type/operator tables. Within a constant expression,
shift-count value validity is deferred from literal checking to evaluation, so a
skipped validly typed shift can remain unevaluated. This does not change ordinary
runtime expression checking.

After static checking, ConstantEvaluator traverses bounded typed expressions with
left-to-right lazy boolean evaluation. References are memoized leaves. Exact
integer operations reuse AstraIntegerValue (including modulo conversions, division
boundary behavior and explicit sign fill). Existing BinaryFloatValue owns exact
bits, decimal parsing, unary transport and cross-format conversion.

## Missing value operations and their implementation

The accepted baseline already had exact integer parsing, wrapping arithmetic,
bitwise/shift/comparison/division/remainder, integer conversions, exact decimal
floating parsing, unary float sign operations and cross-format float conversion.
It had scalar numeric conversion *capabilities* and backend lowering, but no
compiler value implementation for integer↔float conversion or float arithmetic /
comparison. Exact decimal parsing alone did not supply those operations.

ConstantFloat adds exact dyadic/rational addition, subtraction, multiplication and
division using compiler-private unsigned 32-bit limbs with uint64 intermediates.
A product limb plus destination limb plus carry never exceeds uint64. Inputs are
bounded by the existing two floating formats and six integer types; the workspace
needs at most 3,227 bits, and shifts assert the internal 4,096-bit bound. This is
not a general source-sized bignum facility or runtime dependency.

Each operation compares its exact rational result to adjacent representable
midpoints, selecting nearest/ties-even from the shared format description.
Overflow, underflow, signed-zero and special-value decisions use the same masks,
biases, precision and subnormal limits as BinaryFloatValue. The independent test
oracle uses Python Fraction quotient/remainder quantization, a different algorithm.
There is no host float, strtod/strtof, dynamic rounding mode, libm or LLVM evaluator.

New arithmetic NaNs deterministically use the positive quiet representative with
only the quiet payload bit. This is an internal compiler choice; runtime NaN
arithmetic is tested by classification. Every specified finite and zero result is
tested by exact bits. Existing unary NaN transport/sign and conversion policies
remain authoritative. Integer-to-float uses the same rational rounding routine;
float-to-integer extracts integer bits, truncates and checks range before any host
cast. Invalid required integer operations/conversions produce source diagnostics.

## Erasure and downstream independence

CheckedConstantDeclaration retains metadata, and CheckedConstantReference retains
exact symbol identity. The Core builder skips declarations and replaces references
with the precomputed ordinary Checked scalar leaf at the use span, immediately
building existing Core scalar values. It performs no evaluation. Array extents
already form ordinary exact ArrayTypes. No Core/CFG/SSA evaluator, runtime global,
constant initializer, dependency table, owner flag, ABI channel or backend numeric
operation is added.

Core and subsequent verifiers operate after syntax, analyzer, evaluator, constant
symbols and checked graphs are destroyed. Only the existing stage-neutral exact
scalar value/type and source-provenance authorities survive as needed. Ordinary
program dumps remain unchanged. Named-versus-expanded equivalence compares final
executable Core/instances/CFG/SSA/NABI/CABI/LLVM, excluding syntax/semantic declaration
metadata and spans; expansions use already-rounded, exact, type-correct values.

Symbolic type-dependent constants, generic values, user-function CTFE, aggregates,
vector dimensions and runtime immutable bindings require separate decisions and
are not inferred from this representation.

## TEXT-1 immutable content

String is the sole additional constant type. TextBytes is one immutable, explicit
byte-content authority shared by decoded literal leaves and the evaluator's text
equality/length operations. Text expressions produce values only from literals,
constant references and parentheses. Their int/bool results enter the existing
scalar evaluator; no second numerical evaluator or downstream source decoder is
introduced. Declarations erase, while used bytes can remain private runtime data.
[Text IR](../ir/text-values.md) owns stage membership and independent validity checks.
