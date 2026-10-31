# Object reference values

[Computed property](properties.md) get/set operations call exact stage-owned
accessors. Class-reference preparation uses the existing object validation value
and ReceiverType contract. A setter validates the reference before its RHS;
live `this` requires no redundant guard. Property descriptors are compiler-owned
semantic metadata and never add object storage or runtime descriptors.

[Owned object results](object-results.md) retain one exact ClassType pointer-like value and the separate owned-transfer contract. The hidden result input supplies fresh storage; the ordinary returned owner PTR may be null or forwarded. No aggregate ClassType value, runtime descriptor or storage-kind tag is introduced.

[OBJ-OWN-1](object-ownership.md) retains this exact ClassType value representation.
Transferability belongs to LocalSymbol/CoreOwnedLocal and the owned parameter
contract, never a type variant. CheckedOwnershipMove/CoreOwnedArgumentValue carry
exact source, class cleanup authority and local ObjectStorage identity. Temporary
owner borrows use the existing owned-borrow value nodes; persistent owner copies
reject. Ordinary unqualified references retain their existing copy/rebind rules.

OBJ-BOUND-1 adds one exact ClassType parameter value with the existing
PointerParameterContract.BORROWED_NOESCAPE. CheckedParameterReferenceExpression,
CoreParameterValue, CfgParameterValue and SsaFunctionParameter retain that identity
and contract. Local copies and SSA phis carry one reference; no ObjectStorage
parameter or whole-object value exists. Null remains contextually exact ClassType.
Only NativeTypeMapper.map_parameter erases it to PTR after semantic verification.
See [borrowed object boundaries](../decisions/0051-borrowed-object-boundaries.md).

OBJ-LIFE-1 publishes the same ClassType reference only after a constructor returns
normally or complete brace initialization succeeds. Constructor/destructor symbols
are distinct from MethodSymbol, with INITIALIZING/LIVE receivers respectively.
Their ObjectStorage holds optional destructor authority and a stable cleanup rank;
reference copies, nulls, rebinding and SSA block arguments have none. Destructor
operands are explicit original storage addresses, never loads of current reference
bindings. See [lifecycle IR](object-lifecycle.md).

OBJ-1's immutable ClassType has exact nominal identity and `TypeKind.CLASS`.
ClassSymbol creates one canonical ClassType; no structure or name comparison
substitutes for identity. ClassType owns no semantic declaration backlink, so it
survives stage destruction independently. It is neither StructType nor
TypedPointerType. `is_nullable_pointer_value()` admits it for contextual null
and exact equality, while typed pointee/addressability still reject it. Canonical
borrowed/owned parameter and owned-result mappings use its physical PTR representation.

## Shared member and call authority

NativeInstanceSymbol supplies ordered fields, ordered methods, name/provenance,
an ordinal and a receiver contract. StructSymbol and ClassSymbol specialize it
with distinct nominal types. Class and struct ordinals have separate deterministic
source-order domains. The shared native-instance traversal visits structs then
classes; the pre-OBJ struct/function ordering and physical symbols stay stable.
Methods retain their mixed-member ordinal, separate method ordinal and exact
owner. All identities and signatures precede body checking.

There is one MethodSymbol/ReceiverSymbol pair, one CheckedMethod body family,
and one CoreMethod/CfgMethod/SsaMethod family. The exact `declaring_type` can be
a native struct or class descriptor. The same call nodes and native signature,
recursion, borrow and ownership pipeline handle both. Historic struct-specific
field class names and compatibility getters are retained; they do not imply
struct semantics for class fields.

## Reference representations

