# Native method and receiver IR

[Property IR](properties.md) extends the common callable kinds with
PROPERTY_GETTER and PROPERTY_SETTER. Stage-owned accessors are siblings of
Method identities and belong to exact Property identities. They reuse implicit
receivers, selective struct addressability, call ordering, body CFG/SSA and native
ABI lowering. Fields, methods and properties share one semantic member namespace.

[Lifecycle IR](object-lifecycle.md) adds independent Constructor/Destructor
identities alongside Method at checked, Core, CFG and SSA stages. Function-like
bases expose explicit callable kind and implicit receiver for shared lowering.
Constructors retain INITIALIZING mode and Field Initialize; destructor receivers
retain LIVE mode and may use the ordinary method-call nodes. Class lifecycle
members never enter method lookup. Existing struct/class Method identities,
receiver null validation, source argument order and owned commits are unchanged.

OBJ-1 generalizes the declaring owner to a native instance descriptor shared by
structs and classes. There is one MethodSymbol/ReceiverSymbol and one method/call
family at every stage. CheckedObjectReceiverExpression/CoreObjectReceiverValue
prepare a nullable ClassType reference for that same ReceiverType; explicit
CFG/SSA validation executes before all explicit argument effects and transfer
commit. Incoming `this` is already nonnull. Class method symbols use
`astra.class.method.<class-ordinal>.<method-ordinal>`; existing struct symbols stay
unchanged. The receiver still maps to first PTR with no new profile or explicit
ClassType channel. See [object reference IR](object-values.md).

METHOD-1 retains exact member identity from checking through SSA, while reusing
ordinary native body, signature, call, flow and ownership machinery.

| Stage | Method identity | Receiver authority | Invocation |
| --- | --- | --- | --- |
| Checked | MethodSymbol owned by NativeInstanceSymbol (struct or class); CheckedMethod body | ReceiverSymbol and immutable ReceiverType with exact StructType or ClassType | CheckedCallExpression/Statement, METHOD target and separate receiver |
| Core | CoreMethod owned by CoreNativeInstance and program function array | CoreReceiver; CoreReceiverValue for `this` | CoreCallValue/Statement targeting the exact CoreMethod |
| CFG | CfgMethod owned by CfgNativeInstance and program function array | CfgReceiver; immutable CfgReceiverValue | CfgCallInstruction with separately captured receiver |
| SSA | SsaMethod owned by SsaNativeInstance and program function array | SsaReceiver, one implicit SsaDefinition | SsaCallInstruction with exact method and receiver operand |
| NABI | NativeFunction with copied declaring category/type/method ordinals | NativeSignature.receiver, existing PTR | Exact temporary SSA-to-native correspondence |
| LLVM | Internal fastcc function named from compiler ordinals | First physical `ptr %this` input | Direct fastcc call, receiver physically first |

## Exact identity and lifetime

MethodSymbol specializes FunctionSymbol using CallableDomain.METHOD; methods
remain distinct from free-function authority. Explicit parameters and results
use the same checker and contracts. Methods are collected before any bodies.
Semantic method ordinal follows method order and member ordinal follows mixed
field/method order. Struct ordinal follows source struct order. Each successor
builds an exact object map before translating bodies; calls never reconstruct a
target from strings. Method owners and recursive callee backlinks are weak to
avoid ownership cycles. Stage program/struct arrays own the method identities.

Each stage owns its receiver object. The immutable ReceiverType owns the exact
StructType or ClassType and no semantic declaration. It can survive checked-model destruction
without keeping MethodSymbol or ReceiverSymbol alive. Stage-lifetime tests
release checked, Core, CFG and SSA predecessors before verifying/dumping/using
their successors; LLVM also emits an object after SSA and NABI have died.

Receiver inputs are absent from source parameter arrays. `Receiver<S>` is a
compiler-only capability, never a TypedPointerType or source name. It admits no
null constant, assignable local, ordinary parameter/result, block parameter or
ownership operation. The receiver is mutable, non-owning and compiler-guaranteed
nonnull, without uniqueness. A method named `main` is not a program entry;
methods cannot become C exports even through malformed IR construction.

