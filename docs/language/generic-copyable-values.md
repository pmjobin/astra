# Copyable record values in semantic generics

Ordinary generic transport admits ordinary copyable records by default:

```astra
T identity<T>(T value) { return value; }
T choose_value<T>(bool take_first, T first, T second) {
	T selected = second;
	if (take_first) { selected = first; }
	return selected;
}
struct Box<T> { T value; }
T through_box<T>(T input) {
	Box<T> first = { value = input };
	Box<T> second = first;
	T saved = second.value;
	second.value = input;
	return identity(saved);
}
```

These helpers are ordinary source functions. No attribute, copy keyword or
`where T : Copy` is needed. `Copy` and `Move` are not public capabilities.

| Type or proof | Plain-copy T | Further restrictions |
| --- | --- | --- |
| bool; i8/u8/i16/u16/int/i32/u32; f32/f64; void* | Yes | int/i32 share one identity; void* remains unmanaged |
| i8/u8 with 2/4/8/16 lanes | Yes | Whole vector values |
| i16/u16 with 2/4/8 lanes | Yes | Whole vector values |
| int/i32/u32/f32 with 2/4 lanes | Yes | Whole vector values |
| bool with 2/4/8/16 lanes | Yes | Whole mask values |
| Legally formed concrete native record | Yes | Nonempty, complete acyclic recursive copyable fields |
| Concrete generic-origin record | Yes | Same rule, including Box<Kernel>, Box<Box<Kernel>> and Pair<Kernel,OtherRecord> |
| Exact outer plain-copy parameter | In that definition | The exact lexical token supplies the premise |
| Known application such as Box<T> | In that definition | Exact fields must prove copyable from scoped premises |
| Resource/Class or Ownable parameter | No | Separate explicit ownership-transfer domain |
| string, string[], scalar/record arrays, slices and buffers | No | Concrete companions and record elements remain usable |
| Tracked typed pointers; unresolved ownership storage | No | No borrowing is erased by copying |
| Empty, missing, incomplete or cyclic record graph | No | An empty leaf walk is not a legal value |

The first five rows preserve all 34 canonical primitive/vector/mask identities.
Generic origin neither admits nor excludes a record. Eligibility uses fields,
not size, layout or collection zeroability. Concrete record collections separately
satisfy STRUCT-ELEM storage, zero and destruction requirements.

At a concrete site, `var saved = identity(kernels[index]);` creates an independent
snapshot. Later mutation, replacement, disposal or transfer of the source owner
cannot change it. `kernels[destination] = identity(saved);` captures and validates
the destination first, keeps it live through the RHS, and writes only after every
source leaf is captured. Self-copy and overlapping sources are legal. Traps do not
unwind or roll back unrelated earlier effects.

A specialized record parameter uses the ordinary COPY_VALUE boundary: independent
read-only binding and recursive storage. `T local = value` creates mutable local
storage; reassignment, branches, loops and returns work. Scalar/vector parameter
rules are unchanged. A T and a U are distinct inside a definition even when a call
later supplies the same type. Required initialization remains mandatory. There is
no no-input constructor, default(T), zero(T) or implicit generic borrowing.

Known fields such as `Box<T>.value` keep their exact substituted types. Whole
Box<T> copies and its T-field reads/writes specialize to ordinary leaf transport.
Unknown `T.member` access is still invalid. Use explicit T/Box<T> locals in generic
bodies where `var` would have to infer an unresolved type.

A named struct-valued field entry now accepts existing bounded producers:

```astra
Holder holder = { payload = existing_payload };
Box<Kernel> boxed = { value = identity(kernel) };
var copied_box = identity(boxed);
```

Each entry runs once in written order. It snapshots all source leaves before any
copy-generated writes for that field and before later entries run. Native and
generic result producers obey the same rule; complete nested braces still work.
Braces are storage initializers, not aggregate expressions. Missing, duplicate or
wrongly typed fields reject; the local is not visible in its own initializer.

Direct-T inference observes the exact type of a value, Place, indexed element or
bounded call result without evaluating it twice. Explicit and inferred calls use
the same admission and instance registry. Inside outer<U>, `identity(box)` with a
Box<U> local chooses the entire Box<U> as the callee T, exactly like
`identity<Box<U>>(box)`. It does not infer U or inspect a layout. Different
Box<T>/Box<U>, definitions and phantom arguments conflict exactly. Type positions
still require all type arguments; constructed formal patterns, return-context
inference, conversions, partial arguments and phantom guessing remain excluded.

Copyability gives no equality, ordering, numeric/bitwise/shift operations, casts,
address-taking, indexing or arbitrary construction. Eq/Ordered/Numeric/Bitwise/
Shift remain explicit, independent contracts; records derive none. BASELIB
min/max/clamp therefore reject records through their normal capability checks.
Owned T remains GEN-OWN with explicit named moves. Concrete text/array companions
and trailing caller information remain ordinary parameters and never widen T.
Record copying adds no allocation, cleanup, refcount, dictionary or type header.

The executable four-file [consumer](../../examples/generic-copyable-values/main.astra)
uses explicit-source helpers, nested Box storage, BUFFER, ARGS, output and DIAG.
Its selected libraries/providers and tested commands are recorded in
validation.

Limits and deferred features are listed in [ADR 0078](../decisions/0078-generic-copyable-values.md).

GEN-SLICE-1 admits [generic borrowed slice algorithms](generic-slices.md): direct
function T[] formals derive exact mutable element-storage premises. Collections
remain borrowed while plain T parameters/results retain independent value copying.
No concrete element domain or ownership/lifetime rule is enlarged.