| Stage | Storage reference producer | Copies/null/identity |
| --- | --- | --- |
| Checked | CheckedObjectConstruction owns CheckedObjectReferenceExpression and LexicalObjectStorageSymbol | Ordinary ClassType LocalSymbol reads, assignments, contextual null and binary equality |
| Core | CoreObjectConstruction associates separate CoreObjectStorage with the target CoreLocalPlace | Ordinary CoreLoadValue/CoreInitialize/CoreStore, CoreNullPointerValue and exact CoreBinaryValue |
| CFG | CfgObjectReferenceValue publishes storage after all field initializations | Ordinary evaluated values, ClassType local flow, null and binary values |
| SSA | SsaObjectReferenceInstruction returns one ClassType definition | Ordinary scalar definitions, pointer-like block arguments, null constants and bool-result comparison |
| LLVM | Reference is the lexical alloca's opaque pointer | Pointer SSA/copy, `null`, `icmp eq/ne ptr` |

Construction never produces an aggregate object Value. Reference assignment
never emits object field initialization or a memory copy. The source local and
backing storage are different objects in every stage that has both. At SSA the
reference local is promoted; its storage descriptor is retained independently.
Branch and loop ClassType block arguments carry only one reference. Object/null
merges retain normal null validation at later field/method accesses.

Checked reference provenance uses BorrowProvenance and the existing LexicalRegion
tree. Construction originates at LexicalObjectStorageSymbol; literal null has
NULL provenance; local reads conservatively originate at the reference local.
The usual same/ancestor rule applies to initialization and rebinding. Downstream
storage retains region and construction ordinals. BorrowProvenance.snapshot()
can copy an OBJECT_STORAGE origin into the existing immutable provenance format;
SSA storage publication records that exact storage/region snapshot. Ordinary
reference local loads and phis do not carry full origin sets: the stored-borrow
lifetime proof is completed in semantics, as in the existing conservative model.
Core also retains the construction scope. OBJECT_STORAGE is a lifetime origin,
not a TypedPointerType conversion or new borrow checker. No semantic region or
symbol graph survives into Core.

## Null validation and field Places

CheckedObjectFieldPlace retains the reference expression, exact field symbol,
exact field type and null-trap contract. Core generalizes CoreIndirectFieldPlace
to admit that exact ClassType base. CFG evaluates a CfgObjectValidateValue before
forming the indirect field Place and before lowering RHS effects. SSA retains
SsaObjectValidateInstruction at that sequence position; its result feeds the
ordinary SsaIndirectFieldPlace. Loads/stores remain explicit memory operations.
A validation preserves ClassType for a field base.

For a method, CheckedObjectReceiverExpression and CoreObjectReceiverValue
validate the nullable reference into the existing ReceiverType for that exact
class. CFG/SSA validation produces that existing contract before any explicit
argument evaluation. This is receiver preparation in the shared call pipeline,
not a parallel method subsystem. Captures, slice construction, effectful
arguments, owned-transfer commit and the call follow in source order. An incoming
`this` already satisfies the contract and creates no validation instruction.

Verifiers check program-owned nominal identities, category and class ordinals,
member uniqueness and exact receiver/field ownership. They reject mismatched
class comparisons, unchecked class field bases, wrong receiver contracts,
unmanaged ClassType parameter contracts and aggregate/storage misuse. CFG/SSA require
initialization to precede and dominate reference publication. Independent tests
build both valid and malformed IR without semantic/parser dependencies.

## ABI and stage lifetime

NABI profiles remain unchanged. The implicit method receiver uses the existing PTR; explicit
vector or slice channels select their existing effective profile. Body-only
ClassType values do not affect ABI selection. NativeFunction copies declaring
category and member ordinals for distinct class/struct physical symbols.
NativeTypeMapper admits canonical borrowed/owned ClassType parameters through
existing PTR channels. PARAM-BORROW-1 resolves plain and explicit borrowed spelling
to the same contract before Core; ABI mapping never consults source qualifiers.
CABI and VAPI add no object boundary support.

CoreClass, CfgClass and SsaClass own their stage's member identities; storage and
method owner backlinks are weak to avoid cycles when a method constructs its
own declaring class. ClassType is retained directly by the stage. Tests release
every predecessor and verify/dump the successor, then release SSA/NABI and emit
LLVM machine objects from the surviving artifact. There is no LLVM dependency
through NABI.

See [storage](object-storage.md), [methods](methods.md),
[language](../language/objects.md) and qualification.
