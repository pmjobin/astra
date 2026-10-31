# Conditional control flow

Astra supports semantic booleans, integer comparisons, equality, and braced
`if`/`else` statements. The pipeline preserves structured source meaning through
Core, then constructs explicit CFG divergence and joins. See
[ADR 0010](../decisions/0010-conditional-control-flow.md).

## Language and checking

```astra
int choose(bool condition, int a, int b) {
	int x = 0;
	if (condition) {
		x = a;
	} else {
		x = b;
	}
	return x;
}
```

`bool` is an identifier resolved to one canonical `SemanticType(TypeKind.BOOL)`
per program. It specifies semantic identity only. `true` and `false` have bool
type and a `BooleanLiteral.TRUE/FALSE` payload, not integer spelling or an LLVM
constant. Width, ABI, memory, and register representation remain open.

Conditions must be bool. `if (1) {}` fails with
`if condition must have type 'bool', found 'int'`. Bool works in function returns,
parameters, initialized locals, assignments, and return expressions through the
existing generic type/Place machinery. Void remains return-only.

| Operator family | Operand types | Result | Parser power |
| --- | --- | --- | --- |
| Prefix `+`, `-` | int | int | 30 |
| Prefix `!` | bool | bool | 30 |
| `*`, `/`, `%` | int, int | int | 20 |
| `+`, `-` | int, int | int | 10 |
| `<`, `<=`, `>`, `>=` | int, int | bool | 5 |
| `==`, `!=` | matching int or matching bool | bool | 2 |

Binary operators associate left. `a + 1 < b * 2` compares the sum with the
product; `a < b == true` compares the bool result with true. No conversions,
operator overloads, or comparison folding occur. `=` is only statement-level
assignment. `&&`, `||`, bitwise operators, and conditional expressions are absent.

Both arms require braces. Omit else for a one-arm conditional; write a nested
`if` inside `else { ... }` for a subsequent condition. Standalone block statements
and special `else if` grammar are absent.

Each branch creates a lexical scope. Lookup follows current locals, enclosing
locals, then parameters. A local becomes visible after initializer checking.
No declaration may shadow a currently visible local or parameter. This is a
conservative current rule; general shadowing is undecided. Siblings may each
declare `x`, yielding different symbols and Places. Neither sibling's `x` escapes
its block. Ordinals increase across one function in source traversal order.

## Structured checked and Core representations

`CheckedIf(condition, then_body, else_body?)` retains typed checked expressions
and checked blocks, whose declarations/references keep exact LocalSymbol
identities. Lexical frames are analyzer machinery and do not become CFG nodes.

`CoreIf(condition, then_block, else_block?)` contains Core values and CoreBlocks.
Checked bool literals become `CoreBooleanValue`; comparisons and negation use
semantic operator enums. Each LocalSymbol maps exactly once to a CoreLocalPlace,
using object identity, not spelling. In the example, both stores and the return
load refer to local-place `#0`. Branch-local Places are still owned in the
function's deterministic local array; array ownership is distinct from visibility.

Core verification checks bool literals, operator typing, bool conditions,
structured blocks, lexical initialization order, and Place ownership/types.
It never computes reachability or definite return. Source provenance and semantic
types survive after syntax, checked nodes, and symbols die.

See the exact [checked](../../tests/branch/fixtures/choose.semantics) and
[Core](../../tests/branch/fixtures/choose.core) dumps.

## Explicit CFG and shared mutable storage

```text
block #0 reachable
	initialize local-place #0 = integer 0
	conditional-branch parameter #0 : bool -> true #1 / false #2
block #1 reachable
	store local-place #0 = parameter #1
	branch #3
block #2 reachable
	store local-place #0 = parameter #2
	branch #3
block #3 reachable
	return load local-place #0
```

This abbreviated view is frozen in the [mutable-join CFG golden](../../tests/branch/fixtures/choose.cfg).
Structural tests compare object identity: there is exactly one CfgLocalPlace,
both stores target it, and the join load reads it. CFG values/Places are distinct
from Core objects. No phi, path-specific storage, load forwarding, or conditional
expression substitutes for the stores and load.

