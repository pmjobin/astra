# Nominal foreign resource handles

PARAM-BORROW-1 changes plain native Resource parameters to bounded
BORROWED_NOESCAPE, equivalent to explicit `borrowed Resource`. The historical
UNMANAGED native parameter capability is intentionally removed without a new
qualifier. Unmanaged locals/results and foreign metadata remain unchanged.
See [parameter borrowing](parameter-borrowing.md).

BUFFER-1 permits automatic RAII replacement of mutable concrete Resource locals
and parameters: `r = make();` or `r = move other;` produces/captures the incoming
owner before releasing old live contents. A disarmed destination simply rearms;
explicit release is still useful for early destruction. Ownership state and
cleanup rank remain unchanged. See [replacement/rearm](rearming.md).

OWN-FIELD-1 also admits explicit `owned Resource field;` in native classes,
using this exact nominal type and release contract. Plain Resource fields and
Resource-bearing structs remain unsupported. Fields initialize by transfer,
borrow temporarily, support replacement, and clean automatically after normal
user deinit in reverse declaration order. Concrete null owners require no active
bit and no release call. See [owned Resource fields](owned-resource-fields.md).

RESOURCE-1 imports nullable, opaque resource types from VAPI:

```text
[CCode(destroy_function = "resource_destroy", cheader_filename = "resource.h")]
handle Resource;

owned Resource create_resource(int id);
int inspect_resource(borrowed Resource resource);
Resource lookup_resource(int id);
```

`Resource` enters Astra's ordinary type namespace. A source struct, builtin, or
another imported handle cannot use that type name. Every handle declaration has
an exact compiler-owned identity: even two types with the same destroy function
are different types. All loaded handle declarations are collected before any
function signature or body is resolved. The API file may precede the type file.
Handle ordinals follow VAPI CLI file order, then handle declaration order within
each file; ordinals and names are debug information, never identity.

The declaration is VAPI-only. `handle Resource;` is not Astra source syntax.
See [binding grammar and metadata](../vapi/handle-types.md).

## Type, responsibility, and representation

| Form | Responsibility | Physical value |
| --- | --- | --- |
| `Resource` local/result or foreign unmanaged contract | Unmanaged; owns nothing | Nullable PTR |
| Native `Resource` or `borrowed Resource` parameter | Non-owning, noescape during the call | Nullable PTR |
| `owned Resource` local, native parameter/result or imported result | One cleanup responsibility | Nullable PTR |

These are three independent dimensions. `Resource` is neither `void*` nor a
native struct. Ownership qualifiers do not create different machine types.
Native ABI and C ABI both use the existing `scalar-ptr-v1` PTR channel; LLVM sees
ordinary address-space-zero `ptr`. No runtime type tag, descriptor, destructor
pointer, wrapper object, or allocation is attached to the value.

## Unmanaged values

```astra
bool same(Resource a, Resource b) { return a == b; }
Resource empty() { return null; }

int inspect_raw() {
	Resource a = lookup_resource(1);
	Resource b = a;
	if (a == b) { b = null; }
	b = a;
	return inspect_resource(b);
}
```

Unqualified locals, copies, assignments, native results and C import unmanaged
parameters/results carry no ownership responsibility and retain unconstrained
escape behavior. Native parameters instead borrow: `Resource identity(Resource r)
{ return r; }` now rejects because r cannot escape its bounded input contract.
Passing an owner to a foreign unmanaged parameter still rejects. Foreign access
requires explicit borrowed/noescape metadata or an existing ownership contract.

Every handle is nullable. Literal `null` takes the expected handle type in local
initialization, assignment, arguments and returns, or from the other equality
operand. `Resource == Resource` and `Resource != Resource` produce bool; either
operand may be literal null. Different handles cannot compare, copy, assign,
move, rearm or pass into one another, even with identical cleanup contracts.
No implicit conversion or equality with `void*` exists. There is no truthiness;
write `r != null`. Arithmetic, ordering, `*r`, `r->field`, `&r`, `Resource*`, arrays,
casts, layout queries and resource-valued struct fields are unavailable.

## Owned locals and stable cleanup authority

```astra
int scoped() {
	owned Resource r = create_resource(1);
	inspect_resource(r);
	owned Resource next = move r;
	r = create_resource(2);
	release r;
	r = create_resource(3);
	return inspect_resource(next);
}
```

A handle type owns one stable exact cleanup contract. All owned producers of
that type use it, including `extern(C) owned Resource create_resource(int id);`
once the type is imported. Function-level `destroy_function` on a handle result
rejects. An owned result has semantic type Resource plus ownership category
OWNED; capturing it in an unmanaged local, discarding it, returning it through an
unmanaged result, or immediately passing it as an argument rejects.

The existing acquire/move/borrow/release/rearm state machine is reused. Moves
require exact value type and cleanup identity. Concrete Resource assignment accepts
a direct owned producer or `move other` of that exact handle type. A live destination
performs RAII replacement; MOVED/RELEASED storage rearms with no old cleanup. The owner identity,
lexical lifetime and cleanup rank never change; automatic cleanup runs in reverse
lexical owner-slot order. Explicit release remains at its statement position.

An owned null still has OWNED responsibility. Moving it leaves the source MOVED
and the destination OWNED even though both physical pointers are null. Releasing
it gives RELEASED and invokes no destroyer. Lexical cleanup uses the existing
null guard and exact `void destroy(void*)` C call. Traps do not unwind cleanup.

Existing producer-specific `owned void*` contracts remain supported unchanged.
They use the same owner slots and flow algorithm, with their original anonymous
cleanup authority. See [ownership](ownership.md), [moves](moves.md),
[release](release.md), and [rearming](rearming.md).

## Borrowed parameters

```astra
int inspect_native(Resource r) {
	if (r != null) { return inspect_resource(r); }
	return 0;
}

extern(C) int inspect_foreign(borrowed Resource r);
```

A definitely OWNED local, unmanaged exact Resource, literal null or another
borrowed Resource parameter can be passed. Borrowing preserves responsibility;
borrow before move/release and borrow after rearm are valid. Moved, released and
mixed owners reject until definitely OWNED again.

Native borrowed parameters cannot be captured into unmanaged locals, assigned
into unconstrained storage, returned, or forwarded to unmanaged parameters.
Exact borrowed forwarding and equality are allowed. A borrowed parameter owns
nothing and cannot destroy, retain or transfer the resource. Foreign bindings
are trusted promises; no C analyzer or runtime lifetime metadata exists.
Borrowing permits mutation and does not imply readonly. See
[borrowed parameters](borrowed-parameters.md).

## Owned native boundaries

[Owned functions](owned-functions.md) use the type's stable cleanup authority:

```astra
owned Resource pass(owned Resource r) {
	return move r;
}
```

An existing caller owner transfers with `pass(move owner)`. The parameter starts
OWNED; if it retains responsibility it cleans at function exit, after root locals.
`return move r` disarms r before the remaining cleanups. `return null` supplies
owned-null responsibility. The caller must acquire or rearm from the result.
Argument moves affect source legality left-to-right, while physical source nulling
commits after all arguments evaluate, immediately before invocation.

C exports of handles, owned void* native boundaries, direct owned-call chaining,
resource fields/arrays/pointers, persistent borrowed locals, allocation, methods
and refcounting remain deferred. Cleanup-polymorphic code cannot erase nominal
types merely because their values share PTR or a cleanup function.

[ADR 0033](../decisions/0033-nominal-resource-handles.md) freezes this contract.
