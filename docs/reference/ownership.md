# Ownership and cleanup

R-OWNERS. Ownership means one checked responsibility to retire storage, not
merely possession of an address. Acquiring locals, consuming parameters,
owning fields and owning results are distinct channels. Ordinary native class
parameters borrow; an `owned` parameter consumes. A factory returning an owner
must forward responsibility through an admitted result, typically by returning
`move local`. The Guide's [object program](../guide/objects.md) demonstrates this
whole chain with an explicit factory and consumer.

Moving a value invalidates its previous owner's use according to the checked
state. It does not clone an object or necessarily relocate bytes. The physical
transfer must disarm the source cleanup at the correct boundary. Two syntactic
paths that might reach a moved owner do not regain liveness merely because a
pointer happens to be null. Modern conditional/expression-match results require
consistent selected-arm responsibility rather than eager movement of both arms.

R-ABORT-CLEANUP. Consuming argument capture and actual call commitment are
separate. Written-order evaluation can fail after reserving owners or creating
fresh temporaries. Cleanup on this path must preserve exact ownership and retire
temporaries once. Normal scope exit, early returns and recoverable errors share
the checked cleanup plan. Existing regressions observe destructor count, sum and
order, including nested fresh-owner and buffer aborts.

R-MOVED-REFUSAL. This whole program attempts two transfers of one owner:

```astra example=negative-owner
language astra27b;
class Reading {
	init() {}
}
void consume(owned Reading reading) {}
int main() {
	var reading = new Reading();
	consume(move reading);
	consume(move reading);
	return 42;
}
```

The current diagnostic reaches the independent SSA verifier. That refusal is
safety evidence but exposes a diagnostic-quality limitation: it is less helpful
than a source-level “already moved” explanation. No pass is inferred merely
because a compiler process exits nonzero; tests require the expected diagnostic,
an untouched output sentinel and strict returning memory behavior.

## Borrowing, arrays and failure

Borrowing supplies access without creating cleanup responsibility. A stored
borrow must remain rooted in an owner that outlives every use; an ordinary
parameter borrow cannot become an escaping result by changing a spelling.
Owning arrays retain element/partial-initialization cleanup obligations. An
owned field/result is established by checked metadata, not inferred from a
generic `T` or a C pointer.

Recoverable errors run their admitted unwind cleanups. A fatal allocation action
or runtime trap does not promise unwinding or destructor execution. In particular,
no strict “all resources retired on fatal termination” claim follows from
returning-path Valgrind. C0's separate historical process-memory limitation is
preserved in [Limits](limits.md); it is not a waiver of current owner checks.

## Effective ownership channels

R-DEFAULT-CHANNELS. In modern source, spelling and effective responsibility
must be considered together. The declaration elaborator applies these defaults
only to the admitted concrete native types. It does not strengthen a foreign
pointer, interface, arbitrary symbolic type or unproved producer.

| Position | Effective modern contract | Required evidence |
| --- | --- | --- |
| Native class field | Owning unless explicitly borrowed | Constructor initializes its actual field slot |
| Native class result | Owning | A real owning result or proved absence, with source-local acquisition |
| Ordinary native class parameter | Borrowing | Owner survives every use; no transfer at entry |
| Ordinary shared or weak parameter | Borrowing | Modern effective channel; legacy shared defaults differ |
| Acquiring local | Owning when initialized by a checked owning producer | Construction, owning call, move, selected conditional or match arm |
| Scalar/copied record | Copied | Exact copyable shape; no concealed owner leaves |
| Owning enum | Intrinsic ownership derived from its variants | Explicit owned/borrowed sum declarations are refused |
| Readonly borrowed class field | Borrowed relationship | A proved readonly owning sibling initialized first |

These are source contracts, not a claim that every combination lowers natively.
In particular, an alias expression with a class TypeId cannot invent local
acquisition. Generic record channels have explicit specialization exceptions;
see [Generics](generics.md). The authoritative selectors are
[checked_default_owner_type and checked_declared](../../compiler/semantic/elaborate.astra),
with separate [local/result source consumers](../../compiler/semantic/recover-class-locals.astra).
The Guide's [observed defaults program](../guide/objects.md#owning-fields-and-anchored-borrows)
checks implicit field/result/local ownership and a borrowed parameter together.

## Move reservations and reinitialization boundary

R-REARM-BOUNDARY. A source slot can be dead, live, or reserved for a particular
consuming operation. Reservation and commitment are different events. A later
throwing argument can prevent the call from entering. The actual CFG must then
preserve or retire the appropriate responsibilities; a pointer-shaped value or
one convenient branch does not prove a slot live on all paths. SSA checks these
states against the actual graph, independently of the lowering plan.

The following attempted local rearm is currently refused with `Flow rejected`.
It is intentionally a negative whole program, including its observer declarations.
This edition therefore gives no general native promise that assigning a fresh
construction to this moved local is accepted. Earlier rearm implementations and
source state models retain their own historical scope.

```astra example=negative-rearm
language astra27b;
extern(C) void note_drop(int value);
extern(C) int drop_count();
extern(C) int drop_sum();
class Reading {
	int value;
	init(int value) { this.value = value; }
	deinit() { note_drop(this.value); }
}

int consume(owned Reading reading) { return reading.value; }

int work() {
	var reading = new Reading(20);
	int first = consume(move reading);
	reading = new Reading(22);
	return first + consume(move reading);
}

int main() {
	int result = work();
	if (drop_count() != 2 || drop_sum() != 42) return 1;
	return result;
}
```

A usable program can instead give each acquisition its own lexical owner. Do
not remove `move`, copy the old owner or weaken Flow to make the negative pass.
The [negative double move](#ownership-and-cleanup) and this refusal test different
facts: an invalid second transfer versus the current admission boundary for
reinitialization. The unchanged compiler source remains the authority.
