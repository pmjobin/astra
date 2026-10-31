# Owned object results through the pipeline

An exact ClassType with `ResultOwnershipContract.OWNED_TRANSFER` is one semantic
owned result. The contract is shared with Resources. Object results additionally
require exact storage provenance and caller-provided candidate storage; they do
not introduce an OwnedClassType, whole-object value, allocator or runtime flag.

| Stage | Result authority | Fresh/forwarded representation |
| --- | --- | --- |
| Checked | `FunctionSymbol.result_storage`, `ResultObjectStorageSymbol` | `CheckedOwnedObjectResultConstruction`, `CheckedOwnershipReturn.producer`, `CheckedCallExpression` destination |
| Core | `CoreFunction.result_storage`, `CoreResultObjectStorage` | `CoreOwnedObjectResultConstruction`, shared `CoreOwnershipReturn` |
| CFG | `CfgFunction.result_storage`, `CfgResultObjectStorage` | `CfgResultConstructionInstruction`, shared `CfgOwnedReturnValue` capture |
| SSA | `SsaFunction.result_storage`, `SsaResultObjectStorage` | Pointer-like input, `SsaResultConstructionInstruction`, shared `SsaOwnershipReturn` |
| NABI | `NativeSignature.object_result` | `NativeOwnedObjectResultPlan`: candidate PTR and owner PTR |
| LLVM | First hidden `ptr %result.storage` | Direct fastcc ctor call, direct PTR result |

Every stage owns its class/storage/callable identities. Backlinks to declaring
classes are weak. Checked symbol maps die at Core construction, Core maps die at
CFG construction, and CFG maps die at SSA construction. The independent NABI model
contains physical channels only. LLVM needs no semantic ClassSymbol lookup.

## Provenance and verification

`ObjectResultProvenance` distinguishes RESULT_STORAGE, OWNED_PARAMETER_STORAGE,
FORWARDED_OWNED_RESULT, CALLEE_LOCAL_STORAGE, BORROWED_STORAGE and NULL (plus NONE
for the Resource domain). Only the first three and NULL may escape as a result.
A direct call forwarding a same-result-class local owner also rejects. A local
acquired from an owned result remains conservatively local, since its candidate
might have been used; directly forwarding the call preserves ancestor storage.

Core verifies exact result ClassType, ownership contract, constructor class,
function-owned result input, source parameter identity, legal provenance, and
candidate/result destination exclusivity. Ordinary return cannot bypass the owned
result contract. A fixed or borrowed pointer cannot substitute for an owner.

CFG verifies construction and successful capture in the same returning block,
exact forwarded producer and hidden input, and return capture before lexical
cleanup. Return construction must feed that block's ownership return. Pending
owned-call transfers still use the existing ordered capture/commit sequence.
An owned-result call has one immediate acquisition or return consumer; Resource
rearm retains its previous contract.

SSA retains candidate allocations separately from the pointer-like result input
and returned owner values. Fresh results return that input after one exact ctor
call. Null provenance requires a null pointer. Parameter return preserves the
incoming owner pointer. Forwarded results preserve the nested call's pointer and
same hidden candidate. Verifiers reject illegal storage sources and cleanup of
the transferred pointer. No whole-object SSA value or storage-location phi exists.
Owner pointers can still participate in ordinary ownership/control-flow phis.

## Caller allocation and responsibility

Lexical candidate ObjectStorage has a compile-time `result_candidate` marker and
is unique to a producing acquisition site. CFG and SSA reject two live acquisitions
sharing one candidate and reject independent lexical initialization/publication of
candidate bytes. It is not the acquired owner's original
`object_storage` authority. Acquisition initializes the visible owner from the
call result and registers existing null-guarded owner cleanup. It creates no
candidate field initialization, fixed-object cleanup, registration descriptor or
runtime active flag. Fixed lexical construction and existing consuming owners
retain their previous representation and cleanup ordering.

Nullability is orthogonal to OWNED/MOVED possibility states. OWNED can contain a
legitimate null pointer; MOVED is forbidden to read. Null disarming and cleanup
reuse the same CFG ownership flow and SSA definitions as Resource ownership.
Returning move captures before null disarming and all remaining root cleanup.

## Physical signature

```text
owned Counter make(int n):
    hidden candidate PTR, I32 -> owner PTR
owned Counter make(f32<4> values):
    hidden candidate PTR, VECTOR(F32,4) -> owner PTR
owned Counter make(borrowed int[] values):
    hidden candidate PTR, slice.base PTR, slice.len I32 -> owner PTR
```

The hidden channel precedes the method receiver, if any, then explicit parameter
components in their existing order. It changes no source parameter ordinal.
Existing scalar-ptr-v1, vector-v4 and slice-v5 policies select from the effective
signature. The result maps to PTR only with its owned result contract; generic
ClassType-to-NABI type mapping stays unsupported. No object-result-v6 exists.
CABI/VAPI object boundaries remain unchanged and unsupported.

```llvm
define internal fastcc ptr @astra.fn.0(ptr %result.storage, i32 %p0) {
	call fastcc void @astra.ctor.0(ptr %result.storage, i32 %p0)
	ret ptr %result.storage
}
; caller:
; %candidate = alloca %astra.class.0
; %owner = call fastcc ptr @astra.fn.0(ptr %candidate, i32 42)
; cleanup guards and destroys %owner
```

The factory allocates no returned object in its own frame. Forwarding passes the
same `%result.storage` and returns the nested owner PTR. Parameter return may
ignore candidate storage completely. Cleanup follows `%owner`, never candidate
storage unconditionally. No heap operation, memcpy/memmove, byte relocation,
`sret`, `byval`, speculative `noalias`, or nonnull result attribute is emitted.

Constructor signatures remain void with an initializing exact-storage receiver.
Argument and constructor traps do not unwind. Successful construction precedes
remaining lexical destruction; a later callee cleanup trap still returns no owner.
The candidate is not a callee cleanup responsibility.

See [language rules](../language/object-results.md),
[ADR 0053](../decisions/0053-owned-object-results.md), and
qualification, including O2, machine and memory evidence.
