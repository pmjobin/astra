# 0051: Borrowed native object boundaries

Status: implemented for ASTRA-OBJ-BOUND-1 on the accepted OBJ-LIFE-1 model.
Extends [0049](0049-native-object-identity.md) and
[0050](0050-native-object-lifecycle.md) without changing storage, receivers or lifecycle.

## Decision

1. Explicit native ClassType parameters require `borrowed`.
2. Unqualified ClassType parameters remain unsupported.
3. `owned ClassType` parameters remain unsupported.
4. A borrowed object parameter carries the exact ClassType, separately from its contract.
5. Borrowed object parameters are nullable.
6. Borrowed object parameters are non-owning.
7. Borrowed object parameters are noescape.
8. Borrowed object parameters permit mutation of the referenced object.
9. Borrowed object parameters may alias each other and the caller's references.
10. Borrowing never transfers ObjectStorage cleanup responsibility.
11. Borrowing never delays or extends ObjectStorage lexical destruction.
12. Borrowing never creates a second cleanup responsibility.
13. Parameter reference copies do not copy object storage.
14. Parameter reference copies acquire no lifecycle responsibility.
15. A null borrowed argument has no ObjectStorage provenance.
16. A nonnull borrowed argument refers to live storage of the exact ClassType throughout the call.
17. Object-reference lifetime validation reuses LexicalRegion/BorrowProvenance authority.
18. Borrowed object parameters may forward to another exact compatible borrowed object parameter.
19. Borrowed object parameters may be copied into ordinary local ClassType reference variables.
20. Those locals cannot escape the function-region lifetime and obey conservative stored-borrow checks.
21. Object field access through borrowed parameters retains ordinary null traps.
22. Object method calls through borrowed parameters retain ordinary receiver-null traps.
23. `borrowed` does not imply `nonnull`.
24. `borrowed` does not imply `readonly`.
25. `borrowed` does not imply `noalias` or exclusivity.
26. Exact ClassType identity survives checked semantics, Core, CFG and SSA.
27. NABI erases borrowed ClassType to PTR only after exact semantic validation.
28. No NativeObjectType is required or introduced.
29. No new NABI profile is required or introduced.
30. A signature whose only new feature is borrowed ClassType uses existing pointer-capable profiles.
31. Borrowed object parameters coexist with vector-v4 and slice-v5.
32. Borrowed object parameters coexist with owned Resource parameters and results.
33. An implicit class-method receiver remains distinct from an explicit borrowed object parameter.
34. An explicit object parameter is one ordinary nullable ClassType reference value.
35. An implicit method `this` remains compiler-guaranteed nonnull.
36. Passing an object reference creates or copies no ObjectStorage.
37. Passing null creates no dummy object or identity anchor.
38. No runtime borrow token exists.
39. No runtime type tag exists.
40. No runtime object descriptor exists.
41. No lifecycle metadata crosses the call.
42. Destructor responsibility remains entirely with the caller's ObjectStorage.
43. A callee cannot explicitly invoke `deinit`.
44. Object-reference results remain unsupported.
45. Result lifetime relationships remain deferred.
46. Owned and escaping object references remain deferred.
47. CABI/VAPI object-reference boundaries remain unsupported.
48. Future owned object boundaries must extend this exact ClassType/reference model, never reinterpret class references as generic pointers.

## Implementation and alternatives

`ParameterSymbol.pointer_contract` already represents shared native/foreign
borrowing and ownership behavior despite its historical name. Extend its existing
`PointerParameterContract.BORROWED_NOESCAPE` to ClassType; adding an object-only
contract or a borrowed-class type would duplicate an established distinction.
The enum itself stays unchanged. Each later stage copies the exact ClassType and
contract into its ordinary parameter model. The checked parameter's lexical region
is the containing function region. Existing BorrowProvenance queries and local
storage checks supply lifetime authority without runtime data.

The existing slice treatment permits local reference copies while retaining
signature and aggregate-storage guards against escape. Object parameters follow
that treatment; raw/Resource borrowed parameter restrictions remain unchanged.
A local read still summarizes at that local's own lexical region. An inner alias
cannot be stored back outward even when originally copied from the parameter.
Any future producer or escape sink must extend these proofs explicitly.

Field/method name resolution admits a ClassType parameter wherever an existing
object reference base is valid. It creates the same CheckedObjectFieldPlace and
CheckedObjectReceiverExpression used for locals. Core/CFG/SSA retain their existing
null-guard and exact member semantics. No second object access architecture exists.

Parameter bindings remain immutable under ordinary Astra rules; `c = null`
rejects, while `c.value = 42` and rebinding a local copy are valid. Direct
`this == other` remains deferred because `this` is a restricted ReceiverType,
not a ClassType expression. This preserves the existing receiver model. Passing
the receiver's caller reference as `other` is valid and may alias `this`.
Class methods, struct methods and constructors all accept explicit borrowed
object parameters through the shared signature and argument checker.

NABI's parameter mapper alone maps a borrowed ClassType to NativeScalarType.PTR;
the result mapper continues to reject ClassType. Scalar-ptr-v1 suffices for a
simple `PTR -> I32` or `PTR -> void` function. Existing precedence selects integer
v2, f32 v3, vector-v4 or slice-v5 as needed. Physical collisions between classes,
Resource handles and typed/raw pointers do not authorize conversions. SSA and
the NABI compatibility bridge independently reject cross-class call operands.

LLVM needs no modification: the ordinary PTR parameter is bound to the incoming
ClassType SSA value, and existing field/method guards run at the point of use.
No entry guard, parameter object alloca, object copy, cleanup registration or
callee destructor is added. Emission adds none of `nonnull`, `noalias`, `readonly`,
`byval`, `sret`, `dereferenceable` or `nocapture`. Noescape is a semantic promise,
not an excuse to emit unproven pointer attributes.

Arguments retain left-to-right evaluation. A borrowed object value has no
ownership commit; mixed owned Resource transfers still commit only after all
arguments evaluate. `f(null, effect())` evaluates `effect()` and calls `f`.
A null receiver's field write validates before its RHS; a method call validates
before explicit arguments. Only dereference or method use traps on null.

Object results would need an explicit relationship to a parameter, static storage,
or transferred ObjectStorage ownership. None is expressible here. Heap allocation,
escaping storage, object-reference fields/arrays/slices/slot pointers, refcounts,
properties, inheritance, interfaces and virtual dispatch remain future work.

See [language guide](../language/borrowed-object-parameters.md) and
qualification.
