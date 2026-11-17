# Objects, owners and observers

A copied `Sample` was enough to calculate a weighted value. Now suppose a reading
represents a live measurement: some part of the program must eventually finish
with it, even if processing returns early. Copying two integers does not express
that responsibility. A class gives the reading an identity and a lifetime; an
owner takes responsibility for ending that lifetime.

We will process the same five values, total thirty, and also check that each
reading is retired exactly once. This is a reason to use an object, rather than
just a new spelling for the record. For a calculation with no identity or cleanup
requirement, the record from the previous chapter remains the simpler choice.

## Acquire, inspect, then hand over

Read the functions before the loop in this complete
[program](../../tests/books/guide-owners.astra). Predict which function owns the
reading after `consume(move reading)` starts.

```astra example=guide-owners
language astra27b;
extern(C) void note_drop(int value);

extern(C) int drop_count();

extern(C) int drop_sum();

class Reading {
	readonly int value;

	init(int value) {
		this.value = value;
	}

	deinit() {
		note_drop(this.value);
	}
}

Reading acquire(int value) {
	var reading = new Reading(value);
	return move reading;
}

int inspect(Reading reading) {
	return reading.value;
}

int consume(owned Reading reading) {
	return inspect(reading);
}

int main() {
	int total = 0;
	int value = 2;
	while (value <= 10) {
		var reading = acquire(value);
		if (inspect(reading) != value) return 1;
		total += consume(move reading);
		value += 2;
	}
	if (total != 30 || drop_count() != 5 || drop_sum() != 30) return 2;
	return 0;
}
```

`new Reading(value)` constructs an object. `init` initializes its readonly field;
`this` names the object being initialized. Later, `deinit` calls a small C observer
that counts destructions. That observer helps us see cleanup; it is not what
performs or authorizes cleanup.

`acquire` returns a class owner. In this modern profile, a native class result is
owning by default. Its local acquires the construction, and `return move reading`
transfers that responsibility to the caller. There is still one object. A move
neither clones it nor promises to relocate its bytes.

Compare the two parameter declarations. `inspect(Reading reading)` borrows:
it can read the object during the call, while the caller keeps responsibility.
`consume(owned Reading reading)` receives responsibility. Its caller must supply
a transfer, here `move reading`. When `consume` returns its copied integer, its
parameter's object is cleaned up. The caller can use that integer, but cannot
use the moved local as another live owner.

| Point in one iteration | Who owns this reading? | What can the caller still do? |
| --- | --- | --- |
| After `acquire(value)` | The local `reading` in `main` | Borrow it or transfer it |
| During `inspect(reading)` | The same local | Keep it alive until inspection returns |
| Inside `consume` | The consuming parameter | Use the returned integer after the call |
| After `consume` returns | No live owner of this object | Continue with the next reading |

Each loop iteration creates a new local acquisition. The current compiler does
not generally admit assigning a new object into a previously moved local slot;
use a fresh lexical owner, as this loop does. The precise contextual defaults
and that boundary are in [Ownership](../reference/ownership.md).

## Independent lifecycle observer

Keep the terminal from [Getting started](getting-started.md). The declarations
at the top of the program have real implementations in
[lifecycle.c](../../tests/books/lifecycle.c). Its counters start at zero in each
process. `note_drop` increments a count and adds the retired value; `drop_count`
and `drop_sum` return those observations. Compile that provider and link it with
the Astra object:

```sh tutorial=owners
cc -std=c11 -O0 -Wall -Wextra -Werror -c tests/books/lifecycle.c \
    -o "$ASTRA_BOOK_BUILD/lifecycle.o"
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/owners.o" tests/books/guide-owners.astra
cc -no-pie "$ASTRA_BOOK_BUILD/owners.o" "$ASTRA_BOOK_BUILD/lifecycle.o" \
    -o "$ASTRA_BOOK_BUILD/owners"
"$ASTRA_BOOK_BUILD/owners"
printf '%s\n' 'Five owners retired once; total 30 (exit 0).'
```

The last sentence comes from the shell. Astra prints nothing and returns 0 only
if both the calculation and the destructor observations agree. Five calls to
`inspect` alone would not retire five readings: a borrow creates no additional
cleanup responsibility. The C boundary is explained fully in [FFI](ffi.md).

## A move is not a copy

The complete [double-move mistake](../../tests/books/negative-owner.astra)
constructs one reading and passes `move reading` to a consumer twice. Try its
expected compilation failure:

```sh tutorial=owner-error
ASTRA_STATUS=0
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/rejected-owner.o" \
    tests/books/negative-owner.astra || ASTRA_STATUS=$?
test "$ASTRA_STATUS" -eq 1
test ! -e "$ASTRA_BOOK_BUILD/rejected-owner.o"
```

The observed diagnostic includes `SSA verification failed`. That wording is a
current usability limitation; the mistake is the second transfer of an already
moved owner. Removing a verifier is not a repair. If two functions only need to
inspect the object, make both borrow before one final transfer. Our working
program demonstrates the essential repair: inspect first, consume once.

