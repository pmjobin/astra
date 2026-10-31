# ADR 0031: Explicit ownership release

Status: Accepted for ASTRA-RELEASE-1, over accepted OBORROW-1
`faec32fdc9f9133bad742d048328697f0a752ea2`.

## Decision

1. `release` explicitly discharges ownership responsibility at its statement
   position. It is a source operation, separate from automatic lexical Cleanup.
2. The exact grammar is `release-statement := "release" identifier ";"`.
   RELEASE-1 permits only an exact `owned void*` local operand.
3. Release requires the owner to be definitely OWNED at that reachable CFG point.
4. Release invokes the owner's exact existing cleanup contract on its current
   pointer if non-null. No symbol-string lookup happens during release lowering.
5. Its semantic transition is OWNED → RELEASED.
6. A RELEASED owner is unusable by source code, including null comparisons.
7. RELEASED and MOVED are distinct concrete semantic outcomes: move transfers
   responsibility, whereas release ends it without a recipient.
8. RELEASED differs from an OWNED owner whose pointer happens to be null.
   Pointer nullness never defines semantic ownership state.
9. Releasing an owned null value is valid and calls no destroy function.
10. Release physically clears the owner's current pointer to null.
11. Existing lexical cleanup remains in place after explicit release.
12. Later cleanup consumes the current null pointer and no-ops.
13. Release transfers responsibility nowhere.
14. Release creates no new owner and has no source expression result.
15. Release does not permit owner reassignment, reacquisition or rearming.
16. Borrowing before release is legal once the synchronous borrowed call returns.
17. Borrowing after release is illegal. Borrow remains OWNED → OWNED.
18. Moving after release is illegal; releasing a moved source is illegal.
    Releasing the definitely OWNED move destination is valid.
19. Double release is illegal, including possibly repeated releases through loops.
20. Conditional release has path-sensitive state. Joins use set union over
    reachable predecessor outcomes.
21. Loops reuse the deterministic ownership worklist and finite-lattice fixpoint.
    Return removes a continuation predecessor; break and continue contribute to
    their actual exit/header targets. Disconnected source tails contribute nothing.
22. OwnershipState is a nonempty possibility bitset over OWNED=1, MOVED=2,
    RELEASED=4. There are no combinatorial maybe-state enum members. The existing
    `{OWNED, MOVED}` dump spelling `MAYBE_OWNED` remains for compatibility.
23. Compiler-generated Cleanup is legal in every reachable ownership flow state,
    even where a source owner use is illegal. It ends the dynamic lexical lifetime.
24. Traps remain non-unwinding. No exception cleanup is added.
25. No runtime ownership flag, released flag, ownership tag or reference count is
    introduced. State proof finishes before SSA normalization.
26. NABI/CABI physical pointer channels remain unchanged. VAPI's existing
    `destroy_function` supplies all required metadata.
27. Existing CAbiCleanupFunction descriptors remain the physical authority for
    exact ccc cleanup declarations and calls.

## Implementation boundary and alternatives

CheckedOwnershipRelease retains the exact LocalSymbol, cleanup and source span.
Semantic checking proves syntax, binding and contract; CFG proves definitely
OWNED. CoreOwnershipRelease retains CoreOwnedLocal plus CoreCleanupContract;
CfgOwnershipReleaseInstruction retains CfgLocalPlace plus CfgCleanupContract.
Both verify exact stage identity and void* type. Release stays an ordered event
until ownership validation; it is never modeled as an early scope exit.

After validation, SSA emits `cleanup(current(owner))` at that event, then pushes
SsaNullPointerConstant as the owner's new reaching definition. Existing promotion
places pointer block parameters at conditional joins. Existing LLVM cleanup
guards update the physical end-block authority for following instructions,
branches, phi predecessors and backedges. No backend changes are required.

Expanding the old enum with named mixed states would duplicate the powerset and
make later additions fragile. A three-bit possibility set reuses the original
union worklist without losing MOVE-1 precision. `definitely_owned(s)` means
`s == {OWNED}`; `may_own(s)` means `OWNED ∈ s`; `definitely_disarmed(s)` means
`OWNED ∉ s`. The last predicate includes `{MOVED, RELEASED}` and grants no source
capability in this milestone. Reachability/bottom stays separate, as does the
internal out-of-scope bit, now 8.

Lowering release directly to lexical cleanup would lose the explicit state
transition. Adding an SSA release class or runtime flag would retain information
whose proof is already complete. Existing cleanup plus pointer definitions
suffices, so neither alternative is needed.

## Lifetime and limits

Release owns only downstream identities and provenance; no graph node points to
an analysis snapshot. Core scope references and CFG successor references remain
weak. Checked releases may die after Core, Core releases after CFG, and CFG
events plus ownership maps after SSA. LLVM retains only physical calls, guards
and ordinary values.

Explicit release may intentionally change destruction order: releasing `a`
before scope exit with `b` still live destroys a's resource before b's. Automatic
cleanup still visits b then a and skips a's null pointer. Calls, memory effects,
moves, other cleanup and trap-capable arithmetic retain exact source order.

No owner reassignment, move assignment, owned parameters/results or native owned
boundaries, owned fields, persistent void* borrows, native heap allocation,
reference counting, native destructors or unwind cleanup is introduced. Future
rearming must prove disarmed state and explicitly specify its acquisition and
cleanup-contract rules; it cannot reinterpret RELEASED as usable null storage.

See [language rules](../language/release.md), [IR](../ir/ownership-release.md),
and qualification.
