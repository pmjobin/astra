# Borrowed foreign handle parameters

For native nominal Resource, Class and Slice parameters, PARAM-BORROW-1 makes
`borrowed` optional without changing its contract. Raw `void*` and foreign
metadata still require their existing explicit qualifiers. See
[parameter borrowing](parameter-borrowing.md).

This page describes handle borrowing. SLICE-BOUND-1 separately admits native
[`borrowed T[]` slice parameters](slices.md#native-borrowed-parameters), which
permit local view copies and mutable element access under lexical noescape
authority. The handle rules below remain unchanged.

RESOURCE-1 extends this contract to exact imported handle types: `borrowed Resource`.
An owned Resource, unmanaged Resource, literal null or borrowed Resource may be
passed; other nominal types and void* cannot. Native noescape forbids raw local
capture, assignment capture, return and unmanaged forwarding. Type identity is
retained through SSA; native/C transport remains PTR. See [resource handles](resource-handles.md).

`borrowed void*` permits temporary, non-owning access to a foreign handle for the
dynamic duration of one call. It is available on native functions, source C
imports and VAPI C imports in OBORROW-1:

```astra
extern(C) int resource_is_live(borrowed void* p);

int inspect(borrowed void* p) {
	return resource_is_live(p);
}

int scoped() {
	owned void* h = create_resource(1);
	int live = inspect(h);
	inspect(h);
	owned void* next = move h;
	inspect(next);
	return live;
}
```

The producer needs the existing [VAPI cleanup contract](../vapi/owned-results.md).
Each call borrows the current pointer; `h` still owns after the first two calls.
The explicit move transfers responsibility to `next`, which cleans up at lexical
exit. Borrowing does not retain, release, duplicate, destroy, move or rearm.

```text
parameter := ("borrowed" | "owned")? type-name identifier
```

The borrowed type must be exactly `void*` or a nominal HandleType. The owned
qualifier is native-only and requires nominal HandleType; see [owned functions](owned-functions.md). `borrowed int`, `borrowed bool`,
`borrowed Pair`, `borrowed Pair*`, `borrowed void`, and `borrowed void**` reject.
`borrowed` is reserved and cannot be an identifier. Native `Struct*` parameters
already use [lexical typed-pointer borrowing](borrows.md).

The owner must be definitely OWNED at argument evaluation. Borrowing preserves
that state. Repeated borrows and loop backedges containing only borrows remain
OWNED. A conditional move that reaches a join prevents borrowing there; a moved
arm that returns contributes no continuation predecessor. Diagnostics distinguish:

```text
cannot borrow moved owned value 'h'
owned value 'h' may have been moved on another control-flow path and cannot be borrowed
```

A successful null factory result still establishes OWNED responsibility. It may
be borrowed, the callee receives null, and lexical cleanup skips the destroyer.
Raw unmanaged `void*` expressions and `null` are also valid borrowed arguments.
`inspect(create_resource(1))` rejects: acquire an owner first. An owner cannot
otherwise initialize raw storage or enter an ordinary `void*` parameter.

A borrowed parameter owns nothing and cannot escape the invocation. Native uses
are checked individually. These uses are permitted:

```astra
int forward(borrowed void* p, borrowed void* q) {
	if (p == null || p != q) {
		return inspect(p);
	}
	while (p != null && p == q) {
		return inspect(q);
	}
	return 0;
}
```

Normal pointer equality type rules apply: comparisons produce bool. Native
functions can return that bool directly with a bool result type, or use explicit
int branches as above; there is no bool-to-int conversion. Forwarding must be direct into another
borrowed/noescape parameter, optionally parenthesized. No intermediate storage
is allowed, including local storage. These examples reject:

```astra
void* q = p;
q = p;
holder.handle = p;
holder_ptr->handle = p;
return p;
raw_use(p);                 // raw_use(void*) promises no lifetime constraint
owned void* h = p;
owned void* h = move p;
```

The diagnostic for storage, return and unmanaged forwarding identifies the exact
borrowed parameter and explains that only equality and direct borrowed/noescape
forwarding are permitted. Borrowed and unmanaged parameters remain non-assignable.
Owned Resource parameters have mutable ownership slots and ordinary rearm rules.

Borrowed does not mean immutable, readonly or pure. A foreign callee may inspect
or mutate the resource, perform I/O, and update state. It may not retain, free,
destroy, transfer or expose the pointer after returning. Source extern and VAPI
borrowed contracts are binding-author promises; Astra enforces native bodies but
does not analyze C implementations. Violations are foreign-interface contract
violations. Calls retain their usual left-to-right evaluation and effect order.

There are no borrowed locals, fields, results or C exports, and no general
raw-pointer lifetime inference. Owned Resource native calls support explicit
transfer independently of borrowed/noescape access. NABI/CABI still carry
PTR and LLVM still carries `ptr`, with native fastcc and C ccc. Borrow validation
ends before physical lowering: no runtime token, counter, retain/release,
additional storage, source clearing, or LLVM borrow attributes are introduced.
See [ADR 0030](../decisions/0030-borrowed-owner-parameters.md) and
qualification.

## Release interaction

A completed borrow leaves its owner OWNED, so repeated borrowing followed by
`release h;` is valid. Release changes OWNED → RELEASED; borrowing afterward reports
`cannot borrow released owned value 'h'`. Conditional release produces
`{OWNED, RELEASED}` and rejects borrowing at the join. If the released arm returns,
only the OWNED continuation reaches the borrow and it is valid. Borrow-only loops
retain OWNED; a released continue/backedge can invalidate a later borrow.

`release p;` inside `void f(borrowed void* p)` rejects: the parameter has no cleanup
responsibility. Owned Resource parameters may release because they receive
responsibility through explicit transfer. Persistent borrowed locals/results remain deferred. See [release](release.md).

## Rearming interaction

A completed borrow preserves OWNED and cannot by itself authorize rearming.
`inspect(h); release h; h = create_resource(2); inspect(h);` is valid when the
producer uses the slot's same exact cleanup contract. Successful rearm makes h
OWNED even for a null result. The next borrow sees the new pointer; a moved
recipient keeps its independent old resource. Conditional single-arm rearm may
leave a mixed state and still rejects source borrowing at the join. See
[rearming](rearming.md); no borrowed local or result is introduced.

A direct borrowed argument also requires its source to remain OWNED until the
invocation. `f(r, move r)` cannot simultaneously borrow and transfer the same
owner, and `f(r, consume(move r))` cannot preserve a borrowed argument across a
nested consuming call. Both reject with `cannot borrow moved owned value 'r'`.
The completed inspection in `f(inspect(r), move r)` remains valid because that
borrow ends before the move. This uses the existing invocation-time borrow check.
