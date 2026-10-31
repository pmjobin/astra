# Cyclic control flow

ASTRA-LOOP-1 carries structured while loops through the existing scalar compiler
pipeline. ASTRA-LOOPCTRL-1 adds exact structured break/continue targets and
ordinary branch edges; [ADR 0018](../decisions/0018-loop-control-targets.md) freezes
that extension. [ADR 0017](../decisions/0017-while-loop-control-flow.md) freezes the
boundary; [language loops](../language/loops.md) describes source behavior.

## Structured stages and Places

`WhileStatementSyntax` retains keyword/parenthesis tokens, condition, braced
body, and source spans. `CheckedWhile(target, condition, body)` uses the surrounding
scope for the bool condition and a child scope for its CheckedBlockStatement.
Exact LocalSymbols resolve all uses; no graph identities enter checked semantics.

`CoreWhile(target, condition, body)` remains a structured statement. Its CoreValue is
evaluated on every attempted iteration; a stored expression tree does not mean
its result is cached. Function-wide symbol-to-Place mapping preserves one
CoreLocalPlace per declaration. Body-local initialization remains in the body.
Core verification checks bool, nested structure, initialization availability,
function-owned Places, scalar operations, and calls. It does no reachability,
dominance, backedge, or completion analysis.

## CFG construction and source preservation

For each CoreWhile, reserve three blocks in order: header, body, exit. Nested
allocations follow those reserved slots; ordinal adjacency never defines edges.
The previously current block is the preheader:

```text
preheader ──branch──→ header ──false──→ exit → source continuation
                        │
                       true
                        ↓
                       body
                        └──ordinary branch──→ header
```

Build the condition's value/instruction stream in the header, preserving existing
call/trap order, and complete it with CfgConditionalBranch(body, exit). Lower
the body recursively with CfgBranch(header) as its enclosing continuation.
Return ignores that continuation. Continue lowering subsequent outer statements
at the reserved exit. No dedicated preheader or new terminator is necessary.

The existing builder starts disconnected blocks after a return. A disconnected
body tail can receive a structural branch to the header but has no path from
entry. It therefore remains unreachable and contributes no reachable predecessor
or definition. The same applies to a join after two returning if arms. Loops
after a function return remain entirely disconnected. Tests preserve all of
these structures in CFG and omit them in SSA.

Both conditional successors remain even for literal conditions. Iterative
reachability marks before queuing, so revisiting a backedge terminates. A
reachable FunctionEnd remains the only non-void completion failure authority.

## Dominance and promotion

For flagship count, blocks are b0 entry, b1 header, b2 body, b3 exit:

| Block | Reachable predecessors | Dominators | Immediate dominator | Frontier |
| --- | --- | --- | --- | --- |
| b0 | none | b0 | none | empty |
| b1 | b0, b2 | b0, b1 | b0 | b1 |
| b2 | b1 | b0, b1, b2 | b1 | b1 |
| b3 | b1 | b0, b1, b3 | b1 | empty |

Predecessors follow source block ordinal order, with true before false for
parallel edges from one terminator. Unreachable sources are excluded. Generic
dominator fixed-point intersection and the mathematical frontier definition
produce b1's self-frontier without a source-loop case.

The ordinary initialization/store definition worklist places one header
SsaBlockParameter for `i`. Renaming traverses the acyclic dominator tree, not
CFG successors. Header entry pushes the merged value before condition/body/exit
uses; body stores push the updated value before constructing backedge arguments:

```text
b0: branch b1(0)
b1(%i): %condition = %i < %n; conditional-branch %condition b2 / b3
b2: %next = %i + 1; branch b1(%next)
b3: return %i
```

There are no Places, Load, Store, or Initialize operations in SSA. For
`accumulate`, header parameters follow local ordinals: i, sum. Both predecessor
argument arrays use that order even though the body updates sum before i.
Bool carried state uses the same block-parameter rules and becomes B1 downstream.

An initialization must dominate a placement candidate. Body-local `next`
therefore receives no outer header parameter. Nested count reserves b1/b2/b3
for the outer loop and b4/b5/b6 for the inner loop. Outer parameters are
(outer, total); inner parameters are (total, inner). Inner entry receives the
outer total and zero inner; inner exit b6 sends its current total and incremented
outer back to b1. The inner declaration never acquires an outer header value.

