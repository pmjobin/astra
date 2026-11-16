# Records and small calculations

A sensor sample needs a value and a weight that travel together. A record gives
the pair one nominal type while retaining value-copy behavior. Start with the
concrete arithmetic, then use a small generic function to preserve a result:

```astra example=records
language astra27b;
struct Sample {
	int value;
	int weight;
}

T identity<T>(T value) {
	return value;
}

int weighted(Sample sample) {
	return sample.value*sample.weight;
}

int main() {
	int weight = 2;
	var sample = Sample {value = 21, weight};
	Sample copy = sample;
	copy.value = 10;
	return identity<int>(value: weighted(sample));
}
```

The `Sample` declaration names two int fields. Its modern record expression
supplies `value` explicitly and takes `weight` from the same-named local.
All required fields must be present once with compatible types. Naming two
unrelated records with identical fields would not make them interchangeable.

`copy` receives an independent record value. Changing its `value` to 10 must
leave `sample.value` at 21. The program computes with the original and returns
42, so an accidental shared-storage implementation would fail the expectation.
This is a useful distinction when choosing a record for measurements and a
class for an object whose identity or lifetime matters.

## A first generic function

`identity<T>` has one type parameter and returns the same copied value it
receives. The explicit `<int>` selects the concrete instance; `value:` names
the formal argument. Generic functions are checked specializations, not a way
to bypass exact numeric or ownership rules. A function that copies ordinary
values cannot acquire the right to copy an owner merely by spelling its type `T`.
[Generics and matching](generics-match.md) develops this distinction.

Use this pattern for a small scalar numerical calculation before introducing
vectors or a larger library. The current native vector boundary differs from
the older bootstrap numerical contract. The [feature matrix](../reference/limits.md)
shows a directly tested refusal; no SIMD performance or C++ comparison is claimed
here. You can still represent a numerical workload with exact scalar values and
checked arrays, as the readings application does.

For precise field/copy rules see [Records](../reference/values.md), and for
declaration identity see [Names](../reference/declarations.md). The generated
[compiler API](../api/compiler.html) illustrates resolved nominal declarations;
it is a useful reference for compiler development, not a substitute for this
language-level value contract.
