# Ownership rearm through checked, Core, CFG and SSA

Rearm fills an existing lexical owner slot with one fresh direct foreign
owned-result responsibility. It keeps the exact cleanup contract, owner identity,
lexical scope and cleanup rank. [ADR 0032](../decisions/0032-owner-rearming.md)
defines source legality and ordering; [language examples](../language/rearming.md)
show release, move, joins and loops.

| Stage | Representation and authority |
| --- | --- |
| Syntax | Existing AssignmentStatementSyntax; no keyword or parser change |
| Checked | CheckedOwnershipRearmAssignment(owner: LocalSymbol, producer: CheckedCallExpression, span), with the owner's exact CForeignCleanupContract |
| Core | CoreOwnershipRearm(owner: CoreOwnedLocal, producer: CoreCCallValue, cleanup: CoreCleanupContract, span) |
| CFG | CfgCCallInstruction followed immediately by CfgOwnershipRearmInstruction(owner: CfgLocalPlace, value: CfgCallResultValue, cleanup: CfgCleanupContract, span) |
| Flow | Within active lexical lifetime, require definitely_disarmed; set exactly OWNED |
| SSA | Ordinary C call and new pointer definition for the existing owner Place |
| LLVM | Ordinary producer calls, pointer values/phis and existing guarded cleanup |

Semantic checking recognizes the owned destination and validates the direct
producer and exact normalized cleanup contract. Transparent grouping is allowed;
no ownership is inferred through arbitrary expressions. Flow legality is deferred.
Core independently verifies lexical availability, program-owned owner/callee and
cleanup identities, void* type and exact contract equality. Checked objects may
die immediately after construction.

CFG preserves argument/call evaluation order. A result with owned cleanup must
be consumed immediately by its exact acquisition or rearm, once only. The verifier
rejects raw capture, discard, duplicated uses, intervening instructions and
cross-block consumption. No owned result is temporarily available as an unmanaged
value. Core objects may die after CFG construction.

## State and slot invariants

`definitely_disarmed(S)` is the single rearm authority. It means OWNED is absent;
RELEASED, MOVED and MOVED|RELEASED succeed. Every OWNED-containing set rejects.
The transfer function writes `{OWNED}` after successful result production, even
for null. No conditional release is synthesized. The existing ownership FIFO
reaches its fixpoint before producing diagnostics, including unsafe OWNED loop
backedges. Reachability and out-of-scope lifetime bits remain separate.

Only declaration acquisition and fresh move destinations register cleanup slots.
Rearm adds no local, owner ordinal, acquisition marker or cleanup-stack entry.
Automatic cleanup still traverses those slots in reverse lexical order and reads
their current values. Explicit release remains at its statement position.

## Pointer normalization and physical proof

Rearm contributes a definition site to existing SSA Place promotion. Rename
replaces `current(owner)` with the already evaluated producer result. MOVE and
RELEASE have already normalized the old definition to null on every accepted
path. A construction verifier checks this consequence by following pointer block
parameters and incoming edge arguments, including cycles, until all leaves are
null constants. The verifier does not decide semantic permission from nullness.

Conditional rearm merges `[producer, true]` with `[null, false]`. Both-arm rearm
merges two producer pointers. The existing lexical cleanup consumes that phi;
its null guard handles mixed semantic state without a tag. There is no persistent
SSA rearm event, ownership-state value, contract phi, flag, alloca, helper runtime,
new dependency or ABI/backend operation. A real null result is still semantically
OWNED and therefore cannot be overwritten without another discharge.

OwnershipFlowResult, CFG identities and construction proof maps may die after
SSA. SSA/CABI/source provenance may die after LLVM lowering; existing physical
continuation tracking supplies cleanup guard, branch and phi predecessors.
NABI, CABI, VAPI metadata and LLVM lowering remain unchanged.
