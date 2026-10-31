# 0048 — Native struct instance methods

Status: implemented for ASTRA-METHOD-1, extending accepted ASTRA-SLICE-BOUND-1
commit `a912ce4459fa632579727f6bb8207001e1dfe389`.

## Decision

1. Native structs may declare instance methods with ordinary native declaration syntax.
2. Methods have semantic member authority; they are not free functions with syntactic sugar as authority.
3. Every method has one exact MethodSymbol owned by its exact StructSymbol.
4. Each method has one implicit, compiler-owned ReceiverSymbol.
5. The receiver's exact instance type is the declaring StructType.
6. The receiver is non-owning and does not acquire cleanup responsibility.
7. The receiver is mutable in METHOD-1.
8. Every valid invocation guarantees nonnull, live receiver storage.
9. This specialized contract does not introduce a general nonnull pointer type.
10. Source method bodies access the receiver through reserved, explicit `this`.
11. Unqualified field lookup and implicit receiver capture are absent.
12. `this.field` uses the existing field Place, Load and Store semantics.
13. `this.method(...)` binds an exact method of the declaring struct.
14. Method dispatch is static and direct.
15. No vtable exists.
16. No dynamic dispatch exists.
17. No inheritance exists.
18. Method names cannot be overloaded, including by parameter differences.
19. Fields and methods share one member namespace within each struct.
20. Field/method name collisions reject in either declaration order.
21. Calling a method on a direct struct local makes that instance addressable.
22. Receiver addressability reuses existing address-taken struct storage.
23. Instances which need no address or receiver identity remain scalarizable.
24. Invocation creates no whole-struct value, parameter or result semantics.
25. The receiver physically uses existing NativeScalarType.PTR.
26. That PTR is physically first, before all explicit parameter channels.
27. Explicit parameters use the ordinary native signature checker and contracts.
28. Results use the ordinary native result checker and contracts.
29. Existing owned Resource parameter/result boundaries are available unchanged.
30. Existing borrowed slice parameter boundaries are available unchanged.
31. Method calls preserve Astra's left-to-right evaluation rules.
32. Receiver evaluation precedes every explicit argument evaluation.
33. Existing owned-argument transfer commits immediately before invocation, after argument evaluation.
34. Method bodies use ordinary Core, CFG, flow and SSA function machinery.
35. Methods are internal compiler-owned symbols, including a method named `main`.
36. Neither source method names nor compiler ordinals promise a stable symbol ABI.
37. LLVM internal fastcc remains the native physical convention.
38. No runtime method descriptor or RTTI is introduced.
39. No GObject machinery or production runtime dependency is introduced.
40. Future native classes/objects should reuse these exact member identities and direct-call machinery where applicable.

## Representation and alternatives

MethodSymbol specializes FunctionSymbol with `CallableDomain.METHOD`, an exact
declaring StructSymbol, method/member ordinals and ReceiverSymbol. CheckedMethod,
CoreMethod, CfgMethod and SsaMethod likewise specialize the existing native body
containers. This preserves member identity without duplicating parameter, result,
ownership, borrow, control-flow or native-call type systems. Domain-aware call
nodes retain the exact method target and a separate receiver operand. They are
not rewritten to ordinary free-call identities during checking or Core construction.

All struct types, fields and method signatures are collected before any native
body is checked. Method ordinals follow method declaration order within a struct;
member ordinals follow mixed field/method order. Struct ordinals follow struct
declaration order. The program's function arrays also contain the exact method
objects, after free functions, for shared body processing. Exact identity maps,
not names or array ranks alone, bind successors at each stage. Weak owner/callee
backlinks prevent recursive ownership cycles. Immutable ReceiverType holds the
exact StructType without retaining semantic symbols.

The alternative of immediately rewriting a method to a free function with a
hidden source `S* this` parameter would discard member authority and expose
nullable, rebindable pointer semantics. A separate method body/signature pipeline
would duplicate proven native boundary rules. The chosen specialization adds
only the receiver contract and exact member authority to that existing pipeline.

## Storage, aliasing and ordering

Only direct struct locals and `this` are supported receivers. A direct-local
call marks the same `address_taken` bit as `&local`, for the whole relevant
lifetime. Initialization, direct fields, typed-pointer aliases and method
accesses therefore share one authoritative object. Declaring methods alone does
not change any instance's storage classification. A method's incoming receiver
refers to existing caller storage; there is no receiver alloca or copy in the
callee. Receiver field accesses remain explicit memory across calls and aliases.

ReceiverType is a compiler-only `Receiver<S>` contract, not TypedPointerType.
ReceiverSymbol is neither a ParameterSymbol nor a LocalSymbol. `this` cannot be
rebound, returned, copied into a pointer, moved, released, addressed or compared
with null. Its only source uses are `this.field` and `this.method(...)`.
Receiver field memory needs no nullable-pointer guard. Ordinary `p->field`
still traps on null, including inside methods. Multiple mutable aliases remain
valid: no exclusivity, noalias or readonly assumption follows from the contract.
No LLVM nonnull attribute is required or added.

Calls are conservatively effectful. CFG captures a direct-local receiver address
before evaluating explicit arguments. `this` forwards the exact existing input.
Arguments then use ordinary left-to-right evaluation, owned captures and final
transfer commit. A trap in a later argument prevents invocation without changing
the existing non-unwinding trap/ownership policy. Short circuit may skip the call;
eager bool operators evaluate it normally.

## Physical boundary

NativeSignature retains a separate implicit PTR channel, followed by unchanged
ordered explicit parameter groups. Effective signature selection uses existing
profiles: receiver plus int uses scalar-ptr-v1, u8 uses scalar-int-v2, f32 uses
scalar-fp-v3, vectors use vector-v4 and borrowed slices use slice-v5. No method
profile or NativeReceiverType exists. An owned Resource remains PTR with its
ordinary semantic cleanup/transfer contract. A borrowed slice remains one logical
SliceValue, expanding after the receiver into base PTR and length I32.

LLVM names definitions deterministically as
`astra.method.<struct-ordinal>.<method-ordinal>`, with internal linkage and fastcc.
Names are compiler artifacts, never resolution authority. All definitions exist
before bodies, permitting forward, recursive and mutually recursive direct calls.
Methods cannot be C exports, C imports, VAPI members or program entry points.

## Deferred work

METHOD-1 adds no classes, allocation, object references, constructors,
destructors, ownership of struct instances, inheritance, interfaces, virtual
dispatch, static members, overloads, generics, method values, delegates,
properties, extension methods or C/GObject method interop. Arbitrary struct
expressions and `Struct*` receivers remain unsupported. Nullable pointer calls
require a later decision about evaluation, null traps and receiver validity.
Existing nonempty-field struct storage and brace initialization rules remain.

See [language](../language/methods.md), [IR](../ir/methods.md) and
qualification.