`CfgBranch(target)` returns one successor. `CfgConditionalBranch(condition,
true_target, false_target)` returns exactly those two successors in that order.
The condition is a bool-typed CfgValue. Return and FunctionEnd return none.
Targets belong to the same function; successor snapshots cannot mutate edges.

Reservation order is entry, then, optional else, join. Each conditional reserves
its three (or two) blocks before descending into then and else. Lowering resumes
in the join. An arm that falls through gets Branch(join); an arm ending in return
keeps Return alone. Every join exists even if it has no reachable predecessors.
Internal block completion is write-once and verified before graph traversal.

For the [nested fixture](../../tests/branch/fixtures/nested.cfg), outer then/else/join
are `#1/#2/#3`, and inner then/else/join are `#4/#5/#6`. Inner join `#6` branches to
outer join `#3`. The final load in `#3` reads the same Place stored in `#2`, `#4`,
and `#5`. This ordering directly exercises graph traversal independent of array
adjacency. Post-return conditionals remain in disconnected, unreachable graphs.

## Reachability and completion

| Example | Join and result |
| --- | --- |
| Both arms return | Explicit unreachable join with FunctionEnd; non-void function validates |
| Only then returns, no else | False edge reaches join with FunctionEnd; non-void function fails |
| Both arms store, then final return | Reachable join loads the shared Place; validates |
| `if (true)` without else or later return | Both structural edges retained; non-void function fails |
| Void fallthrough | Reachable FunctionEnd is valid |

The [full-return golden](../../tests/branch/fixtures/choose-direct.cfg) retains
unreachable block `#3`. The [partial source](../../tests/branch/fixtures/partial.astra)
produces then `#1` and join `#2`; its false edge reaches FunctionEnd. `--check` and
`--dump-cfg`/`--dump-ssa`/`--dump-nabi`/`--dump-llvm` report `not all paths in function 'partial' return a value` with no
partial stdout. Syntax, semantic, and Core dumps still succeed for that program;
structural tests inspect its valid pre-flow CFG.

Reachability traverses terminator edges without evaluating conditions. CFG
construction/validation preserves unreachable joins and storage operations.
ASTRA-SSA-1 projects reachable blocks into [scalar SSA](ssa.md), where current
local storage becomes explicit reaching values and block arguments. The
[choose SSA golden](../../tests/ssa/fixtures/choose.ssa) has one argument for `x`,
supplied by `a` and `b` on the two incoming edges. Nested joins use the same
dominance-frontier and renaming machinery. Full-return SSA omits the unreachable
join; constant-condition SSA keeps both arms. Core and CFG remain unchanged.
There is no ownership, loop, or short-circuit lowering. LLVM-1 now realizes
verified SSA/NABI as physical i32/i1/void IR. Plain `astrac FILE` still reports
native object/executable emission unimplemented.

SSA block parameters become ordered LLVM phis; bool conditions and bool phis
are i1. Primary blocks exist before instructions. Trap-safe division/remainder
may add helper blocks, and outgoing phi predecessors use the actual physical
end block. Parallel conditional edges to one target use distinct synthetic
edge blocks, preserving distinct argument values without changing Astra SSA.
Choose and choose-call retain their arm structure and join phi. All modules
pass LLVM verification without optimization passes or a target machine. See
[LLVM scalar lowering](../backend/llvm-scalar-v0.md).

## Regression evidence

`tests/frontend/branches.vala` checks tokens, precedence, syntax/provenance,
malformed arms/conditions, truncation, and bounded nesting. Semantic tests check
canonical bool and lexical identities. Core and CFG tests check typed operations,
exact Places, branches/joins, returns, invalid graphs/values, and weak-reference
lifetime independence. The standalone targets construct bool/control flow using
only their own model and shared source/type/operator authority. The standalone
CFG graph deliberately executes against block ordering. Ldd/nm and optional
readelf checks retain the LLVM firewall; the backend smoke is the negative control.