Placement uses finite queued/placed sets. Reachability and predecessor discovery
use visited sets; dominance descends to a fixed point; frontier computation is
a finite matrix scan. Renaming recurses only over the dominator tree. The
independent SSA verifier uses visited path-exclusion traversals for dominance,
and dumpers iterate block arrays. No algorithm recursively follows unguarded
cyclic successors. No liveness/pruned SSA, undef/poison, or loop-specific value
class is required.

## Ownership

Function arrays own blocks; terminators own edge semantics, not successor block
lifetimes. CFG branches/conditionals and SSA edges hold GLib.WeakRef targets.
Expired targets fail existing verifier target/count checks before traversal.
Fresh successor snapshots temporarily retain blocks without becoming a second
edge authority. SSA values retain definitions without backlinks to instructions
or blocks, so cyclic dataflow also avoids strong ownership cycles.

Standalone Core/CFG/SSA tests exercise construction, verification, dumping, and
reclamation without upstream builders or LLVM. Source-stage lifetime tests
release syntax/checked models before Core consumption, Core before CFG
consumption, and every cyclic CFG block before SSA consumption. LLVM and native
artifact tests release SSA/NABI before using the surviving backend artifacts.
Stable weak probes cover headers, bodies, exits, parameters, and results.

## LLVM and execution

NABI signatures are unchanged. LLVM first creates all primary blocks and phis,
then lowers instructions/terminators using a visited graph traversal. Block
parameters are already mapped when condition instructions consume them.
Preheader/backedge terminators attach incoming values to the ordinary phis.

When division/remainder splits a body, its physical continuation executes the
backedge. The header phi's incoming predecessor is that continuation, not the
primary body block. If the header splits, its guard still executes on every
header entry; the condition branch moves to its physical continuation. Ordered
condition calls execute after prior trap guards and before the condition branch.

Every accepted module verifies. Wrapping operations retain no nsw/nuw flags.
Native tests cover zero/one/10,000 iterations, accumulation, body locals, bool,
condition/body calls, nested dimensions, early returns, and repeated condition
traps. A 144-case iterative recurrence compares native results against
AstraIntValue wrapping arithmetic. No optimizer or runtime library is needed.
See [toolchain qualification](../toolchain.md#astra-loop-1-qualification).

## Exact control targets and multiple edges

Semantic analysis creates a CheckedLoopTarget for each while and resolves each
break/continue to the top of a temporary active stack. CoreBuilder maps exact
checked targets to independent CoreLoopTargets; CfgBuilder maps those exact
Core targets to headers/exits. While statements own their structured targets;
transfers use expiring GLib.WeakRef references. Neither map survives its builder.

For continue-merge, the existing diamond allocation yields:

| Block | Role | Reachable predecessors | Frontier |
| --- | --- | --- | --- |
| b1 | header | b0, b4, b5 | b1 |
| b4 | continue arm, x = 10 | b2 | b1 |
| b5 | fallthrough, x = 20 | b2 | b1 |

For break-merge, b4 branches to exit b3 and b5 branches to header b1. Exit
predecessors are b1 and b4; its immediate dominator is b1, not body b2.
DF(b4) is {b3}; DF(b2) is {b1, b3}. Iterated frontiers therefore discover
both header and exit parameters with ordinary edge values. No manual loop
merge placement is needed. Multiple-sites expands to four header and three
exit predecessors; nested control retains distinct inner/outer branches.

Direct transfers and two terminating if arms leave subsequent source tails
unreachable even when those tails contain nested loops. They stay visible in
CFG and disappear through generic reachable SSA projection. Calls before the
transfer remain ordered. Trap-split transfers use the physical final block
for LLVM phi incoming entries, preserving exact incoming values at both merges.
See [loop-control rules](../language/loop-control.md) and
[qualification](../toolchain.md#astra-loopctrl-1-qualification).

## Short-circuit evaluation regions

The original while header H branches to a fresh expression entry E for each
short-circuit operator. Nested lowering may split E before the operator initializes
its bool temporary. That initialization dominates the expression join, but not H;
generic promotion therefore excludes fictitious header parameters for temporaries.
Continue still branches to H, break to the exact exit. Both operands are statically
checked; only the required RHS executes at runtime. All new successor references
use the existing WeakRef architecture. Cyclic stage-lifetime and native execution
tests cover generated Places and joins. See
[the loop SSA golden](../../tests/shortcircuit/fixtures/loop-short.ssa).
