# ADR 0055: Native computed properties

Status: accepted for ASTRA-PROP-1, based on accepted F64-1
`ffb889b48c6e2ebf91146b71a2a300a4bd0e1d55`.

## Decision

1. A property is a semantic member abstraction.
2. A property is not a field.
3. A property is not a Place.
4. Reading a property invokes its getter.
5. Writing a property invokes its setter.
6. Every declaration has one exact PropertySymbol.
7. Its getter has one exact PropertyGetterSymbol identity.
8. Its optional setter has one exact PropertySetterSymbol identity.
9. Accessors are siblings of MethodSymbol, never ordinary source-visible methods.
10. Accessors share native callable implementation, body checking, flow, CFG, SSA and physical lowering with functions and methods.
11. Each property belongs to one exact StructSymbol or ClassSymbol.
12. Fields, methods and properties share one member namespace without overloading.
13. Class names `init` and `deinit` remain reserved for lifecycle declarations.
14. PROP-1 requires one getter.
15. A setter is optional.
16. Setter-only properties are unsupported.
17. The getter has no explicit parameters.
18. The setter has exactly one explicitly declared parameter.
19. The setter parameter type exactly equals the property's value type.
20. There is no implicit `value` binding or other hidden setter local.
21. Property access is conservatively effectful.
22. A getter may mutate state, trap and perform observable effects.
23. A setter may perform arbitrary ordinary callable effects.
24. One source read invokes exactly one getter whenever that source expression evaluates.
25. One source assignment invokes exactly one setter after successful receiver and RHS evaluation.
26. Class-reference access retains ordinary nullable receiver validation.
27. Struct access reuses METHOD-1 receiver formation and addressability.
28. Actual property use may make one particular struct instance addressable.
29. A property declaration does not make all instances addressable.
30. Class ObjectStorage is already addressable.
31. `this.property` forwards the existing exact receiver.
32. It is valid in live methods, accessors and destructors.
33. Constructor `this.property` remains unsupported, even after all fields have been initialized.
34. Access through another fully live object during construction is ordinary object access.
35. Accessors assume a fully initialized live receiver.
36. A getter returns exactly one ordinary value of the property type.
37. A setter returns void.
38. Properties create no backing storage.
39. No automatic backing field exists.
40. No automatic getter or setter exists; each declared accessor has a block body.
41. There is no runtime property descriptor.
42. There is no property table.
43. There is no vtable.
44. There is no RTTI.
45. There is no reflection metadata.
46. There is no property-notification mechanism.
47. There is no GObject property machinery.
48. The accessor receiver physically lowers through existing PTR.
49. The getter result uses the existing native value channel.
50. The setter argument uses the existing native value channel.
51. An f64 property uses F64 and fp64-v6, with exactly F64-1 binary64 semantics.
52. There is no NativeProperty ABI type.
53. No NABI capability profile is added; fp64-v6 remains the latest.
54. Future interface and virtual properties must extend these exact property/accessor identities rather than redefine property semantics.
55. Future automatic or stored properties must explicitly introduce storage semantics rather than treating computed properties as storage.
56. Assignment evaluates receiver, validates it, evaluates RHS, then calls the setter. A null receiver traps before RHS effects or setter entry.
57. Accessors add no receiver `noalias`, `readonly`, `readnone`, `nonnull` or purity attributes.
58. Ordinary parameter bindings remain immutable. Setter parameters use ordinary ParameterSymbol and lexical scope, including field shadowing.
59. Getter results and vector lane extraction are ordinary values; property address-of, lane assignment, compound assignment, increment/decrement and ownership operations through properties remain unsupported.
60. Owned object receiver use is a temporary nonconsuming borrow and never transfers the object owner. Use after move rejects through existing ownership flow.
61. Structural initialization initializes fields only; it never invokes setters.
62. Property and accessor authority survives stage boundaries through exact stage-owned identity maps, never downstream source-name lookup.

## Value-type boundary

Use the intersection of legal ordinary non-owned native method parameter and
result types at F64-1, with the explicit PROP-1 exclusion of nominal handles.
Plain handle parameters/results exist at baseline, but the user confirmed that
handle-valued properties are intentionally deferred to a later property
ownership/borrowing milestone. This exception removes support; it broadens no
callable type or ABI capability.

The supported set is bool; i8/u8/i16/u16/int (i32)/u32; f32/f64; void*; and all
existing legal VectorType shapes, including existing bool masks. Numeric shapes
remain bounded to 128 bits, with 2/4/8/16 lanes as permitted by element size;
f32 permits two or four lanes, and bool masks retain 2/4/8/16 lanes. There are no
f64 vectors. Typed pointers lack baseline return-lifetime contracts, and whole
struct/class/array/slice values, handles, owned values and borrowed contracts
are outside PROP-1. See the [language type matrix](../language/properties.md).

## Representation and alternatives

PropertyAccessorSymbol extends FunctionSymbol alongside MethodSymbol and
LifecycleSymbol. Explicit PROPERTY_GETTER/PROPERTY_SETTER kinds preserve semantic
identity while reusing the callable pipeline. CheckedProperty owns the checked
accessor bodies; CoreProperty, CfgProperty and SsaProperty own their corresponding
accessors. Accessor-to-property and property-to-owner backlinks are weak, as are
recursive call targets. Each stage's program and member arrays own all live
identities. No upstream declaration is required after translation.

CheckedPropertyGetExpression and CheckedPropertySetStatement specialize existing
call nodes. CoreCallValue/CoreCallStatement retain the exact accessor target and
its exact property; CFG/SSA use ordinary direct calls with the same relationship.
This avoids a second body compiler while making property verification and dumps
explicit. Synthesizing MethodSymbols would lose the independent conformance
identity. Treating properties as Places would incorrectly grant storage identity
and addressability. Neither is needed.

Receiver preparation is shared with methods. The existing CFG call routine
captures and validates the receiver before explicit arguments, so a setter's
single RHS follows that rule without new control-flow machinery. The existing
LLVM continuation/predecessor authority handles null-guard splitting. LLVM may
optimize or inline ordinary calls while preserving observable behavior; Astra's
semantic and IR stages never substitute accessor bodies with field operations.

The receiver is always PTR, so one accessor signature cannot simultaneously
contain an f64 property value and a vector property value. A program containing
both uses the established program-wide fp64-v6 profile, which subsumes vector-v4.

## Deferred scope

Automatic/stored/lazy, static/indexed/overloaded/virtual properties, implicit
setter parameters, ownership and borrowing contracts, readonly accessor
contracts, constructor receiver use, interfaces, inheritance, reflection,
notifications, binding systems and C/VAPI/GObject adapters remain deferred.
No production dependency or runtime is introduced.
