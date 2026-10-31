# Lexical object storage

[Owned result storage](object-results.md) distinguishes a caller candidate allocation from the returned owner capability. Fresh constructors write directly to an independent result-storage input. Null or forwarded results leave candidate bytes semantically unused, with no field initialization or fixed cleanup. Object identity is never copied or relocated.

[Transferable ownership](object-ownership.md) uses this same ObjectStorage model.
The compile-time transferable mode distinguishes owner-capability cleanup from
fixed lexical cleanup; it changes neither identity nor layout. CoreOwnedLocal and
CfgLocalPlace retain the exact local storage, and SSA transfer metadata preserves
it after CFG destruction. An owned parameter acquires the original caller pointer
without allocating, copying, relocating or freeing object storage. Physical stack
allocation can outlive the transferred semantic lifetime.

Borrowed object calls pass one ClassType reference into existing object access
nodes. They create no ObjectStorage descriptor, object alloca, field copy or callee
cleanup responsibility. The caller's original storage and cleanup rank remain
unchanged through aliases, forwarding, calls and null rebinding; its deinit sees
callee mutations. Nonnull arguments stay live through the call using existing
lexical authority. Nullable arguments create no storage or provenance token.
See [borrowed parameters](../language/borrowed-object-parameters.md).

Each class constructor or brace construction has a separate compiler-owned storage
identity. A LexicalObjectStorageSymbol identifies the exact ClassSymbol, ordinal,
source provenance and existing LexicalRegion. An ordinary ClassType LocalSymbol
is only a reference binding; it has no authority to end the constructed storage
lifetime. Fixed storage survives rebinding or nulling that binding until the
construction scope ends. An explicit owner instead carries transferable lifetime
responsibility for the same storage. A declared destructor belongs to this storage, together with a stable
lexical cleanup rank. [Lifecycle IR](object-lifecycle.md) retains explicit success
and cleanup authority through each stage without a runtime lifecycle flag.

## Ordered construction

CheckedObjectConstruction retains exact storage, reference local and ordered
CheckedFieldInitializers. Syntax shares native named braces, but class semantics
construct storage and yield a reference; struct semantics initialize the actual
aggregate local. The local is inserted into the source scope only after all
initializer expressions are checked.

CoreObjectStorage retains the mapped CoreClass, exact ClassType, function-local
storage ordinal, lexical region ordinal and weak CoreBlock scope. It belongs to
CoreFunction.object_storage, separately from CoreLocalPlace arrays.
CoreObjectConstruction names that storage and its target reference local and
contains exact CoreObjectFieldInitializer pairs in source order. The verifier
requires one construction per storage, a fresh local, the owning lexical scope,
and every exact field initialized once with its exact type. Classes declaring init
use CoreConstructorObjectInitialization with the exact constructor and ordered
arguments instead of brace fields; constructor validation enforces field completion.

CfgObjectStorage and SsaObjectStorage retain independent stage-owned class and
lexical identity. They are memory descriptors, never aggregate values or local
reference slots. CFG evaluates each initializer and immediately initializes its
exact CfgObjectFieldPlace. Only after the final initialization does it evaluate
CfgObjectReferenceValue and bind the reference local. Short-circuit initializer
expressions may add blocks without changing written evaluation order.

SSA keeps the object memory descriptor, exact initialization Places and ordinary
memory instructions. SsaObjectReferenceInstruction publishes a scalar ClassType
reference. Direct object-storage field Places are restricted to initialization;
source accesses use validated references and existing indirect field Places.
Verifiers require unique field initialization sites and initialization dominance
before publication. Removing unreachable CFG paths may leave an unused reserved
storage descriptor, as with existing lexical storage; no source object identity
is executed along an unreachable path.

## Storage and reference flow

```text
construction site
	LexicalObjectStorageSymbol
		CoreObjectStorage
			CfgObjectStorage
				SsaObjectStorage -> explicit LLVM alloca

source reference local
	ClassType LocalSymbol -> ordinary Core/CFG local
		SSA ClassType definition / branch or loop block argument
			LLVM ptr
```

Object fields never become separately authoritative promoted locals. All aliases
load/store the same memory, including across method calls. A class declaration
does not change selective struct addressability: StructType locals retain their
existing optional field scalarization and typed-pointer behavior.

Loop execution creates a fresh semantic lifetime each time a construction site
runs. The backend reserves one slot per static construction site in a function
activation, initializes it on every executed lifetime, and may reuse its address
after the previous lifetime ends. The existing lexical escape rule prevents a
valid old reference from surviving that reuse. Recursion has separate activations.

## LLVM realization

The backend's generalized native layout registry maps exact SsaClass identities
to `%astra.class.N`. Nonempty object layout is an LLVM struct containing only the
existing physical field types, in declaration order. Each construction site has
an entry alloca named `%objectN`; source-written initialization order determines
GEP/store sequence, independently of field declaration order. Reference aliases
produce no extra object alloca and no memcpy/memmove. Object references use ptr
and exact identity comparisons use pointer `icmp`.

A class with no fields has physical layout `{ i8 }`. The single hidden byte
ensures a nonzero allocation extent and distinct addresses for simultaneously
live empty objects. It is not initialized, read, exposed as a member or treated
as runtime metadata. Normal and O2 execution qualify empty and nonempty distinct
identity. No vptr, RTTI, refcount, GC header, descriptor or allocator is present.

SSA validation lowers at its instruction position to pointer/null comparison,
trap block and valid continuation. Field GEP/load/store occurs only in the valid
continuation. Method argument effects occur after that continuation, followed by
the exact direct fastcc call with PTR physically first. `this` uses its existing
nonnull receiver and needs no guard. No exclusivity or `noalias` attribute is
inferred. LLVM optimization may remove proven redundant guards and storage
operations while preserving observable identity and effects.

Layout, padding, alignment, allocation names and machine instructions are
compiler-private. No source `sizeof(Class)`, `alignof(Class)` or field-offset
contract is introduced. A declared destructor receives the original alloca address
at normal lexical exit, independently of reference values. Escaping references
and heap ownership must extend this separate storage-lifetime authority when designed.
