# Computed property IR

An ordinary property is a semantic accessor member with no storage identity. Field reads
remain FieldPlace → Load and field writes remain Store(FieldPlace, value).
Property reads call one exact getter; property writes call one exact setter.
Astra's frontend and IR never substitute a trivial accessor body with field
operations. LLVM may subsequently inline ordinary callables.

| Stage | Member and callable authority | Read / write |
| --- | --- | --- |
| Semantic | PropertySymbol owns exact getter/setter symbols, exact native owner, value type, provenance, property ordinal and mixed member ordinal. CheckedProperty owns checked accessor bodies. | CheckedPropertyGetExpression / CheckedPropertySetStatement specialize ordinary call nodes and retain exact accessor/property identity. |
| Core | CoreProperty owns CorePropertyGetter and optional CorePropertySetter; these extend CoreFunction alongside CoreMethod. | CoreCallValue / CoreCallStatement target exact accessor objects; their parent property remains available to verification. Dumps use property-get/property-set. |
| CFG | CfgProperty and CfgPropertyGetter/Setter with ordinary callable blocks and receivers. | One CfgCallInstruction; getter has a result, setter has one explicit value input. |
| SSA | SsaProperty and SsaPropertyGetter/Setter with ordinary callable bodies and implicit SsaReceiver definitions. | One direct SsaCallInstruction, ordinary SSA getter result or setter input. |
| NABI | NativeFunction copies PROPERTY_GETTER/PROPERTY_SETTER kind, owner category/ordinal and property ordinal. | Existing NativeSignature.receiver PTR plus ordinary result/parameter channels. |
| LLVM | Deterministic internal `fastcc` functions `astra.propget.<class-or-struct>.<owner-ordinal>.<property-ordinal>` and `astra.propset...`. | Direct calls; f64 results/arguments use `double`. |

All semantic/Core/CFG/SSA accessor classes are siblings of methods. Explicit
callable kinds extend the existing common function implementation. Accessors
never enter method lookup and no synthetic source name such as `get_value`
exists. Source-level parameter arrays exclude the implicit receiver. Setters
have one ordinary exact parameter; getters have zero. Getter return analysis and
setter void-return checking reuse ordinary callable machinery, as do lexical
resource/object cleanup, ownership flow, branching, loops, CFG and SSA.

## Identity and verification

Member collection completes all fields, properties, methods and lifecycle
signatures before checking any body. NativeInstanceSymbol has one conceptual
member lookup; typed field/method/property lookups are views of it. Exact object
maps translate property and accessor identities before bodies. Accessor maps use
the ordinary function identity map. No downstream stage re-resolves members by
source spelling.

Each stage owns property descriptors in its native-instance member arrays and
accessor identities in both property and function arrays. Property-to-owner,
accessor-to-property and recursive call-target backlinks are weak. Shared exact
SemanticType/ReceiverType objects have no semantic declaration backlinks.
Standalone and pipeline tests release predecessors before verifying, dumping,
translating and emitting successor objects.

Core, CFG and SSA verifiers check exact owner/member/property ordinals, member
namespace uniqueness, legal value types, mandatory getter, optional setter,
exact accessor parentage, live receiver mode/type/identity, ordinary unmanaged
setter parameter, exact getter result and void setter result. Existing call
verification checks exact receiver and argument types and getter result type;
existing receiver ownership/dominance and object-lifetime checks still apply.
Malformed tests exercise member, accessor, signature, receiver and call defects.

## Receiver and effects

The shared semantic receiver helper creates CheckedReceiverAddressExpression for
an addressed struct local, CheckedThisExpression for live `this`, or
CheckedObjectReceiverExpression for a nullable ClassType reference. Actual struct
use sets the existing per-local `address_taken` bit. Property declarations add
no per-instance addressability requirement. CoreAddressOfValue, CFG capture,
SSA storage classification and LLVM layout remain authoritative. No property
storage class or backing field exists.

