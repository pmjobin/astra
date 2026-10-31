# Explicit early release

OWNBOUND-1 permits `release r;` for an owned Resource parameter. It uses the
ordinary release event and type cleanup, then clears the parameter's scalar
current value. The stable root cleanup slot remains and later no-ops unless
rearmed. See [owned functions](owned-functions.md).

RESOURCE-1 extends release to `owned Resource` locals, using Resource's exact
type-level cleanup contract. OWNED(null) becomes RELEASED(null) without a destroy
call. Borrow-then-release remains valid; later source reads reject until rearm.
The existing null guard and lexical cleanup behavior below are unchanged.
See [resource handles](resource-handles.md).

`release h;` ends an owned local's responsibility immediately:

```astra
int scoped() {
	owned void* h = create_resource(1);
	inspect(h); // borrowed void* parameter; call completes before release
	release h;
	return 0;
}
```

The exact grammar is:

```text
release-statement := "release" identifier ";"
```

The identifier must resolve to an exact owned void* or owned Handle local, or an
owned Resource parameter, with its existing cleanup contract. Raw void* locals,
Struct* locals, int/bool/struct locals, unmanaged/borrowed parameters, functions
and unknown names reject.
It has no value or success bool. `release(h)`, `release create_resource(1);`,
`release h == null;`, assignments, return expressions and call arguments
containing release all reject. Acquire the producer result into an owner first.

## Responsibility and null

Release requires definitely OWNED, invokes the exact owner's destroy function
if its current pointer is non-null, and changes state to RELEASED. It then
physically clears the pointer to null. Its later lexical cleanup stays present
and safely skips the destroy call.

An acquired null is still OWNED: comparison with null and release are both valid.
After release, even `h == null` rejects. Semantic responsibility never comes from
pointer bits. RELEASED differs from MOVED: release ends responsibility while move
hands it to another owner. Both disarm source use, and both physically clear the
old pointer, but their definite diagnostics remain distinct.

```astra
release h;
release h;                  // owned value 'h' has already been released
if (h == null) {}           // use of released owned value 'h'
inspect(h);                 // cannot borrow released owned value 'h'
owned void* next = move h;  // use of released owned value 'h'
```

Borrowing repeatedly before release is legal; every completed borrow leaves
OWNED unchanged. A borrowed parameter itself owns nothing and cannot be released.
A move destination can be released once; releasing the moved source reports
`cannot release moved owned value 'h'`. Release keeps the lexical slot disarmed;
[rearming](rearming.md) may fill it with another direct owned result carrying the
same exact cleanup contract. No replacement owner or cleanup slot is created.

## Branches and loops

Ownership flow tracks sets of reachable outcomes:

| Paths reaching a join | State | Source owner use |
| --- | --- | --- |
| All still own | `{OWNED}` | Valid |
| One owns, one releases | `{OWNED, RELEASED}` | Invalid |
| Both release | `{RELEASED}` | Invalid |
| One moves, one releases | `{MOVED, RELEASED}` | Invalid |
| Own, move and release paths | `{OWNED, MOVED, RELEASED}` | Invalid |

All these states permit compiler cleanup. A mixed state containing OWNED reports
that the owner may no longer own its resource on another control-flow path.
`{OWNED, MOVED}` retains the established may-have-been-moved wording.

```astra
owned void* h = create_resource(1);
if (condition) {
	release h;
	return 1;
}
inspect(h); // valid: only the OWNED path reaches this call
```

A loop with an outer owner and `release h;` on a backedge rejects: a subsequent
iteration could release again. `continue` also contributes RELEASED to the
header. Release followed by `break` is valid inside the body, but joins OWNED
(zero iterations) with RELEASED (break) at the loop exit. Later source use there
rejects. A returning released arm contributes to neither continuation nor backedge.
Fresh body owners can acquire and release each iteration, including after a move:

```astra
while (condition) {
	owned void* a = create_resource(1);
	owned void* b = move a;
	release b;
}
```

The existing deterministic CFG fixpoint establishes these facts. Unreachable
post-return source is preserved through CFG but does not affect reachable state
or execution. Constant conditions keep the existing syntactic CFG branch policy;
release adds no constant folding.

## Destruction order

Release runs at its statement position. `record(1); release h; record(2);`
observes record 1, destruction, record 2. If a return follows release, its
expression runs after that explicit destruction and before the null lexical
cleanup. Traps still do not unwind.

For owners declared a, b, c, explicitly releasing b destroys b immediately.
Automatic cleanup later visits c, b, a and physically destroys only c then a.
This intentional lifetime shortening can change the order from automatic LIFO.
Release uses the existing cleanup ABI and null guard; it adds no runtime
ownership flag, retain operation, refcount, heap allocator or boundary transfer.

See [ownership](ownership.md), [moves](moves.md),
[borrowed parameters](borrowed-parameters.md) and [release IR](../ir/ownership-release.md).
