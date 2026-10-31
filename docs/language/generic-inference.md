# Generic call inference

[Caller-information parameters](caller-information.md) use the same minimum/maximum
arity check before inference. Their concrete string/int types infer no T.
Completion preserves written-argument observations and staged ownership proofs.
Generic inner calls capture definition provenance before specialization; metadata
never enters instance identity. Forward explicit metadata to carry an outer site.

A [named constant](constants.md) is an ordinary exact typed argument for inference.
Its original literal spelling and ideal magnitude do not participate. Concrete
scalar constants may appear in generic bodies, but unresolved type-parameter values
and symbolic constant evaluation remain unsupported. Capability checking and
specialization keys are unchanged.

Omit a generic function's type arguments when ordinary arguments already identify
every type parameter exactly:

```astra
T identity<T>(T value) { return value; }

T clamp<T>(T value, T low, T high) where T : Ordered {
	if (value < low) { return low; }
	if (value > high) { return high; }
	return value;
}

int main() {
	var answer = identity(42);
	var precise = identity(1.0000000000000002d);
	f64 value = 5.0d;
	f64 low = 1.0d;
	f64 high = 4.0d;
	var result = clamp(value, low, high);
	if (answer == 42 && precise > 1.0d && result == high) { return 0; }
	return 1;
}
```

The readability change is `clamp<f64>(value, low, high)` →
`clamp(value, low, high)`. Explicit calls remain available with their existing
semantics. Supply either the entire ordered list or omit the entire list; there
are no placeholders, defaults or partially explicit arguments.

## Supported patterns

| Callee parameter | Observation | Result |
| --- | --- | --- |
| `T value` | ordinary exact value identity | infer T, then check GEN1_PLAIN_COPY and capabilities |
| `owned T value` with Ownable | exact named owner in `move value` | infer T, then validate the existing ownership contract |
| direct T/owned T inside a generic definition | exact outer type-parameter identity | propagate that identity if the equivalent explicit application is legal |
| concrete parameter unrelated to T | no T observation | retain ordinary argument checking |
| T only in result/constraints, or absent | none | require explicit type arguments |
| `T[]` | one exact SliceType<E> observation of E | signature-derived mutable element-storage obligation |
| `owned T[]` | exact E from a named moved SliceType<E> owner | infer E without committing the move; ordinary call checking validates transfer |
| `T*`, `Box<T>`, `Pair<T,U>` and other nested patterns | no structural inference | existing declaration/application restrictions remain |
| direct `borrowed T` with Ownable | deferred | no Resource/Class generic borrowing |

