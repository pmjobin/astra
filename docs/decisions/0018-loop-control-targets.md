# ADR 0018: Exact loop-control targets

Status: accepted for ASTRA-LOOPCTRL-1.

## Context

LOOP-1 established structured while loops, ordinary cyclic CFG/SSA branches,
and LLVM physical end-block tracking. Break and continue introduce additional
backedges and exit predecessors. Their enclosing-loop meaning must survive
stage boundaries without turning lexical nesting into a second edge authority.

## Decision

1. `break;` exits exactly one resolved enclosing loop.
2. `continue;` begins the next condition evaluation of exactly one resolved
   enclosing loop; it never skips condition reevaluation.
3. Unlabeled break/continue resolve to the innermost enclosing while. Non-loop
   lexical scopes, including nested if arms, do not change the active target.
4. Semantic analysis resolves the target once using an explicit active-target
   stack. Empty-stack transfers are source errors at the keyword span.
5. Each CheckedWhile owns a CheckedLoopTarget object with keyword provenance
   and a deterministic zero-based function-local source-preorder ordinal.
   Object identity is authority; ordinal, depth, and source text are not identity.
6. Downstream stages translate exact identities through temporary maps. They
   never select targets by walking source parents, counting nesting, or guessing
   the nearest loop/block. Maps have construction-only lifetimes.
7. Core remains structured. CoreWhile owns its CoreLoopTarget; CoreBreak and
   CoreContinue retain explicit transfer semantics and exact Core targets.
8. Core verification checks unique target ownership, function-local ordinals,
   same-function membership, expiration, and that the supplied identity encloses
   the transfer. Its active identity set validates membership only; it does not
   select or rewrite a target. It performs no CFG reachability analysis.
9. CFG temporarily maps each CoreLoopTarget to its reserved header and exit
   before recursively lowering the body. Nested targets coexist in the map.
10. Break becomes an existing ordinary Branch to the mapped exit. Continue
    becomes an existing ordinary Branch to the mapped header. Neither CfgBreak
    nor CfgContinue, a special edge kind, a latch abstraction, nor a second
    successor authority is introduced.
11. Both transfers terminate their current source path. Following statements
    remain structured in checked/Core and survive in disconnected CFG blocks,
    consistently with LOOP-1's post-return policy. Disconnected structural
    backedges cannot make those tails reachable from function entry.
12. All new edges participate normally in reachability, predecessor ordering,
    dominance, frontiers, SSA block-argument placement, renaming, and LLVM phis.
    Multiple backedges and exit predecessors require no SSA special case.
13. Body-local definitions remain bounded by initialization-dominated
    availability. No undef, poison, zero, or false is fabricated to satisfy an
    unavailable value. Dead but available merges remain allowed; no pruned SSA
    or liveness pass is added for presentation.
14. Transfer references use GLib.WeakRef with owned nullable getters, so detached
    targets expire safely. Targets have no owning-loop/function backlink.
    Checked, Core, CFG, SSA, and LLVM remain independently reclaimable. Existing
    weak CFG/SSA successor ownership and LLVM physical end-block authority stay
    unchanged, including trap-split paths.
15. Labels, numeric/multi-level transfers, and transfer values remain future
    features. No grammar exposes an outer-loop selection. Semicolons are
    mandatory; break and continue are statements, never expressions.

## Alternatives and consequences

Nesting depth would be an unstable surrogate for the already resolved target.
Keeping exact identities makes nested-loop mistakes inspectable before CFG and
rejects foreign objects even when their display ordinals match. A strong
transfer-to-while link would form a While/Body/Transfer cycle; the established
GLib.WeakRef pattern avoids retention and raw weak-pointer expiration hazards.

Existing Branch terminators and disconnected continuation handling express both
transfers directly. Special loop-control CFG operations would duplicate graph
and SSA authority without solving a new problem. The existing generic frontier
and renaming algorithms handle all merge workloads, so they remain unchanged.
LLVM uses actual physical branch blocks for incoming phi entries, including
backend division/remainder continuations; no upstream backend identity appears.

The false edge remains structurally present even for `while (true)`. Break is
not a function return and does not satisfy non-void completion rules. Calls and
trap-capable operations before a transfer retain order; source-preserved calls
after it vanish only in the ordinary reachable SSA projection.

NABI, scalar, Place, call, execution, and optimizer architecture are unchanged.
There are no new dependencies or copied Vala/LLVM-v2 implementation sources.
See [language rules](../language/loop-control.md),
[cyclic IR](../ir/cyclic-control-flow.md), and
[qualification](../toolchain.md#astra-loopctrl-1-qualification).