Core setter argument order is receiver first, then its one RHS. The ordinary CFG
call routine builds the receiver before arguments; CfgObjectValidateValue is
captured by CfgEvaluateInstruction before any RHS calls. SSA makes validation
explicit and retains the same direct callable target. The existing LLVM
continuation and physical-predecessor machinery places the RHS in the successful
null-guard continuation. A statically null receiver can fold to `br i1 true`
without changing trap order. Live `this` and direct struct receivers need no
null check at entry or invocation.

Both accessors are conservatively effectful. Getters can mutate and trap; repeat
reads remain repeat calls. Short-circuit expressions use ordinary control flow.
There are no receiver noalias, readonly, readnone, nonnull or purity attributes.
Borrowed/owned reference use preserves aliasing and does not transfer ownership;
existing owner-use checking rejects calls after move and consuming a captured
receiver during RHS evaluation. Constructors cannot use their initializing
receiver for property calls. Destructors have live receivers and may do so.

## Values and ABI

PropertyValueTypes freezes the ordinary non-owned method parameter/result
intersection with explicitly deferred handle values; it does not change native
callable admissibility. F32, F64, integer, bool, raw-pointer and supported whole
vectors use their existing channels. Getter signatures are PTR → value; setter
signatures are PTR, value → void. F64 retains exact BinaryFloatFormat/BinaryFloatValue
identity, F64 channels and fp64-v6. There is no F32 fallback, arithmetic rounding,
fast-math or contraction step at accessor boundaries. The existing global profile
rule subsumes vector-v4 when a program also contains F64 accessors. NABI validates
matching getter/setter physical property channels and exact copied ordinals.
CABI/VAPI are unchanged; accessors are never exports.

A vector property's lane read is getter call → whole VectorValue → ordinary
vector extraction. Neither the property nor its lanes have a Place. Getter
values participate in ordinary SSA and phis. No special property phi exists.

Ordinary copied-value properties have no runtime descriptor, property table, object-header addition, vtable,
RTTI, reflection, notification, binding or GObject adapter. Future automatic
properties must explicitly add storage semantics. ERROR-1's bounded virtual
diagnostic properties use the existing class dispatch and checked receiver loans.

## LAZY-1 intent and projection

Property descriptors carry an explicit `is_lazy` bit through Checked, Core, CFG
and SSA. Getter `throws_type` uses each stage's existing function effect channel.
Reads still target the exact getter and retain static checked effects on both
cold and warm paths. Builders copy identity and intent; stage verifiers enforce
the concrete copied-value class/get-only/nonvirtual boundary.

NABI adds detached `NativeLazyCache` v1 plans with exact declaration provenance,
class/property/getter/cache ordinals, copied ABI channel and state/value member
indices. Its verifier checks independent completeness and bounded channels.
SSA/NABI correspondence checks the original source property and effect before
LLVM emission. The plan retains no predecessor declaration objects.

LLVM emits the original getter as a gate and a private `astra.lazy.body.C.P`
initializer with the same physical signature. Every source recursive call still
selects the gate. Explicit construction initializes Empty in the declaring
class's appended slots, including inherited complete prefixes. Retained physical
bindings verify layout, exact receiver/GEP/value/success/exception channels,
signature/convention, branches, memory effects/alignment and ordered transitions.
Gate/body function sequences and private success extent survive predecessor
release. See [the cache ABI](../abi/lazy-properties.md).

## Owned lazy authority

Owning lazy properties add an exact private factory identity and
`is_owned_lazy` intent. Checked/Core/CFG/SSA getter bodies contain a canonical
LazyObserve node; the factory owns the original checked body. LazyDrop nodes
represent prescribed reverse cache retirement in destructor epilogues. Getter
and factory ownership/effects are independently verified at every stage.
Observe/drop backlinks are weak; the property owns its getter/factory identities.
Native v2 plans detach both ordinals and the result Class destruction plan.
Calls to the private factory are forbidden in ordinary IR; only the physical
cache gate invokes it. Public checked observations retain borrowed provenance
through guarded success definitions, and loan verification spans the exact
success path to its borrowed consumer.
