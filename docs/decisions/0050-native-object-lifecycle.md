# 0050: Native object lifecycle

Status: accepted for ASTRA-OBJ-LIFE-1. Extends
[0049](0049-native-object-identity.md) without changing lexical object identity,
reference provenance, field admissibility or native method dispatch.

## Decision

1. Class constructors are explicit lifecycle members.
2. Class destructors are explicit lifecycle members.
3. ConstructorSymbol and DestructorSymbol identities are distinct from MethodSymbol.
4. Lifecycle bodies reuse ordinary callable infrastructure while retaining their kind.
5. Constructor declaration syntax is `init(parameters?) { body }`, without a result type.
6. Destructor declaration syntax is `deinit() { body }`, without parameters or result type.
7. A class may declare at most one constructor.
8. A class may declare at most one destructor.
9. Constructor overloading does not exist; changing parameter types/counts does not permit another declaration.
10. Named constructors do not exist.
11. Constructor delegation/chaining does not exist.
12. Constructor-based lexical construction uses `TypeName.init(arguments)`.
13. This spelling denotes a construction initializer, not static method dispatch.
14. Construction is allowed only as the complete initializer of a fresh exact ClassType local, never a general first-class expression.
15. No `new` keyword exists or is reserved by this milestone.
16. Construction creates caller-owned lexical ObjectStorage.
17. The constructor receives that exact storage address as an initializing receiver.
18. The constructor does not allocate its receiver storage.
19. The constructor does not physically return an object reference; its physical result is void.
20. Normal constructor completion activates the storage lifecycle before publishing the local reference.
21. A trapping constructor never activates destructor cleanup.
22. Classes without explicit constructors retain complete named brace construction.
23. Classes declaring `init` cannot bypass it with direct brace construction.
24. Brace construction activates a declared destructor only after all field initializers complete successfully.
25. Every field is initialized exactly once on every reachable successful constructor path, with no implicit default initialization.
26. Reads require definite field initialization at the read point.
27. Constructor field initialization is explicit `this.field = expression` and retains Initialize semantics.
28. Initializing receiver fields inside loops is unsupported, including loops nested in branches.
29. `this.method(...)` is unsupported throughout constructor bodies, even after every field is initialized.
30. Constructor `this` cannot escape, be copied as a reference, rebound, passed as an explicit argument or stored.
31. Every explicit constructor `return`, including `return;`, is unsupported.
32. Normal constructor completion is reachable body fallthrough; unreachable completion paths require no initialization.
33. A destructor receives the exact fully initialized, nonnull, live receiver.
34. Destructors may read and mutate fields.
35. Destructors may call ordinary exact instance methods.
36. Source cannot explicitly invoke a destructor through a reference, `this` or a class name.
37. A destructor cannot be taken as a value.
38. Each successfully constructed lexical ObjectStorage declaring a destructor receives exactly one cleanup responsibility, discharged at its normal lexical lifetime end.
39. Aliases do not create cleanup responsibilities.
40. Reference assignment does not transfer cleanup responsibility.
41. Reference nulling does not discharge cleanup responsibility.
42. Cleanup timing is lexical and deterministic; last-reference disappearance and reference liveness have no lifecycle meaning.
43. Object cleanup shares the existing lexical cleanup planner with owned Resource cleanup.
44. Applicable responsibilities execute in reverse activation/declaration order; stable storage ranks are independent of reference use and Resource rearm retains its existing slot rank.
45. Return expressions evaluate and preserve result/ownership-transfer state before lexical cleanup.
46. Break and continue clean the scopes they exit before transferring control.
47. Loop-body storage is destroyed before the ordinary body backedge; each successful iteration has a fresh lifetime and one matching destructor.
48. Traps remain non-unwinding.
49. Destructors are therefore not guaranteed to execute when execution traps.
50. A destructor trap stops execution and prevents subsequent cleanup; there is no exception unwind.
51. No runtime cleanup stack, registration table or finalizer registry is introduced.
52. No runtime initialization/lifecycle flag is introduced.
53. Object construction authority and cleanup actions are explicit compiler IR, validated independently of LLVM.
54. Constructor and destructor receivers physically use existing PTR, first in the signature.
55. No new NABI channel is required.
56. No new NABI profile is required; effective explicit parameters continue to select v0-v5 rules.
57. Lifecycle functions remain compiler-internal native fastcc callables, without CABI/VAPI exports or interop.
58. Object layout remains compiler-private and unchanged; an empty object's existing identity byte suffices without a lifecycle header.
59. No object heap allocator/deallocator, refcount, GC, vtable, RTTI or runtime dependency exists.
60. Future owned/escaping/heap references must extend lifetime authority on ObjectStorage identity rather than attaching accidental ownership to reference bindings.

## Scope and implementation choices

Class member names `init` and `deinit` are reserved against ordinary fields or
methods, whether or not the corresponding lifecycle member is declared. Structs
gain no lifecycle syntax or behavior; existing ordinary struct methods with these
spellings retain ordinary method semantics. The parser recognizes a complete
`TypeName.init(...)` local initializer. Other member-call syntax stays unresolved
until semantic class/struct lookup; class lifecycle calls then reject.

Two-phase collection establishes fields, ordinary methods and optional lifecycle
symbols before checking bodies. LifecycleSymbol is a FunctionSymbol subclass
alongside MethodSymbol. Each later stage has independent constructor/destructor
subclasses of its ordinary function definition. A void sentinel reuses body
machinery's no-result representation; it is not a source constructor result.

Exact field analysis uses definitely-initialized and possibly-initialized sets.
Joins intersect definite sets and union possible sets over reachable predecessors.
An initialization requires absence from the possible set; a read requires presence
in the definite set. Structured semantic and Core analysis and independent CFG/SSA
fixed points enforce this before physical lowering. Constructor-local loops and
ordinary calls remain valid; only receiver field initialization in loops is deferred.

The existing CleanupScope list now contains Resource and ObjectStorage actions.
This preserves one ordering authority, including constructor/destructor locals.
CFG/SSA lifecycle phase analyses validate the explicit actions; they never insert
cleanup or generate runtime state. Constructor calls and destructor calls retain
their exact target/storage identities through shared native call lowering.

Heap allocation, owned or explicit borrowed ClassType boundaries, object results,
object/Resource/owned fields, resurrection, explicit destruction, constructor
overloads/names/delegation, properties, inheritance, interfaces, virtual dispatch
and C/GObject lifecycle interop are deferred.

See [language](../language/object-lifecycle.md), [IR](../ir/object-lifecycle.md)
and qualification.
