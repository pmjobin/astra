# Native instance methods

Methods and constructors share the native [parameter defaults](parameter-borrowing.md):
plain Resource/Class/Slice parameters borrow, explicit `borrowed` is equivalent,
and `owned` transfers. This does not change receiver or property contracts.
Static methods remain deferred.

Methods support [copyable concrete struct parameters/results](struct-values.md),
including concrete generic-origin structs. Explicit by-value parameters are
independent read-only local values. Method receivers retain existing mutable
storage identity and PTR transport; they are not flattened value parameters.
Class constructor parameters share this support. Destructors retain void results.
Property value types remain nonaggregate, even though accessor bodies can call
struct-boundary helpers. A signature containing a struct value selects aggregate-v7.

Methods may call [top-level generic functions](generic-functions.md) with full
explicit type arguments. Generic bodies may invoke existing concrete methods;
Core specialization preserves the exact resolved MethodSymbol/CoreMethod target
and receiver contract. Generic methods themselves remain deferred.

[Computed property accessors](properties.md) share native callable implementation
with methods while retaining independent getter/setter identities. They use the
same receiver formation, null validation and per-instance struct addressability.
Methods may read/write properties; accessors may call methods or other
properties, including later declarations. All accesses remain effectful.

Methods may have explicit [owned ClassType parameters](object-ownership.md),
independently of the non-owning implicit receiver. Class and struct methods share
normal owned parameter cleanup, nullability and forwarding. An owned receiver
binding may call methods temporarily. Consuming the same owner during its method
call, directly or within an argument expression, rejects. Temporary receiver and
field bases remain valid until their actual call/load/store; RHS or nested calls
cannot consume them first. There is no receiver ownership or new dispatch model.

An explicit `borrowed Counter other` parameter is nullable, mutable and aliasable
in both class and struct methods. It shares the free-function noescape contract,
local-copy/forwarding behavior and exact ClassType matching. A caller may supply
the same object as receiver and `other`; there is no exclusivity. Implicit `this`
remains nonnull and restricted to field/method access, so `this == other` stays
deferred. Parameter rebinding remains unsupported, while field mutation is valid.
See [borrowed object parameters](borrowed-object-parameters.md).

Class [constructors/destructors](object-lifecycle.md) reuse callable body,
parameter and direct-call machinery but have distinct lifecycle identities.
`init`/`deinit` are reserved against ordinary class field/method declarations.
Constructor `this` has INITIALIZING mode: field writes initialize exactly once,
reads require definite initialization and `this.method()` rejects throughout the
constructor. Destructor `this` is LIVE, so ordinary field mutation and method
calls work. Lifecycle members cannot be ordinary member-call targets or values.
Structs acquire no lifecycle semantics and retain existing ordinary method names.

OBJ-1 extends the same method architecture to [classes](objects.md). A nullable
class-reference receiver validates nonnull before explicit arguments evaluate,
including owned captures; then it satisfies the same exact ReceiverType as `this`.
`this.method()` requires no guard. Class fields are always explicit memory and
reference aliases observe method mutations. Plain and explicit `borrowed ClassType`
parameters reuse ordinary native noescape rules; `owned ClassType` parameters
use consuming transfer. Unqualified/borrowed object results remain rejected.
Supported scalar/vector/DSP, borrowed-slice and owned Resource signatures are
unchanged. The struct example and selective-storage rules below
retain METHOD-1 behavior.

A native struct or class may declare methods which read or mutate that instance's fields:

```astra
struct Counter {
	int value;

	void add(int amount) {
		this.value = this.value + amount;
	}

	int get() {
		return this.value;
	}
}

int main() {
	Counter counter = { value = 40 };
	counter.add(2);
	return counter.get();
}
```

This returns 42. The methods access the same storage as `counter.value`.

## Grammar and member names

```text
struct-declaration := "struct" identifier "{" struct-member* "}"
struct-member := field-declaration | method-declaration | property-declaration
class-declaration := "class" identifier "{" class-member* "}"
class-member := field-declaration | method-declaration | property-declaration
field-declaration := type-name identifier ";"
method-declaration := "owned"? result-type identifier "(" parameters? ")" block
parameters := parameter ("," parameter)*
parameter := ("borrowed" | "owned")? type-name identifier
method-call := receiver "." identifier "(" arguments? ")"
receiver := identifier | "this"
arguments := expression ("," expression)*
```

Parameter/result qualifiers have exactly their ordinary native restrictions;
for example `owned` results require a supported nominal Resource. Method calls
also admit the ordinary direct `move resource` argument form. Structs remain
top-level declarations without a closing semicolon. The parser accepts mixed
members in source order; semantic checking still requires at least one supported
field. Brace initialization must initialize every field exactly once and does
not mention methods. No `function` keyword is introduced. Class constructors
use the separate lifecycle grammar.

