# ADR 0010: Boolean semantics and conditional control flow

Status: implemented in ASTRA-BRANCH-1, on accepted ASTRA-PLACE-1
`79356a807214d70ddf5f8464326c878a96eaab9b`.

## Decision

1. `bool` is a canonical Astra semantic type independent of physical width,
   memory/register representation, host types, or ABI. It is not C `_Bool`,
   Vala `bool`, or an LLVM integer type.
2. Conditions require semantic `bool`. Integers have no implicit truthiness;
   there are no implicit conversions.
3. `if` remains structured through the checked model and Core IR. `CoreIf`
   contains a condition, a then `CoreBlock`, and an optional else `CoreBlock`.
4. Structured conditionals lower to explicit Astra-owned CFG branches.
5. Terminators are the sole successor authority. `CfgBranch` has one target;
   `CfgConditionalBranch` has ordered true/false targets and a bool condition.
   `Return` and `FunctionEnd` still have no successors. Traversal arrays are
   snapshots, never a second mutable edge graph.
6. Every conditional has an explicit join block, even when both arms return.
7. Mutable Places are shared across branch paths. Exact declaration maps
   translate each LocalSymbol once; outer Places are never cloned per arm.
8. Branch lowering does not imply SSA. Stores on divergent paths and a load
   after the join remain explicit storage operations. There are no phi nodes,
   virtual registers, block arguments, dominance, or promotion.
9. Reachability follows entry identity and terminator edges, never source order,
   block ordering, or adjacency.
10. Constant-valued conditions are not folded during construction. Both edges
    remain structurally reachable, including for `if (true)` and `if (false)`.
11. `&&` and `||` remain deferred: conditional evaluation itself carries control
    flow semantics and needs a deliberate later lowering.
12. LLVM blocks and branches are not Astra CFG identity. Bool and branch nodes
    contain no LLVM or physical representation.

## Syntax and semantic authority

`true`, `false`, `if`, and `else` join `return` as syntax keywords. `bool`, like
`int` and `void`, remains an identifier resolved by the semantic type authority.
`!`, `<`, `<=`, `>`, `>=`, `==`, and `!=` are new operator tokens; maximal matching
keeps `=` distinct from `==`. Assignment remains a statement.

The grammar is `if (expression) block (else block)?`. Both arms require braces.
There is no special `else if`, unbraced arm, or standalone block statement.
Nested conditionals use ordinary branch blocks. A host nesting limit of 256
blocks, counting the function body, bounds recursive parsing and model traversal;
it is not a permanent source-language limit.

Prefix `+`/`-` and arithmetic consume/produce int; `!` consumes/produces bool.
Relational operators consume two ints and produce bool. Equality consumes two
values of the same supported non-void semantic type and produces bool. Semantic
operator enums own these rules, shared by the analyzer and standalone IR
verifiers. Precedence is prefix, multiplicative, additive, relational, equality;
all binary operators are left associative.

`BooleanLiteral.TRUE/FALSE` is a semantic truth-value payload. Checked, Core,
and CFG boolean nodes retain it separately from provenance and canonical bool
type identity. The host enum implementation makes no target representation
promise. Dumps print `true`/`false`, never a numeric bool encoding.

## Lexical scope and storage

Each function body and branch block has a lexical `ValueScope` frame whose
parent is the enclosing frame; parameters occupy the outer lookup frame.
Initializers are checked before insertion of their new LocalSymbol. A new local
cannot shadow a currently visible local or parameter in this milestone.
General shadowing policy remains deliberately undecided.

Sibling blocks can declare the same spelling because their frames are separate.
Each declaration receives a distinct LocalSymbol and one function-wide ordinal
in source traversal order: outer statements, then arm, else arm, continuation.
Branch locals are visible in subsequent statements and nested branches within
their own block, but neither in siblings nor after their block. Function-owned
local arrays establish downstream ownership; they do not establish visibility.
Assignments to visible outer locals bind to the exact same symbol. Parameter
assignment remains unsupported.

Core recursively preserves branch bodies and exact Place bindings. Its verifier
tracks unique initializations plus lexical availability in structured order,
removing branch declarations from availability when leaving their block. This
checks structural scope and initialization rules without definite-assignment,
reachability, or return-path analysis. CFG only counts one initialization per
local across its blocks; it makes no initialization inference from their order.

## Canonical lowering and block completion

Start with entry `#0`. At each CoreIf reserve, in order, the then block, optional
else block, and join block before descending into either arm. Nested allocations
follow those reservations. The current block ends in a ConditionalBranch to
then and else, or then and join if else is absent. Lower then, then else, then
continue source statements in the reserved join.

The recursive block lowerer receives the enclosing completion terminator. An
arm that reaches its end uses `Branch(join)`. A return completes its block with
`Return` and has no join edge. Later statements start a disconnected block.
Every reserved join is retained, including unreachable ones. At function end,
a remaining continuation gets `FunctionEnd`; an ordinary final return still
creates no extra trailing block.

Forward targets require identity before a terminator is known. Extending
`CfgBlock` with internal reservation and write-once completion is smaller than
introducing a parallel graph of pending labels/edges or reordering source
construction backward. The existing completed-block constructor remains.
Completion fixes the block span and terminator once; double completion fails,
and the verifier rejects incomplete blocks before graph consumers run.
Published builder results contain only completed blocks. Target references are
exact CfgBlocks, with ownership and successor consistency checked by the verifier.

## Flow, boundaries, and evidence

A reachable FunctionEnd is valid only for void. The existing worklist and flow
checker operate naturally over branches; bool returns use the same non-void
rule as int. Full-return arms leave an unreachable join and validate. A partial
return leaves a reachable join and fails, even with a constant true condition.
Constant propagation, unreachable-block deletion, and other optimization remain
future work.

See [conditional control flow](../ir/conditional-control-flow.md) and
`tests/branch/fixtures/` for mutable joins, full/partial returns, nested joins,
branch scope errors, bool Places, operator precedence, and post-return branches.
Core/CFG structural and weak-reference lifetime tests extend both standalone
LLVM-free representations. No dependency, ownership, loops, SSA, LLVM lowering,
ABI, physical bool representation, or copied Vala/LLVM-v2 implementation source
is introduced.
