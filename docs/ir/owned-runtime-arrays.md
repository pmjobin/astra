# Owned runtime arrays through the pipeline

[Struct elements](struct-elements.md) extend element eligibility and physical layout qualification without changing owner groups or replacement/cleanup order. Core keeps structural-zero promises; LLVM checks complete record stride and address-domain arithmetic. No per-element lifecycle action or mandatory aggregate temporary is introduced.

[Generic owned arrays](generic-owned-arrays.md) carry exact SliceType<T> owner
slots, complete scoped element premises and symbolic buffer cleanup in parameterized
Core. Materialization creates the existing concrete operations below before CFG;
no unresolved layout or cleanup reaches the physical stages.

Every stage owns its graph. Shared immutable semantic type authorities may
survive; Checked symbols, Core nodes and CFG nodes do not survive into later
graphs. [ADR 0065](../decisions/0065-owned-runtime-arrays.md) freezes the contract.

[Owned buffer exchange](owned-buffer-exchange.md) adds a dedicated closed operation
over two initialized owner Places. CFG/SSA retain ordered destination captures;
independent flow and overlap checks protect both slots. The exchange captures both
complete groups before any store, preserving cleanup responsibility at each slot.
It uses neither public field moves nor ordinary transfer disarms.

| Stage | Owning representation | Borrow and cleanup |
| --- | --- | --- |
| Checked | SliceType plus ownership contracts; CheckedOwnedBufferAllocate, CheckedOwnedBufferReplace, existing whole-owner move/return/field-transfer nodes | CheckedOwnedBufferBorrow or owned-field borrow; one local identity and static buffer cleanup |
| Core | CoreOwnedBufferAllocate(count, cleanup), CoreOwnedLocal, CoreOwnershipTransfer/Rearm/Return; owned field contract | CoreOwnedBufferBorrow uses the existing SliceType; native-buffer-deallocate cleanup; unified reverse field cleanup descriptors |
| CFG | CfgBufferAllocate checked target-neutral operation; CfgBufferResults bounded owner token with PTR/I32 leaves; CfgBufferOwnerGroup storage components | Existing Slice bounds and Place operations; explicit borrow, source capture/commit, rearm and cleanup instructions |
| SSA | Ordinary PTR and I32 Values grouped by SsaBufferPair; SsaBufferStorage/Place; complete Allocate/Read/Write/Deallocate operations | SsaBufferBorrowInstruction creates the existing nonowning slice view; static cleanup, exact buffer arguments/results and pair return |
| NABI | NativeBufferValuePlan and ordered parameter/result ownership channel groups under buffer-v8 or exact record shapes under struct-elements-v11 | Physical transport metadata only; no lifetime analysis or runtime cleanup channel |
| LLVM | Concrete pair loads/stores, checked allocation/deallocation, two parameter leaves and backend-only return carrier | Existing checked Slice indexing and target-qualified direct host allocator calls |

`BufferValueShape` is representation metadata over the canonical SliceType,
void* base type and int length type. It is neither a new semantic type nor a
universal expression or SSA value. `SsaBufferPair` is a SsaNode, not a SsaValue.
Its leaves come from one parameter group, allocation, call result or complete
storage read. Arbitrary base/length recombination and individual leaf transport
are rejected. No buffer phi silently combines different owner identities.

Representative semantic dump:

```text
(owned-buffer element=f64 owner=local#0 base+len cleanup=native-buffer-deallocate ...)
(owned-buffer-allocate element=f64 (count ...) zero-initialize)
(owned-buffer-borrow owner=local#0 slice=f64[] bounded non-owning)
(owned-buffer-move owner=local#0 base+len)
```

Allocation stays target-neutral in Core and CFG. The checked allocation operation
promises negative-count validation, canonical empty production, checked physical
byte size, zero initialization and nonempty failure trapping. The hosted LLVM
strategy expands its branches; libc symbols never enter Core. This composite
checked-operation design follows existing Slice bounds operations.

Owner replacement captures the complete incoming payload before disarming a
named source, cleaning the old live destination and storing the complete new
payload. Concrete Resource rearm uses the same existing flow authority for
OWNED → OWNED replacement. SSA consults exact flow facts when lowering; it then
independently verifies concrete group and memory actions. No runtime state bit
is introduced. Release/rearm and conditional ownership use null-disarmed storage
for guarded cleanup while source state remains semantic.

Field replacement retains receiver-first ordering and uses existing bounded
ResourceCapture/field-store machinery generalized to static buffer cleanup.
Field read/write operations carry their exact class field and cleanup identity.
Final destructor epilogues unify Resource and buffer fields in reverse declaration
order. OBJ-RET initialization stores the pair directly in final ObjectStorage.

Verification independently rejects invalid element/length authority, missing or
duplicated ownership consumers, mismatched cleanup, owner copies, partial pairs,
borrowed values stored as owners, missing parameter acquisition/result transfer,
uninitialized or released storage reads, missing normal cleanup, old-value
overwrite, duplicate deallocation and unsupported field disarm. Buffer borrow
provenance rejects replacement/destruction across live captured views, including
possibly aliasing containing-class calls. Existing bounds proofs remain required
before element Place address use.

Transfer capture lifetime is checked through the exact source disarm. A second
read/deallocation cannot destroy the captured allocation before that commit;
later cleanup of the disarmed empty slot remains valid. Every owned call
argument also names the disarm belonging to its own captured pair. Swapping
same-type arguments' commit metadata rejects independently of pair layout.

Standalone Core/CFG/SSA/NABI tests construct their own graphs. Pipeline tests
destroy Checked before Core verification, Core before CFG verification, CFG
before SSA verification and SSA before final NABI/LLVM artifact verification.
They also cover containing-class generic monomorphization and object forwarding.

No stage recovers ownership or elements from source spelling. NABI owns physical
boundary planning only. LLVM receives explicit group operations and layout;
the allocator backend does not run semantic ownership flow.
