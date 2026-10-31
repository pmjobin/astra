# Object lifecycle IR

[OBJ-OWN-1](object-ownership.md) adds transferable owner responsibility alongside
fixed lexical lifecycle actions. Successful owned construction acquires the
original storage pointer through the shared owner machinery. The common cleanup
contract selects exact native class/destructor authority or foreign Resource
cleanup. Transferable cleanup uses the current null-disarmable capability; fixed
cleanup still targets its original storage. Both use the same lexical ordering
and the same DestructorSymbol. Classes without deinit still own semantic lifetime.

Lifecycle authority follows ObjectStorage from checked semantics through LLVM.
The ClassType reference published after construction is an ordinary nullable SSA
value and owns no cleanup. All object/reference layout and provenance contracts
from [OBJ-1 storage](object-storage.md) and [values](object-values.md) remain intact.

## Identity and shared callable bodies

| Stage | Constructor | Destructor | Construction/cleanup authority |
| --- | --- | --- | --- |
| Checked | ConstructorSymbol / CheckedConstructor | DestructorSymbol / CheckedDestructor | CheckedConstructorObjectInitialization, LexicalObjectStorageSymbol |
| Core | CoreConstructor | CoreDestructor | CoreConstructorObjectInitialization, CoreObjectStorage, CoreCleanupAction |
| CFG | CfgConstructor | CfgDestructor | CfgLifecycleCallInstruction with exact CfgObjectStorage |
| SSA | SsaConstructor | SsaDestructor | SsaStorageReceiverInstruction and SsaLifecycleCallInstruction with exact SsaObjectStorage |
| NABI | NativeFunction CONSTRUCTOR | NativeFunction DESTRUCTOR | Exact kind/class ordinal, receiver PTR, no physical result |
| LLVM | `astra.ctor.N` | `astra.dtor.N` | Direct call using original `%objectN` alloca address |

Lifecycle symbols are siblings of MethodSymbol under FunctionSymbol, through
LifecycleSymbol. Later stages use the same pattern with their own Function base;
none retain an upstream lifecycle declaration. CallableKind distinguishes FUNCTION,
METHOD, CONSTRUCTOR and DESTRUCTOR. Source spans, exact class/type, mixed-member
ordinal, parameter order/contracts and receiver survive each stage. Separate class
ordinals provide deterministic constructor/destructor identities; lifecycle members
never enter ordinary method lookup. All signatures precede body checking.

Shared callable infrastructure supplies native parameter checking, body scopes,
Resource owned parameters, local cleanup, CFG blocks, SSA values, NABI signatures
and LLVM function emission. The common void type is a no-result sentinel: there
is no source constructor result or physical object-reference result. Destructor
explicit parameter arrays are empty. Explicit ClassType boundaries remain invalid.

ReceiverType adds mode INITIALIZING beside existing LIVE. A constructor receives
one exact immutable receiver belonging to its class; a destructor receives the
class's live receiver contract. Both identify mutable nonnull storage, never a
rebindable local, transferable owner or ordinary ClassType value. Mode survives
through SSA and is checked before mapping to PTR. No separate native receiver
channel or source pointer conversion is created.

## Definite field initialization

CheckedFieldInitialize retains an exact CheckedReceiverFieldPlace and checked RHS.
CoreFieldInitialize extends CoreInitialize against a CoreIndirectFieldPlace whose
pointer is the exact initializing receiver. CFG uses CfgInitialize on that receiver
field and SSA uses SsaInitializeInstruction, preserving initialization through the
last LLVM-free stage. Ordinary methods/destructors retain Store for field mutation.

FieldInitializationState contains definite/possible bit sets indexed by verified
exact field ordinals, plus reachability. These are compiler analysis data only.
The transfer for `Initialize(field, rhs)` first checks RHS reads, requires the
field absent from possible, then adds it to both sets. Reads require definite.
Joins intersect definite sets and union possible sets from reachable predecessors.
Normal constructor completion requires all fields definite. This detects missing,
read-before-init, double and maybe-double initialization without path enumeration.

Semantic analysis tracks exact structured control flow. Core independently
revalidates it, including loop restrictions, explicit returns and receiver-mode
restrictions. CFG and SSA each solve an independent monotone fixed point, then
validate reads/writes against block-entry states and normal exits. No upstream
analysis object supplies unchecked physical authority. Literal constructor edges
are pruned by CFG lowering so unreachable field reads disappear before LLVM;
nonliteral branches remain subject to conservative definite initialization.

Constructor loops may calculate locals or read already initialized fields. They
cannot initialize receiver fields, and ordinary instance calls on initializing
`this` cannot form a live receiver. Explicit constructor returns reject; the
ordinary function-end terminator denotes successful constructor fallthrough.
Trapping paths have no normal-success obligation and no cleanup unwind edge.

## Caller construction and activation

CoreConstructorObjectInitialization retains the exact constructor, ObjectStorage,
new reference local, ordered arguments, lexical region/scope and provenance. Its
brace initializer array is empty. The verifier rejects mismatched constructors,
duplicate storage construction, stale identities and brace bypass of explicit init.
Checked/Core brace construction remains complete ordered initialization for classes
without a constructor. Each storage exposes its exact class destructor and stable
cleanup rank assigned from the lexical declaration ordinal.

