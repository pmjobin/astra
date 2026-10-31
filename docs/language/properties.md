# Native computed properties

Current [structural generic properties](structural-generics.md) include admitted
copied-record, explicit owning/borrowed and checked member channels. The original
PROP/LAZY component profiles below keep their historical scope; their earlier
generic/record exclusions do not override the later checked structural contract.
First-success caching, backing-root lifetime and exact accessor effects remain
required. Historical LAZY-1 Q4 remains HELD/INCOMPLETE.

ERROR-1/R1 adds get-only virtual string properties with a proved readonly snapshot or literal getter subset and receiver lifetime: see [native exceptions](exceptions.md). Stored local receiver views and copies carry checked backing-owner loans across assignments, loops and catches. Ordinary effectful properties retain their existing semantics.

LAZY-1 adds [first-success cached class properties](#first-success-cached-properties) and a bounded checked `throws C` clause on copied-value get-only class properties. It preserves the diagnostic string getter subset above.


STRUCT-ABI-1 preserves PROP-1's explicit value matrix: struct-valued properties
remain excluded even though ordinary methods can return structs. Accessor bodies
may call [concrete struct-boundary helpers](struct-values.md), copy their results
and use fields. This does not introduce an aggregate property Place or Value.

Accessors may invoke [top-level generic functions](generic-functions.md), for
example `get { return identity<int>(this.raw); }`. Generic bodies may read/write
properties of concrete receivers. Substitution preserves the exact property and
accessor targets without member-name lookup; null checks, effects and cleanup
order remain ordinary PROP-1 semantics. Properties/accessors cannot be generic,
and accessing a property on a plain-copy type parameter T rejects at definition.

Native structs and classes may declare explicit computed instance properties.
An ordinary property reads and writes through accessors; it creates no storage.

```astra
class Counter {
	int raw;
	init(int initial) { this.raw = initial; }
	property int value {
		get { return this.raw; }
		set(int next) { this.raw = next; }
	}
}
int main() {
	Counter c = Counter.init(1);
	c.value = 42;
	return c.value;
}
```

The assignment invokes the setter once, and the return expression invokes the
getter once. A field access such as `c.raw` continues to load/store its field
Place. A property never becomes a Place, even when its body is a simple field
read or write. There is no implicit backing field.

## Grammar and binding

```text
native-instance-member := field-declaration | method-declaration | property-declaration
                         | constructor-declaration | destructor-declaration
property-declaration := "lazy"? "property" ("borrowed" | "owned")? type identifier throws-clause? "{" getter setter? "}"
throws-clause := "throws" class-type
getter := "get" block
setter := "set" "(" "owned"? type identifier ")" block
```

Lifecycle declarations remain class-only. `lazy`, `property`, `get` and `set` are
contextual member/accessor keywords. Exactly one getter is required and one setter
is optional and follows the getter. Both require explicit blocks. Duplicate
accessors reject. An empty property, setter-only property, `get;`, `set;`, property initializer, unsupported modifier,
indexed parameter list or extra accessor parameter rejects.

The setter parameter has an ordinary exact ParameterSymbol. Its explicitly
written type must equal the property type (`int` and `i32` denote the same type).
Its binding is immutable, like any ordinary parameter. It may shadow a field,
which remains available through `this.field`. No implicit identifier named
`value` exists: `set(int next)` binds only `next`. A user may explicitly choose
`set(int value)`.

Fields, methods and properties share one namespace per declaring native type.
Collisions reject regardless of declaration order or differing value types.
Class properties cannot be named `init` or `deinit`. Different types may each
have a property with the same spelling; their identities are independent.
Every member signature exists before checking any body, so forward method and
property references work.

## Value types

The rule is the intersection of ordinary **non-owned** native method parameter
and result support at F64-1, excluding nominal handles by the explicit PROP-1
scope decision. Handle-valued properties are intentionally deferred to a later
ownership/borrowing property milestone, including plain non-owned handles.

| Property type | Support | Value channel / minimum effective profile with receiver |
| --- | --- | --- |
| bool | Yes | B1 / scalar-ptr-v1 |
| int, i32 | Yes, one exact type | I32 / scalar-ptr-v1 |
| i8, u8, i16, u16, u32 | Yes | Existing exact integer channel / scalar-int-v2 |
| f32 | Yes | F32 / scalar-fp-v3 |
| f64 | Yes | F64 / fp64-v6 |
| void* | Yes, plain raw pointer | PTR / scalar-ptr-v1 |
| i8/u8 vectors | 2, 4, 8, 16 lanes | Existing vector channel / vector-v4 |
| i16/u16 vectors | 2, 4, 8 lanes | Existing vector channel / vector-v4 |
| int/i32/u32/f32 vectors | 2, 4 lanes | Existing vector channel / vector-v4 |
| bool masks | 2, 4, 8, 16 lanes | Existing mask vector channel / vector-v4 |
| f64 vectors | No such type | Rejected by existing vector type rules |
| Typed pointers | No | Baseline typed-pointer result contracts are unsupported |
| void, ClassType, StructType, ArrayType, SliceType | No | Explicit PROP-1 value-policy exclusion |
| Handles, owned values, borrowed contracts | No | Intentionally deferred |

An accessor signature uses receiver PTR plus these ordinary channels. The
program-wide effective profile may be higher because of other callables; no
property profile or property ABI type exists. F64 transport retains finite
binary64 values beyond F32 precision, signed zero, subnormals and infinities.
Qualification also checks exact transport of representative NaN payloads through
plain field-copy accessors. This adds no source guarantee about the payload or
sign selected by NaN arithmetic. Passing through an accessor adds no arithmetic
rounding point.

## Effects, receivers and ordering

A read evaluates the receiver, validates a nullable class reference, invokes its
exact getter and produces one ordinary value. A write evaluates the receiver,
validates it, evaluates the RHS and invokes its exact setter. A null receiver
traps **before RHS evaluation**, so `c.value = effect()` does not call `effect`
when `c` is null. The trap does not enter the accessor and follows existing
non-unwinding cleanup behavior.

Getters may mutate state, call methods/properties, allocate ordinary lexical
locals, clean them up and trap. Two evaluated ordinary property reads mean two getter calls;
there is no purity or common-subexpression assumption. `condition && c.ready`
short-circuits; `condition & c.ready` eagerly evaluates the bool getter.

Supported receivers match methods: a direct struct local, live `this`, or a class
reference local/parameter. Borrowed class parameters, owned locals/parameters
before move, and objects acquired from owned results work. Property access borrows
the receiver temporarily and does not move it. Aliased references observe the
same ObjectStorage, including two borrowed parameters at O2. Struct-pointer and
arbitrary-expression receivers remain unsupported.

Using `b.value` makes that struct instance addressable through METHOD-1's existing
receiver path. Another `a` of the same type, used only through fields, remains
eligible for field scalarization. Merely declaring a property does not change
instance storage. Fields, methods, properties and permitted pointer aliases all
observe the same storage.

`this.property` is valid in methods, getters, setters and destructors, whose
receivers are fully initialized and live. It needs no redundant null guard.
Constructor `this.property` rejects even after explicit field initialization:
accessor effects could bypass constructor definite-field rules. A constructor
may access a different live object normally. Destructor property access observes
mutations performed before cleanup.

`this.same_property` inside an ordinary getter recurses into that getter; assignment to
it inside its setter recurses into the setter. The property name never aliases a
hidden field.

## Values without storage

A getter-only property can be read, but writing reports its exact owner/property
and missing setter. Properties cannot appear in structural initializer field
lists. Initializers establish fields and never call setters.

For a vector property, `object.samples[2]` first calls the getter, then extracts a
lane from its returned value. Lane assignment rejects. A whole-value update is:

```astra
object.samples = insert(object.samples, 2, next);
```

This has one explicit getter occurrence and one setter call. BIT, DSP and DOT
operations consume returned vectors normally. There is no vector lane Place.

Property address-of, pointer-to-property, compound assignment, `++`/`--`, move,
release or rearm through a property are unsupported. There are no automatic,
static or indexed properties, no ownership-bearing property values, and no property reflection, notifications, bindings or GObject
machinery. Accessors cannot be called as methods or through `.get()`/`.set()`.
Virtual properties are limited to the diagnostic string subset described above.

See [ADR 0055](../decisions/0055-native-computed-properties.md),
[property IR](../ir/properties.md) and qualification.

## First-success cached properties

```astra
class Sample {
	int input;
	int calls;
	init(int input) { this.input = input; this.calls = 0; }
	lazy property int value {
		get { this.calls = this.calls + 1; return this.input * 2; }
	}
}
int main() {
	var sample = new Sample(20);
	sample.input = 21;
	int first = sample.value;
	sample.input = 99;
	if (sample.calls != 1 || sample.value != first) { return 1; }
	return first;
}
```

Construction initializes Empty state without invoking the getter. The first read
marks that exact receiver/property Evaluating. After its getter and normal local
cleanup complete, the copied result is stored and the state becomes Ready. Later
reads copy that result. Mutation before the first read affects computation;
mutation after Ready does not invalidate it. Different objects and different
properties have independent caches, including inherited properties through base
views. Ownership transport preserves the actual object's state.

An ordinary exception completes getter-local cleanup, resets only the failed
cache to Empty and propagates the original exception through the existing checked
channel. The caller may retry in its handler. Side effects and successfully
initialized sibling properties remain. A locally caught error followed by a
normal return caches the successful result. Recursive access to an Evaluating
cache traps, directly, indirectly, through a cycle or during local cleanup.
The fatal trap does not promise unwinding of remaining owners.

`lazy` requires a concrete nonvirtual get-only class property returning one of
the copied scalar, vector, mask or raw `void*` types in the table above. Zero,
false, null and any floating-point payload are successful values. String,
record, enum, slice/array, Resource owner and Task caches are excluded. Owned
Class caches use the separate form below.
There is no setter, reset, automatic invalidation, generic/static/async getter,
hidden lock or concurrent first-access guarantee. Destruction does not force
unused getters. Live destructors may read a lazy with ordinary local effect
handling; constructor receiver restrictions still apply.

`property int value throws DecodeError { get { ... } }` and its lazy form declare
an existing class exception bound. Reads require the same normal catch or throws
coverage as calls, even after a prior successful read. Subtypes and bare rethrow
use existing exception authority. This clause also requires a nonvirtual
get-only copied-value class property; string diagnostics, setters and structs
retain their previous exclusions. `Error.message` and formatting are unchanged.

See [ADR 0093](../decisions/0093-first-success-cached-properties.md),
[cache lowering](../abi/lazy-properties.md) and finite qualification.

## Explicit generic capabilities

Concrete property getters/setters and methods may call constrained generic
functions, for example `max_value<int>(this.raw, limit)` with an Ordered
requirement. Constrained generic bodies may use concrete property/method/field
identities; specialization preserves those exact targets. Capabilities never
grant members on T, and generic properties remain deferred.
See [generic capabilities](generic-capabilities.md).

## Recursive struct fields

Struct property accessors may use `this.inner.x` through ordinary recursive Places.
The property remains an accessor call with no backing Place. Property invocation
on a nested substruct receiver is deferred, and class embedded aggregates remain
unsupported. See [nested fields](nested-struct-fields.md).

## Owning lazy results

```astra
class Card {
    lazy property owned Utf8Message content throws Error {
        get {
            var bytes = new u8[1];
            bytes[0] = 65;
            var message = utf8_message(bytes);
            return move message;
        }
    }
}
```

The getter body produces an exact unique heap Class owner. Public reads such as
`inspect(card.content)` borrow the cached value for that exact borrowed consumer;
reads retain the declared checked effect on both cold and warm paths. First
success caches the owner, failure leaves an empty retryable cache, and moving the
receiver preserves cache identity. Destruction retires a ready cache once and
never initializes an unused cache. Recursive evaluation traps.

Views cannot be stored, returned, captured or converted to owners. Moving or
potentially invalidating the containing receiver during a loan is forbidden.
The supported result is an exact nongeneric nonpolymorphic native Class;
getters are direct, synchronous and get-only. There is no setter/reset or
thread-safe first access. Ordinary `property borrowed` remains a separate
nonthrowing field-view operation. See [ADR 0120](../decisions/0120-owned-lazy-factory-observation.md).

Closed general-body containers may be owned child fields, exposed through an
ordinary borrowed projection, or cached by a lazy owned property. For example,
`lazy property owned Vector<Packet> packets throws Error` transfers the factory's
one heap container into the cache. Getter observations remain scoped to the
receiver and cannot be copied or moved into a new owner. Owning record elements
keep their complete cleanup plan. A computed virtual property may observe this
cache and continues to execute on every access. The factory is synchronous;
an owning receiver may survive cooperative suspension using the existing frame
owner contract, after its temporary cache loans end. See
[ADR 0149](../decisions/0149-generic-child-and-lazy-cache-composition.md).

General-body generic Classes can declare direct computed get-only `int` and
`bool` properties over their exact specialization, alongside ordinary and copied
generic methods. They execute on every access, including after insertion or
extraction. Their declaration names, result roles and native receiver/target
bindings are checked independently at each stage. Template-level lazy, throwing,
virtual and T-valued properties remain excluded; the owning cached-container
profile above is a separate receiver/factory contract. See
[ADR 0153](../decisions/0153-direct-properties-on-general-generic-classes.md).
