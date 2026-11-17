# Text, failures and useful diagnostics

Our readings have all been valid. A real input source may supply a negative
value where our measuring policy allows only nonnegative readings. We need to
reject that value without confusing a recoverable input problem with a compiler
error or a fatal process failure. We also want a message whose bytes remain
alive long enough to report the result.

This chapter introduces validation first, then text ownership and formatting.
The small programs use the same five readings and explicitly select the library
sources and C providers they need. Keep the terminal from Getting started.

## Make an error part of the function contract

The complete [validation program](../../tests/books/guide-errors.astra) checks
the good total, then deliberately tries a negative reading:

```astra example=guide-errors
language astra27b;
int validated(int value) throws Error {
	if (value < 0) {
		throw new Error("negative reading");
	}
	return value;
}

int main() {
	int total = 0;
	try {
		int value = 2;
		while (value <= 10) {
			total += validated(value);
			value += 2;
		}
		if (total != 30) return 1;
		int rejected = validated(-1);
		return 2;
	} catch (Error error) {
		if (error.message != "negative reading" || total != 30) return 3;
		return 0;
	}
}
```

`throws Error` tells a caller that `validated` can fail with this error type.
The negative branch constructs an error and throws it; that call does not
produce an ordinary integer result. The `try` body continues only along normal
returns. Its `catch` checks both the message and the already completed total. Reaching
`return 2` would mean that the deliberately invalid value was incorrectly
accepted, so this is an executable check of the failure path too.

`Error` comes from [base/errors.astra](../../lib/astra/base/errors.astra), which
nominates the exception root. It is not an invisible built-in package. Its
hosted text support is another explicit input. Compile its installed C provider
sources and name the resulting objects:

```sh tutorial=hosted-providers
for ASTRA_PROVIDER in args-posix files-posix text-posix text-ops-posix diagnostics-trap; do
    cc -std=c11 -O2 -Wall -Wextra -Werror -c \
        "lib/runtime/platform/$ASTRA_PROVIDER.c" \
        -o "$ASTRA_BOOK_BUILD/$ASTRA_PROVIDER.o"
done
export ASTRA_PROVIDER_ARGS="$ASTRA_BOOK_BUILD/args-posix.o"
export ASTRA_PROVIDER_FILES="$ASTRA_BOOK_BUILD/files-posix.o"
export ASTRA_PROVIDER_TEXT="$ASTRA_BOOK_BUILD/text-posix.o"
export ASTRA_PROVIDER_TEXT_OPS="$ASTRA_BOOK_BUILD/text-ops-posix.o"
export ASTRA_PROVIDER_DIAGNOSTICS="$ASTRA_BOOK_BUILD/diagnostics-trap.o"
```

The five `ASTRA_PROVIDER_*` variables name the C objects just compiled in your
workspace. The provider sources supply arguments, files, text, text operations
and diagnostics.
Only the dependencies actually used by this program matter to its behavior.

```sh tutorial=validation
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/validation.o" \
    tests/books/guide-errors.astra lib/astra/base/errors.astra lib/astra/hosted/text.astra
cc -no-pie "$ASTRA_BOOK_BUILD/validation.o" \
    "$ASTRA_PROVIDER_ARGS" "$ASTRA_PROVIDER_FILES" "$ASTRA_PROVIDER_TEXT" \
    "$ASTRA_PROVIDER_TEXT_OPS" "$ASTRA_PROVIDER_DIAGNOSTICS" \
    -o "$ASTRA_BOOK_BUILD/validation"
"$ASTRA_BOOK_BUILD/validation"
printf '%s\n' 'Total 30 checked; negative reading caught (exit 0).'
```

Astra prints nothing here. The shell message means the valid computation and
the caught message both passed their checks. Zero is valid under this policy:
`value < 0` rejects negatives, not zero.

## Decide where recovery belongs

A caller must handle a throwing call or propagate it through a compatible
`throws` contract. The [unhandled version](../../tests/books/guide-unhandled.astra)
puts `validated(-1)` directly in a nonthrowing `main`. Compile it to see the
mistake, without expecting an executable:

