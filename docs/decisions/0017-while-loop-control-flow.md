# ADR 0017: While loop control flow

Status: accepted for ASTRA-LOOP-1.

## Context

ASTRA-EXEC-1 qualifies scalar source through native execution. A pre-test loop
introduces the first source-generated CFG cycles and loop-carried scalar values.
The existing branch terminators, graph analyses, SSA block arguments, and LLVM
phi realization must handle these cycles without a second loop dataflow model.

## Decision

1. `while` is structured language and Core control flow. Its grammar is
   `"while" "(" expression ")" block`; braces are mandatory.
2. The condition executes before every attempted iteration, including the
   first. Its established left-to-right operand, call, and trap order applies
   on every evaluation. Neither condition hoisting nor caching is permitted.
3. Conditions require semantic bool, without integer truthiness or conversion.
4. The body introduces one lexical child scope. Initializers are checked before
   their new local becomes visible. Locals do not escape; declarations cannot
   shadow visible locals or parameters under the current conservative policy.
5. `CheckedWhile` contains a checked bool expression and checked block;
   `CoreWhile` contains a CoreValue, CoreBlock, and source provenance.
   Neither contains labels, CFG blocks, or backend identities.
6. Each local declaration maps to one exact function-owned Place per stage.
   Outer condition/body/continuation references share that Place. A body-local
   has one declaration identity whose initialization executes on each visit;
   function ownership does not confer visibility outside its lexical scope.
7. CFG lowering reserves header, body, and exit, in that order, before lowering
   nested body structure. The current block acts as preheader. It branches to
   the header, whose freshly evaluated condition branches to body or exit.
8. Body fallthrough branches to the header. A backedge is an ordinary
   `CfgBranch`, with no new terminator kind or separate graph.
9. Terminators remain the sole successor authority. Returns have no successor.
   Disconnected source statements after a return remain disconnected even if
   they receive a structural continuation to a header.
10. Reachability, predecessors, dominance, frontiers, placement, renaming,
    verification, and dumping must terminate on cyclic graphs. Analyses
    consume generic graphs, with no source-specific loop cases.
11. Loop-carried state uses existing `SsaBlockParameter` values and ordered
    predecessor edge arguments. Iterated dominance frontiers discover header
    parameters, including header self-frontiers; no loop-phi abstraction exists.
12. A Place whose initialization does not dominate a candidate header must not
    acquire a fictitious value there. Initialization-dominated availability
    remains distinct from liveness or pruned SSA.
13. Astra never invents undef, poison, zero, or another arbitrary value to repair
    missing reaching definitions. Valid loop loads must have real definitions.
14. `while` implies no constant-condition folding. Both literal true and false
    conditions retain both CFG edges. A non-void function with only a returning
    loop body still fails flow checking through its reachable FunctionEnd.
15. Function arrays own CFG/SSA blocks. Terminator successor references are
    non-owning, expiring `GLib.WeakRef` references, so topology creates no
    strong ownership cycle. Detached expired targets are invalid.
16. LLVM loop phis remain backend realizations of ordinary Astra block
    arguments. Incoming predecessors are actual physical end blocks, including
    division/remainder continuations. No loop-specific backend operation exists.
17. Loop correctness requires no optimizer. There is no loop optimization,
    liveness pass, NABI change, runtime support, or new dependency.
18. LOOP-1 adds no break, continue, for, foreach, do/while, or short-circuit
    operators. Only `while` becomes a new keyword; break/continue stay identifiers.

## Alternatives and consequences

Manual discovery of mutated locals from CoreWhile would duplicate CFG dataflow
and miss the intended proof of generic promotion. Existing iterated frontiers
and dominator-tree renaming already provide the required initial/backedge values.
Body locals remain outside outer headers using the existing initialization
dominance restriction; neither liveness nor fabricated values is needed.

Strong CFG successor references would retain the first real loop forever.
Function ownership plus WeakRef edges follows the existing non-owning callee
pattern. The lifetime audit also exposed SSA's raw Vala `weak` target: it avoided
retention but did not clear when a detached target died. A failing retained-edge
regression and inspection of generated C established that defect; WeakRef
corrects it without changing SSA graph or value semantics.

The existing CFG continuation mechanism preserves disconnected blocks after
returns. Keeping it avoids a separate source-level reachability computation;
generic reachability excludes their structural backedges from SSA predecessors.
The regression includes both a direct return and an if with two returning arms.

See [language loops](../language/loops.md), [cyclic IR](../ir/cyclic-control-flow.md),
and [qualification](../toolchain.md#astra-loop-1-qualification).
