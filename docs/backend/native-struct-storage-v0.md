# Backend-private native struct storage v0

TPTR-1 materializes aggregate storage only where addressability requires it:
an SsaAddressableStruct local or a direct/indirect SSA memory field operation.
A typed pointer signature used only for comparison needs no LLVM struct type.
Untouched STRUCT-1 locals still arrive as ordinary scalar SSA and produce no
aggregate type, alloca, GEP, or memory operation.

LlvmStructRegistry is private to `src/backend/llvm/`. It discovers needed
SsaStruct identities from storage/memory instructions and visits their ordered
SSA descriptors deterministically. It creates LLVM named structs such as:

```llvm
%astra.struct.0 = type { i32, i32 }
%astra.struct.1 = type { i32, i1, ptr }
```

Fields follow semantic declaration order. int becomes i32, bool i1, and opaque
void* ptr in this backend realization. LLVM computes padding, alignment, and
offsets for the configured target. Source field names do not define physical
identity; exact compiler field descriptors select declaration ordinals.

This is an internal, target-dependent implementation, unstable across compiler
versions. It defines no language struct ABI, C interoperability, stable bool
memory layout, sizeof, alignof, or offsetof. Upstream stages contain no sizes,
offsets, LLVM handles, or hand-computed padding.

## Storage and fields

Each SsaAddressableStruct receives one alloca in the primary LLVM entry block,
before user operations. It reserves frame storage but does not initialize it.
Lexical visibility remains semantic, and Initialize runs at its source control
flow position, including each loop iteration. The allocation may last for the
entire frame because lexical borrow checks prevent any pointer from surviving
its source scope. No lifetime intrinsics or runtime lifetime checks are needed.
Loop-body initialization still executes per iteration; break and continue need
no new backend lifetime operation.

SsaAddressOfInstruction maps its pointer result directly to that alloca.
Promoted pointer locals remain ordinary ptr values/phis, with no pointer-local
alloca.

Direct field addressing uses the exact storage alloca, backend struct type,
and field declaration ordinal through LLVMBuildStructGEP2. Indirect field
addressing uses the exact typed pointer value and matching backend struct type.
No byte offsets, ptrtoint/inttoptr, aggregate load, extractvalue/insertvalue,
memcpy, or memmove are needed. Loads use the field's scalar type.
Initialize and Store both realize scalar LLVM stores, while their semantic
distinction remains explicit in Astra SSA.

## Null traps and physical control flow

Every indirect Load or Store first compares its pointer with null. A null branch
calls llvm.trap and ends in unreachable. Only the non-null continuation computes
the GEP and performs memory access. Under BORROW-1, every constructible non-null
typed pointer addresses valid live storage in the active native call chain.

The Store instruction occurs after RHS computations, so `p->x = effect()` emits
the effect call before the null guard. Loads, stores, initialization, calls, and
trap-capable arithmetic retain SSA instruction order. Short-circuit paths may
skip the memory instruction entirely.

Null guards reuse the existing trap-block creation and per-source-block physical
end tracking used by division/remainder. The current end becomes the post-check
continuation. Branches, loop backedges, and phi incoming operands use that actual
physical predecessor. Qualification checks real LLVM successor identity,
including indirect access before branches, backedges, and short-circuit joins.

## ABI and artifact boundaries

Native Struct* parameters use existing NABI PTR / scalar-ptr-v1 and LLVM
`internal fastcc` functions with `ptr` parameters. Nullable aliases prohibit
inferred nonnull, noalias, nocapture, readonly, writeonly, dereferenceable, or
alignment parameter attributes. Ordinary LLVM memory instruction alignment is
backend layout information, not a language or parameter guarantee.

CABI remains void*-only; physical ptr coincidence does not authorize typed native
pointers at C imports/exports or in VAPI. NABI carries no struct layout or
aggregate channel. Existing scalar-v0/scalar-ptr-v1 dumps remain unchanged.

The qualified backend is LLVM 22.1.8. LLVM modules retain all physical aggregate
types after SSA descriptors die, and emitted native code has no dependency on
compiler IR, LLVM libraries, GLib, or a new Astra runtime. See
[execution](native-execution-v0.md), [SSA memory](../ir/addressable-storage.md),
and qualification.

BORROW-1 requires no production backend changes. Stored addresses, copies,
reassignments, branch/null phis, and loop pointer backedges all use existing ptr
SSA. One borrowed aggregate gets one alloca; pointer locals get none, and
untouched aggregates remain scalarized. Semantic regions expire before Core and
never reach LLVM. No pointer-to-integer conversion, region ID, borrow counter,
retain/release, heap allocation, ownership, or alias exclusivity is introduced.
See BORROW-1 qualification.