The plain-copy universe is defined by `GenericArgumentTypes`, documented in
[generic functions](generic-functions.md#plain-copy-argument-universe). It includes
the original 34 canonical scalar, vector and mask types plus eligible copyable
records. Whole vectors/masks and records infer one exact semantic type. `int` and `i32` share identity; signed/unsigned integers, f32/f64,
vector shapes and nominal types remain distinct. Typed pointers, text, slices, arrays, Resource and Class values remain outside
plain T. An exact known generic-struct application, including symbolic Box<U>,
can be the entire direct-T candidate when its scoped field proof succeeds. This
does not match/decompose constructed formal patterns. An exact unsupported candidate reports
the existing generic-argument rejection, not missing inference.

## Argument typing and agreement

No assignment destination, declared local type, return type, property type or
enclosing call parameter participates. Plain T expressions use their ordinary
standalone rules before inference. In particular:

| Argument | Inferred T |
| --- | --- |
| `42` | int |
| `1.25`, `1.25f`, `1.25F` | f32 |
| `1.25d`, `1.25D` | f64 |
| `1.0000000000000002d` | f64 with bits `0x3ff0000000000001` |
| `value as f64` | f64 |
| `true` | bool |
| targetless `null` | void* |

Repeated T positions must agree exactly. `same(1, 2.0d)` reports conflicting
inferred int and f64 observations, with argument numbers and source provenance.
There is no numeric promotion or common-type selection. Multiple type parameters
are collected independently in declaration order.

`int marker<T>(int x)` cannot infer T from `marker(1)`; the diagnostic requests an
explicit type argument. A `T make<T>()` call remains uninferable in `f64 x = make()`,
`return make()` from an f64 function/property, and `consume_f64(make())`. Constraints
also cannot infer a phantom T. Nested calls such as `identity(identity(42))` work
because each call determines its arguments locally.

`var x = identity(42)` first resolves the call to identity<int>, then infers the
local as int. There is no circular or bidirectional inference. Once a call's result
is known, ordinary expression rules may use that result as forward literal context:
`1.0 + identity(1.0d)` has the same f64 arithmetic as its explicit equivalent.
This does not feed an expected result type back into the call. The independent
local-inference restriction on unresolved T still applies: a generic body uses
`T local = identity(value)`, not `var local = identity(value)`.

## Outer generic parameters and capabilities

```astra
T outer<T>(T value) { return identity(value); }
T minimum<T>(T a, T b) where T : Ordered {
	if (a < b) { return a; }
	return b;
}
T ordered_outer<T>(T a, T b) where T : Ordered { return minimum(a, b); }
```

The inner argument is the exact outer T, independent of spelling. This is symbolic
identity propagation through the existing generic representation. It never solves
relationships between type parameters: distinct A and B conflict in a repeated
inner U position. Multiple inner parameters may independently receive A and B.

Eq, Ordered, Numeric, Bitwise and Shift validate inferred candidates through their
existing authority. Removing Ordered from `ordered_outer` produces a capability
failure at definition checking, even if all callers use f64. Capabilities never
imply one another or generate a missing type. Recursive calls may infer the same
exact outer identities without changing recursive specialization.

## Ownership stays visible

```astra
owned T relay<T>(owned T value) where T : Ownable { return move value; }
owned T forward<T>(owned T value) where T : Ownable { return relay(move value); }
```

`relay<Resource>(move resource)` becomes `relay(move resource)`. **Move remains
explicit.** The same rule holds for exact native Class identities and for outer
Ownable T. `relay(resource)` still requires explicit transferable responsibility.
Null supplies void*, never a guessed Resource/Class; void* does not satisfy Ownable.

Inference inspects a move source without consuming it. The ordinary validated call
commits the transfer. Failed observations, constraints and argument contracts do
not commit an enclosing ownership proof. Resource handles, Class ObjectStorage,
cleanup identity and exactly-once destruction follow the existing GEN-OWN rules.

Existing owned argument rules reject inline producers such as `relay(make())`,
both explicitly and inferred. Acquire an allowed direct Resource/Class producer
into a named owner, then pass `move owner`. Direct record results use their ordinary bounded producer/STRUCT-ABI route.
They are not ownership producers. Direct Resource/Class generic borrowing remains
deferred. [Owned T[]](generic-owned-arrays.md) uses its separate buffer contract,
with the same named-move requirement and inline consuming-argument exclusion.

## Sources and generated code

Helpers, outer generic definitions and concrete callers may live in different
supplied [source files](source-files.md). Explicit and inferred requests share one
global canonical key: exact definition plus ordered semantic arguments. Outer
arguments substitute before concrete requests; paths and CLI order do not enter
identity. Identical specializations deduplicate across all callers.

After semantic checking, inferred and explicit calls have the same Checked
representation. Parameterized Core may retain existing outer T tokens, but no
inference variable or equation. Concrete instances, Core, CFG, SSA, NABI, CABI and
LLVM are identical for equivalent calls. There is no runtime inference or generic
metadata. See [ADR 0070](../decisions/0070-generic-call-inference.md) and
validation.

## TEXT-1 boundary

A string argument supplies an exact inference candidate. It then receives the
existing unsupported-generic-domain diagnostic; direct text equality does not
admit StringType to Eq or GEN1_PLAIN_COPY. Existing generic bodies may use concrete
text literals/constants and native helpers through ordinary cloning and static
provenance. No type-dependent text or generic string collection is introduced.

GEN-SLICE-1 adds only the [direct borrowed slice layer](generic-slices.md). It does
not target-type participating literals or treat the whole collection as plain T.

For direct owned T[] formals, inference observes the exact element from a named owner without moving it. Ordinary call checking still requires and commits an explicit move. Owned results provide no result-context inference. See [generic owned arrays](generic-owned-arrays.md).
