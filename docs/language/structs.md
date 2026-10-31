# Native local structs

[Computed properties](properties.md) share the field/method member namespace.
Their accessors use the existing struct receiver and direct-local addressability
path. Calling a property on `b` makes only `b` addressable; field-only `a` remains
scalarizable even if its type declares properties. Properties add no fields and
cannot be named in brace initializer field lists or addressed with `&`.

OBJ-1 adds a separate [class reference type](objects.md). A struct local still
denotes its actual value/storage aggregate and may scalarize until addressability
is needed. A class local is a nullable reference to separately identified lexical
object storage, which is always explicit memory. Class reference copy and identity
equality are separate from native struct storage copy; struct equality remains
unsupported. Both declarations share one owner-parameterized field authority and the same
[method system](methods.md); only structs admit nested structs and vectors; all existing struct
pointer, receiver and selective-addressability rules remain unchanged.

ASTRA-STRUCT-1 introduces named aggregate storage with scalar fields:

```astra
struct State {
	int count;
	bool ready;
	void* handle;
}

int main() {
	State state = { ready = true, count = 20, handle = null };
	state.count = state.count + 22;
	if (state.ready && state.count == 42) { return 0; }
	return 1;
}
```

The implemented grammar is:

```text
struct-declaration := "struct" identifier "{" struct-member* "}"
struct-member := struct-field-declaration | method-declaration | property-declaration
method-declaration := "owned"? result-type identifier "(" parameters? ")" block
struct-field-declaration := type-name identifier ";"
type-name := identifier ("*")?
local-declaration := type-name identifier "=" local-initializer ";"
local-initializer := expression | struct-initializer
struct-initializer := "{" field-initializer ("," field-initializer)* "}"
field-initializer := identifier "=" (expression | struct-initializer)
field-access := identifier ("." | "->") identifier ("." identifier)*
assignment := (identifier | field-access) "=" expression ";"
```

Struct declarations are top-level only and have no closing semicolon. The parser
retains empty declarations for a deterministic semantic rejection; accepted
structs have at least one field. It also retains unsupported type names and extra
pointer stars for semantic diagnostics. No initializer trailing comma or empty
initializer is accepted.

Fields may be an [IntegerType](integers.md), [f32](f32.md), [f64](f64.md), `bool`,
`void*`, a concrete native StructType, or an existing supported VectorType. INTS-1
adds i8/u8/i16/u16/u32 fields; int and i32 are the same field type. `void`, unknown
types and other pointer field types remain invalid. Structs are nominal: two
declarations with identical fields remain distinct types. Names occupy type-name
authority, rejecting collisions with builtins or another struct. Function and
local names have separate authority; a function named `State` may coexist with
the type. All struct identities are collected before field resolution and native
body checking, so a function may use a later struct declaration.

A brace initializer is valid on a struct local declaration or a nested struct
subobject initializer. Each declared field must appear exactly once; struct fields
use complete nested braces or an exact bounded producer; scalar/vector leaves
use an expression of the exact type. GEN-COPY-1 applies this producer-entry rule
to ordinary and generic enclosing records alike. No implicit
conversions, omitted fields, defaults, zero initialization, or constructor exist.
The local becomes visible after the complete initializer finishes. This rejects
self-reference even to a field whose initializer appeared earlier:

```astra
struct Pair { int x; int y; }
int invalid() {
	Pair p = { x = 1, y = p.x };
	return 0;
}
```

Initializer expressions execute in written order, independent of declaration
order. `Pair p = { y = record(2), x = record(1) };` calls `record(2)` before
`record(1)`. Existing operand/argument order, short circuit, and traps apply
within each expression. A later trap prevents initialization from completing;
there is no language-visible partially initialized local or resource cleanup.

`p.x` projects the exact local struct variable `p`. A scalar/vector leaf read
loads one value; a struct-valued field is storage for further projections.
`p.x = expression;` evaluates the RHS before storing a leaf. The same spelling
on different struct types binds different fields, and `a.x` and `b.x` denote
different storage even if `a` and `b` have the same type. Struct locals retain
ordinary lexical scopes, including branch and loop bodies. Visible locals and
parameters cannot be shadowed; sibling scopes may reuse names.

Finite acyclic field chains are supported through recursive Places. There are no
arbitrary-expression receivers, static properties, or visibility modifiers. METHOD-1 supports
[instance methods](methods.md) on direct locals and explicit `this`. Fields and
methods share one namespace; duplicates and collisions reject, without overloading.
All field identities and method signatures exist before body checking. Methods
use native parameter/result contracts and require `this.field` for field lookup. Struct equality and general struct literal expressions remain unsupported.
Whole copy initialization/assignment are dedicated Place contexts. Copyable concrete
struct parameters/results are valid in native functions and methods through
[bounded value contexts](struct-values.md). Parameters are independent read-only
local storage; results and arguments use complete leaf snapshots. `extern(C)`,
`export(C)`, and VAPI still reject aggregate boundaries. VAPI cannot declare structs.

