# Owned buffer exchange across stages

Implemented and qualified; the source contract is in
[owned buffer exchange](../language/owned-buffer-exchange.md).

Checked/Core slots retain exact owning Place identity and cleanup authority.
Locals reference their declared owners; fields reference the native class member
and admitted receiver. Borrowed views cannot substitute for owners. Constructor
reads require definite field initialization. Core applies the existing ownership
flow lattice to exchange-containing concrete bodies as well as generic definitions;
an exchange is a read of both live responsibilities and changes neither state.
The generic cloner remaps both places, owner identities and cleanup contracts.

CFG has `CfgBufferSlotCapture` followed by `CfgBufferExchange`. The builder emits
the left capture after its receiver validation, then resolves and checks the right,
emits its capture and commits one exchange. Capture nodes are resultless destination
proofs, not payload borrows or additional owners. Each belongs to exactly one
operand of one exchange. Independent verification checks function membership,
left/right/commit dominance and all intervening paths for invalidation. Ownership
flow requires both slots live without exchanging declaration responsibilities.

SSA preserves this structure with `SsaBufferSlotCaptureInstruction` and
`SsaBufferExchangeInstruction`. A `SsaBufferPlace` names exactly one local descriptor
storage or owning class field. Existing field initialization, receiver validation,
buffer storage identity and cleanup authorities apply. Both operands invalidate
dependent buffer-view intervals. The memory-flow checker requires definitely live
initialized local contents at capture and commit; null/zero cannot prove liveness.

There is no public move-out/disarm sequence and no aggregate Astra SSA value. A
malformed exchange cannot be assembled from independently acceptable half moves.
The closed operation contains the simultaneous logical permutation; its private
snapshots never acquire cleanup duties.

LLVM planning copies exact type leaves, function/operation coordinates, local and
owner ordinals, field/class identities, receiver identity and cleanup correspondence.
Plans retain no Core, CFG or SSA executable graph. Validation rejects a valid plan
for another source operation. Independent physical bindings associate local storage,
receiver definitions and class layout members with their LLVM handles.

Each destination capture emits the existing descriptor and field projections only
after required receiver validation. Exchange loads left pointer/count, then right
pointer/count, then stores the complete opposite snapshots. Its eight memory
instructions are consecutive. Retained LLVM verification checks ordered component
types, exact addresses, opposite pre-store values and absence of intervening effects.
An aliasing self-swap therefore works without pointer comparison or noalias promises.
Element layout and stride remain the existing buffer allocation/indexing authority;
the exchange neither calculates a payload address nor reads record padding.

The retained physical receiver proof checks the exact null comparison, terminal
trap and successful continuation. An independent walk of the LLVM graph verifies
that this continuation dominates field-address formation, that the left capture
precedes the right receiver check/projection and that both destinations precede
all snapshots. This proof retains raw LLVM handles and immutable type leaves,
without retaining an SSA validation or block. LLVM guard splits still update the
actual final block used for phi predecessors.
Receiver expressions can have their ordinary checks and costs; only the successful
descriptor capture/store region has finite work independent of count and element
size. No new ABI profile, runtime helper, payload memcpy, allocation, free or global
optimization switch is introduced.