## Field Places and authoritative storage

`CheckedThisExpression` retains exact ReceiverSymbol. `this.field` creates
CheckedReceiverFieldPlace with that expression and the exact StructFieldSymbol;
reads/writes use CheckedLoadExpression/CheckedStore. Core translates it to the
existing CoreIndirectFieldPlace using CoreReceiverValue and mapped field identity.
CFG and SSA retain their existing indirect field Places, now also accepting an
exact receiver input as base. Backend layout alone determines the GEP.

A direct-local call creates CheckedReceiverAddressExpression and marks the
existing local.address_taken bit. CoreAddressOfValue, CfgAddressOfValue and
SsaAddressOfInstruction then use ReceiverType as their specialized result
contract. They reference ordinary addressable struct storage. No new object or
receiver storage class exists. Classification happens before body lowering, so
all initialization, direct fields and aliases of that local share memory for its
whole lifetime, including across branch joins and loops.

SSA retains a declaring struct layout when a method needs it even if no local
uses receiver storage. Descriptor retention does not make local instances
addressable. Filtered SSA struct arrays retain source ordinals, which may have
gaps; ordinals are not reconstructed from filtered array positions. Instances
used only through fields still promote independently. A method receiver itself
has no callee alloca, struct copy or promoted field shadow. Every `this.field`
read/write remains an explicit memory operation coherent with external aliases.

## Calls, evaluation and ownership

Domain-aware call nodes have one exact method target, a separate receiver and an
ordered array of explicit arguments. The method subtype remains explicit in
Core/CFG/SSA and dumps label these operations `method-call`. Free calls must
have no receiver; method calls must have one of the exact declaring ReceiverType.
Core and CFG receiver input references must belong to the containing method.
SSA receiver uses also satisfy ordinary definition ownership and dominance.

CFG prepares/captures the receiver before lowering explicit arguments, then
reuses normal native argument lowering. Direct `this` calls forward their
immutable receiver. Owned arguments capture values in source order; the existing
OwnedCallTransferCommit remains immediately before invocation. Receiver handling
adds no transfer event. Borrowed slices remain one SliceValue argument through
SSA, including when accompanied by owned Resource arguments/results.

Method calls remain conservatively effectful. Recursion and mutually recursive
methods use the same exact call machinery and receiver input. Short circuit
lowers to ordinary control flow; eager bool operators retain their call effects.
Existing bounds, arithmetic, cleanup and non-unwinding trap behavior is unchanged.

## Verification and physical boundary

Standalone Core/CFG/SSA verifiers check exact declaring native type, member/receiver
ownership, deterministic ordinals, field/method namespace, exact receiver type,
supported receiver formation, addressable caller storage, field identity,
explicit argument types/contracts, result contract and absence of a receiver on
free calls. Malformed tests include wrong owner/type/input/field, omitted or
pointer receiver, receiver copies, missing storage, mismatched arguments/results,
method membership, receiver-as-parameter and C export attempts.

NativeSignature.receiver uses NativeScalarType.PTR, not a new receiver ABI type.
Physical count includes it first; explicit parameter ordinals and slice groups
stay unchanged. Effective signatures select existing v1/v2/v3/v4/v5 policy, and
the ordinary program-wide profile rule still applies. Native verification checks
receiver shape, internal linkage and copied identity ordinals. NABI remains
independent of semantic and LLVM models.

LLVM binds that input directly to `%this`, performs exact field GEP/load/store,
and invokes `astra.method.<struct-ordinal>.<method-ordinal>` through internal
fastcc. Receiver null guards are omitted only for the exact SsaReceiver field
base; ordinary Struct* field accesses still guard. No receiver noalias, readonly
or nonnull attributes are added. A borrowed slice follows as `ptr %p0.base,
i32 %p0.length`; vectors remain existing whole-vector channels. No receiver
temporary, memcpy, vtable, RTTI, runtime method descriptor or new dependency exists.

See [language](../language/methods.md),
[ADR 0048](../decisions/0048-native-struct-methods.md) and
qualification.
