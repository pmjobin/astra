# Whole-vector memory through ordinary Places

VEC-MEM-1 extends DPTR-1's capability predicate to valid numeric VectorTypes.
TypedPointerType owns the same exact semantic pointee identity. No new pointer,
dereference, memory Place, load, or store class is needed for vector storage.

| Stage | Representation and authority |
| --- | --- |
| Syntax | General PointerTypeSyntax wraps VectorTypeSyntax with a star; existing scalar TypeNameSyntax star tokens retain their spelling/dumps. |
| Checked | CheckedAddressOfExpression identifies the direct LocalSymbol, exact TypedPointerType and lexical region; CheckedDereferencePlace carries exact VectorType and CheckedLoadExpression/CheckedStore use it. |
| Core | CoreLocalPlace.address_taken, CoreAddressOfValue, CoreDereferencePlace, CoreLoadValue, CoreStore. |
| CFG | CfgLocalPlace.address_taken, CfgAddressOfValue, CfgDereferencePlace, ordinary load/store and the existing unconditional null-trap contract. |
| SSA | SsaAddressableLocal of VectorType, SsaLocalMemoryPlace or SsaDereferencePlace, ordinary SsaInitializeInstruction/SsaLoadInstruction/SsaStoreInstruction. |
| NABI | Typed pointer → PTR; a by-value vector remains a separate vector-v4 channel. |
| LLVM | Exact fixed-vector alloca/load/store and opaque ptr with existing null guard and final physical predecessor tracking. |

The vector pointer itself remains an ordinary promotable value. A vector local
whose address is taken anywhere in the checked body loses ordinary promotion
for its relevant lifetime; no block argument represents its authoritative
contents. An unaffected local remains one promotable vector value. Pointer and
direct stores share one explicit memory object, so aliases and native mutations
need no new alias analysis or exclusivity policy.

Conceptually, a source `loaded = *p` produces:

```text
%loaded : f32<4> = load (dereference-place %p : f32<4> null-traps)
store (local-memory v : f32<4>) %loaded
```

The result and store operand are each one vector SSA value. `(*p)[k]` adds an
ordinary VectorExtractValue/Instruction using that result. It does not create a
LanePlace, and its source cannot be assigned. `*p = insert(*p,k,x)` is load,
whole-vector value insertion, whole-vector store. No frontend lane-load or
lane-store expansion occurs. Physical LLVM legalization is separate.

Core/CFG/SSA independently validate supported exact vector pointees, canonical
element/vector/pointer identities, exact address/load/store types, provenance,
initialization, and the existing promotion and dominance invariants. Bool mask
pointees reject without freezing object representation. Stage destruction tests
retain complete exact type and storage information without earlier-stage graphs.
LLVM types, numeric alignment, and layout remain absent through NABI.

| Vector element | Exact LLVM memory type |
| --- | --- |
| i8/u8 | `<N x i8>` |
| i16/u16 | `<N x i16>` |
| int/i32/u32 | `<N x i32>` |
| f32 | `<N x float>` |

The backend's existing alloca and load/store builders consume these exact types.
LLVM determines alignment from its DataLayout; tests compare every emitted
alignment with the configured target's ABI alignment for all 20 shapes. No
frontend payload-width alignment calculation or hardcoded 16-byte rule exists.
Alignment numbers recorded during qualification are evidence for that target,
not source semantics. Local construction and compatible native forwarding
provide suitably aligned live exact objects.

The existing memory_address/guard_nonnull path compares the opaque pointer with
null, branches to trap/unreachable or a continuation, then performs the vector
access. Null stores preserve RHS effects before that guard. CFG source edges do
not change; LLVM records the final continuation as the actual predecessor for
branch, loop and short-circuit phi inputs. No GEP or inbounds assumption is needed.

Integer lane bits and f32 binary32 values survive transport without arithmetic,
conversions, or fast-math flags. Backend splitting makes no new semantic lane
operation and no atomicity, volatile, synchronization or tearing contract. Source
byte order, lane offsets, padding, register packing and numeric alignment remain
unexposed. Null, borrowing, ownership and native argument evaluation rules are
unchanged.

A vector pointer alone selects no new ABI profile. Actual by-value vector
parameters/results still select vector-v4; scalar output pointers can receive
dot/MAC results. CABI/VAPI remain deferred. Qualified execution remains default
x86-64 Linux. Arrays/slices, arithmetic/indexing, vector fields, mask memory,
unaligned memory and foreign vector pointers require explicit future decisions.

See [dereference Places](dereference-places.md), [ADR 0044](../decisions/0044-vector-memory.md),
and the audit and acceptance report.
