# Borrowed typed struct pointers

A native `Pair*` is a nullable, non-owning pointer to exact Pair storage.
Passing a local's address to a native function lets that function read or mutate
its scalar fields:

```astra
struct Pair {
	int x;
	int y;
}

void set_x(Pair* p, int value) {
	p->x = value;
}

int main() {
	Pair p = { x = 1, y = 2 };
	int before = p.x;
	set_x(&p, 42);
	if (before != 1 || p.x != 42) {
		return 1;
	}
	return 0;
}
```

The final `p.x` reads the same storage that `set_x` mutated. Two arguments may
alias: `set_two(&p, &p)` gives both parameters the same pointer. No disjointness
or non-null guarantee is inferred for parameters.

## Grammar and exact types

```text
type-name := identifier ("*")?
address-expression := "&" identifier
indirect-field-access := identifier "->" identifier
assignment := (identifier | field-access | indirect-field-access) "=" expression ";"
```

`void*`, supported scalar T*, and native `StructName*` resolve as pointer types. Whitespace and
comments around the type star are lexical; `Pair /* comment */ *` is equivalent
to `Pair*`. Extra stars parse for the diagnostic
`pointer depth greater than one is unsupported`. `bool*`, `Resource*`, vector
pointers, `Pair**`, `void**`, complex/function declarators, casts, arithmetic,
ordering, and whole-struct `*p` values are unsupported. DPTR-1 adds integer/f32
`*p` Places; see [typed data pointers](typed-data-pointers.md). `&`/`&&`, `|`/`||`,
and `-`/`->` use maximal token matching; bitwise operators do not accept pointers.

Struct identity is nominal. Two identically shaped structs A and B have
different types, including `A* != B*` as type identities. Analysis canonicalizes
one TypedPointerType per exact pointee in its type universe, shared with scalar
typed pointers. RawPointerType is reserved for void*. Struct identities
are collected before signatures, so a function may use a later declared Pair*.
No implicit conversion exists to/from `void*` or another struct pointer type.

Native parameters and initialized locals may have Struct* type. Locals may
borrow a visible struct local, copy a parameter or compatible pointer local, or
receive null. Each stored value must outlive the destination lexical region:

```astra
int read(Pair* p) {
	Pair* q = null;
	q = p;
	return q->x;
}
```

Pointers do not own their pointees. Copies and local destruction have no pointee
cleanup. Pointer locals themselves remain scalar-promotable; referring to
storage does not expose the pointer local's own storage address.

Typed pointer results reject with
`typed-pointer function results are unsupported; escaping pointers require return-lifetime contracts`.
Existing `void*` results remain valid. Struct fields remain exactly int, bool,
and void*: typed pointer fields are unsupported. Source C imports/exports reject
typed pointers with
`typed native struct pointers are not supported by the C ABI yet`.
VAPI foreign type checking rejects native-looking pointer spellings with
`unsupported foreign pointer type; C/VAPI supports only 'void*'`;
it never resolves Astra native structs.

## Contextual null and comparisons

`null` is a contextual null-pointer literal, realized as the exact expected
pointer type in local initializers, assignments, and call arguments.
Equality takes its context from the other pointer operand: both `p == null` and
`null != p` work. Parentheses around null retain this behavior. No more specific
context, including `null == null`, defaults to `void*`. Null is never integer zero.

Equality and inequality require exactly matching pointer types after literal
contextualization. An ordinary `void*` variable containing null cannot initialize
a Pair* variable. Null contextualization is not a general conversion rule.
Conditions must be bool: use `p != null`, not `if (p)`. Pointers have no
arithmetic, ordering, integer conversion, or truthiness.

## Lexically stored local address borrows

`&pair` requires a visible, fully initialized native struct local and produces
its exact Struct* type. It is a general expression in BORROW-1:

```astra
Pair* p = &pair;
p = &pair;
consume((&pair));
if (&pair == p) { p->x = 42; }
```

Pointer initializers and assignments require the source region to equal or
lexically enclose the pointer local's region. Each block owns an exact region;
function parameters guarantee the invocation root, pointer reads guarantee their
own local region, and null has no lifetime requirement. Same-scope late borrows
are valid after the pointee initializer, regardless of declaration order.
Inner to outer stores fail with a shorter lexical lifetime diagnostic, including
copies through an inner pointer. See [borrows](borrows.md) for safe/unsafe examples
and the intentionally conservative pointer-local summary.

Arguments still evaluate left-to-right. A callee can copy the parameter and
forward it, including through bounded recursion, while caller storage remains
live. `return &pair`, typed pointer fields, and C/VAPI destinations stay invalid.
Passing to void* or a different Struct* fails ordinary exact type checking.

Address operands that are bool/resource/vector/pointer locals, parameters,
missing, out of scope, or the struct currently being initialized report
`address borrow requires a direct local integer, f32, numeric vector, or native struct variable`.
Supported integer and f32 locals use this same addressability/borrow machinery.
`&(expression)`, `&pair.x`, and `&ptr->x` remain outside the narrow syntax.

## Indirect fields and traps

`p->x` requires an identifier naming a Struct* parameter or local. It binds the
exact pointer value, pointee type, and declared scalar field. Reads produce the
field type; assignments require that exact scalar type. Arbitrary expression
bases, chaining (`p->nested.field`), and whole-struct loads/copies do not exist.

Null access is a deterministic non-returning runtime trap, for reads and writes.
A read checks and loads at its expression point. An assignment evaluates its
RHS first, then checks the target pointer and stores. Thus RHS effects in
`p->x = effect()` happen before a null trap. No particular host signal is part
of the language contract.

Short circuit retains its ordinary rules: `p != null && p->ready` and
`p == null || p->ready` skip the field read for null. Forms requiring the RHS
still trap when null. BORROW-1 non-null typed pointers can only originate from
valid live Astra storage, so no additional dynamic validity check is required.

Taking a struct local's address anywhere in the valid checked function, even
after a return, makes all its fields memory-backed for the whole function.
Other locals remain scalarized. Backend layout is private and target-dependent;
there is no stable struct ABI, size/alignment/offset query, heap allocation,
ownership, escaping reference, or address-of arbitrary storage.

See [ADR 0027](../decisions/0027-lexical-borrow-regions.md),
[ADR 0026](../decisions/0026-typed-struct-pointers.md),
[addressable storage](../ir/addressable-storage.md), and
[native struct realization](../backend/native-struct-storage-v0.md).
