# CFG ownership-state dataflow

OWNBOUND-1 reuses the same lattice and fixpoint for native boundaries. Owned
parameters acquire `{OWNED}` at entry before source body execution. Argument
capture and owned-return capture use the ordinary source OWNED → MOVED
transition; call commit has no semantic state transition. A later argument read
therefore sees MOVED even though the physical source pointer has not yet cleared.
Return captures precede cleanup, and terminating predecessors remain excluded
from subsequent joins. See [ownership boundaries](ownership-boundaries.md).

RESOURCE-1 changes no transfer function, worklist or possibility lattice in this
engine. Exact owner identities may carry void* or nominal HandleType values;
structural verifiers establish exact types and cleanup contracts first. Acquire,
move, borrow, release, rearm and lexical cleanup use the same events. The complete
standalone matrix is built twice, once with void* and once with Resource owners.
Pointer nullness remains independent of OWNED/MOVED/RELEASED.

Ownership validation runs in CfgFlowChecker after CfgVerifier and before SSA.
SsaBuilder invokes the same boundary for direct API callers. Syntax, checked and
Core dumps may describe a structurally valid move, release or rearm that later fails flow checking;
CFG and later CLI dumps require ownership validity. LLVM is independent of this
analysis and its storage.

## Exact events

| Event | Authority | Preconditions and effect |
| --- | --- | --- |
| Acquire | CfgInitialize.acquisition, exact CfgLocalPlace and producer contract | Outside lifetime → OWNED |
| Acquire parameter | CfgAcquireParameter, exact incoming parameter and root owner slot | Outside lifetime → OWNED at function entry |
| Move argument | CfgOwnedArgumentCapture / CfgPendingOwnedArgument | Source requires OWNED → MOVED at argument evaluation; owned-null has no source |
| Call commit | CfgOwnedCallTransferCommit | No lattice transition; physical source disarm only |
| Owned return | CfgOwnershipReturnInstruction / exact CfgOwnedReturnValue | Source requires OWNED → MOVED before cleanup; owned-null has no source |
| Transfer | CfgOwnershipTransferInstruction(source, destination, cleanup, span) | Source OWNED, fresh destination; source → MOVED, destination → OWNED |
| Borrow | CfgOwnedBorrowInstruction / exact CfgOwnedBorrowValue source and parameter | Requires OWNED; preserves OWNED |
| Release | CfgOwnershipReleaseInstruction(owner, cleanup, span) | Requires `{OWNED}`; owner → `{RELEASED}` |
| Rearm | CfgOwnershipRearmInstruction(owner, producer result, cleanup, span) | Requires definitely_disarmed; owner → `{OWNED}` |
| User read | CfgLoadValue of an owned CfgLocalPlace, with original span | Requires OWNED |
| Cleanup | CfgCleanupInstruction of the owner's load with exact contract | Accepts every reachable possibility set; ends lexical lifetime |

Ownership is never inferred from stores of null. CfgLocalPlace.cleanup is a
stage-owned exact contract; ordinals identify dump positions, not authority.
CoreOwnershipTransfer survives intact through lowering at declaration execution.
Core and CFG verify distinct exact owners, exact ownable value types, contract identity and one
destination initialization. CFG rejects owner stores and missing acquisition
markers. Existing CoreBlock cleanup insertion registers transferred destinations
in the same stack as acquisitions, preserving reverse declaration execution order.

The load inside compiler cleanup is exempt from user-read validation. Other
expression trees, call arguments, indirect Places, evaluations and terminators
are checked at their ordered CFG position. Return-expression evaluation snapshots
remain before cleanup, so returning a previously evaluated bool comparison is safe.

## Lattice and reachable inputs

OwnershipState is a nonempty possibility bitset over concrete OWNED=1, MOVED=2,
RELEASED=4. Join is set union (bitwise OR) over reachable predecessors:

| Inputs | Joined set |
| --- | --- |
| O, O | `{OWNED}` |
| O, M | `{OWNED, MOVED}` (dump spelling `MAYBE_OWNED`) |
| O, R | `{OWNED, RELEASED}` |
| M, R | `{MOVED, RELEASED}` |
| O, M, R | `{OWNED, MOVED, RELEASED}` |

There are no enum members for mixed states. `definitely_owned(s)` is `s == {OWNED}`;
`definitely_moved/released` likewise test exact singletons. `may_own(s)` means
`OWNED ∈ s`; `definitely_disarmed(s)` means `OWNED ∉ s`, including `{MOVED, RELEASED}`.
Disarmed proves no remaining responsibility and authorizes same-contract rearming
within the active lexical lifetime. Pointer nullness is never this authority.

An internal out-of-scope bit (8) checks lexical availability. It is removed by
acquisition and restored by lexical cleanup; no CLEANED source state crosses scope
boundaries. Release leaves the lexical lifetime active. Active/out-of-scope joins,
source operands outside lifetime, duplicate cleanup, active reinitialization and
normal exits missing cleanup are malformed CFG errors. Scope absence is separate
from an uncomputed block input, which is bottom and contributes nothing.

CfgPredecessors first projects entry reachability, then scans blocks in existing
ordinal order, preserving true-before-false parallel edges. It moved unchanged
from the SSA source directory to CFG so both analyses share the same authority.
Disconnected post-return blocks never enter the predecessor snapshot.

