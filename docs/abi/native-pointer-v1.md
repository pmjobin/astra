# Native scalar and pointer ABI v1

[Owned object results](../ir/object-results.md) use `NativeOwnedObjectResultPlan`: hidden candidate PTR followed by an optional receiver and explicit parameter components, with ordinary owner PTR result. Only owned ClassType result contracts map this way; generic ClassType mapping remains rejected. Existing vector-v4 and slice-v5 profiles include these PTR channels, with no new profile.

OBJ-OWN-1 also maps `owned C` native parameters to existing PTR after exact
ClassType and OWNED_TRANSFER validation. `void consume(owned C c)` has PTR -> void.
Null parameters are legal. Object/Resource domains and destructor authority remain
upstream; NABI adds no owner type, hidden argument, profile or pointer attribute.
Borrowed objects, Resources, vectors and slices coexist under existing profile
selection. Unqualified/borrowed object results and C object ownership remain unsupported. See
[ADR 0052](../decisions/0052-transferable-object-ownership.md).

OBJ-BOUND-1 maps an explicit `borrowed C c` parameter to one existing PTR
channel after exact ClassType and BORROWED_NOESCAPE validation.
`int inspect(borrowed C c)` has `PTR -> I32`; a void result gives `PTR -> void`. Multiple
objects are separate PTR parameters. The existing profile policy selects v1 or
higher from companion channels. No NativeObjectType or new profile exists, and
Unqualified/borrowed ClassType results still reject. Physical PTR collisions with other classes,
Resource handles and typed/raw pointers cannot establish semantic compatibility.
The nullable, mutable, aliasable contract emits no new pointer attributes; in
particular no `nonnull`, `noalias`, `readonly`, `byval` or `sret` object ABI exists.
See [ADR 0051](../decisions/0051-borrowed-object-boundaries.md).

OBJ-LIFE-1 constructor/destructor receivers use the same independent first PTR.
Both have no physical result; constructor explicit parameters follow existing
profile selection. NativeFunction.kind distinguishes FUNCTION, METHOD, CONSTRUCTOR
and DESTRUCTOR and retains exact class ordinal for internal identity. The initializing
receiver contract is validated before PTR mapping. No new channel/profile,
lifecycle CABI/VAPI support or exported lifecycle symbol exists.
See [lifecycle IR](../ir/object-lifecycle.md).

OBJ-1 class methods reuse the same first PTR receiver channel after caller null
validation. Receiver-only calls use PTR; vectors and borrowed slices select the
existing vector-v4 and slice-v5 policies (`PTR + VECTOR` or `PTR + Slice(PTR,I32)`).
No profile or explicit ClassType channel is added. Class references in a body have
no ABI effect; unqualified/borrowed object results and unqualified parameters remain rejected; owned parameters use the explicit transfer contract.
Explicit borrowed ClassType parameters reuse PTR as described above. NativeFunction copies the declaring class/struct
category and exact ordinals for physical identity. ClassType remains distinct
from TypedPointerType and has no implicit `void*` conversion. CABI/VAPI support
is unchanged. See [object IR](../ir/object-values.md).

METHOD-1 uses existing PTR as a separate implicit first receiver channel in
NativeSignature. It introduces no NativeReceiverType or ABI profile. The exact
semantic ReceiverType and method target are validated before this mapping;
PTR itself carries no receiver, lifetime, uniqueness or nullability semantics.
A receiver-only `int get()` selects at least scalar-ptr-v1. Effective signatures
including narrow integers, f32, vectors or borrowed slices select the existing
later program-wide profiles. Explicit parameter ordinals remain unchanged.
Methods are internal native members and cannot attach C export boundaries.
See [method IR](../ir/methods.md).

Numeric vector pointers use the same PTR mapping as scalar and struct pointers.
Exact VectorType identity, including int/i32 aliasing and signedness/shape
distinctions, survives through SSA and is erased only at physical planning.
`void clear(i16<8>* p)` selects scalar-ptr-v1; its vector pointee does not create
a by-value vector channel. Mixing PTR and an actual vector value selects existing
vector-v4. No pointer result, C typed-vector boundary or new profile is added.

OWNBOUND-1 maps unmanaged, borrowed and owned nominal handle signature values to the
existing NativeScalarType.PTR. No new profile or machine channel is introduced.
Exact handle/native call types are validated before this physical erasure:
ResourceA, ResourceB and void* remain distinct even though each maps to PTR.
`Resource identity(Resource r)` and `owned Resource pass(owned Resource r)` both
use internal fastcc ptr(ptr). Their semantic contracts remain distinct through
SSA. NABI is physical authority only and introduces no ownership channel, hidden
flag, cleanup-function argument or descriptor. Owned/unmanaged/borrowed parameter
NABI dumps are byte-identical; owned/unmanaged Resource results also match.
See [ownership boundaries](../ir/ownership-boundaries.md).