Ordinary scope exit, an early return, and an admitted recoverable error have
checked cleanup paths. A fatal trap or allocation failure does not promise the
same unwinding. We will use that distinction in the next chapter.

## Owning fields and anchored borrows

Exercise: instead of consuming each reading immediately, put it in a `Holder`
that owns it. Let a separate readonly field provide a view for inspection. Keep
the total and the destruction count unchanged. Where must that view point?

Here is the [complete answer](../../tests/books/guide-holder.astra):

```astra example=guide-holder
language astra27b;
extern(C) void note_drop(int value);

extern(C) int drop_count();

extern(C) int drop_sum();

class Reading {
	readonly int value;

	init(int value) {
		this.value = value;
	}

	deinit() {
		note_drop(this.value);
	}
}

class Holder {
	readonly Reading root;
	readonly borrowed Reading view;

	init(owned Reading incoming) {
		this.root = move incoming;
		this.view = this.root;
	}
}

int inspect(Reading reading) {
	return reading.value;
}

int summarize() {
	int total = 0;
	int value = 2;
	while (value <= 10) {
		var reading = new Reading(value);
		var holder = new Holder(move reading);
		total += inspect(holder.view);
		value += 2;
	}
	return total;
}

int main() {
	if (summarize() != 30 || drop_count() != 5 || drop_sum() != 30) return 1;
	return 0;
}
```

`root` is an owning field in this modern native class. The constructor first
moves the incoming owner into `root`, then initializes `view` from that same
root. `view` borrows; it does not cause a second destruction. When the holder
leaves the loop body, cleanup retires its root. Returning the scalar total lets
`main` check the counters after all five holders have gone away.

```text
holder owns root ──> Reading
holder.view ───────> the same Reading, without another ownership responsibility
```

A readonly field alone does not keep an arbitrary caller's object alive. The
[stored-borrow mistake](../../tests/books/negative-stored-borrow.astra) removes
the owning sibling and stores only an incoming borrowed parameter. It is refused
with `Flow rejected`; the answer above supplies the missing lifetime anchor.
Build and run the answer with the observer already compiled:

```sh tutorial=holder-answer
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/holder.o" tests/books/guide-holder.astra
cc -no-pie "$ASTRA_BOOK_BUILD/holder.o" "$ASTRA_BOOK_BUILD/lifecycle.o" \
    -o "$ASTRA_BOOK_BUILD/holder"
"$ASTRA_BOOK_BUILD/holder"
printf '%s\n' 'Owning fields: five readings, one retirement each (exit 0).'
```

The earlier [ownership-defaults experiment](../../tests/books/ownership-defaults.astra)
checks one holder with value 42. The [original factory experiment](../../tests/books/owners.astra)
checks an explicit `owned` factory result. Both retain their documented exit-42
convention; neither changes the meaning of success in our new examples.

## Sharing when two parts must keep an object alive

An owner and a borrower can both refer to one object without both owning it.
Sometimes, however, two components really must keep the object alive independently.
Use explicit shared handles for that requirement. The complete
[sharing experiment](../../tests/books/shared.astra) shows the operations:
`shared_acquire(move unique)` transfers a unique owner into a shared handle;
`shared_clone` creates another strong owner; `shared_borrow` supplies immediate
borrowed access. Cloning a handle is different from copying the payload.

Ordinary shared parameters borrow in the modern profile. The experiment passes
`shared_borrow(value)` straight to a borrowing helper rather than storing an
unsupported local alias. Neither a shared handle nor a readonly field grants a
general thread-safety guarantee. Use [Sharing](../reference/shared.md) for the
specific admitted contracts.

## Observing expiry

A weak observer answers “is it still alive?” without keeping the payload alive.
`shared_downgrade` creates that observer. `weak_upgrade` can obtain a strong owner
while the payload lives, or return null after the last strong owner retires.
The weak handle itself still requires cleanup.

Predict the difference between the live sharing experiment and
[weak-expiry.astra](../../tests/books/weak-expiry.astra): the latter returns an
observer from a function, leaving its last strong owner behind to retire. Its
upgrade must be null and its destructor counters must already be 1 and 42.
Run both complete experiments, capturing their intentional sentinel statuses:

```sh tutorial=shared-observers
for ASTRA_LESSON in shared weak-expiry; do
    "$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/$ASTRA_LESSON.o" \
        "tests/books/$ASTRA_LESSON.astra"
    cc -no-pie "$ASTRA_BOOK_BUILD/$ASTRA_LESSON.o" "$ASTRA_BOOK_BUILD/lifecycle.o" \
        -o "$ASTRA_BOOK_BUILD/$ASTRA_LESSON"
    ASTRA_STATUS=0
    "$ASTRA_BOOK_BUILD/$ASTRA_LESSON" || ASTRA_STATUS=$?
    test "$ASTRA_STATUS" -eq 42
    printf '%s: exit %s\n' "$ASTRA_LESSON" "$ASTRA_STATUS"
done
```

You can now distinguish copying a scalar record, borrowing an object, transferring
an owner, and explicitly sharing responsibility. Next, [Text and errors](text-errors.md)
uses those lifetime questions when a reading is invalid and a message needs backing.
