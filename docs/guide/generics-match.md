# Generic functions and matching

The record chapter used `identity<int>` to preserve an exact copied value.
Generics are most useful when several concrete types need the same small,
explicitly constrained operation. Start with the working concrete function,
identify the required capabilities, and verify real instantiations rather than
assuming a parsed template supports every type.

Named arguments help explain a call when several parameters share a type. They
use declared labels, not local variable names guessed by the compiler. Written
argument order remains evaluation order, even when labels select a different
formal order. The [Reference](../reference/expressions.md) gives an unknown-label
negative and describes consuming-call abort behavior.

## Represent alternatives explicitly

A reading can hold a value or a structured problem. Two enums express these
alternatives without nullable sentinel integers:

```astra example=matching
language astra27b;
enum Problem {
	Missing,
	Invalid(int code)
}

enum Reading {
	Value(int value),
	Failure(Problem problem)
}

int decode(Reading reading) => match (reading) {
	case Reading.Value(value) => value;
	case Reading.Failure(Problem.Missing()) => 0;
	case Reading.Failure(Problem.Invalid(code)) => code;
};

int main() {
	return decode(Reading.Failure(Problem.Invalid(42)));
}
```

`Reading.Failure` holds a `Problem`, which can itself be `Missing` or `Invalid`.
The expression match covers every variant product. The selected `code` belongs
to that arm and becomes the result. For the constructed invalid reading its
value is 42. The other branches provide meaningful alternative results rather
than an implicit undefined default.

Parentheses are required even for a zero-payload pattern. Each expression arm
ends in a semicolon. Leaving out the missing case fails exhaustiveness, as the
[negative match](../reference/values.md) demonstrates. An overlapping nested case
is also invalid. Exact checked variant identity selects payloads; a name from
another enum cannot be substituted merely because it has the same field names.

This program has copied scalar payloads. Owning enum payloads require a separate
decision between inspection and consumption. A match does not grant an escaping
payload borrow or permission to move an owner twice. The independent regressions
cover those cases, while [Ownership](../reference/ownership.md) describes the
cleanup boundary. Generic source instances remain capped at 256, with the
existing SSA work ceiling unchanged. No general pattern-reflection framework,
runtime polymorphic iterator or user-defined operator system is introduced by
these examples.

## Constraints at concrete calls

A Numeric constraint states exactly what addition needs. Begin with the concrete
operation, then use one parameter consistently in the declaration, body and
calls. Instantiate small and ordinary integers separately:

```astra example=generic-contract
language astra27b;
T add<T>(T first, T last) where T: Numeric {
	return first + last;
}

int main() {
	u8 left = 20;
	u8 right = 22;
	u8 expected = 42;
	if (add<u8>(last: right, first: left) != expected) return 1;
	return add<int>(20, 22);
}
```

The u8 expected local gives the comparison an explicit domain. It avoids relying
on a generic result to contextualize a literal through every enclosing operation.
The int call returns 42. Calling this same function with bool is rejected by
its [capability constraint](../reference/generics.md#concrete-capability-rules),
not silently treated as integer addition.

Constraints are a finite set of admitted operations, not a reflection mechanism
or permission to substitute arbitrary classes into a native body. An instance
still passes ordinary ownership and native verification. Keep actual substitutions
small and explain their costs: each distinct declaration/argument specialization
uses compiler work, while repeated use of the same checked instance can reuse
its identity. The implementation ceiling remains 256. Owning channels and
copied record specialization require the [separate Reference rules](../reference/generics.md#concrete-capability-rules).
