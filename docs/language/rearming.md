# Concrete owner replacement and rearm

BUFFER-1 generalizes ordinary assignment for mutable concrete Resource and buffer
locals and owned parameters. Their exact static cleanup authority permits:

```astra
owned R value = make_resource();
value = make_other_resource();
value = move replacement;

owned f64[] samples = new f64[count];
samples = new f64[len(samples) + 1];
```

Evaluate the incoming producer completely, capture its payload, commit any named
source transfer, clean old live destination contents exactly once, then install
the new owner. Buffer base/length are one complete group. A production trap
leaves the old destination untouched. Self-move rejects. Locals and parameters
use the same rule; ClassType/ObjectStorage replacement is not generalized.

| Destination state after RHS production | Assignment behavior |
| --- | --- |
| OWNED | Clean old contents, install incoming owner, remain OWNED |
| MOVED / RELEASED / their union | Rearm to OWNED without old cleanup |
| Mixed state including OWNED | Guarded cleanup of live contents, then OWNED |

The shared OWNED/MOVED/RELEASED lattice and stable cleanup rank are retained.
Explicit `release value;` remains intentional early destruction and subsequent
rearm is valid. `value = relay(move value);` may transfer through a producer and
rearm its now-disarmed source. No duplicate owner or runtime active flag appears.
Generic ownership ambiguity remains rejected.

See [owned buffers](owned-runtime-arrays.md), [owned functions](owned-functions.md)
and [ADR 0065](../decisions/0065-owned-runtime-arrays.md). The following legacy
producer-specific `owned void*` contract keeps its original disarm-first policy;
it is not the concrete Resource or buffer rule.

## Legacy producer-specific owned void* rearm

An existing producer-specific owned void* local can acquire another resource after release or move:

```astra
owned void* h = create_resource(1);
release h;
h = create_resource(2);
```

The ordinary assignment syntax `identifier "=" expression ";"` performs a rearm
when its destination is a producer-specific owned void* local. The RHS must
be a direct foreign owned-result call with the
**same exact type and cleanup contract** as the slot. Parentheses
may group that direct call. Different producers may share one contract. Raw
pointers, literal null, another owner, arbitrary expressions and `move other`
are invalid RHS forms. There is no new keyword or implicit release.

## Definitely disarmed

Rearm requires `definitely_disarmed(state)`: OWNED must be absent from every
reachable possibility. The destination itself is not read by this assignment.

| State before assignment | Result |
| --- | --- |
| RELEASED | OWNED |
| MOVED | OWNED |
| MOVED, RELEASED | OWNED |
| OWNED | Error: still owns a resource; release or move it before reassignment |
| OWNED, RELEASED | Error: may still own a resource on another control-flow path |
| OWNED, MOVED | Same may-still-own error |
| OWNED, MOVED, RELEASED | Same may-still-own error |

```astra
owned void* h = create_resource(1);
if (condition) {
	release h;
} else {
	owned void* x = move h;
}
h = create_resource(2); // {MOVED, RELEASED} is definitely disarmed
```

Removing the else discharge makes this illegal: the false path still owns the
first resource. A completed borrow also leaves OWNED, so borrowing alone cannot
permit rearming. Terminating arms contribute no predecessor to the continuation.

Rearming a moved-from source does not affect its destination:

```astra
owned void* a = create_resource(1);
owned void* b = move a;
a = create_resource(2); // b still owns 1; a now owns 2
```

Every successful producer return establishes OWNED even if it returns null.
Null comparisons, borrowed calls, move and release then follow ordinary OWNED
rules. Nullness never authorizes assignment. `h = null;` cannot acquire a cleanup
responsibility. Producer arguments execute before the call and before rearming;
an argument cannot read a still-disarmed h. Conversely, `r = pass(move r);` may
move a live Resource into an owned parameter before the returned responsibility
rearms r: rearm validates state after producer argument evaluation and invocation. Traps and nonreturning foreign code
retain existing non-unwinding behavior.

## Stable cleanup slots

The binding has one lexical cleanup slot, one exact cleanup contract and one
fixed rank throughout its lifetime. Rearming changes the resource in that slot.
It registers no additional cleanup and never changes the slot's order.

```astra
owned void* a = create_resource(1);
owned void* b = create_resource(2);
release a;               // destroys 1 immediately
a = create_resource(3);
// lexical exit visits b, then a: destroys 2, then 3
```

The overall destroy order is **123**, including when the earlier slot is rearmed
conditionally. Before REARM-1, reverse acquisition order and reverse lexical
owner-slot order were equivalent; automatic cleanup is now explicitly defined
by the latter. Every earlier program keeps its cleanup order. Explicit release
still executes at its source position.

## Branches and repeated cycles

After disarming h, rearming only one branch yields `{OWNED, RELEASED}` (or
`{OWNED, MOVED}`): source use rejects, while lexical cleanup safely destroys the
resource only on the owning path. Both branches rearming with the same contract
produce definitely OWNED. An ordinary pointer phi merges producer/null or two
producer results; no runtime ownership flag is needed.

```astra
owned void* h = create_resource(0);
release h;
while (condition) {
	h = create_resource(1);
	release h;
}
```

This converges with RELEASED on the preheader and backedge. Moving h into a fresh
body owner instead is also valid: that owner cleans each iteration and h reaches
the backedge MOVED. Continue obeys the same rule. A path back to the next rearm
without discharge produces a may-still-own error at the loop fixpoint. Repeated
straight-line cycles likewise require discharge before each rearm.

See [ownership](ownership.md), [moves](moves.md), [release](release.md),
[borrowed parameters](borrowed-parameters.md), and [ADR 0032](../decisions/0032-owner-rearming.md).
