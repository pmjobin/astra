# Ownership release through the compiler

Release is explicit through ownership validation. It discharges responsibility
without changing the lexical scope, transferring an obligation or creating an owner.

| Stage | Representation and authority |
| --- | --- |
| Syntax | ReleaseStatementSyntax(keyword, owner identifier, semicolon); complete statement span |
| Checked | CheckedOwnershipRelease(owner: exact LocalSymbol, cleanup from owner, span); statement only |
| Core | CoreOwnershipRelease(owner: exact CoreOwnedLocal, cleanup: exact CoreCleanupContract, span) |
| CFG | CfgOwnershipReleaseInstruction(owner: exact CfgLocalPlace, cleanup: exact CfgCleanupContract, span) |
| Ownership flow | Require `{OWNED}`, then assign `{RELEASED}` |
| SSA | SsaCleanupInstruction(current pointer, exact mapped contract, release span), followed by a new null reaching definition |
| LLVM | Existing null-guarded ccc cleanup plus ordinary pointer SSA |

The semantic checker validates identifier binding, exact owned void* local type
and its contract. It does not attempt a syntax-tree moved/released state analysis.
Core verifies exact registered owner, availability, void* type and contract
identity; same-name impostors or another owner's cleanup are invalid. CFG verifies
the same stage-local identities and unique ordered event placement. The event
does not register a new lexical acquisition, remove an owner from a cleanup stack
or require a new VAPI/CABI concept.

OwnershipFlow runs over reachable CFG and a three-bit possibility lattice. Its
release transition is a constant `{RELEASED}` update during convergence, followed
by definitely-OWNED validation during the deterministic final scan. This is the
same pattern used by Move. It handles loops without a syntactic special case;
unreachable preserved predecessors do not join. `definitely_disarmed` means no
OWNED bit and grants no rearming capability. [Ownership flow](ownership-flow.md)
documents the lattice and lifetime checks.

## Pointer normalization

The release event adds a definition site for its promotable owner Place.
At the ordered rename point:

```text
pointer = current(owner)
cleanup pointer via exact-contract       // explicit-release source provenance
current(owner) = typed-null
...
cleanup current(owner) via exact-contract // original lexical cleanup site
```

There is no result visible to source and no SsaOwnershipReleaseInstruction,
SsaReleasedFlag or ownership-state value. The null constant is an internal
reaching definition, not a source-readable state. Move then release gives the
destination the old pointer, the source null, cleanup of the destination pointer,
then destination null; both eventual lexical cleanups consume null.

Conditional release contributes null on the released path and the original
pointer on the other. An ordinary void* block parameter becomes one `phi ptr`
in LLVM. A three-way join can carry original/null/null, while its independent
semantic state is `{OWNED, MOVED, RELEASED}`. Even a producer that returns actual
null has the same ownership join. No pointer phi or null test is ownership authority.

## Effects, physical control and lifetime

The cleanup instruction retains the release event's position relative to calls,
memory loads/stores, other cleanups, moves and trap-capable arithmetic. It uses
the owner's exact mapped CAbiCleanupFunction; C ABI pointer channels and NABI
signatures are unchanged. LLVM's existing cleanup guard calls the destroyer only
on non-null. Constant null later yields an always-skipped lexical call block.
That textual call site is unreachable; runtime and object audits prove there is
no second physical destruction.

Every cleanup guard updates LlvmBlockState.end. Following conditional branches,
short-circuit entry edges, loop backedges and phi predecessors use that actual
continuation, including the final lexical no-op continuation after a body release.
No new LLVM primitive or production backend source is required.

Stage objects have acyclic ownership: release events own Places/contracts,
CoreOwnedLocal uses a weak scope reference, CFG edges remain weak, and graphs
never own the flow snapshot. The possibility representation is a value bitset;
analysis maps own exact identity keys and scalar facts. Checked objects die after
Core, Core after CFG, and flow plus CFG after SSA. Standalone/lifetime tests prove
these boundaries, and LLVM artifacts remain valid after SSA/NABI/CABI die.

Rearming, assignment, owned call boundaries, persistent void* borrows, refcounts
and unwind cleanup are outside RELEASE-1. See [ADR 0031](../decisions/0031-explicit-release.md).
