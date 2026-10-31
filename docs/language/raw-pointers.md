# Opaque raw pointers

Astra's ordinary raw pointer is `void*`: a nullable, copyable, unmanaged value that
represents an opaque machine-address identity or foreign handle. Its semantic
type is independent of pointer size and distinct from the absent-result type
`void`. PTR-1 provides no way to inspect the pointed-to object.

```astra
void* identity_ptr(void* p) {
	void* copy = p;
	return copy;
}

void* maybe_ptr(bool enabled, void* p) {
	void* result = null;
	if (enabled) {
		result = p;
	}
	return result;
}
```

The supported source type grammar is `type-name := identifier ("*")?`.
`void*`, `void *`, and `void    *` are equivalent. Lexical whitespace and comments
may separate identifier and star. The star belongs to the type, before the
parameter/local/function name. Pointer declarators after names and C complex
declarators are unsupported. Parsers retain extra stars for a useful semantic
diagnostic; this does not make pointer-to-pointer a supported type.

`void*` and [typed data pointers](typed-data-pointers.md), including native
Struct* and supported integer/f32 T*, resolve as distinct pointer types.
`bool*`, resource, and vector pointees reject; two or more stars
receive `pointer depth greater than one is unsupported`. Unknown names keep
their existing diagnostic. Parameters and results support `void*` in
native definitions, source C imports, C exports, and independent VAPI declarations.
Locals require initializers and use the same Place architecture as int/bool.

`null` is a contextual null-pointer keyword, realized as the expected raw
pointer type in initialization, assignment, calls, or equality with another
pointer. Without a more specific context, including `null == null`, it defaults
to canonical `void*`. Checked/Core/CFG/SSA null nodes retain this exact type and
source provenance without a numeric payload. `void* p = null;`, `return null;`,
and `identity_ptr(null)` remain supported. Null cannot satisfy int/bool contexts.
An ordinary void* value cannot convert to a typed data pointer, even if null.

Every `void*` can contain null or a non-null foreign address. No implicit
non-null assertion or runtime nullability check occurs at a native or C call.
Assignments, arguments, and returns require exact semantic type identity.
Functions returning pointers undergo the same CFG completion checks as other
non-void functions.

`==` and `!=` accept two `void*` values and return bool. They compare only address
identity: `p == null`, `null == p`, and `null == null` are valid. Mixed pointer/int
or pointer/bool equality rejects. There is no pointer ordering, arithmetic,
truthiness, void* dereference, indexing, or casts. Native typed pointers alone
add bounded direct-local address borrows, scalar dereferences, and struct field
accesses. Write an explicit
nullable-handle guard:

```astra
if (p != null && is_handle_a(p) != 0) {
	return 0;
}
```

The RHS executes only when `p` is non-null. `if (p)` and `while (p)` reject because
conditions remain bool-only. Prefix `*p` with a void* base and addresses of void*
locals reject; infix `*` retains numeric multiplication semantics. No pointer can
be converted to/from an integer.

An unmanaged raw pointer owns nothing. Ownership-qualified local bindings instead
carry a separate [cleanup obligation](ownership.md). Copies of unmanaged pointers
do not retain, release, free, destroy, acquire, or duplicate a pointee, and dropping
an unmanaged local requires no cleanup. Foreign code
can invalidate a handle; Astra does not validate its lifetime. All C calls remain
conservatively effectful. Neither aliases nor optimization attributes are inferred
from pointer shape.

A pointer value is distinct from the Place storing it. Astra cannot expose
a pointer local's own address, so pointer locals fully promote to ordinary SSA
definitions/block parameters, including null merges and loop-carried values.
BORROW-1 and DPTR-1 expose native struct and supported scalar local storage through lexically checked typed
borrows, including pointer locals; it never converts that address into void*.
Future escaping references, ref/out,
captures, or ownership transfer must revisit this promotion proof explicitly.
OWN-1 materializes cleanup before promotion while keeping owner pointers scalar.

See [native PTR](../abi/native-pointer-v1.md), [C PTR](../abi/c-pointer-v1.md),
[VAPI](vapi.md), and [ADR 0024](../decisions/0024-opaque-raw-pointers.md).
[TPTR-1](typed-struct-pointers.md) adds native typed pointers without changing
opaque handles. Non-null raw types, allocation/free, ownership transfer, escaping borrows,
strings, callbacks, C bool, and variadics remain unsupported.

## Pointer fields in native structs

STRUCT-1 permits `void*` scalar fields in [native local structs](structs.md).
Their values retain the exact nullable, unmanaged pointer semantics above.
Field Loads/Stores and generic scalar promotion preserve pointer identity through
calls, branches, loops, and null guards. A field value is neither its own storage
address nor a pointer to the containing struct. An address-taken containing
struct keeps its void* fields in explicit memory; untouched fields promote.
The native typed borrow path cannot be stored in a void* field. Ownership,
stable layout, and aggregate C/VAPI channels remain unsupported.

[Stored lexical borrows](borrows.md) add static lifetime provenance to Struct*.
They do not change void*, C/VAPI pointer contracts, or runtime representation.
Null has no pointee-lifetime requirement; typed pointer-local reads guarantee
their own lexical region. No ownership or alias exclusivity is implied.

## Owned foreign handles

`owned void* h = create();` retains the same pointer value type but adds lexical
responsibility from a VAPI owned-result contract. Owners cannot decay into the
copyable raw forms above; OWN-1 permits only null comparison and automatic
cleanup. Null skips the destroyer, normal exits clean in reverse acquisition
order, and traps do not unwind. See [ownership](ownership.md).
