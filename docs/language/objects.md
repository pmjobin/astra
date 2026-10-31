# Lexical native objects

ERROR-1 adds a bounded explicit heap and single-inheritance path alongside these lexical contracts: see [native exceptions and reusable class prerequisites](exceptions.md). Participating classes use a complete zero-offset base/header and virtual dispatch; prior header-free direct lexical classes retain their layout. General object allocation/lifetime work remains open.


Native classes additionally support [owned Resource fields](owned-resource-fields.md)
with explicit `owned` declarations and definite initialization through `init`.
They borrow non-consumingly, permit live replacement, and automatically release
their final contents after normal user deinit in reverse declaration order.
Plain Resource, owned ClassType and embedded aggregate fields remain excluded.

[Computed properties](properties.md) are accessor members in the same namespace
as class fields and methods. A nullable class reference is validated before its
getter call or before the RHS of a setter assignment. Accessors see the same
ObjectStorage through aliases. Properties add no object fields, header, vtable,
property table, reflection descriptor or notification runtime. Class-valued
property results and C/VAPI/GObject properties remain unsupported.

[Owned object results](object-results.md) add `owned C` native function/method results and visible owned local acquisition. Fresh `return C.init(...)` constructs directly in caller candidate storage; null and ancestor-parameter forwarding are legal. ClassType identity is unchanged, and callee-local storage cannot escape.

[Explicit owned bindings](object-ownership.md) opt into transferable cleanup:
`owned Counter c = Counter.init(42); consume(move c);`. The ordinary reference
and fixed lexical lifetime rules below continue to apply to unqualified bindings.
An owned local instead requires fresh construction, cannot rebind or create a
persistent alias, and may use temporary borrowed calls, fields and methods.
Both forms use the same ClassType and ObjectStorage.

[Borrowed native parameters](borrowed-object-parameters.md) let a function,
method or constructor receive `borrowed Counter c`. This is one exact nullable,
mutable, aliasable, non-owning, noescape reference. Copies and forwarding retain
lexical lifetime authority, and the caller keeps ObjectStorage cleanup. Field and
method access through a parameter use the same null rules as local references.

A class declares a nominal object type. Values of that type are nullable
references to objects. Copying a reference shares the object:

```astra
class Counter {
	int value;
	void add(int amount) {
		this.value = this.value + amount;
	}
}

int main() {
	Counter c = { value = 40 };
	Counter alias = c;
	alias.add(2);
	return c.value;
}
```

This returns 42. `c` and `alias` name separate reference locals pointing to the
same field storage. `alias.value = 42` would also change the value observed
through `c.value`.

## Declaration and construction grammar

```text
class-declaration := "class" identifier "{" class-member* "}"
class-member := field-declaration | method-declaration | property-declaration | constructor-declaration | destructor-declaration
field-declaration := "owned"? type-name identifier ";"
method-declaration := "owned"? result-type identifier "(" parameters? ")" block
object-local := class-type identifier "=" "{" field-initializers? "}" ";"
field-initializers := identifier "=" expression ("," identifier "=" expression)*
reference-local := class-type identifier "=" (reference-expression | "null") ";"
```

Classes are top-level, without a trailing semicolon. Fields, methods and properties share
one namespace per class. Duplicate fields, duplicate methods, and a field and
method with the same name reject; method overloading is absent. Class names
share the ordinary type namespace with builtins, structs and imported resource
handles, and cannot collide with any of them. Class identities are nominal:
same-shaped `class A`, `class B` and `struct S` have distinct types.

Ordinary class value fields retain the existing scalar predicate: `i8`, `u8`, `i16`,
`u16`, `i32`/`int`, `u32`, `f32`, `f64`, `bool` and `void*`. Explicit owned nominal
Resource fields are also supported. Vector, array, slice, plain Resource, struct,
class-reference, and typed-pointer fields remain unsupported.
Class method syntax and explicit signature rules are the ordinary
[method rules](methods.md).

Classes may declare [explicit lifecycle members](object-lifecycle.md): `init(...)`
and `deinit()`. Constructor-based construction is `Counter c = Counter.init(40);`,
restricted to fresh exact class locals. Class member names `init` and `deinit` are
reserved; ordinary fields/methods with those names reject. A declared constructor
cannot be bypassed with braces. A destructor without a constructor is valid.

Brace construction is a direct local declaration only, for classes without `init`. Every field must appear
exactly once, in any written order. Expressions evaluate and store in that
written order, independently of declaration/layout order. Methods are excluded.
The new reference local is invisible while its fields initialize; using `c`
inside `Counter c = { value = c.value };` rejects. If any initializer traps,
normal execution stops before the reference becomes observable.

Each executed construction creates fresh lexical object storage and then binds
a nonnull reference to it. Construction is not a copyable whole-object value.
`c = { ... }`, `f({ ... })` and `return { ... }` are unsupported. There is no
`new`: lexical local storage makes no decisions about heap allocation, escaping
ownership. Those remain separate future work. Lexical destruction follows
ObjectStorage through the [lifecycle rules](object-lifecycle.md).

An empty class is valid: `class Empty {}` and `Empty e = {};`. Two simultaneously
live empty objects are distinct. The backend reserves a hidden byte for an empty
object, with no source-visible member or runtime metadata.

## References, identity and null

```astra
Counter a = { value = 1 };
Counter b = { value = 1 };
Counter alias = a;
bool same = a == alias; // true
bool distinct = a != b; // true even though fields match
alias = b;             // rebind; no fields are copied
alias = null;
bool absent = alias == null;
```

