# 0033: Nominal foreign resource handles and type-level cleanup contracts

Status: accepted for ASTRA-RESOURCE-1.

Baseline: accepted ASTRA-REARM-1,
`578110f977b9aeec076b8586cb942780f0877f6b` (`astra: add owned handle rearming`).
The local ownership state machine is architecturally complete for this campaign.

## Decision

1. `handle` introduces a nominal opaque foreign resource type.
2. RESOURCE-1 handle declarations originate only from VAPI.
3. Handle names enter Astra's ordinary semantic type namespace with builtins and structs.
4. Every declaration receives an exact compiler-owned nominal type identity.
5. Two handle declarations remain different types even with identical representation and cleanup.
6. Every current handle value is nullable.
7. Handle values are opaque.
8. Handles cannot be dereferenced or used for field access.
9. Handles cannot participate in pointer arithmetic, ordering or other arithmetic.
10. Handles cannot implicitly convert to or from void*; casts are not introduced.
11. Handles cannot implicitly convert between different nominal handle types.
12. Unqualified handles are unmanaged and non-owning, permitting ordinary copies.
13. `borrowed Handle` is a noescape parameter contract, with no responsibility transfer.
14. `owned Handle` is an ownership-bearing local binding or imported-result contract.
15. Each handle type owns one stable exact cleanup contract.
16. Every owned binding of that type uses precisely that contract.
17. Cleanup authority comes from the handle declaration, never an individual handle producer.
18. Existing producer-specific owned void* contracts remain supported unchanged.
19. Handle ownership reuses acquire/move/borrow/release/rearm and the existing possibility-set flow engine.
20. Owned slots retain stable lexical cleanup ranks, including after rearm.
21. Native and C transport use existing PTR channels.
22. Nominal identity never becomes a pointer-width or machine-channel decision.
23. LLVM sees ordinary address-space-zero ptr, pointer null and pointer equality.
24. No runtime type tag, resource descriptor, wrapper or destructor pointer is emitted.
25. Future owned native boundaries should primarily use nominal resource types, with bare owned void* remaining the legacy anonymous path.

## Collection and stage independence

All handle identities are collected before source struct field resolution,
foreign/source function signatures and native bodies. Handle ordinals follow
CLI VAPI file order and declaration order within each file. Lookup timing does
not assign ordinals. A source struct colliding with a handle is diagnosed at
the struct name; duplicate handles are diagnosed at the later handle name.

The implementation follows existing nominal StructType stage independence:
HandleType is an immutable identity token containing only a debug name and kind.
HandleSymbol owns it and the type contract. CoreHandle, CfgHandle and SsaHandle
retain the exact token but own independently copied cleanup/header descriptors.
Temporary exact object maps translate symbols and stage descriptors; downstream
name lookup is never type authority. Verifiers require a program-owned descriptor
and exact type-level cleanup match. Syntax, semantic symbols and prior-stage
handle/cleanup descriptors may die without affecting later stages.

Recreating type tokens at every stage would require replacing every scalar type
reference throughout the existing builders. A shared token without upstream
backlinks provides the same nominal distinction and lifetime independence using
the established type model. Sharing the upstream symbol or cleanup descriptor
would retain obsolete stage authority; those descriptors are copied instead.

VAPI exposes separate ordered syntax/input arrays for handles and functions,
preserving existing function normalization clients and the standalone frontend
firewall. The driver passes both to semantic collection. Headers remain opaque
metadata and have no physical lowering effect.

## Ownership and physical erasure

Type, responsibility and physical transport are orthogonal. Nullness never
authorizes a source ownership operation. A successful null producer yields
OWNED; moving it gives MOVED at the source and OWNED at the destination; release
gives RELEASED and makes no destroy call. Joins remain unions of OWNED/MOVED/
RELEASED indexed by exact owner identity. No second solver or handle-specific
ownership instruction family exists.

Exact type checks precede physical erasure. In particular cross-handle move,
borrow, call, equality and rearm reject even when both contracts share an interned
destroy function. Native raw/borrowed handles and C imported raw/borrowed/owned
results map to existing scalar-ptr-v1. Owned-result cleanup links and borrowed
parameter behavior remain supplemental ABI contracts. Existing null guards,
ccc destroy(ptr), scalar promotion and pointer phis are sufficient.

## Limits and future work

Owned native parameters/results, ownership transfer through calls, C exports of
handle types, resource fields/arrays/pointers, persistent borrowed locals, native
allocation, refcounting, methods, header parsing, generated typedefs, GIR and
GObject are excluded. No production dependency is added.

Nominal cleanup authority is a prerequisite for future owned native boundaries,
not permission to infer transfer semantics now. Those boundaries must define
sender/recipient responsibilities and transfer timing. Resource-contract-polymorphic
code will require an explicit generic contract model; shared physical PTR or
shared destroy symbols cannot supply one implicitly.
