# Records, classes and enums

R-RECORDS. A record is a nominal value with named fields. Eligible copied records
transport their field values independently; changing a copy does not mutate its
source. Record construction must supply every required field exactly once with
the checked field type. Modern record expressions name the type and permit
field shorthand when a same-named value supplies that field. A matching spelling
does not permit a field from a different nominal declaration.

The [Guide's record example](../guide/records.md) copies a `Sample`, changes the
copy, then computes from the original. It tests actual value independence rather
than assuming it from an aggregate's physical size. Owning-record transport is
a separate, constrained contract; general copied records cannot conceal owner
leaves or manufacture an ownership channel through a plain generic parameter.

R-CLASSES. Native classes have object identity and constructor initialization.
An owning local acquires construction responsibility. Parameters ordinarily
borrow it, while an `owned` parameter consumes responsibility. A method's
receiver does not implicitly transfer an owner. Constructor fields are checked
against their declared storage and initialization contracts. Cleanup belongs
to the retained storage identity, not a guessed C pointer type.

Properties are checked accessors with their own bodies and lifetime rules.
The executable object chapter uses a field projection getter and an explicit
owned factory. Arbitrary expression getters, setters, inheritance and dynamic
dispatch must not be inferred from that one example. The current source has
separate property/function admission and verification; unsupported getter
shapes can fail Core after parsing successfully.

R-ENUMS. An enum declaration defines named variants with positional typed payloads.
Construction selects the exact checked variant; `Variant()` parentheses are
required for zero-payload patterns. Payload storage/alignment follows checked
all-variant contracts, rather than an assumed tag-plus-union layout exposed to
C. Expression matches combine compatible result channels and require exhaustive,
nonoverlapping cases, including nested products.

```astra example=negative-match
language astra27b;
enum Reading {
	Value(int value),
	Missing
}
int main() {
	return match (Reading.Value(42)) {
		case Reading.Value(value) => value;
	};
}
```

This negative is missing one variant. Adding a wildcard-looking expression or
using a variant from a different enum does not repair the contract. Inspection
borrows payloads; consumption moves the selected ownership under independent
cleanup checks. Payload bindings cannot escape their arm or be moved twice.
The broader match tests cover consuming/nested/error paths independently of
the Guide's scalar example. No arbitrary C enum ABI or reflection registry is
specified by a source enum declaration.