Fields, methods and properties share one namespace per declaring struct or class. A field `foo` and method
`foo`, or two methods `foo`, reject even when signatures differ. `A.reset`,
`B.reset` and a free function `reset` are separate identities. Each method has
one exact MethodSymbol owned by its declaring StructSymbol or ClassSymbol
through NativeInstanceSymbol. All field identities
and method signatures exist before body checking, so calls to later methods,
self recursion and mutual recursion work.

## Explicit receiver

`this` is reserved. In a method of `S`, it denotes the compiler's exact
`Receiver<S>` contract: mutable, non-owning, nonnull storage of one live S.
It is not an ordinary `S*` variable, cannot be rebound, moved, released or copied,
and cannot be used as a pointer argument or compared with null. The compiler
adds no hidden source parameter. Outside an instance method, its diagnostic is
`'this' is only valid inside a struct instance method`.

`this.field` binds the exact declaring field and produces a field Place. Reading
loads that Place; assigning stores it. Fields never participate in unqualified
lexical lookup. `value = 1;` therefore reports `unknown assignment target 'value'`
if only a field has that name; `return value;` reports `unknown name 'value'`.
An explicit parameter may use the same name:

```astra
void set(int value) {
	this.value = value;
}
```

Inside the declaring struct or class, `this.add(1)` performs a direct call to its exact
`add` method and forwards the same receiver storage. Recursive calls do the same.
There is no global method search, free-function fallback or dynamic dispatch.

## Addressability and aliases

A struct receiver must be a visible, completely initialized direct struct
local. Using `counter.add(...)` anywhere in its checked body marks that local
address-taken for its whole relevant lifetime, using the existing selective
memory architecture. Initialization and every field access then use one object.
Another local of the same type, used only through fields, remains scalarizable.
Merely declaring methods has no instance-storage cost.

```astra
Counter c = { value = 1 };
Counter* p = &c;
Counter* q = p;
p->value = 40;
c.add(1);
q->value = q->value + 1;
// c.value, p->value, q->value and c.get() all observe 42.
```

The call neither copies nor transfers c. Its receiver may alias ordinary typed
pointers; borrowing imposes lifetime constraints, not exclusivity. Direct-local
and `this` receiver construction prove nonnull storage without a runtime null
guard. General `p->field` accesses retain their existing null traps. Neither
`p.method()` nor `p->method()` is supported for `Struct*`.

## Calls and native boundaries

Evaluation order is receiver, argument 0, argument 1, and so on, then invocation.
Supported receivers have no source runtime side effects, but their preparation
still precedes arguments in IR. Calls are conservatively effectful. `&&`/`||`
retain short circuit; eager bool `&`/`|` evaluate both operands. Owned arguments
use the ordinary capture/transfer commit point after all arguments evaluate.
Receiver preparation does not move the struct or add an ownership operation.

Methods reuse ordinary native parameters/results: exact integers, bool, f32,
vectors, supported typed pointer parameters, nominal handles, borrowed slice
parameters, and qualified owned Resource parameters/results. F32 rounding and
whole-vector semantics are unchanged. For example:

```astra
struct Accumulator {
	int bias;

	int sum(borrowed int[] values) {
		int result = this.bias;
		int i = 0;
		while (i < len(values)) {
			result = result + values[i];
			i = i + 1;
		}
		return result;
	}
}

int main() {
	Accumulator accumulator = { bias = 32 };
	int[4] array = { 1, 2, 3, 4 };
	return accumulator.sum(slice(array));
}
```

NABI uses existing PTR for the first receiver channel. Explicit slices then
expand to base PTR and length I32 under slice-v5; vectors use vector-v4. Explicit
struct values use aggregate-v7 leaf channels. No runtime descriptor, vtable, RTTI
or GObject machinery exists.
Physical method symbols are internal compiler artifacts with no stable ABI.

## Unsupported forms

Arbitrary expression receivers, `make_struct().method()`, struct results, method
values, `object.method` as a value, address-of-method, static members, overloads,
generic methods, implicit field lookup, virtual properties and extension methods remain
unsupported. [OBJ-1 classes](objects.md) reuse this same method and receiver
foundation. Heap allocation, struct lifecycle members, inheritance, interfaces,
virtual dispatch and C/GObject interop remain deferred.

See [native functions](functions.md), [IR](../ir/methods.md),
[ADR 0048](../decisions/0048-native-struct-methods.md) and
qualification.

## Recursive struct fields

Struct methods may read/write `this.inner.x` through ordinary recursive FieldPlace
lowering. Receiver and addressability policy are unchanged. Invoking a method on
`outer.inner` remains unsupported; no receiver redesign is included. See
[nested fields](nested-struct-fields.md).