CFG lowers a constructor construction in this order:

1. Retain the lexical storage reservation (no source effect).
2. Evaluate/capture explicit arguments left to right using CALL-1/OWNBOUND-1.
3. Emit any OwnedCallTransferCommit immediately before the call.
4. Emit an effectful, resultless CfgLifecycleCallInstruction to the exact constructor,
   with CfgStorageReceiverValue naming the original storage and initializing mode.
5. On normal continuation, register that storage's destructor in the current
   compiler CleanupScope and publish CfgObjectReferenceValue to the fresh local.

Brace construction takes steps 4's place with all exact ordered field Initialize
operations. Publication requires complete successful initialization. Neither
constructor nor brace failure has a normal continuation that can activate cleanup.
The lexical alloca can be hoisted without making arguments or the reference local
visible early. Constructor bodies never allocate/copy their receiver storage.

SSA makes the storage-address receiver an explicit SsaStorageReceiverInstruction
and retains a resultless exact lifecycle call. Publication becomes the existing
SsaObjectReferenceInstruction. Reference assignment, nulling and block arguments
remain ordinary SSA and cannot change the cleanup operand.

## One lexical cleanup planner

CfgBuilder's existing CleanupScope.acquired array now holds CoreCleanupAction:
OWNED_DESTROY targets the existing CoreOwnedLocal slot for Resources or transferable objects; OBJECT_DEINIT targets fixed CoreObjectStorage. Acquisition, transfer and rearm retain Resource slot semantics.
Successful object construction appends one action if the class declares deinit.
Copies/null references append nothing. The existing emit_cleanups traversal visits
the same list in reverse, from inner to outer applicable scopes. There is no
separate object cleanup inserter.

For an object action, this traversal emits CfgLifecycleCallInstruction to the
exact destructor with the original storage address and LIVE receiver. Resource
actions still emit their existing CfgCleanupInstruction. Return evaluation and
ownership result preservation precede this traversal; fallthrough, break,
continue and body backedge reuse their existing scope-exit paths. Constructor
and destructor bodies use the same mechanism for their own locals/owned inputs.

CfgObjectLifecycleFlow and SsaObjectLifecycleFlow are verifiers of explicit IR,
not planners. Their compiler-only path sets describe inactive storage,
constructor-returned storage and live storage with destructor responsibility.
They converge before checking exact transitions, reject premature/duplicate or
missing cleanup on normal exits, and check reverse ranks among active objects.
Structural checks also require exact storage/class/destructor association,
constructor dominance before reference publication and complete brace initialization.
Unified mixed Resource/object order is determined by the single planner and
qualified by ordered CFG and native-effect fixtures.

No phase set is lowered into runtime bits. Traps have no unwinding successor.
A destructor trap prevents subsequent emitted calls from executing. Reference
liveness never changes source cleanup position, and there is no last-reference
cleanup, registration list, finalizer table or runtime invalidation of aliases.

## NABI and LLVM

NativeFunction retains a stage-independent NativeCallableKind, exact class ordinal
and internal linkage. NativeSignature.receiver is the existing PTR first, followed
by the unchanged explicit parameter groups. Constructor/destructor results are
null in the physical signature. Receiver-only/int signatures use scalar-ptr-v1;
f32/narrow integer/vector/slice signatures select the existing effective profile.
For `init(borrowed f32<4>[] blocks)`, slice-v5 expands to PTR receiver, PTR base,
I32 length. Resource borrowed/owned parameters remain PTR. No profile/channel,
CABI or VAPI lifecycle support is added.

```llvm
%astra.class.0 = type { i32 }
define internal fastcc void @astra.ctor.0(ptr %this, i32 %initial) {
	%field = getelementptr %astra.class.0, ptr %this, i32 0, i32 0
	store i32 %initial, ptr %field
	ret void
}
; Caller owns %object0 before this direct call:
; call fastcc void @astra.ctor.0(ptr %object0, i32 42)
; ... reference copies/rebinding/nulling ...
; call fastcc void @astra.dtor.0(ptr %object0)
```

The storage receiver instruction binds an existing backend alloca address; it
creates no new object, receiver alloca, pointer result or memory copy. Field
Initialize becomes an exact private-layout GEP/store. Deinit uses the original
address even if every reference local has changed. Calls are effectful direct
fastcc calls with no purity/noalias/readonly inference. Normal LLVM optimization
may inline or simplify calls while preserving their observable effects and order.

Layouts contain only baseline fields; empty objects keep `{ i8 }` as an identity
anchor. There is no lifecycle flag, header, destructor pointer, allocator, GC,
refcount, vtable, RTTI, landingpad, personality or exception runtime. Default x86-64
and O2 evidence, exact runtime traces, stage release tests, malformed standalone
IR cases and unsuppressed Valgrind qualification are recorded in
OBJ-LIFE-1 validation.