`NativeAbiVersion.SCALAR_PTR_V1`, dumped as `scalar-ptr-v1`, extends the native
channel set with `NativeScalarType.PTR`. It denotes opaque native raw-pointer
transport and carries no bit width, layout, ownership, or address arithmetic.
It is an internal compiler artifact profile, not a stable linking contract.

| Semantic form | Native channel |
| --- | --- |
| `int` | I32 |
| `bool` | B1 |
| `void*` | PTR |
| Typed data pointer parameter: integer/f32 T* or native `StructName*` | PTR |
| `Resource`, `borrowed Resource`, `owned Resource` parameter | PTR |
| `Resource`, `owned Resource` result | PTR |
| `void` result | Absent result |

One pointer parameter maps to one direct PTR channel; a pointer result maps to
one direct PTR result for void* or Resource. All typed-pointer results reject
semantically. Ordinary free signatures have no hidden channels or nullability
assertions. Method signatures additionally carry the separate first receiver PTR
described above; PTR itself still implies no nullability attribute.
A NativeAbiProgram uses v1 when at least one native function signature contains
PTR and no signature requires a later integer/f32/vector profile. All its signatures use the same version,
including int/bool-only signatures, in unchanged source order. Pointer-valued
body locals alone do not select v1. C imports do not select the native version.
The [frozen scalar-v0 contract](native-scalar-v0.md) continues to apply to
pointer-free native signatures; the standalone verifier rejects PTR under v0.

```text
(native-abi scalar-ptr-v1
	(function #0 "identity_ptr"
		(linkage native-internal)
		(signature
			(parameters
				(parameter #0 PTR)
			)
			(result PTR)
		)
	)
)
```

NativeTypeMapper is the semantic-to-native authority. Completed models,
verifiers, and dumpers depend on neither semantic types nor LLVM. Their
identities, ownership rules, weak program links, and stage lifetime contracts
are unchanged. Raw pointer payloads are not compiler-owned foreign objects.

LLVM's native mapper realizes PTR as opaque `ptr` in address space 0. Native
functions remain internal/fastcc; native calls and recursion use fastcc. LLVM
target data layout determines physical width during emission. No ptrtoint,
inttoptr, host pointer typedef, or semantic numeric width is required.

[The C PTR channel](c-pointer-v1.md) remains an independent enum/domain even
when LLVM representation matches. A C export never changes its native target's
identity or convention. Future addressable or owned types must establish their
own semantic and promotion rules rather than inferring them from PTR.

## Typed pointee authority

NativeTypeMapper maps general TypedPointerType and opaque RawPointerType to
existing PTR without a new channel/profile. Semantic/Core/CFG/SSA checking
enforces exact pointee identity before physical planning: i8*, u8*, f32*, Pair*,
State*, and void* are not interchangeable; int* and i32* are exactly one type.
Call-bound borrows, nullability, aliases, and memory operations do not alter NABI.
Typed pointer parameters remain native-only; CABI accepts void* and nominal
resource handles, while scalar, struct, and vector typed pointers remain excluded.
Old scalar-v0 and scalar-ptr-v1 goldens are unchanged. See
[typed pointers](../language/typed-data-pointers.md).

Pointee type does not itself require a newer physical profile: `void f(i8* p)`
uses PTR under v1, while `i8 f(i8* p)` also needs an I8 result and selects v2.
An f32 result selects scalar-fp-v3. Vector arguments and a scalar output pointer
coexist under vector-v4. Body-only pointer locals do not affect selection.
No pointee layout, numeric alignment, exclusivity, readonly, ownership, or
non-null promise follows from the PTR channel.

## Integer-capable successor

INTS-1 preserves this profile for signatures without i8/u8/i16/u16/u32.
`int` and `i32` both map to existing I32 and do not require a newer profile.
A native parameter/result using a new integer selects
[scalar-int-v2](native-integers-v2.md), which subsumes I32/B1/PTR and retains
I8/U8/I16/U16/U32 as distinct signedness-bearing channels. Body-only integer
locals or struct fields do not change profile selection. Existing v0/v1 golden
output remains byte-identical, and no C ABI capability is implied.

## Generic ownership specialization

GEN-OWN-1 creates no generic NABI type or profile. Generic definitions have no ABI;
ordinary native planning runs after Core specialization. `relay<Resource>` uses
one owner PTR parameter and returns PTR. `relay<Counter>` uses the existing hidden
caller result-candidate PTR followed by owner PTR and returns owner PTR. Resource
results never acquire object storage parameters. Void-returning dispose instances
use their existing PTR owner channels and concrete cleanup domains. See
[generic ownership IR](../ir/generic-ownership.md).