```sh tutorial=unhandled-error
ASTRA_STATUS=0
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/rejected-unhandled.o" \
    tests/books/guide-unhandled.astra lib/astra/base/errors.astra \
    lib/astra/hosted/text.astra || ASTRA_STATUS=$?
test "$ASTRA_STATUS" -eq 1
test ! -e "$ASTRA_BOOK_BUILD/rejected-unhandled.o"
```

The diagnostic says `checked error is neither caught nor within the declared
throws bound`. At the program boundary, our working repair catches the error
and chooses an exit status. Inside a larger calculation, propagation can instead
let a caller with more context decide what to do.

Exercise: replace the reading six with -6, skip that one rejected reading, and
continue processing the others. Predict the count, total and number of errors.
Moving the `try` inside the loop makes recovery local to one reading. Here is
the [complete answer](../../tests/books/guide-errors-skip.astra):

```astra example=guide-errors-skip
language astra27b;
int validated(int value) throws Error {
	if (value < 0) {
		throw new Error("negative reading");
	}
	return value;
}

int main() {
	int total = 0;
	int count = 0;
	int rejected = 0;
	int value = 2;
	while (value <= 10) {
		int input = value == 6 ? -6 : value;
		try {
			total += validated(input);
			count += 1;
		} catch (Error error) {
			if (error.message != "negative reading") return 1;
			rejected += 1;
		}
		value += 2;
	}
	if (count != 4 || total != 24 || rejected != 1) return 2;
	return 0;
}
```

The answer accepts 2, 4, 8 and 10: count 4, total 24, one rejection. Advancing
`value` happens after either path, so a rejected value cannot stall the loop.
An unexpected message still fails the program; the handler does not silently
turn every possible problem into a skipped sample.

```sh tutorial=validation-answer
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/skip.o" \
    tests/books/guide-errors-skip.astra lib/astra/base/errors.astra lib/astra/hosted/text.astra
cc -no-pie "$ASTRA_BOOK_BUILD/skip.o" \
    "$ASTRA_PROVIDER_ARGS" "$ASTRA_PROVIDER_FILES" "$ASTRA_PROVIDER_TEXT" \
    "$ASTRA_PROVIDER_TEXT_OPS" "$ASTRA_PROVIDER_DIAGNOSTICS" -o "$ASTRA_BOOK_BUILD/skip"
"$ASTRA_BOOK_BUILD/skip"
printf '%s\n' 'Four accepted, total 24, one rejected (exit 0).'
```

## Keep message backing alive

A `catch (Error error)` binding borrows the caught owner for the handler's
lifetime. Its message can be inspected there; returning borrowed text after
that backing retires would be a different lifetime promise. Our handler compares
it with a literal and returns an integer, so no text borrow escapes.

Astra's `string` is counted, validated UTF-8. Its length describes bytes, not
characters as a reader sees them. A NUL byte may occur inside counted text; it
is not automatically an end marker. An owned `Utf8Message` keeps its text backing
alive. Borrowing `message.text` for an immediate call lets the receiver read
those bytes while the message remains owned by the caller.

Recoverable errors use admitted cleanup paths. A bounds trap, fatal allocation
action or other process termination does not promise the same unwinding. Do not
wrap a computation in `try` expecting every possible failure to become `Error`.
[Errors](../reference/errors.md) gives the exact boundary.

## Format into storage, or create owned text

We can now report the summary as real program output. This
[complete program](../../tests/books/guide-text.astra) makes two different
formatting choices and checks that their text agrees:

```astra example=guide-text
language astra27b;
[CCode(text_abi = "utf8-i32")]
extern(C) int show_text(borrowed string text);

int main() {
	try {
		int count = 5;
		int total = 2 + 4 + 6 + 8 + 10;
		var builder = new Utf8ByteBuilder();
		if (!builder.reserve(64)) return 1;
		if (!format_into(builder, $"readings: count={count} total={total}")) return 2;
		var snapshot = builder.snapshot();
		if (snapshot.text != "readings: count=5 total=30") return 3;
		var message = format_text($"readings: count={count} total={total}");
		if (message.text != snapshot.text) return 4;
		return show_text(message.text);
	} catch (Error error) {
		return 5;
	}
}
```

