# Generic functions

[Caller information](caller-information.md) can annotate concrete trailing
string/int parameters of a generic definition. Inner calls retain definition
provenance after specialization. Explicit forwarding carries outer values;
neither captured metadata nor calling-file identity belongs in specialization keys.

GEN-1 supports top-level native functions with explicit type parameters:

```astra
T identity<T>(T value) {
	T copy = value;
	return copy;
}

T first<T, U>(T a, U b) {
	return a;
}

int main() {
	int answer = identity<int>(42);
	f64 fraction = identity<f64>(1.25);
	i16<8> vector = {1,2,3,4,5,6,7,8};
	i16<8> copy = identity<i16<8>>(vector);
	return answer;
}
```

The declaration grammar is `result-type name "<" identifier ("," identifier)*
">" "(" parameters? ")" where-clause* block`. A generic call is `name "<" type ("," type)*
">" "(" arguments? ")"`, or an ordinary call with the entire list omitted.
[GEN-INFER-1](generic-inference.md) infers a complete list from direct T/owned T
argument positions, including exact outer type-parameter identities where the
explicit form is legal. Explicit lists still require every argument. Too few/many
arguments reject, as does `ordinary<int>(42)` for an ordinary function. No defaults,
partial inference, overloads or function values exist.

The parser recognizes a generic call only when the complete type-list-plus-call
shape parses. Otherwise `<`/`>` remain relational operators. While consuming a
type close it can split `>>` into two `>` tokens, so `identity<i16<8>>(vector)`
works. Ordinary `x >> count` retains its shift token.

A declaration owns exact lexical type-parameter symbols. Two functions' `T`
parameters are different identities. T is visible throughout its declaration,
including its result type and nested generic-call type arguments, and is invisible
outside it. Duplicate names, reserved/builtin names, and shadowing an outer named
type reject deterministically in GEN-1. Generic and ordinary functions share one
name namespace without overloading. `main`, C boundaries, members, constructors,
properties cannot be generic. The separately bounded
[exact-Class bag declaration](generic-class-bags.md) admits one parameterized
Class and five direct operation patterns; it adds no member type parameters or
new free-function argument domain. Native [generic structs](generic-structs.md)
are supported separately by GEN-STRUCT-1.

## Plain-copy argument universe

| Category | Admitted exact types/shapes |
|---|---|
| Boolean | bool |
| Integers | i8, u8, i16, u16, int/i32, u32 |
| Floating | f32, f64 |
| Opaque pointer | void* |
| 8-bit vectors | i8/u8 with 2, 4, 8, 16 lanes |
| 16-bit vectors | i16/u16 with 2, 4, 8 lanes |
| 32-bit vectors | int/i32/u32 with 2, 4 lanes |
| Floating vectors | f32 with 2, 4 lanes |
| Boolean masks | bool with 2, 4, 8, 16 lanes |

These are the original 34 canonical types/shapes; `i32` spellings alias the
corresponding `int` identities. GEN-COPY-1 also admits legally formed concrete
copyable records, including generic-origin records, through the shared recursive
field proof. There are no f64 vectors. Void, text, typed pointers, arrays, slices,
classes and Resource/handle types remain excluded from PLAIN_COPY. Ownable has
the separate Resource/Class domain. See [copyable generic values](generic-copyable-values.md).

A T without an explicit Ownable requirement has the implicit compiler-owned
`GEN1_PLAIN_COPY` baseline capability. It may occur
directly as a parameter, result, local or explicit generic-call type argument.
It supports initialization, assignment, return/pass by value and branch/loop
flow. Direct borrowed or owned T[] parameters and owned T[] results additionally
supply the scoped [buffer element premises](generic-owned-arrays.md). Borrowed
algorithms use [temporary slice views](generic-slices.md); allocation also requires
the separately recorded zero and destruction facts. T cannot occur in `T*`, `T[4]`
or `T<4>`.
A plain T value cannot have `owned`/`borrowed` qualifiers in this mode. [Value capability requirements](generic-capabilities.md)
refine this baseline. GEN-OWN-1 adds the separate [OWNABLE transport mode](generic-ownership.md)
for explicit owned parameters/results; user-defined capabilities remain deferred.

```astra
T choose<T>(bool condition, T a, T b) {
	T result = a;
	if (condition) { result = b; }
	return result;
}

T outer<T>(T value) {
	return identity(value);
}
```

A generic definition is checked once, including unused definitions. Unconstrained T arithmetic,
equality, ordering, bitwise/unary operations, truthiness, casts, null
contextualization, members/properties, indexing, address-of and dereference
reject at definition checking. Calling an invalid `add<T>` exclusively with int
never grants it Numeric capability. Different type parameters remain different
types even if some calls substitute the same concrete type for both.

Concrete code inside a generic function keeps its ordinary rules. Borrowed
Counter parameters can access exact concrete properties/methods/fields; owned
Resource or object parameters/locals retain their normal transfer and cleanup
contracts independently of T. Generic calls work from free functions, methods,
constructors and property accessors. Direct and mutual generic recursion work,
as do calls with reordered type parameters and concrete arguments inside a
generic definition.

## Instances

Only requested concrete instances are generated. The canonical key is exact
definition identity plus ordered canonical semantic type identities: int/i32
calls deduplicate; i8/u8, i16/u16, int/u32 and signed/unsigned vectors remain
separate even when their LLVM representations match. `tag<i8>()` and
`tag<u8>()` also remain distinct when T is unused in the signature/body.
Deduplication covers all native callers in one compilation.

Specialization substitutes checked Core identities before CFG. Concrete branch
and loop values use existing Places and SSA block parameters; there is no phi<T>.
Instances use ordinary native channels and LLVM functions. Definitions have no
ABI or LLVM function, and an unused valid definition emits none. There is no
runtime type argument, descriptor, dictionary, boxing or dispatcher.

See [generic IR](../ir/generics.md), [ADR 0056](../decisions/0056-semantic-generic-functions.md)
and qualification.

## Generic native structs

A generic function may declare Pair<T,U>, Box<T> or Bundle<T> locals and transport their exact substituted leaf values. Its existing type parameters and GEN1_PLAIN_COPY authority are reused. Specialization requests concrete aggregate instances in the same Core context; int/i32 deduplicates both function and struct instances. Eligible concrete generic structs and exactly proved symbolic applications are also T arguments; whole Box<T> copies and its exact T-field transport specialize through existing concrete struct operations. See [generic structs](generic-structs.md).

## Generic ownership contracts

An explicit `where T : Ownable` permits `owned T` parameters/results and move,
while prohibiting plain T value positions and generic owned locals. A separate U
retains its ordinary plain-copy authority. Only Resource and transferable native
Class types satisfy Ownable; records belong to the separate plain-copy domain.
See [generic ownership](generic-ownership.md).

## Multi-source composition

A generic definition in one [source file](source-files.md) can be instantiated
from any supplied file. One program-global exact definition/type-argument key
materializes each concrete instance once, including recursive demand. Caller file
and path are absent from that key. Canonical source ordering only stabilizes
ordinals and request traversal; it does not grant visibility or capabilities.

Direct owned T[] parameters/results and explicit owned T[] locals are specified in [generic owned arrays](generic-owned-arrays.md). Array ownership does not make SliceType a plain-copy T value.
