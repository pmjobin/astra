# ADR 0026: Borrowed typed struct pointers and addressable storage

Status: accepted for ASTRA-TPTR-1.

STRUCT-1's aggregate Place remains authoritative when its address is exposed.
A native callee may mutate that storage through an alias. Independent field
promotion would lose those writes, so addressability must survive into explicit
SSA memory. A bounded call argument borrow supplies the first address path
without introducing escaping references or lifetime inference.

1. `T*`, where T is a native StructType, is a nullable, non-owning typed raw pointer.
2. Exactly one pointer level is supported; deeper spellings receive a capability diagnostic.
3. Typed struct pointers are native-language types.
4. `void*` retains its opaque nullable raw-pointer semantics.
5. Struct pointers and `void*` are distinct semantic types.
6. There is no implicit conversion between Struct* and `void*`, or between different struct pointees.
7. `null` contextually initializes, assigns, compares, or passes to any supported raw-pointer type. With no specific context, including `null == null`, it defaults to `void*`.
8. Typed struct pointer function results are unsupported; `void*` results remain supported.
9. Typed struct pointers cannot cross C ABI or VAPI boundaries.
10. `&local_struct` creates a non-owning address borrow of exact local storage.
11. This expression is valid only as the direct argument to a native parameter of exactly that StructType*. Parenthesized address arguments are not direct address expressions.
12. This call-bound restriction prevents local-address escape without a lifetime or borrow checker.
13. A native Struct* parameter may be copied into initialized Struct* locals, assigned to compatible locals, and passed transitively to compatible native parameters.
14. Pointer values do not own, retain, release, destroy, or free their pointees.
15. `p->field` denotes exact indirect scalar field storage, bound by pointer pointee and field identity.
16. Indirect access through null traps deterministically for both reads and writes.
17. Every non-null typed pointer constructible in TPTR-1 comes from valid live Astra struct storage in the active native call chain. Null is the only required dynamic validity check in this subset.
18. Taking a local's address makes its aggregate storage semantically addressable.
19. No field of an address-taken aggregate is independently scalar-promotable.
20. Fields of non-address-taken aggregates retain STRUCT-1 scalar promotion unchanged, including alongside addressable locals.
21. SSA governs values; mutable storage and ordered memory operations may remain explicit in SSA.
22. Native PTR remains the physical pointer transport channel.
23. Native Struct* and `void*` both use PTR without becoming the same semantic type.
24. The C ABI remains `void*`-only for pointers.
25. Physical struct layout is compiler-internal, target-dependent, and unstable across compiler versions.
26. Physical offsets never establish semantic field identity.
27. LLVM aggregate layout is materialized only for addressable storage or indirect access.
28. Persistent references, typed pointer results, C struct pointers, and ownership must explicitly revisit lifetime and escape rules.

Addressability is conservative across the entire valid checked function,
including source-preserved unreachable borrows. All fields of that local become
memory-backed from initialization onward. No flow-sensitive alias analysis,
load forwarding, or field-specific call-clobber inference is introduced.

A read evaluates its pointer and checks/loads at that expression point.
Assignment retains RHS-first order: `p->x = effect()` executes `effect()` before
checking p and storing. Null therefore traps after RHS effects. Operands and
call arguments retain left-to-right order. Short circuit may suppress an
indirect access; memory operations, calls, and trap-capable operations retain
their ordered instruction positions.

The permitted storage destinations prevent escape: there are no typed pointer
results, typed pointer fields, globals, captures, pointer casts, C typed pointers,
or persistent `&local` initializers/assignments. Transitive calls and bounded
recursion keep caller storage live until the call chain unwinds. This proof
does not apply to future FFI, persistent references, or arbitrary pointer sources.

Core/CFG retain separate direct and indirect field Places and exact addressable
aggregate bases. SSA owns layout-free struct/field descriptors, addressable
storage objects, and direct/indirect memory Places. AddressOf produces a pointer
SSA value; Initialize, Load, and Store are ordered instructions. Initialize
remains distinct from replacement Store despite identical scalar LLVM stores.
There is no aggregate SSA value or whole-struct dereference/copy.

LLVM privately realizes required structs in declaration field order using
i32/i1/ptr, reserves each addressable local with one entry alloca, and uses typed
aggregate GEPs. Indirect GEP/load/store follows an explicit null guard and
`llvm.trap`/`unreachable` path. Existing physical continuation tracking supplies
phi predecessors after guard splits. Pointer parameters receive no inferred
nonnull, alias, capture, access, alignment, or dereferenceability attributes.

No architecture redesign or new dependency was required. The necessary change
to scalarization is an explicit eligibility barrier and bounded SSA memory
representation. See [language rules](../language/typed-struct-pointers.md),
[addressable storage](../ir/addressable-storage.md),
[backend storage](../backend/native-struct-storage-v0.md), and
qualification.
