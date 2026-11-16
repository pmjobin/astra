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
