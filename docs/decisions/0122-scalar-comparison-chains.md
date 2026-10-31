# ADR 0122: ordered scalar comparison chains

Status: implemented; Surge 7 integrated qualification in progress.

Unparenthesized sequences of two or more `<`, `<=`, `>`, or `>=` operators form
one comparison chain. `a < b <= c` evaluates `a`, then `b`, compares them, and
evaluates `c` only if the first comparison succeeds. The middle value is captured
once and reused. Each operand occurrence is evaluated at most once, left to right.
Effects and checked errors retain that order. A failing comparison skips all
remaining runtime evaluations; every operand still undergoes static checking.

All operands must have one exact integer or floating scalar type. Existing scalar
literal context rules apply. There are no mixed-width/signedness promotions,
vector-mask conversions, pointer chains, or generic numeric capability extensions.
Ordered floating comparisons retain IEEE NaN behavior and strict FP lowering.
Equality and inequality keep their binary precedence and associativity. Explicit
parentheses retain ordinary binary semantics: `(a < b) < c` still rejects because
the left operand of the outer comparison is bool.

Syntax, Checked, and Core carry an ordered operand/operator list. Core independently
checks arity, exact scalar typing, relational operators, and unique operand-node
occurrences. Checked and Core ownership proofs model each operand after the first
two as conditionally evaluated; optional evaluations cannot establish constructor
field initialization on all paths. Constant dependency checking visits every
operand, while constant evaluation short-circuits exactly like native evaluation.

CFG lowering captures each reached operand in an immutable evaluation event,
branches to the next operand only after success, and joins a scalar bool temporary.
SSA promotion and the existing native ABI/LLVM verifiers consume ordinary typed
scalar comparisons, branches, and phis. No runtime helper or new C ABI is involved.
Mutation tests reject duplicate Checked/Core operand occurrences, wrong operators,
lost arity, repeated CFG evaluation definitions, and repeated SSA definitions,
then restore the original valid model. Invalid models never execute.

The public witness combines effect counters, a four-operand chain, both ordering
directions, a loop condition, NaN/infinity, skipped and throwing calls, constant
chains, and a skipped constant division by zero. Dedicated refusals retain vector,
bool, mixed scalar types, moved ownership, explicit parentheses, and static checking
of skipped source. Tests run at O0/O1/O2 with unsuppressed Valgrind.

With explicit user approval, the historical frontend relational-associativity
expectation now describes the chain node, and the old semantic rejection of
`1 < 2 < 3` is replaced by the still-invalid `(1 < 2) < 3` control.
U3 remains open until bounded `with` receiver scopes are also implemented.