TPTR-1 adds [native typed pointers](typed-struct-pointers.md) and `p->field`
access with null traps. BORROW-1 permits lexically safe [stored `&local`
borrows](borrows.md). There is no ownership,
layout, size, alignment, padding, or field-offset operation. These are native
Astra storage types with no C struct ABI. Non-address-taken scalar/vector leaves promote independently;
ordinary LLVM scalar/vector operations execute the program without
materializing an aggregate. See [field Places](../ir/field-places.md) and
[ADR 0025](../decisions/0025-native-local-structs.md).

Taking a struct local's address or calling a method on it anywhere in a valid
checked body makes
every field of that local memory-backed for the whole function, including
initialization and direct field reads. Direct and indirect Places may alias.
Other locals remain scalarized. Physical aggregate realization exists only in
the backend where required; no stable language layout is specified. Typed
pointer fields, general whole-struct Values, and struct ABI channels remain
unsupported. See [addressable storage](../ir/addressable-storage.md).

## Exact-width fields

Field initializers and assignments provide literal context, including through
arithmetic: `u8 tag` accepts `tag = 255`, and `p.tag = 1 + 2;` uses u8 literals.
Non-address-taken fields use ordinary scalar promotion, branch parameters, and
loop carries. Address-taken fields and `p->field` use existing memory Places;
LLVM uses i8 for i8/u8, i16 for i16/u16, and i32 for int/i32/u32 loads/stores.
Signedness changes arithmetic interpretation, not storage width. No padding,
alignment, offset, sizeof, or stable native aggregate ABI is specified.

## F32 fields

F32-1 permits exact binary32 initialization, reads, and mutation. Promoted f32
fields use ordinary scalar SSA values and branch/loop block parameters. A local
whose address is borrowed retains explicit mutable memory; native Struct*
mutation uses backend float GEP/load/store. Signed zero and subnormals survive
both paths. This adds no struct layout or C struct ABI promise and does not
change Resource field restrictions or ownership.

METHOD-1 methods operate on existing authoritative instance storage. `this.field`
is a field Place; `this.method(...)` forwards the same exact non-owning, mutable,
nonnull receiver. Merely declaring methods does not make instances addressable.
An instance used only through fields remains scalarizable, even if another
instance of the same type is method-called. No receiver copy, object allocation,
constructor, destructor or class identity is implied. See [ADR 0048](../decisions/0048-native-struct-methods.md).

## Nested storage and vector leaves

[STRUCT-AGG-1](nested-struct-fields.md) generalizes ordinary field storage. A struct
subobject is a Place, not a whole-struct Value. Nested braces initialize directly
without aggregate temporaries or copies. Recursive completeness and cycle checks
run before LLVM; declaration field order remains unchanged. Nested scalar/vector
leaves scalarize under existing local rules. Address-taken roots use one concrete
nested storage object and recursive address projections. Class field policy remains
unchanged. No aggregate ABI or generic aggregate semantics is introduced.

## Generic native structs

GEN-STRUCT-1 adds [generic native struct definitions](generic-structs.md) as semantic type constructors. Explicit applications materialize into ordinary concrete struct storage before CFG, with the same recursive initialization, field access, vector leaves and selective addressability. Concrete whole copying is supplied by STRUCT-COPY-1; concrete native boundaries are supplied by [STRUCT-ABI-1](struct-values.md).

## Whole copy contexts

[Whole struct copy](struct-copy.md) now permits `S b = a;` and `b = a;` for the
exact same nominal concrete storage type. Locals, nested subobjects and existing
Struct* dereference roots compose. Both source and destination remain independent
initialized storage. The compiler snapshots all recursive scalar/vector leaves
before any write. Copy itself does not make a local addressable. It introduces
neither a general struct Value nor ownership transfer. Native boundaries are a
separate [copyable value contract](struct-values.md), sharing the same leaf order.

## Multi-source composition

A struct declared in one [source file](source-files.md) is directly usable from
any other supplied file. Exact nominal identity, COPY_VALUE boundaries, independent
copies, member access and ABI plans are unchanged. Equal layout does not equate
two types; duplicate names are conflicts, not partial declarations. Layout-cycle
checks see the complete program, including cycles that cross files.

## Flat owning records

A nongeneric synchronous local struct may hold multiple `owned Resource` fields
and scalar companions. Initialize every field once; expressions run in written
order. Each successful owned field becomes independently responsible for cleanup.
Checked failure retires only that prefix, in reverse acquisition order. Whole
`move` into a fresh local transfers all fields and preserves that order; copying
and moved-source use are rejected. Null in one field cannot suppress another
field's cleanup. Field extraction, nested/generic owning records, owned Class
fields and owning record parameters/results remain deferred.
See [ADR 0119](../decisions/0119-flat-record-field-obligations.md).
