# Object ownership through the shared pipeline

[Owned Resource fields](owned-resource-fields.md) extend the containing class's
exact destructor authority. Object moves, result forwarding and concrete Ownable
specialization preserve ObjectStorage and transfer eventual field cleanup
transitively. No field owner state, field-by-field relocation, ABI channel or
runtime destructor pointer is added.

[OBJ-RET-1](object-results.md) reuses Checked/Core ownership return, CFG return capture and SSA ownership return. Native result producers now support the object payload domain through the existing exact class cleanup contract. Object results additionally retain provenance and caller-provided storage; nullable ownership and source disarming use the existing state authority.

OBJ-OWN-1 extends OWN/MOVE/OWNBOUND responsibility payloads. It does not introduce
an owned ClassType variant, OwnedObjectStorage, object-specific transfer solver,
a semantic NABI object type or a new profile. The physical allocation remains lexical.

## Checked authority and Core

LocalSymbol retains exact ClassType, `TRANSFERABLE_OBJECT_OWNER`, exact
`object_owner` ClassSymbol, optional local `object_storage`, lexical region and
optional incoming ParameterSymbol. Its foreign cleanup field remains absent for
objects. CheckedObjectConstruction and CheckedConstructorObjectInitialization
still allocate the ordinary LexicalObjectStorageSymbol. CheckedOwnershipMove
retains the source binding, class cleanup authority and exact storage when local.
CheckedOwnedArgument retains the exact parameter and `OWNED_TRANSFER` contract;
null supplies class cleanup authority without a source or storage.

CoreCleanupContract now carries either the existing foreign cleanup symbol or an
exact native CoreClass. The class supplies its existing CoreDestructor, optionally
absent for lifetime-only cleanup. Weak stage-owned class links avoid ownership
cycles and checked-stage retention. CoreOwnedLocal retains the same owner Place,
scope and cleanup contract, plus exact ObjectStorage for a fresh object owner.
CoreObjectConstruction has an acquisition marker. Owned parameter slots retain
CoreAcquireParameter. CoreOwnedArgumentValue is the common move/call argument form.
There are no source-name lookups downstream.

CoreObjectStorage's compile-time transferable mode is independent of identity.
The verifier checks unique fresh construction and the exact matching owner,
class, storage, scope and cleanup contract. It rejects a fixed reference used as
an owner, cross-class transfers, owner rebinding, local owner destinations,
persistent owner copies and direct/nested receiver self-consumption. Structured
Core retains source ownership operations; path-state validation is performed by
the established CFG OwnershipFlow, as for Resource ownership.

## CFG ownership, temporary views and ordering

CfgLocalPlace carries cleanup authority and, for a local object owner, the exact
CfgObjectStorage. CfgAcquireParameter establishes the incoming owner capability.
Successful construction publishes the exact storage reference and CfgInitialize
acquires it. Failed argument/constructor evaluation has no acquisition event.
Fixed lifecycle verification checks construction and hands transferable lifetime
responsibility to the existing owner flow; fixed storage still requires its own
exact lexical destructor edge.

```text
argument evaluation / CfgOwnedBorrowInstruction
CfgOwnedArgumentCapture        # semantic OWNED -> MOVED
later argument evaluation      # may trap
CfgOwnedCallTransferCommit     # exact pending identities, immediately before call
CfgCallInstruction             # old captured pointers
...
CfgCleanupInstruction          # current owner capability, null-aware
```

The same OwnershipState possibility set contains OWNED, MOVED and their join
(the existing dump spelling is MAYBE_OWNED). Object operations never produce
RELEASED or rearm events. Reads require definitely OWNED. The existing fixed point
handles conditional transfer, loop-carried possibilities and cleanup exits. Null
pointer bits never authorize source use.