`$"...{count}..."` is a typed formatting plan for an immediate consumer, not an
owned string to store for later. `format_into` writes through a named builder
and reports success with a Boolean. Reserving capacity happens separately and
can allocate; formatting into adequately reserved capacity need not grow it.
Check the Boolean even when you have reserved space. A failed sink write does
not promise to roll back earlier bytes.

`snapshot()` copies the builder's current bytes into an owned message; that
materialization also allocates. It is not a freely escaping borrow of the builder.
`format_text` separately materializes an owned `Utf8Message` and has a recoverable
error contract. These are different costs and lifetimes, even though the
resulting bytes agree. The program borrows `message.text` only during `show_text`.
Neither owned message escapes `main`.

`show_text` is a small C sink supplied in
[guide-text.c](../../tests/books/guide-text.c): it writes the supplied byte count
with `fwrite` and appends a newline. It retains no pointer. Its declaration's
counted-text annotation is a real foreign contract, explained in [FFI](ffi.md),
not a built-in Astra printing function. Compile every selected library source
and that actual provider:

```sh tutorial=formatted-output
"$ASTRA_HOST" -c -O0 -o "$ASTRA_BOOK_BUILD/text.o" tests/books/guide-text.astra \
    lib/astra/base/errors.astra lib/astra/base/diagnostics.astra \
    lib/astra/text/utf8-message.astra lib/astra/text/utf8-byte-builder.astra \
    lib/astra/text/scalar-format.astra lib/astra/hosted/text-ops.astra \
    lib/astra/collections/bag.astra lib/astra/hosted/text.astra
cc -std=c11 -O0 -Wall -Wextra -Werror -c tests/books/guide-text.c \
    -o "$ASTRA_BOOK_BUILD/text-sink.o"
cc -no-pie "$ASTRA_BOOK_BUILD/text.o" "$ASTRA_BOOK_BUILD/text-sink.o" \
    "$ASTRA_PROVIDER_ARGS" "$ASTRA_PROVIDER_FILES" "$ASTRA_PROVIDER_TEXT" \
    "$ASTRA_PROVIDER_TEXT_OPS" "$ASTRA_PROVIDER_DIAGNOSTICS" -o "$ASTRA_BOOK_BUILD/text"
"$ASTRA_BOOK_BUILD/text"
```

Expected stdout is exactly `readings: count=5 total=30` and a newline; exit is 0
and stderr is empty. This time the message is program output through the C sink,
not the shell describing a silent test. The earlier
[formatting experiment](../../tests/books/formatting.astra) checks different
messages and deliberately returns 42; [errors.astra](../../tests/books/errors.astra)
likewise retains its original sentinel.

## Cleanup when a later argument fails

There is one subtle extension of the ownership lesson. A consuming call can
fail while evaluating its arguments, before the callee starts. In
[call-abort.astra](../../tests/books/call-abort.astra), two reading owners are
prepared for a call, then a later argument throws. The handler checks the error,
and the observer checks that both objects still retire exactly once. On the
successful call it sees count/sum 2/42; after the failing call it sees 4/84.
The complete source uses [lifecycle.c](../../tests/books/lifecycle.c) and the
same Error/text sources as our validation program. It is a further experiment,
not a second failure model: written argument order and cleanup still matter
before call entry.

A throw inside a handler belongs to an outer error contract; that handler does
not catch its own throw again. Keeping this scope distinction clear prevents
“recovery” from becoming an accidental loop of handlers.

We have made input rejection and reporting explicit. Next,
[Sequences](sequences.md) replaces our hand-written traversal choices with
storage, ranges and lazy plans while keeping ownership and costs visible.