OwnershipFlow uses a deterministic FIFO. For each block it joins available
reachable predecessor outputs, simulates explicit events and enqueues successors
when the output changes. Queue membership and maps use exact object identity;
no hash enumeration determines results or ordering. The domain is a finite
powerset; joins ascend and transfer/release/acquisition/cleanup are monotone constant
updates. Cycles converge without widening or an iteration cutoff. Tests assert
convergence for fresh body owners and outer owners with moved or released backedges.

Only after convergence does a deterministic block/instruction scan validate all
source uses. This prevents an initially OWNED loop input from hiding a later
mixed backedge. Definite move and second move report
`use of moved owned value 'a'`; uncertain use reports
`owned value 'a' may have been moved on another control-flow path`.

## Precision and physical normalization

A conditional move joins OWNED and MOVED into MAYBE_OWNED. Two moved arms join
MOVED. A moved arm that returns contributes no continuation input. A move that
breaks contributes MOVED to the loop exit, not the header; a moved continue
contributes to the header. Fresh body-local acquisitions reset responsibility
each iteration only after the previous dynamic lifetime has ended.

Lexical cleanup locations are unchanged and never elided. During SSA promotion,
transfer contributes two definition sites. Destination initialization receives
the old source SSA value; the source receives SsaNullPointerConstant with transfer
provenance. Conditional source definitions merge with ordinary pointer block
parameters, becoming LLVM pointer phis. No SSA ownership instruction, contract
phi, runtime armed flag, retain/copy call or ownership stack is needed.

An actual-null factory result remains semantically OWNED. After moving it both
physical pointers may be null while their semantic states differ. Existing LLVM
cleanup guards handle both values without knowledge of the ownership lattice.
Existing physical end-block tracking supplies correct phi predecessors after
cleanup guards, including chained cleanups and backedges.

## Inspection and lifetime

OwnershipFlowResult.entry_state(block, owner) and dump() expose focused analysis
snapshots; no CLI flag is added. Dumps list reachable blocks and locals in
stable declaration order, with owner Place ordinals and out-of-scope entries.
See [the conditional dump](../../tests/move/fixtures/move-conditional.flow).

Snapshots own references to their queried blocks/Places; no graph node links
back to an analysis object. Places own immutable contracts and provenance, never
blocks. CFG successor links remain weak. Checked move objects die after Core,
Core transfers/releases/rearms after CFG, and CFG plus lattice maps after SSA. Lifetime tests
also retain a snapshot after releasing its source program and prove complete
reclamation when the snapshot dies.

The `ownership-flow-standalone` target compiles only CFG models/analysis and shared
source/type authorities. It cannot reference syntax, checked nodes, Core, SSA,
ABI or LLVM. Explicit linkage firewalls cover it and the move pipeline suite.
BORROW-1 remains a separate checked-region proof. Traps remain non-unwinding.

## Temporary borrowed uses

BORROW is a use/event, with no BORROWED, BORROWING or LOANED state. The existing
fixpoint and reachable predecessor policy suffice: borrow-only loops remain
OWNED, and a terminating moved arm cannot contaminate its continuation. MOVED
reports `cannot borrow moved owned value 'h'`; MAYBE_OWNED reports
`owned value 'h' may have been moved on another control-flow path and cannot be borrowed`.
An acquired null is still OWNED. Calls preserve all owner cleanup contracts.
SSA captures the current pointer at each event and retains no OwnershipFlowResult
or runtime borrow node. See [ADR 0030](../decisions/0030-borrowed-owner-parameters.md).

## Release states and diagnostics

Release requires exactly `{OWNED}`, then assigns `{RELEASED}`. An actual-null
producer remains OWNED before release; pointer bits never affect the transfer
function. Both released arms join RELEASED. A released terminating arm does not
contaminate continuation state; release-break contributes to the exit and
release-continue to the header. A repeated outer-owner loop release rejects at
fixpoint; fresh body acquisition/release/cleanup is valid each iteration.

Definite source reads distinguish `use of moved owned value 'h'` from
`use of released owned value 'h'`. Release reports
`cannot release moved owned value 'h'` or
`owned value 'h' has already been released` for those exact states. Mixed states
containing OWNED report that the value may no longer own its resource on another
control-flow path; the MOVE-1 `{OWNED, MOVED}` wording is preserved. All-disarmed
mixed state reports that it no longer owns a resource on every reachable path.
Borrow/release diagnostics append their operation where needed.

After validation, release contributes a pointer definition site and normalizes to
ordered cleanup(current) followed by current=null. Conditional source pointers
merge normally, independent of the ownership-state set. Every later compiler
cleanup remains legal and consumes the current pointer. There is no SSA ownership
flag, contract phi or runtime state. See [release IR](ownership-release.md).

## Rearm transition

Within its lexical lifetime, REARM requires `definitely_disarmed(S)` and assigns
exactly `{OWNED}`. RELEASED, MOVED and MOVED|RELEASED succeed. A singleton OWNED
reports `owned value 'h' still owns a resource; release or move it before reassignment`;
any mixed state containing OWNED reports
`owned value 'h' may still own a resource on another control-flow path`.

The existing worklist handles repeated cycles without a new state or algorithm.
A RELEASED preheader and released backedge converge to RELEASED; a moved backedge
joins MOVED|RELEASED and remains safe. An OWNED backedge makes a subsequent rearm
illegal, including through continue or conditional discharge. Return and break
use only their actual successors. The transfer tracks responsibility, never
dynamic destructor-order permutations. See [rearm IR](ownership-rearm.md).