ClassType temporary borrowing uses the same Checked/Core/CfgOwnedBorrowValue
adaptation as Resource borrowing. PARAM-BORROW-1 requires a borrowed object's
owner to remain live through invocation even when that call also receives a
pending ownership transfer. The old exception is removed. A nested earlier
consumer cannot extend the outer borrow. Resource through-invocation behavior
stays unchanged. Captured method/field bases are checked at their actual use, preventing
an argument/RHS consumer from destroying the base first.

For borrowed input references that may alias owned inputs of the same ClassType,
OwnershipFlow derives a conservative provenance closure over existing parameter
copies and assignments. A view read checks the relevant incoming ownership state;
forwarding a potentially aliasing borrowed view and owner together rejects. Fresh independent
construction does not inherit an input-borrow dependency. This closes the concrete
same-call alias/forwarding hazard without introducing stored borrows from owners,
NLL, new runtime data or a separate ownership engine. Conservative provenance can
reject a view whose independence is known only to its caller.

CfgVerifier checks unique pending captures, exact source/parameter/class/cleanup,
capture dominance, source uniqueness, and commit adjacency. A transferable storage
has exactly one owner; its acquisition must use that storage's published pointer.
Fixed deinit cannot silently discharge a transferable owner. Persistent owner
alias stores reject. Object lifecycle and ownership flow remain LLVM-free.

## One lexical cleanup order

CleanupScope.acquired contains CoreCleanupAction. `OBJECT_DEINIT` targets fixed
ObjectStorage. `OWNED_DESTROY` targets CoreOwnedLocal and its payload-specific
contract, whether Resource or object. There is one reverse traversal, with root
locals before parameters and parameters reversed. Return expressions are captured
before cleanup. Resource rearm keeps its existing rank; objects cannot rearm.

Fixed cleanup always calls the original lexical storage's destructor. Transferable
cleanup emits CfgCleanupInstruction on the current owner pointer, including for a
class without deinit. Thus semantic responsibility survives independently of
whether backend cleanup needs a call.

## SSA, native ABI and LLVM

SSA uses one ClassType pointer-like value. Capture preserves its current value;
commit adds a SsaNullPointerConstant definition to the existing promoted owner
stack. Conditional control flow merges original PTR and null. SsaOwnedArgument
retains exact parameter, cleanup, source ordinal, committed null definition and
original local SsaObjectStorage where applicable. Verification ties the local
transfer pointer to its exact construction instruction. SsaCleanupInstruction
uses the current value and the stage's exact class/destructor contract.

NativeTypeMapper maps owned ClassType parameters to existing PTR, using pointer-v1
or the already-selected integer/f32/vector/slice profile. Owned ClassType results additionally use the hidden PTR plan in OBJ-RET-1;
unqualified/borrowed results remain rejected. Native enums and profiles are
unchanged. CABI represents foreign cleanup only; its builder/validator and LLVM
correspondence filter native object cleanup without changing any C boundary rule.

LLVM emits one `alloca %astra.class.N` at the original caller's construction site.
The consuming callee receives that original pointer, with no object alloca/copy.
Object cleanup branches around the exact fastcc destructor when the capability
is null; foreign Resource cleanup retains its C binding. A compile-time null
comparison may fold to a constant branch, leaving an unreachable dtor(null) block
until optimization. Forwarders consequently skip their own destruction. No
allocator/deallocator, memcpy/memmove, header, refcount, GC, active i1, `noalias`,
`nonnull`, `readonly`, `byval` or `sret` is introduced. Fields stay memory-backed.

All stages retain their own class, storage and cleanup authority after upstream
stages die. NABI/CABI retain only physical authority, and the final LLVM artifact
retains none of the semantic graph. Traps are non-unwinding before and after
commit; they create no cleanup edge or runtime ownership stack.

## Generic ownership

Ownable Class specializations reuse exact class responsibility, ObjectStorage, incoming owner slots, destructor identity and object-result provenance. Incoming owner returns and recursion preserve the original storage; caller candidate storage appears only after concrete Class specialization. Empty/no-deinit classes remain lifetime-bearing without extra metadata. See [generic ownership IR](generic-ownership.md).
