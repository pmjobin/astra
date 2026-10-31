# Nested native struct fields

[Struct collection elements](struct-elements.md) compose recursive FieldPlaces over an indexed array/slice root. Nested fields preserve exact containing type and one captured collection/index; vector fields remain whole leaves.

[Native struct boundaries](struct-values.md) recursively snapshot nested fields
in the same declaration order as whole copy. Vector fields remain whole leaves.
Copyable concrete nested structs can be native parameters/results and exact
field-return sources, with no padding channels or mandatory aggregate storage.
The ordinary pointer/address and method receiver rules remain unchanged.

Native structs may embed another concrete native struct and contain any supported
vector shape. Classes retain their previous scalar field policy.

```astra
struct Inner {
	int x;
	f64 gain;
	i16<8> samples;
}
struct Outer {
	Inner inner;
	int tag;
}
int main() {
	i16<8> samples = {1, 2, 3, 4, 5, 6, 7, 8};
	Outer o = {inner = {x = 10, gain = 0.5, samples = samples}, tag = 7};
	o.inner.x = 42;
	o.inner.samples = insert(o.inner.samples, 2, 99);
	if (o.inner.x != 42 || o.inner.samples[2] != 99) { return 1; }
	return 0;
}
```

`o.inner` is a storage subobject Place. Reaching `o.inner.x` projects that Place;
it does not load a whole Inner value. Leaf reads/writes preserve exact scalar or
whole-vector semantics. Finite acyclic chains can have arbitrary depth.
`p->inner.x` works through an existing Outer* root and traps on null as usual.
Two valid aliases observe the same storage, including after optimization.

Nested braces target subobject storage directly, with no temporary struct or copy.
Every field must be initialized exactly once at every level. Unknown, duplicate
and missing fields reject; for example, omitting gain reports
`missing initializer for field 'inner.gain'`. Scalar/vector leaves use existing
exact type checking. Initializers evaluate recursively in written order; declaration
field order still defines field ordinals. The local becomes visible only after
its complete initializer. Defaults and partial initialization remain unsupported.

Vector fields contain a single vector value. `o.inner.samples[2]` loads the vector
and extracts a lane Value. `o.inner.samples[2] = 99` remains unsupported; assign
the whole result of `insert` instead. This does not add lane storage or addresses.

By-value layout recursion is illegal. Forward-collected declarations permit
semantic diagnostics such as `recursive by-value struct layout: A → B → A`.
The compiler decides legality before LLVM. Physical offsets and alignments are
backend details and are not part of nominal semantic identity.

Nesting alone does not allocate memory. Eligible leaves promote independently;
borrowing the address of one local makes that whole root memory-backed, while
other locals of the same type remain eligible for scalarization. Nested memory
access uses ordinary concrete GEP/load/store operations. No heap or runtime
metadata is needed.

Struct methods and property accessors can use `this.inner.x`. Method/property
invocation on the nested receiver itself and subobject address-of remain deferred.
General whole-struct Values, general struct
literal expressions, aggregate C ABI, ownership fields,
and embedded class aggregates remain unsupported. Typed pointer field policy is
unchanged: typed pointers are rejected as fields; void* remains accepted.
GEN-STRUCT-1 [generic structs](generic-structs.md) materialize into ordinary concrete structs and reuse this storage machinery.

See [ADR 0058](../decisions/0058-recursive-struct-fields.md) and
[recursive FieldPlaces](../ir/recursive-field-places.md).

## Copying subobjects

`Inner x = outer.inner;`, `outer.inner = x;` and `outer.left = outer.right;` are
[exact whole-copy contexts](struct-copy.md). Recursive FieldPlaces retain their
exact owners through arbitrary depth. Snapshot order follows declaration order;
every source leaf is read before any destination write. Vectors remain whole
leaves and scalarized roots remain eligible for promotion. No LanePlace,
aggregate Value or aggregate ABI follows from these storage operations.
