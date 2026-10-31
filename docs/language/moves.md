# Explicit ownership moves

OWNBOUND-1 also permits direct `move owner` arguments for exact owned Resource
native parameters and `return move owner` in owned Resource functions. Sources
may be owned locals or owned Resource parameters. See
[owned functions](owned-functions.md) for the exact boundary contract.

RESOURCE-1 permits `owned Resource b = move a;` when a is an exact owned Resource.
Different handles reject even when their destroy functions coincide. The type's
stable cleanup, source/destination states and lexical cleanup ranks use the same
operations below. An owned-null Resource transfers responsibility while both
physical pointers remain null. See [resource handles](resource-handles.md).

A move transfers an existing foreign handle's cleanup responsibility to a fresh
owned local:

```astra
owned void* a = create_resource(1);
owned void* b = move a;
```

The exact grammar is:

```text
move-expression := "move" identifier
owned-local-declaration := "owned" type-name identifier "=" owned-initializer ";"
owned-initializer := direct-owned-result-call | move-expression
```

`type-name` must resolve to void* or an imported handle. The move source must resolve to an
owned local or owned Resource parameter of that exact type, never an unmanaged
or borrowed parameter, raw pointer, int, Struct*, or function call.
The destination becomes visible after initialization and inherits the exact
cleanup contract. Moving does not call a producer, clone, retain or destructor.

After this move, b is OWNED and a is MOVED. Source code may compare b with null,
but cannot read or move a again. Copying, returning and passing either owner
remain subject to the [owned-local restrictions](ownership.md).

```astra
owned void* c = move b; // transfer chain; only c now owns the resource
if (a == null) {}       // error: use of moved owned value 'a'
owned void* d = move a; // same error: double move
```

## Branches and loops

```astra
owned void* a = create_resource(1);
if (condition) {
	owned void* b = move a;
} // b destroys the resource on the true path
// a is MAYBE_OWNED: true moved it, false retained it.
```

At the join, a may still own responsibility, but source code cannot use it:
`a == null`, `a != null` and another move all reject with
`owned value 'a' may have been moved on another control-flow path`.
Automatic cleanup remains legal and destroys exactly once across either path.
Moving into the inner scope intentionally shortens the resource lifetime.

If both arms move a, its join state is MOVED. If the moved arm returns, it does
not reach the continuation: a remains OWNED there and a null comparison is legal.
Source after return cannot contaminate reachable state.

Loops are analyzed to a fixpoint over actual CFG edges. Moving an outer owner
on a path that reaches the backedge (including continue) makes a repeated move
unsafe. A move followed by break is safe; the exit may be MAYBE_OWNED. A move
followed by return cannot contaminate the header. Fresh acquire/move declarations
inside a loop body are safe because each iteration has new dynamic owners:

```astra
while (condition) {
	owned void* a = create_resource(1);
	owned void* b = move a;
} // b destroys, a cleanup is a no-op, each iteration
```

## Pointer representation and cleanup

Semantically OWNED means responsibility, not non-nullness. A factory can produce
an owned null pointer. Moving it still makes the source MOVED and destination
OWNED; neither cleanup calls a destructor.

Physically a move copies the old pointer value into the destination and clears
the source to null. This clearing is inaccessible as a source-language moved-state
query. At a conditional join the source may become a pointer phi of original/null;
its independent semantic state is MAYBE_OWNED. No runtime ownership boolean exists.

Both lexical cleanups stay present. For `a; b; c = move a;`, cleanup order is
c, b, a, and physical destruction order is a's resource followed by b's resource.
Return expressions finish before cleanup. Break/continue clean the scopes they
exit. Traps still terminate without unwinding.

## Unsupported contexts

These remain invalid for the owned void* locals used above:

```astra
void* raw = move a;
int x = move a;
consume(move a);
return move a;
move a == null;
owned void* b = (move a);
owned void* c = move create_resource(1);
b = move a;
a = null;
```

There is no move assignment or move to a field. Native parameter/result transfers
require nominal Resource; bare owned void* boundaries reject. A moved-from
source may be [rearmed](rearming.md) by a direct producer with its original exact
cleanup contract; `{MOVED, RELEASED}` also permits this, while any OWNED path rejects.
Explicit early destruction uses [release](release.md). Native struct
borrowing is a separate system. See [ADR 0029](../decisions/0029-ownership-transfer.md)
and [ownership flow](../ir/ownership-flow.md).

## Borrowing and moves

OBORROW-1 permits temporary [borrowed arguments](borrowed-parameters.md) before a
move and from its destination. Borrowing requires OWNED and leaves it unchanged.
Borrowing a moved source reports `cannot borrow moved owned value 'h'`; a joined
MAYBE_OWNED source reports that it may have been moved and cannot be borrowed.
A terminating moved arm does not affect the unmoved continuation. A borrow-only
loop preserves OWNED at its header and backedge; adding a borrow cannot hide an
invalid move backedge. A null-valued owner may be borrowed and subsequently moved.

## Release interaction

Move transfers responsibility; release ends it without a recipient. A move source
is MOVED and cannot release. Its definitely OWNED destination may release once.
A RELEASED owner cannot move, even though its physical pointer is null. A join of
moved and released paths is `{MOVED, RELEASED}`: definitely disarmed, still unusable
by source, and still eligible for compiler cleanup. Mixed joins containing OWNED
also reject source use. The possibility-set lattice preserves all MOVE-1 decisions
and its established may-have-been-moved diagnostics.