Assignment and initialization require the exact same ClassType or contextual
`null`. Both `==` and `!=` compare reference identity. Two null references of the
same class compare equal. `a == null` and `null != a` are valid; null is not an
object identity. Cross-class assignment or comparison rejects. There is no
ordering, truthiness, arithmetic, bitwise operation or integer `as` cast for
references; use `if (ref != null)` explicitly. Branches and loops may choose,
carry or rebind references, including object/null merges.

A class reference is distinct from `void*` and TypedPointerType. No conversion in
either direction, address-of-reference operation, dereference operator or `C*`
type is added. `C` already denotes a reference; `C*` would need a separate design
for storage containing a reference. Object size, alignment and field offsets
remain compiler-private.

## Fields and methods

`ref.field` is a mutable Place in the referenced object's storage. Reading loads
the field, and assignment stores it. The reference base evaluates exactly once.
Null reads trap before loading. A write evaluates the base, validates nonnull,
then evaluates its RHS and stores. Thus `null_ref.value = record();` traps
without calling `record`.

`ref.method(args)` resolves an exact method on the exact class. It evaluates the
reference, validates nonnull, evaluates explicit arguments left-to-right,
performs the existing owned-transfer commit, and invokes the direct method.
`null_ref.consume(move resource, record());` traps before capture/move or
`record`. With a valid receiver, existing ownership rules apply unchanged.

Inside a class method, `this` has precisely METHOD-1's mutable, non-owning,
nonnull receiver contract. It cannot be assigned, rebound, copied to a reference
local, set to null or used as an ordinary argument. `this.field` and
`this.method()` work without source-required null guards. Direct and mutual
recursion reuse ordinary methods; no virtual dispatch exists. Methods retain
existing vector/DSP, borrowed-slice and owned Resource parameter/result support.
Multiple references may alias, and all direct/alias/method field mutations remain
coherent. The receiver has no exclusivity or `noalias` promise.

## Lexical lifetime

The storage and the constructing reference local have separate identities.
Storage ends with its construction scope, even if the original reference is
rebound earlier:

```astra
Counter c = { value = 40 };
Counter alias = c;
c = null;
alias.add(2); // storage remains alive; alias.value is 42
```

The existing LexicalRegion ancestor/same-region rule checks stored references.
Construction borrows its storage's region. A reference local read conservatively
uses that local's region, without following previous assignments. Literal null
has no storage provenance requirement. Same-region aliases and outer-to-inner
copies are valid. Inner-to-outer copies reject:

```astra
Counter outer = null;
{
	Counter inner = { value = 1 };
	outer = inner; // error: inner has a shorter lexical lifetime
}
```

This conservative rule also rejects copying an inner alias back outward, even
when it originally received an outer reference; no full provenance sets or
flow-sensitive null proofs are added. An object construction in a loop creates
a fresh lifetime each iteration. Stack reuse after a lifetime ends is safe
because references cannot escape that lifetime. A declared destructor runs once
at normal storage lifetime end, using its final field state. Copies, reference
rebinding and nulling neither duplicate, transfer nor cancel that responsibility.
Objects and Resources share reverse lexical cleanup order. Traps do not unwind.

## Struct contrast and deferred features

| Property | `struct S` | `class C` |
| --- | --- | --- |
| Meaning of a local | Actual aggregate storage | Nullable reference binding |
| Backing storage | May scalarize until identity is needed | Always explicit memory |
| Copying `T b = a` | Independent whole-value copy when fields are copyable | Copies one reference; aliases |
| Equality | No whole-struct equality | Exact object identity |
| Address/pointer | Qualified `S*` and selective `&s` | No `C*` or `&c` |
| Method contract | Nonnull exact storage receiver | Same receiver after null validation |

Ordinary records support [whole-value copy](struct-copy.md) and independent
[native parameter/result values](struct-values.md), including nested records.
The shared [copyability authority](../../bootstrap/semantic/copyability.vala),
[ADR 0061](../decisions/0061-whole-struct-copy.md) and
[ADR 0062](../decisions/0062-native-struct-values.md) define these boundaries;
the existing [copy fixture](../../tests/struct-copy/fixtures/struct-copy-basic.astra)
and [value-call fixture](../../tests/struct-abi/fixtures/struct-abi-basic.astra)
exercise independent storage. Copyability does not derive record equality.
The finite owning-local contract
separately supports a nongeneric record with one owned Resource and scalar
companions: complete nonthrowing construction, fresh whole-local moves and
lexical cleanup across later checked calls/throws and ordinary try/catch.
Checked initialization, partial rollback and owning aggregate transport remain
deferred. See the [current matrix](capabilities.md)
and [owned-data track](../vision-and-roadmap.md#track-b) for remaining work.

Objects introduce no heap, allocator, GC, refcount, vtable, vptr, RTTI or runtime
descriptor. Plain and explicitly borrowed native Class parameters share bounded
borrowing; owned parameters retain explicit transfer. Unqualified/borrowed object results,
C/VAPI boundaries, fields and array/slice elements
remain unsupported. Owned lexical bindings follow the separate fresh-only contract. Inheritance syntax, virtual/static or
access modifiers, interfaces, virtual properties, constructor overloading/delegation, delegates,
`new`, `delete` and C/GObject classes remain unsupported.

See [borrowing](borrowing.md), [object values](../ir/object-values.md),
[object storage](../ir/object-storage.md) and
[ADR 0049](../decisions/0049-native-object-identity.md).
