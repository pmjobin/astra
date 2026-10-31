# ADR 0011: Scalar SSA with block arguments

Status: implemented in ASTRA-SSA-1, on accepted ASTRA-BRANCH-1
`c936f686faa182596a59e5b156aac2387781f57c`.

## Decision

1. SSA is a distinct Astra-owned representation downstream of structurally
   verified, reachable-flow-valid CFG. Core and CFG retain explicit Places,
   Loads, Initialize, and Store operations.
2. SSA projects graph-reachable CFG blocks only. CFG remains the complete,
   source-preserving graph. Reachability follows both syntactic conditional
   edges even for literal conditions; projection is not constant folding.
3. Astra SSA uses block arguments, with no phi instruction or compatibility phi
   representation. A successor defines ordered block parameters.
4. Branch terminators explicitly supply ordered arguments for each successor.
   Terminators remain the sole edge authority; block parameters never store
   predecessor lists. Conditional edges have independent argument lists.
5. Block parameters follow ascending originating local ordinal, within blocks
   projected in CFG ordinal order. Edge arguments follow their target's order.
6. Current local int/bool Places are fully promotable: no address-taking,
   references, captures, aliases, or storage escapes exist.
7. Promoted local storage disappears. Initialize/Store establish current SSA
   definitions; Load resolves to the current definition. No local Place or
   storage instruction survives in the SSA model.
8. SSA values retain semantic types and source provenance, independent of
   target registers, stack slots, bit widths, alignment, layout, or ABI.
9. SSA freezes no LLVM value, block, or type representation. Future lowering
   may translate block arguments into backend constructs at its own boundary.
10. Predecessors, dominance, immediate dominators, and dominance frontiers derive
    solely from Astra CFG entry and terminator successor edges. Deterministic
    snapshots are analysis results, not a second mutable graph authority.
11. Promotion of these scalar Places does not imply that all future Places
    must be promotable. Addressable/resource-bearing storage needs a separate
    eligibility and processing decision.
12. Erasing Initialize versus Store is valid here because current promoted
    int/bool values have no ownership or resource behavior. This is a downstream
    normalization after the Place disappears, not a change to storage semantics.
13. Future resource-bearing/addressable Places may require ownership before or
    during promotion, partial promotion, or another pipeline order. SSA-1 does
    not freeze that future ordering.

## Construction and identity

Use iterative dominator-set intersection and the definition of dominance
frontiers, followed by iterated-frontier placement and dominator-tree renaming.
The analyses support finite cyclic and irreducible graphs without source-order
assumptions. No source loops or loop-specific SSA machinery are introduced.

Placement respects local availability: a candidate block must be dominated by
the local's unique initialization block. Unrestricted function-wide placement
for a branch-local initialization would demand an argument from a sibling where
that local never exists. Such a merge is outside this Place's availability
region. The dominance boundary avoids fabricating a value without introducing
liveness analysis or merging same-spelled locals. Ordinary iterated-frontier
placement retains unused merges within that region, including dead-after-join
locals. A reachable load with no current definition is an internal compiler
failure; no zero, false, undef, poison, or source-order definition repairs it.

Function and block ordinals are SSA-owned. Blocks receive dense projection
ordinals and copy original CFG ordinals only as provenance. One increasing
value ordinal per function numbers function parameters first, block parameters
in block/local order second, and instruction results in dominator-tree preorder
last. Children are visited in original block order. Constants remain inline.
No hash iteration or object address determines emitted order or identity.

Nested pure expressions flatten to single-result prefix/binary instructions,
visiting left operands before right operands. This is a builder implementation
rule for current side-effect-free expressions; it does not establish public
evaluation-order semantics for future calls or other effects.

SSA owns its functions, blocks, parameters, instructions, results, constants,
terminators, and edge argument lists. Terminator-owned edges weakly reference
function-owned successor blocks to avoid reference-counting cycles. Only
semantic types/operators, source files/spans, and copied debug fields survive
from earlier stages. Temporary CFG construction maps do not escape the builder.

## Consequences and limits

`--check` now includes SSA construction and verification. `--dump-ssa` verifies
the whole result before emitting a deterministic dump. Earlier dump modes
remain stage-specific: `--dump-cfg` still displays disconnected post-return
blocks and unreachable full-return joins.

The independent SSA verifier checks definitions, types, graph ownership,
reachability, edge counts/types, operation/return shapes, and domination of
every use. It checks domination by excluding a proposed defining block and
searching paths, independently of the builder's CFG dominator algorithm.

There is no liveness/pruned SSA, dead-argument removal, CSE, DCE, constant or
branch folding, algebraic simplification, critical-edge splitting, ownership,
physical lowering, or new dependency. See the [SSA inventory](../ir/ssa.md)
for implemented APIs, examples, and regression coverage.
