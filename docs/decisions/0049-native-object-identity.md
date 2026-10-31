# ADR 0049: Native object identity

Status: accepted for ASTRA-OBJ-1. Baseline: ASTRA-METHOD-1,
`7935f9a566d015173076c83182058ea5faedd344`.

## Decision

1. `class` declares an Astra-native nominal object type.
2. Its canonical ClassType is a reference type.
3. StructType remains a storage/value aggregate.
4. ClassType and StructType are different semantic categories, irrespective of shape.
5. Declaring a class does not imply GObject.
6. Declaring a class does not imply heap allocation.
7. Declaring a class does not imply reference counting.
8. Declaring a class does not imply virtual dispatch.
9. OBJ-1 object construction is lexical and local only.
10. Construction uses direct local named brace initialization: `C c = { x = 1 };`.
11. OBJ-1 deliberately introduces no `new` expression.
12. Every execution of a construction site creates one fresh semantic object identity.
13. Object identity belongs to storage, independently of reference bindings.
14. The constructing reference local is not itself the object.
15. Copying a reference aliases the same object storage.
16. Assigning a reference never copies fields.
17. Object-reference equality compares identity.
18. Distinct live objects remain unequal when all fields match.
19. Class references are nullable.
20. Null is not an object identity.
21. Object field access through null traps explicitly.
22. Object method invocation through null traps explicitly.
23. `this` in a class method remains compiler-guaranteed nonnull.
24. Class object storage is always addressable.
25. Class object storage is never a whole-object SSA value.
26. Class reference values are scalar, promotable SSA values.
27. Object fields remain explicit memory storage.
28. Multiple references may alias one object.
29. No exclusivity or `noalias` assumption follows from a reference or receiver.
30. Reference lifetime uses the existing lexical borrow-region checker.
31. Object storage lifetime is lexical in OBJ-1.
32. A reference local may not outlive the storage it can reference.
33. Literal null has no live-storage provenance requirement.
34. Constructed storage survives reference rebinding until its own lexical lifetime ends.
35. Future destruction must attach to object-storage identity, independently of current reference contents.
36. Class methods reuse METHOD-1 MethodSymbol architecture.
37. Classes do not create a second method subsystem.
38. Reference method calls form the same exact mutable, non-owning, nonnull receiver contract.
39. Physical receivers continue to lower through the existing NABI PTR channel.
40. Object references are not TypedPointerType.
41. ClassType and `void*` have no implicit conversion in either direction.
42. `ClassType*` is unsupported in OBJ-1.
43. Object layout remains compiler-private, without source size/alignment/offset guarantees.
44. No vptr is present.
45. No runtime object descriptor is present.
46. Empty objects still have distinct identities when simultaneously live.
47. The backend may use a hidden nonzero identity anchor for otherwise zero-sized storage.
48. That anchor is storage, with no source-visible field or metadata semantics.
49. Class references cannot cross ordinary native parameter/result boundaries yet.
50. The implicit method receiver is the only OBJ-1 class-reference call boundary.
51. Future owned references and lifecycle features must extend this storage-identity model, without redefining classes as ordinary pointers.

## Construction and observation

The local initializer checks every declared field exactly once. Fields may appear
in any order, as for existing structs; their expressions evaluate and store in
source-written order. Methods are not initializer members. The reference binding
becomes visible only after complete initialization. The source cannot name the
new local in its own initializer. A trap prevents publication of a partially
initialized object.

LexicalObjectStorageSymbol and LocalSymbol are separate compiler identities.
Their common initial lexical region does not make them interchangeable. Nulling
or rebinding the local leaves the constructed storage alive, including for other
aliases. A construction inside a loop starts a fresh lifetime on each execution;
a backend stack slot may be reused after the previous lifetime ends because
valid references cannot escape that lifetime.

For `ref.field = rhs`, evaluate the reference once, validate nonnull, evaluate
rhs, then store. For `ref.method(args)`, evaluate the reference once, validate
nonnull, evaluate explicit arguments left-to-right, perform the existing owned
argument transfer commit, then invoke the exact method. A null receiver therefore
prevents every explicit argument effect, including owned-argument capture.
`this.field` and `this.method()` use the existing proven-nonnull receiver.

## Implementation choice and alternatives

NativeInstanceSymbol generalizes only shared member ownership. StructSymbol and
ClassSymbol construct different canonical types; MethodSymbol, ReceiverSymbol,
and ordinary checked/Core/CFG/SSA direct-call nodes remain shared. The historic
StructFieldSymbol/CoreStructField/CfgStructField/SsaStructField names remain for
compatibility, with generalized exact `containing_type` authority. The old
`containing_struct`/`declaring_struct` getters return a struct or null and do not
supply a separate class pipeline.

CoreObjectStorage, CfgObjectStorage and SsaObjectStorage are independent lexical
memory descriptors. Reference locals use ordinary local-value flow. Core retains
an ordered construction statement; CFG splits initialization and publication,
and introduces explicit validation evaluations before argument/RHS instructions.
SSA retains memory initialization, scalar reference definitions and validation
instructions. Delaying validation until a final backend call would violate the
required effect order, so the guard has its own instruction position.

The actual METHOD-1 field predicate admits all six integer types (`int` aliases
`i32`), f32, bool and `void*`. NativeFieldTypes centralizes that unchanged positive
predicate. It admits no vector, array, slice, handle, nested struct, ClassType,
typed-pointer or owned field.

LLVM uses `%astra.class.N = type { ... }`, exact existing field physical types,
and one lexical alloca per construction site. For a zero-field class the layout
is exactly `{ i8 }`; the byte is not initialized or source-accessible and only
ensures a nonzero storage extent. References use opaque `ptr`; equality uses
`icmp eq/ne ptr`. No object copy, vtable, header, allocator, deallocator or runtime
is involved. Source and LLVM profiles remain separate: ClassType is never an
explicit NABI channel, even though its body representation is a pointer.

## Deferred work

No constructors, destructors, `new`, `delete`, heap allocation, GC, refcounting,
weak references, owned class references, explicit borrowed class syntax, object
parameters/results, object-reference fields, arrays/slices of references,
pointer-to-reference storage, casts, inheritance, interfaces, virtual methods,
properties, static/access modifiers, method values or C/GObject interop are added.

Future destruction needs storage lifetime events and must not inspect a
particular reference binding to identify what to destroy. Future object
boundaries need explicit lifetime/ownership contracts before references may
escape; heap/lifecycle, property and dispatch work must preserve nominal type,
storage identity, aliasing and receiver evaluation rules.

See [objects](../language/objects.md), [reference IR](../ir/object-values.md),
[storage IR](../ir/object-storage.md) and qualification.
