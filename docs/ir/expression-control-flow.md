# Expression control flow

Short-circuiting is Astra's first expression normalization that changes the
enclosing CFG continuation. [ADR 0019](../decisions/0019-short-circuit-expression-control.md)
freezes the contract. The [AND source](../../tests/shortcircuit/fixtures/logical-and.astra)
has [semantics](../../tests/shortcircuit/fixtures/logical-and.semantics),
[Core](../../tests/shortcircuit/fixtures/logical-and.core),
[CFG](../../tests/shortcircuit/fixtures/logical-and.cfg),
[SSA](../../tests/shortcircuit/fixtures/logical-and.ssa), and
[LLVM](../../tests/shortcircuit/fixtures/logical-and.ll) goldens.

| Stage | Representation | Evaluation/result authority |
| --- | --- | --- |
| Syntax | ShortCircuitExpressionSyntax | Token plus left-associative children |
| Checked | CheckedShortCircuitExpression | ShortCircuitOperator AND/OR; exact bool types |
| Core | CoreShortCircuitValue | Structured conditional RHS; independent provenance |
| CFG | Branch/ConditionalBranch + CfgTemporaryPlace | Initialize default; RHS Store; join Load |
| SSA | Ordinary block parameter and edge arguments | Generic scalar Place promotion |
| LLVM | br i1 + phi i1 | Existing backend physical-edge lowering |

For each operator the CFG builder:

1. Reserves evaluation entry E, terminates current with Branch(E), and enters E.
2. Lowers the left completely, following any nested continuation and preserving
   calls/traps before the decision.
3. Allocates a function-owned bool temporary T at the next temporary ordinal,
   then Initialize(T, false) for AND or Initialize(T, true) for OR.
4. Reserves RHS R and join J. AND selects R on true and J on false; OR selects J
   on true and R on false.
5. Enters R, lowers the entire RHS, Store(T, result), then Branch(J).
6. Enters J and returns Load(T) to the enclosing expression/statement lowering.

The mutable builder `current` is the sole continuation authority. Recursive
statement lowering resets it to each reserved arm; if/while conditions branch
from the final expression join, with no source-condition fusion. Source-local
initialization and assignment follow the completed expression. Multiple arguments
traverse left-to-right through their respective joins before the consuming call.

```text
entry -> evaluation
evaluation:
	initialize temporary #0 = false
	conditional a -> rhs, join
rhs:
	store temporary #0 = b
	branch join
join:
	return load temporary #0
```

Temporary Places contain only a deterministic ordinal, semantic type, and span.
They have neither LocalSymbol nor invented source spelling. The function's
separate `temporaries` array owns them; instruction/value references share exact
object identity, without parent references. Each nested operator gets a distinct
Place even when type or provenance matches. Allocation follows actual lowering
order: nested-left temporaries precede the enclosing operator's temporary.

Generic promotion enumerates source locals first and temporaries second, each in
ordinal order. One PlaceDefinitions algorithm gathers Initialize/Store sites,
places parameters on iterated dominance frontiers inside the initialization's
dominated region, and renames definitions/loads/edge arguments. The builder's
block-parameter-to-Place map preserves exact object identity. Completed SSA keeps
only copied source-local or synthetic `temporary #N` debug origins. No Place,
Initialize, Store, Load, or logical-specific instruction remains in SSA.

For AND, J receives false from the decision edge and b from R. For OR, it
receives true from the decision edge and b from R. Nested/chained expressions
use the same recursion and independently discovered merges, without flattening,
reassociation, manual phis, or liveness pruning.

The [loop source](../../tests/shortcircuit/fixtures/loop-short.astra) and
[loop SSA](../../tests/shortcircuit/fixtures/loop-short.ssa) show why E is separate:
the original while header H branches to E, and ordinary backedges/continue still
target H. The initialization block dominates J but does not dominate H. The
existing availability restriction therefore promotes i at H and T at J, without
asking either the loop preheader or backedge for a fictitious T. Break transfers
independently to the original exit and carries real local values there.

Earlier call/evaluation results can be consumed after a later expression splits
the block. CFG verification requires an earlier same-block definition or a
definition on every incoming path. It checks path reachability with the defining
block removed, including disconnected source roots, without introducing CFG
phis or relocating SSA dominance/frontiers. Cross-function, sibling-only,
disconnected, self, and forward uses remain invalid. Trap-capable earlier trees
use the existing CfgEvaluateInstruction before any later call or control region.

LLVM receives only ordinary SSA. Its branch and phi lowering requires no source
logical handling and emits no eager logical and/or. Existing division guards
retain their internal overflow conjunction. In the
[trap golden](../../tests/shortcircuit/fixtures/trap-short.ll), the bool result phi
names the final `.continue` block, after the guarded division/remainder, as its
incoming predecessor. Both traps and calls reside solely in their required RHS
regions. All goldens are verified modules, without an optimization pass.

Weak successor references preserve cyclic ownership safety. Stage tests release
syntax/checked nodes before Core, Core before CFG, all generated Places/blocks
before SSA, and SSA/NABI before LLVM. Standalone CFG builds a temporary/branch/
join directly; standalone SSA builds the bool join with no knowledge of source
logical syntax. Neither links LLVM. No new dependency, NABI change, constant
folding, undef/poison, or ownership semantics are introduced.
