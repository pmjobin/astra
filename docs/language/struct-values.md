# Native struct parameters and results

Eligible [struct elements](struct-elements.md) are bounded native argument and result producers. Passing or returning an element completes its leaf snapshot. COPY_VALUE parameter storage remains recursively read-only; mutable slice elements do not change that rule or aggregate-v7 value transport.

Concrete, recursively copyable structs can be passed and returned by value in
native Astra functions and ordinary struct/class methods. Class constructors
accept the same explicit parameters. A boundary preserves one exact nominal
struct value with copy semantics.

```astra
struct Vec2 { f64 x; f64 y; }

Vec2 add(Vec2 a, Vec2 b) {
	Vec2 result = { x = a.x + b.x, y = a.y + b.y };
	return result;
}

Vec2 twice(Vec2 value) { return add(value, value); }

int main() {
	Vec2 a = { x = 1.5, y = 2.5 };
	Vec2 b = twice(a);
	b = add(a, b);
	return 0;
}
```

A parameter owns an independent local value. The caller's source remains usable
and unchanged by this contract. Parameter bindings and all their struct fields
are read-only. Copy a parameter into a mutable local before changing fields:

```astra
Vec2 shifted(Vec2 value) {
	Vec2 local = value;
	local.x = local.x + 1.0;
	return local;
}
```

Direct parameter field writes, rebinding, mutable address-taking, and using that
parameter as a mutable method/property receiver reject. Ordinary method receiver
semantics remain unchanged; the receiver itself is not passed by struct value.
A void* field copies its pointer identity, not the object it points to.

## Eligibility and exact identity

The existing CopyabilityAuthority decides recursively. Eligible leaves are bool,
exact integers, f32, f64, void*, and every accepted numeric or mask VectorType.
Nested concrete structs recurse; vectors are single whole-value leaves. Physical
size, layout, alignment and padding cannot establish compatibility. Resource,
ClassType, array, slice, typed-pointer and ownership-bearing struct fields remain
outside the accepted field/copyability policy. Empty structs remain unsupported.

`A { int x; }` and `B { int x; }` are distinct even when both physically carry I32.
The mismatch diagnostic states `struct boundary requires exact nominal type 'B',
found 'A'; equal layout is insufficient`. A one-field wrapper is likewise distinct
from its leaf type. There are no implicit struct conversions.

Concrete generic-origin types follow the identical rule: Box<int>, Box<f64>,
Box<i16<8>>, Box<bool<4>>, and Bundle<f64> qualify when their fields do.
Box<int>/Box<i32> share canonical identity; Box<i8>/Box<u8> do not. Generic function
signatures containing parameterized Box<T> remain deferred. A generic body may
call an ordinary concrete struct helper. GEN-COPY-1 admits eligible concrete
records as T arguments and reuses these exact boundaries after specialization,
without adding public Copy/Move capabilities.

## Producers, consumers and evaluation

An exact initialized local, parameter, field/subobject, indexed element, or permitted dereference
can supply a by-value argument or return. Returning a field copies its entire
subtree; returning `*ptr` uses existing pointer validity and null rules. No result
retains the source's storage identity or lifetime. Source syntax does not need an
output pointer or explicit result temporary.

A struct-returning call has these bounded storage/value contexts:

| Consumer | Example |
| --- | --- |
| Local initialization | `Pair p = make();` |
| Fixed-array entry initialization | `Pair[1] records = {make()};` |
| Assignment to existing exact storage | `p = make();` |
| Exact struct argument | `consume(make());` |
| Exact result forwarding | `return make();` |

Arguments evaluate left-to-right. A Place-sourced struct argument is completely
snapshotted at its own argument position, before evaluation of the next argument.
For `observe(pair, mutate(&pair))`, `observe` receives the old value of `pair`.
A struct call result already provides captured leaves. Return evaluation snapshots
every source leaf before cleanup and before source lifetime ends. Result assignment
validates its destination before the producer and writes its leaves after the call.

These contexts do not introduce a universal struct expression Value. Struct
comparisons, arithmetic, conditional aggregate expressions, arbitrary aggregate
literals, temporary field receivers, and struct-valued properties remain excluded.
PROP-1's property value matrix remains explicit, although accessor bodies can use
ordinary concrete struct helpers.

## Transport

Native aggregate-v7 carries fields in recursive declaration order, with no padding
channels. Field values preserve their own exact semantics: f32/F32, f64/F64,
void*/PTR, integers/bool, and whole vector channels. No conversion or rounding is
introduced by flattening. Padding bytes have no transport preservation guarantee.

Scalarized parameters and results need no allocation. Native struct transport
uses no hidden input pointer, default hidden result pointer, sret, byval,
memcpy/memmove, heap, or runtime descriptor. LLVM may use a backend-only aggregate
return carrier; this is not an Astra aggregate SSA value. CABI, export(C), extern(C)
and VAPI aggregate boundaries remain excluded. See [ADR 0062](../decisions/0062-native-struct-values.md),
[IR](../ir/struct-values.md), and [aggregate-v7](../abi/native-aggregates-v7.md).
