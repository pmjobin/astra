# 0034: Owned native parameters and results

Status: accepted for ASTRA-OWNBOUND-1.

Baseline: accepted ASTRA-RESOURCE-1,
`fd181d8835a88476e622b2605f474cf5b7602d6a` (`astra: add nominal foreign resource handles`).
Acquire, Borrow, Move, Release, Rearm and Cleanup remain the local ownership machinery.

## Decision

1. Owned native boundaries support only exact nominal `HandleType` values.
2. Bare `owned void*` native parameters and results remain unsupported. Their producer-specific cleanup authority cannot define a stable native signature.
3. `owned Resource` parameters transfer one responsibility from caller to callee.
4. `owned Resource` results transfer one responsibility from callee to caller on successful return.
5. Cleanup authority comes from the nominal Resource declaration, on both sides of a boundary.
6. Owned parameters physically use the existing PTR channel.
7. Owned results physically use the existing PTR channel.
8. Ownership qualifiers are semantic call contracts, not machine types. Unmanaged, borrowed and owned Resource share the exact value type but have different callable contracts.
9. Passing an existing owner to an owned parameter requires explicit `move owner`.
10. Literal `null` may directly supply an owned parameter and means owned-null responsibility.
11. Each owned parameter begins body execution definitely OWNED, established by its entry acquisition event.
12. Each owned parameter has a stable function-root lexical cleanup slot.
13. Normal exits automatically clean any responsibility remaining in that parameter. Moved and released slots remain present with null current pointers.
14. Root cleanup ranks put owned parameters in declaration order before root locals in lexical declaration order. Reverse cleanup therefore visits root locals first, then owned parameters in reverse declaration order. Nested owners clean first as before.
15. An owned result requires explicit transfer from a definitely live owner of the exact type/contract, or an explicit owned-null return.
16. `return move owner` captures and transfers that responsibility out of the function.
17. `return null` produces an owned-null Resource result.
18. Ordinary `return resource` never implies ownership transfer.
19. A native owned-result call requires ownership-aware consumption.
20. It may initialize a fresh compatible owned local.
21. It may rearm a compatible definitely-disarmed owner, including a parameter slot.
22. It may not be discarded, captured unmanaged, borrowed inline, or silently duplicated.
23. Argument expressions and source ownership transitions follow left-to-right evaluation.
24. Physical caller-source nulling commits immediately before invocation, after every argument expression has successfully evaluated, including the final argument's trapping arithmetic.
25. Delaying that physical commit does not weaken semantic moved-state rules.
26. A later argument cannot use an owner moved by an earlier argument. Repeated transfer of the same source rejects.
27. If a later argument traps, the call never happens and existing non-unwinding behavior applies. No recovery obligation or runtime pending-owner stack is introduced.
28. No ownership flag, token, descriptor, destructor-pointer argument or runtime owner object is introduced.
29. NABI remains physical authority only: `scalar-ptr-v1`, existing PTR channels, unchanged physical dumps.
30. LLVM uses ordinary pointers and existing native `fastcc`; no ownership calling convention is needed.

## Implementation choice

The existing parameter identity is an incoming scalar value, whereas local owner
operations require a mutable current value and a lexical slot. Making every
parameter addressable would add unnecessary storage and reopen unrelated aliasing
rules. A separate parameter-only ownership engine would duplicate the accepted
flow and cleanup machinery.

Instead, an owned parameter has an additional ordinary scalar owner slot linked
to its exact incoming parameter identity. The checked slot is a `LocalSymbol`
with `incoming_parameter`; Core and CFG copy that relation into their own Places.
An entry `CoreAcquireParameter` / `CfgAcquireParameter` initializes the slot.
It is ranked before local declarations and registered with the existing root
cleanup scope. Borrow, move, release and rearm use the same slot authority as
locals. SSA promotion replaces its current value with the incoming parameter,
producer results or typed null; it introduces no alloca.

`OwnedValueProducer` records native or foreign producer domain, exact semantic
type and cleanup. Native signatures retain a result ownership contract and the
type's cleanup. Core rearm accepts either direct call kind, and CFG's existing
immediate/exact/exactly-once consumer verifier uses a domain-independent cleanup
map. Foreign metadata normalization and C physical transport are unchanged.

## Evaluation and transfer

A checked owned argument retains its exact source (or owned null), parameter,
argument position through parameter identity, type, cleanup and source span.
Core retains that argument category. CFG emits `CfgOwnedArgumentCapture` at its
expression point, then evaluates later arguments, then emits one grouped
`CfgOwnedCallTransferCommit` immediately before its associated native call.
A capture changes source state OWNED → MOVED; commit has no lattice transition.

A potentially trapping final argument must be materialized before commit. Earlier
pure expressions that read an owner must also be captured before a later nested
transfer. The lowering snapshots these expressions only where ownership transfer
requires the ordering; pre-boundary fixtures retain their previous IR.

CFG verifies unique captures and exact call bindings, dominance across expression
regions, immediate commit/call adjacency and absence of lexical cleanup or rearm
on every path from capture to commit. It rejects deferred expression trees in a
committed call's ordinary arguments. No source-observable effect can occur between
commit and invocation. SSA captures the ordinary pointer at the capture event,
defines typed null at commit, then invokes the callee with the captured value.

`CoreOwnershipReturn` becomes `CfgOwnershipReturnInstruction`, followed only by
lexical cleanups and its `CfgOwnershipReturn` terminator. The event captures the
result pointer, requires OWNED, and changes its source to MOVED. SSA defines null
for the source before lowering any cleanup, then returns the captured pointer.
There is no lexical result-owner slot. Owned null follows the same return ordering
without a source owner.

## Boundaries and exclusions

Ownership contracts do not create overloads, function values or new type identity.
Recursion and mutual recursion use predeclared exact signatures and weak callee
references; no runtime ownership metadata is required. Executable entry remains
exactly `int main()`.

Direct `return owned_call()` and `consume(owned_call())` remain deferred. Bind the
result to a lexical owner, then move it. C-owned exports, native owned void*, owned
fields/arrays/slices, generic or contract-polymorphic ownership, move assignment,
shared/refcounted ownership, native allocation and exceptions/unwinding are excluded.
No new production dependency or copied Vala/LLVM-v2 implementation is needed.
