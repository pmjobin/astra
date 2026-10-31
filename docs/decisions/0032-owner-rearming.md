# ADR 0032: Owner rearming and stable cleanup slots

Status: Accepted for ASTRA-REARM-1, over ASTRA-RELEASE-1
`cd0ca58039abd50102a034cd9aa1946fcdef745d`.

## Decision

1. An owned binding is a stable lexical cleanup slot.
2. A slot may carry multiple resources over its lexical lifetime, with at most
   one active cleanup responsibility at any instant.
3. Rearming requires the slot to be definitely disarmed.
4. Definitely disarmed means OWNED is absent from every reachable concrete
   ownership-state possibility, within the slot's active lexical lifetime.
5. MOVED and RELEASED are both disarmed states.
6. The mixed `{MOVED, RELEASED}` state is definitely disarmed.
7. Any state containing OWNED forbids rearming.
8. `h = producer(arguments);` transfers a fresh direct foreign owned-result
   responsibility into the existing owned void* local. Transparent parentheses
   may group the same direct call, as with initial acquisition.
9. Successful producer return transitions the slot to exactly `{OWNED}`.
10. Rearming creates no additional lexical cleanup obligation.
11. Rearming changes neither the owner's ordinal nor its cleanup rank.
12. Automatic cleanup order is reverse lexical owner-slot order, independent of
    the most recent resource acquisition time.
13. This refinement changes no pre-REARM program: declaration, first acquisition
    and slot order previously coincided because each owner acquired at most once.
14. Rearming never implicitly releases an active resource.
15. Assigning an owned producer to a definitely or possibly OWNED slot is illegal.
16. The direct producer must carry the same exact normalized cleanup contract as
    the slot. Different producer functions sharing that contract are allowed.
17. Cleanup-contract-changing reassignment remains unsupported. Symbol spelling
    or physical PTR identity cannot substitute for exact stage contract authority.
18. Rearming may follow explicit Release.
19. Rearming may follow Move from that slot; the destination remains independent.
20. Rearming may follow a mixed MOVED/RELEASED join.
21. A producer returning null still arms ownership semantically.
22. Pointer nullness and semantic responsibility remain distinct. A disarmed null
    is unusable until rearmed; an OWNED null may be compared, borrowed or discharged.
23. Rearming requires no runtime ownership flag, generation or cleanup-order tag.
24. Rearming requires no new ABI concept or VAPI metadata.
25. Rearming requires no new LLVM primitive or runtime helper.
26. Existing lexical cleanup sites remain intact and consume the current pointer.

## Representation and proof boundaries

CheckedOwnershipRearmAssignment owns the exact LocalSymbol and checked producer
call, exposing the slot's cleanup and source span. Semantic checking validates
binding, direct-call shape and contract identity, deferring state legality.
CoreOwnershipRearm retains CoreOwnedLocal, CoreCCallValue, CoreCleanupContract and
provenance. Core verifies exact owner, lexical availability, producer authority,
void* type and cleanup identity independently of checked objects.

CFG evaluates producer arguments in their ordinary order, emits the effectful
CfgCCallInstruction, then CfgOwnershipRearmInstruction with the exact owner,
call-result identity and cleanup. The verifier requires an owned result to have
one immediate acquisition/rearm consumer, with no intervening effect, branch,
copy, discard or second use. This also closes a pre-existing standalone CFG gap
that admitted owned producer results into raw locals; source checking already
rejected that form. No source program or old IR output changes as a result.

OwnershipFlow adds the transfer function `definitely_disarmed(S) → {OWNED}` to
its existing deterministic FIFO worklist. Validation follows convergence. Safe
release/rearm and move/rearm cycles converge; any OWNED backedge rejects. Joins
use actual reachable predecessors, so terminating arms do not contaminate a
continuation. Lexical cleanup remains valid for mixed OWNED/disarmed states.

SSA promotion records rearm as another definition of the existing owner Place.
After flow validation it uses the producer pointer as the current definition;
no SSA rearm node survives. A construction verifier follows the old pointer's
incoming phi graph, including cycles, to verify that every terminal value is null.
This checks the physical consequence of disarmament; it never grants semantic
permission. No ownership state or proof map is retained by SSA or LLVM.

## Cleanup order and alternatives

For a=1, b=2, `release a; a = create(3);`, the physical destroy recorder is **123**:
explicit release destroys 1 immediately, then lexical slots b and a destroy 2
and 3. Rearming a does not move its slot after b. This resembles replacing the
resource in an existing RAII slot.

Dynamic cleanup stacks, priorities, contract phis and path-dependent destructor
permutations would require runtime machinery to preserve dynamic reacquisition
order. Fixed slots fit the existing cleanup construction and preserve all earlier
program behavior. A new keyword would duplicate ordinary assignment syntax;
explicit checked/Core/CFG events preserve ownership meaning without one.

## Lifetime and limits

Checked objects may die after Core, Core objects after CFG, CFG/worklists after
SSA, and SSA/CABI/provenance after LLVM lowering. Calls, pointer values, phis and
existing null-guarded cleanups suffice. Arguments and the producer remain effectful;
if evaluation traps or the producer never returns, no result transfer or rearm
transition occurs. Abnormal exits remain non-unwinding.

Move assignment, implicit release-on-assignment, cleanup-contract changes, owned
parameters/results, call-bound transfer, borrowed locals/results, native object
ownership, heap allocation, refcounting and exception unwinding remain excluded.
Future extensions must specify transfer timing, active-slot replacement and
contract authority explicitly, without treating physical PTR equality as proof.

See [language](../language/rearming.md), [IR](../ir/ownership-rearm.md), and
qualification.
