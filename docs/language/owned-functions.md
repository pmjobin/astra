# Owned native functions

[Parameter borrowing](parameter-borrowing.md) intentionally supersedes the old
plain native Resource UNMANAGED parameter contract. Plain and explicit borrowed
forms now share bounded noescape semantics; `owned` and named `move` remain
explicit. Resource result contracts and foreign metadata are unchanged.

BUFFER-1 intentionally generalizes concrete Resource local/parameter assignment
to automatic RAII replacement. Incoming production completes before old live
cleanup; MOVED/RELEASED destinations rearm without old cleanup. Explicit release
and existing capture/commit ordering remain valid. [Owned buffer boundaries](owned-runtime-arrays.md)
use the same principle with complete base/length groups and a distinct buffer-v8
contract. ClassType slot reassignment remains unsupported.

A native function can receive and return responsibility for a nominal resource:

```astra
owned Resource pass_through(owned Resource r) {
	return move r;
}

int main() {
	owned Resource a = create_resource(1);
	owned Resource b = pass_through(move a);
	return 0;
}
```

Resource is an imported [nominal handle](resource-handles.md) with a type-level
cleanup contract. The caller moves a, the callee receives r as OWNED, the return
moves r, and b acquires the returned responsibility. Only b's final cleanup
physically destroys the resource. The source slots remain present but null.

## Signatures

```text
parameter := ownership-qualifier? type-syntax identifier
ownership-qualifier := "owned" | "borrowed"
native-result := type-syntax | "owned" nominal-handle-type
native-definition := native-result identifier "(" parameter-list? ")" block
```

The Resource boundary described below requires an exact nominal HandleType.
[Object ownership](object-ownership.md) and [owned runtime arrays](owned-runtime-arrays.md)
define the additional ClassType and SliceType ownership contracts.
`owned void*`, `owned int`, `owned bool`, `owned Pair` and `owned Pair*` reject.
Borrowed void* and borrowed Resource parameters retain their existing rules.
Qualifiers describe responsibility contracts, independently of the value's type:

| Signature position | Contract | Responsibility |
| --- | --- | --- |
| Native `Resource r` | BORROWED_NOESCAPE | Temporary access; no ownership |
| `borrowed Resource r` | BORROWED_NOESCAPE | Temporary access; no ownership |
| `owned Resource r` | OWNED_TRANSFER | Caller transfers one responsibility |
| `owned Resource` result | OWNED_TRANSFER | Successful return transfers one responsibility |

There are no ownership-based overloads. `int main()` remains the only executable
entry signature. C exports with owned parameters/results remain unsupported.

## Calling an owned parameter

Use `consume(move owner)` for an existing owned local or owned parameter.
The source must be definitely OWNED and must match the exact nominal type and
cleanup contract. `consume(owner)` never implies a move. Unmanaged and borrowed
values have no transferable responsibility, even when their pointer equals an
owned resource. Sharing a destructor does not make two handle types compatible.

`consume(null)` is valid. Its exact expected Resource type supplies the cleanup
contract; the callee starts OWNED with a physical null pointer. Automatic cleanup
and release skip the destroy call for null while still ending responsibility.

Arguments evaluate left-to-right. At `move owner`, the source becomes semantically
MOVED. Every subsequent use, including a null comparison or borrow in another
argument, must obey that state:

```astra
consume_with_id(resource_id(r), move r); // valid: borrow finishes first
consume_with_flag(r == null, move r);   // valid for a bool first parameter
consume_then_id(move r, resource_id(r)); // error: cannot borrow moved owned value
consume_two(move r, move r);             // error: use of moved owned value
```

The compiler captures each transferred pointer at the move expression but delays
physical source clearing until all arguments have evaluated successfully. It then
clears all moved sources immediately before invocation. A later argument trap
prevents invocation; Astra does not unwind or recover ownership on that path.

A direct borrowed argument also requires its source to remain OWNED until the
invocation. `f(r, move r)` cannot simultaneously borrow and transfer the same
owner, and `f(r, consume(move r))` cannot preserve a borrowed argument across a
nested consuming call. Both reject with `cannot borrow moved owned value 'r'`.
The completed inspection in `f(inspect(r), move r)` remains valid because that
borrow ends before the move. This uses the existing invocation-time borrow check.

## Inside the callee

Each owned parameter starts definitely OWNED and has a stable function-root
cleanup slot. It supports the ordinary [borrow](borrowed-parameters.md),
[move](moves.md), [release](release.md) and [rearm](rearming.md) operations:

```astra
void consume(owned Resource r) {
	resource_id(r);
	release r;
	r = create_resource(2);
	owned Resource local = move r;
}
```

Release destroys the original pointer. The replacement moves to local; local
cleans the replacement, then the parameter's null slot cleans as a no-op.

Owned parameters rank in declaration order before root locals. Normal return or
fallthrough cleans root locals first, then parameters in reverse declaration
order. Nested owners clean before root owners. Explicit release does not change
slot rank, and rearm never registers another cleanup. Existing branch and loop
possibility-set analysis applies unchanged.

## Returning ownership

Every reachable successful return from `owned Resource f(...)` supplies exactly
one responsibility using either `return move owner;` or `return null;`.

A return move captures the pointer, changes the owner to MOVED and clears its
current pointer before other lexical cleanups run. The captured result survives
those cleanups. The returned responsibility leaves the function; the callee does
not create a result-owner cleanup slot.

A null return performs normal lexical cleanups, then returns owned-null of the
exact result type. These two paths are independently valid:

```astra
owned Resource choose(owned Resource r, bool discard) {
	if (discard) {
		release r;
		return null;
	}
	return move r;
}
```

The terminating released arm never contaminates the other return. Released,
moved or maybe-owned return sources reject, as do the wrong nominal type,
unmanaged values and bare `return owner;`.

## Consuming a native result

Native and foreign owned producers use the same immediate, exact, exactly-once
acquisition/rearm rules:

```astra
owned Resource r = make_native();
release r;
r = make_native();
```

The destination must have the exact Resource type and cleanup contract. Assignment after producer evaluation performs RAII replacement for live slots
and ordinary rearm for definitely disarmed slots. Incoming capture precedes any
old-value cleanup.
The slot may belong to a local or owned parameter. Owned-null results still arm it.

Discard, unmanaged capture and inline borrow reject. Direct owned-call chaining
is deferred; use a lexical owner:

```astra
owned Resource temporary = make_native();
consume(move temporary);
```

Similarly, return a named owner with `return move temporary;`, rather than
`return make_native();`. Owned void* native boundaries, owned fields, move
assignment, generic/shared ownership, native allocation and exception cleanup
are not part of this feature.

The native ABI erases each resource to PTR, and LLVM uses ordinary `ptr` and
`fastcc`. There is no ownership flag, token or destructor-pointer argument.
See [the decision](../decisions/0034-owned-native-boundaries.md) and
[ownership boundary IR](../ir/ownership-boundaries.md).
