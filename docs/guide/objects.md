# Objects, owners and observers

Use a class when a value has object identity and a lifetime that a caller must
manage. A factory can create a reading, let a borrowing function inspect it,
then transfer it to one consumer:

```astra example=owners
language astra27b;
class Reading {
	readonly int value;

	init(int value) {
		this.value = value;
	}

	property int reading => this.value;
}

owned Reading make_reading(int value) {
	var reading = new Reading(value);
	return move reading;
}

int inspect(Reading reading) {
	return reading.reading*2;
}

int consume(owned Reading reading) {
	return inspect(reading);
}

int main() {
	var reading = make_reading(21);
	return consume(move reading);
}
```

The acquiring factory local owns the construction. Returning `move reading`
forwards responsibility to the caller; it does not duplicate the object.
`inspect` borrows its parameter and reads a checked field-projection property.
`consume` receives an explicit owner and retires it when its scope exits.
`main` therefore cannot use `reading` after the consuming call.

Think of the lifetime as a sequence of responsibilities:

```text
factory local -> returned owner -> caller local -> consuming parameter -> cleanup
                       inspection borrows; it creates no additional owner
```

The diagram describes source responsibilities, not a promise about pointer
relocation or refcount implementation. The [Reference's double-move negative](../reference/ownership.md)
demonstrates what happens when source tries to transfer the same owner twice.
Its current SSA-level diagnostic is a known usability limit, not a reason to
disable verification.

## Sharing when ownership really is shared

Sometimes several parts of an application need to keep one reading alive.
Acquire a shared handle explicitly rather than copying a unique owner:

```astra example=shared
language astra27b;
class Reading {
	readonly int value;

	init(int value) {
		this.value = value;
	}
}

int main() {
	var unique = new Reading(42);
	var retained = shared_acquire(move unique);
	var copy = shared_clone(retained);
	var observer = shared_downgrade(copy);
	var upgraded = weak_upgrade(observer);
	if (upgraded == null) return 1;
	return shared_read(upgraded);
}

int shared_read(shared Reading value) {
	return read(shared_borrow(value));
}

int read(Reading value) {
	return value.value;
}
```

`shared_clone` creates another strong owner. Downgrading creates a weak observer,
and upgrade may return null when the payload has expired. This example retains
live strong handles, so its upgrade succeeds. The independent weak regression
also tests expiry; a successful upgrade alone cannot establish that behavior.

`shared_borrow` is consumed immediately by a borrowing helper. It does not
manufacture an independently retained local descriptor. The ordinary modern
shared parameter borrows; an explicit consuming parameter would have a different
contract. Stored borrows, owning fields and `[Shared]` class policies require
their own checked relationships. See [Sharing](../reference/shared.md).

Keep unique ownership when one component is responsible for the lifetime. Use
sharing to express a real lifetime requirement, and remember that a weak observer
does not keep a payload alive. No general cross-thread safety promise follows
from either example. Strict memory verification covers returning executions;
traps and fatal termination have different cleanup guarantees.
