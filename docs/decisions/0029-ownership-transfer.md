# ADR 0029: Explicit ownership transfer

Status: accepted for ASTRA-MOVE-1. Baseline: ASTRA-OWN-1,
`008d1fbae68a76a32224ccc4edd5d24b09b91a07`.

## Decision

1. `move` explicitly transfers cleanup responsibility; it never duplicates it.
2. MOVE-1 permits only `owned void* destination = move source;`, where the
   destination is a fresh local and the source identifier resolves to an exact
   owned void* LocalSymbol. Parenthesized moves and general move expressions reject.
3. The source must be definitely OWNED at the execution point.
4. The destination inherits the source's exact cleanup contract by identity.
   There is no destructor-name lookup or new foreign contract.
5. The destination becomes definitely OWNED, including when its pointer is null.
6. The source becomes definitely MOVED on that path.
7. A MOVED owner cannot be read, copied, compared, moved again, returned or passed.
8. Reachable control-flow joins can produce MAYBE_OWNED.
9. MAYBE_OWNED is not a legal source operand, including in a null comparison.
10. Compiler-generated lexical cleanup accepts OWNED, MOVED and MAYBE_OWNED,
    then ends that owner's dynamic lexical lifetime.
11. Physical cleanup remains guarded by pointer != null.
12. Physical transfer gives the destination the old pointer value and defines
    the source pointer as typed null at the transfer's ordered execution point.
13. Semantic ownership state is never inferred from physical pointer nullness.
14. A producer's actual-null owned result still transfers responsibility: the
    destination is OWNED and source MOVED even though both pointers are null.
15. Definitive ownership validation runs over reachable, structurally verified
    CFG, after exact ownership events are lowered and before SSA construction.
16. Loops require a deterministic iterative fixpoint, followed by diagnostics
    using converged block inputs. No source-order approximation is authoritative.
17. Unreachable source-preserved predecessors do not affect reachable joins.
18. Moves do not change either owner's lexical cleanup scope or remove cleanup
    instructions. The source declaration retains its original cleanup contract.
19. Moving into a nested owner deliberately shortens resource lifetime on that
    path: the nested destination cleans before the enclosing source scope ends.
20. Transfer into pre-existing owner storage is unsupported.
21. Owner reassignment and rearming are therefore unsupported.
22. No runtime ownership-state flag, stack, refcount or new runtime call exists.
23. No cleanup-contract phi is needed: a destination receives one exact source
    contract at its declaration. Only pointer values may need SSA joins.
24. Borrow-state and ownership-state analysis remain separate. LexicalRegion and
    the existing Struct* borrow proof are unchanged.
25. Traps remain non-unwinding. There is no Release, early destruction, owned
    call/return boundary, owned native struct, allocation or exception feature.

## Representation and convergence

CheckedOwnershipMove retains source LocalSymbol, exact cleanup, void* type and
source span. CoreOwnershipTransfer owns stage-local source/destination owner
identities and cleanup; each CoreOwnedLocal keeps its existing weak scope link.
CfgOwnershipTransferInstruction retains exact CfgLocalPlace identities, cleanup
and provenance. CfgInitialize.acquisition marks acquisition explicitly; owned
CfgLocalPlace.cleanup identifies the local's immutable contract. Ordinary owned
CfgLoadValue operands are user reads except at compiler cleanup sites.

OwnershipState is OWNED / MOVED / MAYBE_OWNED. Equal inputs join to themselves;
OWNED and MOVED join to MAYBE_OWNED, which absorbs either state. A block with no
computed reachable input is bottom. An internal out-of-scope bit tracks lexical
availability separately and detects malformed lifetime joins, duplicate cleanup,
rearming and missing cleanup at normal exits. It is not a new source state.

The existing CfgPredecessors implementation moves unchanged from `src/ssa/` to
`src/cfg/`. It enumerates reachable blocks and incoming edges in established
block/true-before-false order. A FIFO with identity-based queue membership
recomputes entries and schedules successors when outputs change. Facts are finite
sets; joins only add possibilities and event transitions are monotone constant
updates. Convergence needs no widening, arbitrary iteration limit or runtime flag.
Diagnostics run afterward in deterministic block/instruction order.

SSA placement counts both transfer definitions. Renaming reads the pre-move source
value, defines the destination with it and defines the source with typed null.
No persistent SSA transfer instruction or semantic ownership object survives.
Conditional source cleanup consumes an ordinary pointer block parameter/LLVM phi.
Existing LLVM constant construction may fold the moved source's null test to
`true`; the lexical cleanup and its physical guard/call blocks remain emitted.

## Consequences

Acquire creates responsibility, Transfer relocates it, and Cleanup discharges it.
Lexical scopes still determine where cleanup occurs; pointer definitions determine
which physical calls run. Return expressions evaluate before cleanup. Break,
continue, body fallthrough and branch exits retain existing reverse owner order.
No NABI, CABI, VAPI or production LLVM implementation change is required.

Future Release must explicitly extend the state machine. Rearming needs a policy
for the old obligation and contract compatibility. Borrowed owner parameters need
non-retaining contracts; owned function boundaries need explicit transfer and
lifetime contracts. These are separate milestones, not implicit extensions here.

See [moves](../language/moves.md), [ownership flow](../ir/ownership-flow.md), and
qualification.
