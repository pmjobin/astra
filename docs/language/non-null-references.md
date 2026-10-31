# Explicit nonnull references

Existing Class and Resource references remain nullable. Opt into a static promise
with `nonnull` on an initialized local, native parameter or owned result:

```astra
owned nonnull Value create() {
	var result = new Value(7);
	return move result;
}
int inspect(nonnull Value input) { return input.number; }
int optional(Value input) {
	if (input == null) { return 0; }
	nonnull Value ready = input;
	return inspect(ready);
}
```

Ownership goes first: `owned nonnull Value`, or `borrowed nonnull Resource` for
an established call-scoped view. The promise requires a construction, promised
native result, qualified input or current null check. A nullable value cannot
implicitly enter a qualified destination. Both paths of a join must establish
the promise. `&&` and `||` refine their reached right operands. Loops include
backedges and continue steps. Assigning null, using an old Boolean check after
assignment, or relying on an unqualified mutable field fails the proof.

Owned native Class fields can opt in. Their constructors and replacements must
supply a proven owner. A get-only borrowed property may expose that guarantee
without changing the existing receiver lifetime:

```astra
class Holder {
	owned nonnull Value child;
	init(owned nonnull Value child) { this.child = move child; }
	property borrowed nonnull Value item { get { return this.child; } }
}
```

Borrowed property values retain the existing temporary-use restrictions. They
cannot become independent owners or escape their receiver. A promise does not
permit use after move, release or destruction. Checked failure carries its own
exception channel and does not produce a successful nonnull result.

The qualified profile includes closed general-body container applications,
borrowed interfaces and exact native `Fn` values. For example,
`int count(nonnull Vector<Point> values)` checks the same exact container type
and ownership as its unqualified counterpart. A promised native code result can
return a known function address. Native Fn null-admission rules stay unchanged;
integers and data pointers cannot manufacture code values.

A pure borrowed projection can be checked at the point of use:

```astra
if (repository.item != null) {
	return count(repository.item);
}
```

The proof identifies that exact receiver and getter. Ordinary calls, writes,
ownership effects, cleanup scopes and suspension discard nullable projection
facts; check again afterward. A separately declared nonnull owned field retains
its invariant because constructors and replacement must prove it. Temporary
borrow restrictions still apply.

Existing owning frame retention now composes with nonnull across cooperative
`delay_ticks` boundaries. A moved or retired owner remains unavailable. Nullable
property guards must be repeated after suspension; no new stored loan or async
generic parameter contract is implied. General task/effect shapes still require
their own qualification.

Raw pointers, Shared/Weak, closures, open generic references and virtual/override
strengthening remain excluded. Lazy nonnull declarations and borrowed setters
are also excluded. An unknown C result needs an explicit null check; C
import/export signatures cannot promise nonnull. Unsupported effect shapes
receive a diagnostic instead of inferred guarantees. See
[ADR 0150](../decisions/0150-composed-nonnull-and-property-refinement.md).

The compiled examples are [Class and receiver borrow](../../tests/language-usability-7/nonnull-control.astra),
[Resource with checked failure](../../tests/language-usability-7/nonnull-resource.astra)
and [A51 boundary processor](../../examples/language-usability-7/nullable-boundary-processor.astra).
[ADR 0127](../decisions/0127-explicit-native-nonnull-contracts.md) describes the
independent source/Core/CFG/SSA proofs. Native and C ABI stay unchanged, and no
new runtime trap substitutes for a compile-time proof.
