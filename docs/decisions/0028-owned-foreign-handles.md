# ADR 0028: Owned foreign handles and lexical cleanup

Status: accepted for ASTRA-OWN-1. Baseline: ASTRA-BORROW-1,
`c19fa90f3ea0a7c5aac9d40f4c05a01f2c1dd7a2`.

## Decision

1. `owned` is an ownership qualifier. Pointer representation and the canonical
   semantic `void*` type remain unchanged; responsibility is distinct from address
   identity. There are no tags, refcounts, headers, or inferred LLVM attributes.
2. OWN-1 permits `owned` only on local `void*` declarations. Owned int, bool,
   native struct, Struct*, parameters, fields, and Astra results are unsupported.
3. An owned local must initialize directly from a foreign call with an explicit
   owned-result cleanup contract. Parentheses around that same call preserve its
   category; nesting it inside another expression does not acquire ownership.
4. The producer transfers one cleanup responsibility when it successfully returns.
   There is no extra acquire runtime call, and the local becomes visible only
   after its initializer completes.
5. The physical pointer may be null. A null owner still has a semantic obligation;
   its eventual cleanup performs no foreign call.
6. Owned locals retain responsibility for their lexical lifetime. OWN-1 prohibits
   reassignment, copying, moves, early release, and explicit deletion. This is a
   milestone capability restriction, not a permanent immutable pointer type.
7. Owners cannot return, initialize raw locals/fields, or pass to ordinary pointer
   parameters. An owned-result call cannot be discarded, returned, nested in an
   argument, or captured as a raw value. Responsibility cannot silently disappear.
8. An owner may appear on either side of `== null` or `!= null`, including inside
   short-circuit conditions. This contextual permission creates no general raw
   value conversion, pointer alias, or ownership state change.
9. Each successful acquisition has exactly one cleanup on every normal exit from
   its lexical lifetime. Cleanup is reverse successful acquisition order within
   each scope and innermost to outermost across exited scopes.
10. A normal return cleans every active owner. Its complete return expression,
    including effects and potential traps, evaluates before cleanup; the computed
    result then returns. Bare return cleans immediately before transfer.
11. Break and continue clean precisely the lexical scopes they exit. Enclosing
    owners stay active. Loop-body fallthrough cleans before the backedge, once
    for each dynamic declaration execution. Branch-local owners clean before
    their join and produce no cleanup on unentered arms.
12. **Astra traps do not unwind owned resources in OWN-1.** Division/remainder by
    zero, null typed-pointer accesses, and llvm.trap remain immediate abnormal
    termination. Non-returning foreign calls likewise do not run later cleanup.
    There are no exceptions, landing pads, invoke, personalities, or trap-to-cleanup
    rewrites.
13. Cleanup is compile-time control-flow semantics. The compiler has a temporary
    cleanup stack during lowering; generated programs have no destructor stack,
    ownership runtime, heap allocation, or refcount operations.
14. VAPI adds exactly `destroy_function = "external_symbol"` to CCode metadata.
    The result must be exactly void*. Empty strings, duplicate keys, and invalid
    metadata values reject deterministically. cname and opaque header metadata
    remain independent. Source extern(C) gains no ownership metadata syntax.
15. The cleanup symbol names the physical C contract `void cleanup(void*)` with
    exactly one PTR argument and absent result. It is never resolved through the
    Astra direct-function namespace and need not be exposed as a source import.
16. Normalization uses immutable generic CForeignOwnedResultContract and
    CForeignCleanupContract objects with symbol provenance, without VAPI syntax.
    Semantic collection interns cleanup contracts across supplied declarations
    by physical symbol before any downstream identity mapping. First occurrence
    supplies cleanup provenance and deterministic declaration ordinal order.
17. Core receives independent cleanup descriptors, an explicit CoreOwnedLocal,
    and an acquisition marker on CoreInitialize. One CoreBlock per checked
    LexicalRegion normalizes lexical scope identity using the existing block
    containment tree; no separate region tree is invented.
18. Core → CFG maintains acquired-owner lists per active lexical block. Cleanup
    insertion follows executed declarations, not local ordinals. Transfers emit
    reverse cleanups without changing another source path's lowering context.
    Source tails stay disconnected and SSA's reachable projection removes them.
19. CfgCleanupInstruction loads the owner through ordinary Place/value authority.
    SsaCleanupInstruction consumes the promoted pointer, is ordered and effectful,
    and has no result. No SsaOwnedPlace, owner-state phi, or move lattice is needed.
20. Every stage owns its cleanup identity and maps exact upstream objects once.
    Frontend, semantic metadata, Core, and CFG ownership graphs may die in turn.
    SSA and later need no LexicalRegion or lexical cleanup-scope object.
21. CABI is the physical authority: CAbiCleanupFunction is separate from source
    imports and uses the existing scalar-ptr-v1 profile. One declaration exists
    per interned symbol. Cleanup symbols may not collide with any ordinary
    import/export; incompatible or duplicate physical contracts reject before
    LLVM can silently rename them. NABI and native signatures are unaffected.
22. LLVM emits one external ccc declaration per cleanup contract and a null guard
    around each ordinary ccc call. Each continuation updates the established
    physical end-block authority for later instructions, terminators, and phi
    predecessors. Chained cleanups preserve their exact order. No readonly,
    readnone, speculatable, nounwind, nonnull, nocapture, or noalias is inferred.
23. Ownership and borrowing remain separate semantic dimensions even when the
    same checked lexical region supports both. BORROW-1's Struct* provenance and
    addressable storage rules are unchanged.
24. Future Acquire/Transfer/Release/Cleanup semantics must modify responsibility
    explicitly. Safe non-owning calls will require parameter noescape/borrow
    contracts. Owned parameters/results, native ownership/destructors, heap
    values, refcounting, and unwinding require their own architectural decisions.
    None is implemented by OWN-1.

## Consequences and qualification

This deliberately narrow form keeps one owner armed from successful initialization
through lexical cleanup. It cannot express resource use through arbitrary C pointer
parameters yet: such parameters might retain, free, return, or capture a handle.
The prohibition must not be mistaken for a permanent ban on borrowing owners.

[Ownership](../language/ownership.md), [VAPI owned results](../vapi/owned-results.md),
and [cleanup IR](../ir/cleanup.md) specify usage and stage authority.
Qualification records structural, runtime, lifetime,
strict-build, firewall, object, and Valgrind evidence.
