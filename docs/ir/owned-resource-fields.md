# Owned Resource fields in the pipeline

OWN-FIELD-1 extends exact native class field metadata. Ownership remains separate
from nominal Resource identity. The existing HandleType is used throughout; no
OwnedType, runtime field flag or new ABI channel exists.

## Checked and independent Core

FieldSymbol.owned_cleanup retains the exact normalized foreign release contract;
semantic_type retains the nominal Resource, and ownership_kind is OWNED_FIELD.
The existing field identity, ordinal and source spans supply owner and provenance.
CheckedOwnedFieldTransfer retains the destination Place, exact field, incoming
move/result, and initialization-versus-replacement mode. CheckedOwnedFieldBorrow
retains the source Place and exact borrowed parameter or null-comparison use.

CoreStructField.owned_cleanup maps to an independent program-owned
CoreCleanupContract, paired with the exact CoreHandle's type and cleanup.
CoreOwnedFieldTransfer keeps a CoreIndirectFieldPlace and exactly one incoming
CoreOwnedLocal or direct CoreCallValue/CoreCCallValue. Its `initializes` flag is
compiler metadata for the operation, never a persistent runtime field state.

```text
(field #0 "resource" : R (ownership owned-field) (cleanup #0 of_release))
(owned-field-init (cleanup #0) ... (move-source #0))
(owned-field-replace (cleanup #0) ... (incoming owned-result))
(owned-field-borrow temporary-noescape ...exact field Place...)
```

Constructor definite/possible field analysis is reused. Core independently checks
field eligibility, nominal cleanup identity, exact constructor receiver, one
initialization on every normal path, no premature read/borrow, no duplicate init,
and legal incoming producers. Ordinary CoreInitialize/CoreStore/CoreLoadValue
cannot stand in for owned-field operations. No move-out or release-to-empty node
exists. Concrete named owner flow continues through the existing CFG
OWNED/MOVED/RELEASED authority.

CoreDestructor.field_cleanups is a normal-exit epilogue of exact
CoreOwnedFieldCleanup actions in reverse declaration order. Core checks missing,
extra, duplicate, reordered and mismatched cleanup identities. A class without
user deinit receives an exact synthetic CoreDestructor sharing its class's LIVE
receiver contract. User returns and fallthrough both execute the epilogue after
ordinary local cleanup. A trap has no cleanup edge.

Checked destruction leaves the Core fields, cleanup authority and lifecycle
semantics independently verifiable. Generic monomorphization preserves concrete
field operations and ordinary containing-class Ownable contracts. Temporary
borrow overlap is independently validated while checking call arguments; there
is no destructor-specific restriction or call-graph analysis.

## CFG

Initialization expands to receiver resolution, incoming production, concrete
CfgResourceCapture and CfgInitialize. Replacement expands to:

```text
validate object receiver
produce incoming Resource
resource-capture: stabilize handle, consume named source or owned result
cleanup (load exact old field), null guarded
store captured incoming handle into exact field
```

Receiver validation precedes the producer; the old field is not loaded before
production succeeds. Capture is an explicit concrete ownership event, feeding
one immediate initialization or cleanup/store pair. CFG verifies exact capture,
source and release contracts and ordered unique store consumption. Existing
ownership flow marks named sources MOVED. No field-state lattice or generic
ownership field enters CFG. Borrowing lowers to an ordinary concrete handle load.

Every normal destructor exit has exact reverse field loads and cleanup actions
following the user body and its local cleanup. CFG independently verifies the
suffix from physical field identities and nominal Resource cleanup authority.
Traps terminate without unwinding. Core can be destroyed before CFG verification.

## SSA, ABI and LLVM

SSA removes concrete capture events: it preserves the incoming handle value and
null-disarms the named source's ordinary pointer definition. Fields stay in the
existing memory-backed ObjectStorage. Replacement is ordinary handle load,
SsaCleanupInstruction and store. Destructor epilogues are ordinary handle loads
and direct cleanup instructions; their order is independently verified. SSA owns
no high-level field-ownership type and can outlive CFG.

NABI has only the existing class/resource PTR channels and existing object result
storage contract. CABI/VAPI continue to supply Resource release contracts but do
not import/export native class layouts. LLVM lowers the existing physical handle
representation and null-guarded direct release calls. No generic ownership policy,
object memcpy, heap, header bit, field-active bitmap, destructor pointer, dynamic
cleanup table or runtime dispatch reaches the backend.

See [language rules](../language/owned-resource-fields.md),
[ADR 0064](../decisions/0064-owned-resource-fields.md), and
qualification.
