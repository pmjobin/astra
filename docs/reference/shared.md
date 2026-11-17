# Sharing, observers and stored borrows

R-SHARED. `Shared<T>` provides explicit shared ownership of an admitted native
class payload. `shared_acquire(move unique)` consumes a unique owner into a
shared owner. `shared_clone` creates another owning shared handle;
`shared_borrow` provides a nonowning payload access. A clone and a borrow are
different operations even when both ultimately refer to the same object.
Plain copying must not duplicate cleanup responsibility.

R-WEAK. `shared_downgrade` creates an owning weak observer handle, and
`weak_clone` duplicates that observer responsibility. A weak observer does not
keep the payload alive. `weak_upgrade` obtains an owning strong handle only if
the payload still exists; callers must handle its nullable result. Releasing
the last strong owner retires the payload even when weak handles remain.
Weak-handle storage itself still has cleanup obligations.

The Guide's [sharing program](../guide/objects.md) checks a successful upgrade
while live strong handles remain. The original weak regression additionally
checks the expired case and destructor effects. A live-only demonstration cannot
prove expired behavior. Neither case provides a general thread-safety promise
or qualifies arbitrary atomic shared use across threads.

`[Shared]` intrinsic class policies and boxed `Shared<T>` remain separate
declaration-derived contracts. Modern ordinary shared parameters borrow;
explicit consuming parameters and returns must retain their effective owning
flags. The API renderer exposes these flags rather than pretending that every
surface `shared` spelling means the same transfer operation.

## Stored relationships

R-STORED-BORROW. A checked owning field can anchor a readonly stored borrowed
field. Both the initialization relation and later lifetime uses require proof.
An independently stored local alias is not automatically admitted: the current
sharing example passes `shared_borrow(value)` immediately to a borrowing function
instead of retaining an arbitrary descriptor in a local. This distinguishes
payload access from establishing a new owner slot.

Do not return a borrow whose owner is a local that will retire, replace an owner
while a retained dependent borrow remains live, or treat weak upgrade as a raw
pointer cast. Nullness and ownership are separate properties. A nonnull check
does not restore moved state, and an owning handle alone does not prove that
every possible payload projection is a permitted receiver root. The source-owned
regression consumers and physical mutation controls verify these boundaries
independently of layout caches or LLVM's structural verifier.

## Anchors, expiry and distinct observer storage

R-BORROW-ANCHOR. The admitted stored relationship has two distinct fields: a
readonly owning class field and a readonly borrowed class field that is proved
to refer to it. Initialize the owner first. The borrower does not perform a
second destruction, and passing it to an ordinary borrowing function does not
transfer the anchor. A constructor's external borrowed parameter, by itself,
supplies no sufficiently long-lived sibling owner. This negative is refused in
Flow rather than receiving a fabricated successful lifetime proof:

```astra example=negative-stored-borrow
language astra27b;
class Reading { int value; init(int value) { this.value = value; } }
class Holder {
	readonly borrowed Reading view;
	init(Reading incoming) { this.view = incoming; }
}

int main() {
	var reading = new Reading(42);
	var holder = new Holder(reading);
	return holder.view.value;
}
```

The [independent source consumer](../../compiler/semantic/class-storage-flow.astra)
reconstructs field initialization, while
[SSA's shared consumer](../../compiler/ssa/recover-shared.astra) follows the actual
root version from payload definition to its use. Replacing a root, moving it,
and using a nullable upgraded handle require their separate checked obligations.
A readonly spelling alone is insufficient.

The Guide now tests [expiry after the last strong owner retires](../guide/objects.md#observing-expiry).
The weak control storage outlives the payload while observers remain. This is
why observing one successful upgrade is not an expiry test, and why a weak
handle still needs cleanup even though it cannot keep the payload alive.
