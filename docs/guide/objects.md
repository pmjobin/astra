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

## Owning fields and anchored borrows

A holder can own a reading while keeping a readonly view of that same reading.
This is useful when one field expresses responsibility and another expresses
how an object is accessed. Read the constructor in order: it transfers the
incoming owner into root, then initializes view from that root. It does not
keep the constructor caller's temporary borrow.

```astra example=ownership-defaults
language astra27b;
extern(C) void note_drop(int value);

extern(C) int drop_count();

extern(C) int drop_sum();

class Reading {
	readonly int value;

	init(int value) { this.value = value; }

	deinit() { note_drop(this.value); }
}

class Holder {
	readonly Reading root;
	readonly borrowed Reading view;

	init(owned Reading incoming) {
		this.root = move incoming;
		this.view = this.root;
	}
}

Reading make(int value) {
	var result = new Reading(value);
	return move result;
}

int inspect(Reading reading) { return reading.value; }

int work() {
	Reading reading = make(42);
	var holder = new Holder(move reading);
	return inspect(holder.view);
}

int main() {
	int result = work();
	if (drop_count() != 1 || drop_sum() != 42) return 1;
	return result;
}
```

`make` demonstrates the modern default owning result. The declared local acquires
it, and `Holder.root` owns it without an explicit owned field qualifier. In
contrast, `inspect` borrows. Returning from work destroys the holder and its one
reading. The independent observer must report one retirement with value 42.
The [Reference table](../reference/ownership.md#effective-ownership-channels)
spells out which defaults are contextual; it is not safe to extrapolate them
to every foreign or generic type.

```text
work's holder owner
    root: owns Reading(42) ---- cleanup retires Reading once
    view: borrows root ------- inspection creates no new owner
```

Removing root and retaining only the constructor parameter's borrow fails the
[stored-borrow control](../reference/shared.md#anchors-expiry-and-distinct-observer-storage).
Reusing a moved local also has a [current native refusal](../reference/ownership.md#move-reservations-and-reinitialization-boundary).
Give each acquisition a clear lexical owner rather than treating a null/moved
slot as automatically reusable.

## Observing expiry

A weak observer is useful precisely when the observed object may disappear.
This function returns an observer while letting its last strong owner retire:

```astra example=weak-expiry
language astra27b;
extern(C) void note_drop(int value);

extern(C) int drop_count();

extern(C) int drop_sum();

class Reading {
	int value;

	init(int value) { this.value = value; }

	deinit() { note_drop(this.value); }
}

Weak<Reading> observe() {
	var reading = new Reading(42);
	var strong = shared_acquire(move reading);
	var observer = shared_downgrade(strong);
	return move observer;
}

int main() {
	var observer = observe();
	var expired = weak_upgrade(observer);
	if (expired != null || drop_count() != 1 || drop_sum() != 42) return 1;
	return 42;
}
```

The upgrade in main must be null, but the observer itself is still a managed
handle. The destructor counters show that the payload retired before the
upgrade. Successful live upgrade, expired upgrade, and cleanup of the weak
handle are three separate facts. Avoid making a cross-thread guarantee from
this synchronous example.

## Independent lifecycle observer

Compile this small provider with the examples that declare its functions. It
records retirement counts/sums and a decimal call trace. It allocates no storage
and makes no claim about the compiler's internal owner state; the examples
compare its observations with independently specified expected values.

```c example=lifecycle
#include <stdint.h>

static int retired;
static int total;
static int trace;

void note_drop(int value) {
	++retired;
	total += value;
}

int drop_count(void) {
	return retired;
}

int drop_sum(void) {
	return total;
}

int tick(int value) {
	trace = trace * 10 + value;
	return value;
}

int tick_trace(void) {
	return trace;
}
```

From the checkout, select the authenticated compiler and a fresh external output
directory as in the first-program recipe. This complete command sequence includes
both source inputs; change both optimization switches to O2 for the other target:

```sh
mkdir -p "$ASTRA_BOOK_BUILD/owner-observer"
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/owner-observer/app.o" tests/books/ownership-defaults.astra
cc -std=c11 -O0 -c tests/books/lifecycle.c -o "$ASTRA_BOOK_BUILD/owner-observer/observer.o"
cc -no-pie "$ASTRA_BOOK_BUILD/owner-observer/app.o" "$ASTRA_BOOK_BUILD/owner-observer/observer.o" -o "$ASTRA_BOOK_BUILD/owner-observer/app"
"$ASTRA_BOOK_BUILD/owner-observer/app"
```

The final command returns status 42 and prints nothing. Its nonzero sentinel is
intentional; run it separately from a shell that exits on any nonzero status.
The automated book runner performs host and target O0/O2, LLVM verification,
exit 42 with empty stdout, and strict returning compiler/program memory checks.
