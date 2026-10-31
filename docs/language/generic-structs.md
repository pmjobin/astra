# Generic native structs

Current declaration-derived substitutions and member/callable composition follow
[structural generics](structural-generics.md). The profiles below preserve their
original component scopes; the owning-storage addition also retains M17's exact
context/frame lifetime and Send requirements.

M17 adds an explicit closed owning-storage profile:

```astra
struct OwnerRecord<T> where T : Ownable {
	owned T item;
	int marker;
}
struct NestedOwnerRecord<T> where T : Ownable {
	OwnerRecord<T> child;
	int stamp;
}
```

An `Ownable` parameter currently accepts an exact native Class or Resource
handle, including an allocator handle. The `owned` field is required. Closed
applications enter the ordinary record move, recursive cleanup and bounded
observation proofs before CFG. Each leaf preserves its own allocation origin;
moving a record into a context-backed Class does not reallocate its children.
Other unbounded parameters retain plain-copy rules, including copyable generic
record arguments. A record may also contain a concrete primitive owned buffer.
Whole-record synchronous borrows permit bounded copied field/buffer reads while
retaining the caller's complete ownership graph.
Concrete owning records can also move into cold async frames and remain live
across suspension. Dropping a cold task, throwing, or joining cancellation
retires its initialized fields in reverse acquisition order. An owning record
success transfers through `await` into a typed local; discarding a published
success retires that complete result instead. Worker captures and results
require the record's full transitive graph to satisfy Send. Borrowed records
remain restricted to synchronous observation. `checked_task_in` also accepts
named whole-record moves. Frame refusal restores every original owner and
buffer pair; admission leaves the caller's owning fields empty and preserves
its copied leaves. Fresh record expressions still require a named owner first.
The same whole-record admission contract applies to `try_new(context)`
constructors. Refusal restores the original graph; a checked constructor error
after admission retires the consumed inputs and initialized destination prefix.
Copied record constructor arguments retain ordinary copy semantics.
The declared parameter roles, field types and cleanup inventory are checked
again in Core, CFG, SSA and the independent native ABI. Explicit exported closed
applications retain their bounds in opaque native-unit declarations.

The unqualified profile below retains its existing plain-copy argument rules.
Owning generic functions, buffer/record arguments to `Ownable`, and general
owning-record leaf extraction are still outside this implementation checkpoint.
This addition does not close M17's remaining ownership-composition gates.

Concrete applications with eligible fields can be [fixed/owned array elements and borrowed slice elements](struct-elements.md). Canonical aliases deduplicate and phantom arguments remain nominal. Materialization still happens before CFG; no generic T[] matching or Copy capability is added. [GEN-COPY-1](generic-copyable-values.md) separately admits eligible record arguments as ordinary T values.

Concrete generic-origin structs can be native [COPY_VALUE parameters/results](struct-values.md).
Box<int>, Box<f64>, Box<i16<8>>, Box<bool<4>> and nested Bundle<f64> use ordinary
recursive copyability and aggregate-v7. Canonical int/i32 identities interoperate;
signed/unsigned specializations remain distinct. Parameterized Box<T> boundaries
are rejected before specialization. GEN-COPY-1 expands GEN1_PLAIN_COPY to copyable records without adding public
Copy/Move capabilities.

GEN-STRUCT-1 supports explicitly applied native struct type constructors:

```astra
struct Pair<T,U> {
	T first;
	U second;
}

int main() {
	Pair<int,f64> p = { first = 42, second = 3.5 };
	p.first = 7;
	return p.first;
}
```

The declaration grammar is `struct identifier "<" identifier ("," identifier)*
">" "{" field-declarations "}"`. Type application grammar is `identifier "<"
type ("," type)* ">"`. Every application supplies the exact number of arguments;
there is no inference or default argument. Empty lists, duplicate parameters,
missing arguments, wrong arity and name collisions reject. Definitions share the
existing nominal type namespace with ordinary structs and classes; arity does not
create an overload. Parameters follow GEN-1 lexical rules and cannot shadow
builtin or outer nominal types. An empty struct remains unsupported.

Only fields are supported in generic structs. Methods, properties, constructors
and destructors are absent. The unqualified profile has no where clauses;
the owning-storage profile above accepts explicit `Ownable` bounds. A definition is checked once,
including when unused. An invalid field in an unused definition still rejects.

## Arguments and identity

Arguments use the shared plain-copy domain: the original 34 canonical types
below plus legally formed, recursively copyable concrete native records.

| Category | Canonical arguments |
| --- | --- |
| Scalars and opaque pointer | bool, i8, u8, i16, u16, int/i32, u32, f32, f64, void* |
| i8 and u8 vectors | Each of 2, 4, 8 and 16 lanes |
| i16 and u16 vectors | Each of 2, 4 and 8 lanes |
| int/i32 and u32 vectors | Each of 2 and 4 lanes |
| f32 vectors | 2 and 4 lanes |
| bool masks | 2, 4, 8 and 16 lanes |

`struct Box<T> { T value; }` supports all 34, including all 20 numeric vector and
4 mask shapes. Box<i16<8>>, Pair<i16<8>,bool<4>> and Bundle<i16<8>> use contextual
type-close parsing; expression `x >> y` remains a shift.

Identity is the exact generic definition plus ordered canonical semantic
arguments. Box<int> and Box<i32> are one application and one concrete instance.
Box<i8> and Box<u8> are distinct. A<int> and B<int> remain distinct definitions.
`struct Tagged<T> { int value; }` preserves Tagged<i8> versus Tagged<u8> even though
the fields match. Names, field composition, size, alignment and LLVM representation
never determine identity or argument eligibility.

Void, text, resource handles, classes, slices, arrays and typed pointers remain
ineligible arguments. The sole pointer argument is opaque void*. Box<Kernel>,
Box<Pair<int,int>> and identity<Pair<int,f64>>(p) are legal when their exact field
graphs prove ordinary copyability. No public Copy/Move capability is introduced;
physical layout alone never establishes admission.

## Fields and composition

A generic field may directly contain T, any accepted ordinary native struct field
type, or another generic application. This includes concrete scalar fields, all
accepted vectors and masks, and ordinary concrete StructType fields. Class field
restrictions remain unchanged. T*, T[], T[N], generic vector construction, owned T
and borrowed T remain unsupported.

```astra
struct Bundle<T> {
	Pair<T,T> pair;
	int tag;
}
struct Swap<T,U> { Pair<U,T> pair; }
struct Mixed<T> { Pair<T,int> pair; }
struct Meta { int tag; f64 scale; }
struct Item<T> { Meta meta; T value; }

f64 example() {
	Bundle<f64> b = {
		pair = { first = 1.0, second = 2.0 },
		tag = 7
	};
	return b.pair.second;
}
```

Applications within definitions accept their current parameters or eligible
concrete arguments, including mixed and reordered arguments. Each projection
retains its exact generic field origin and substituted type. Pair<T,U>.first is
the same exact T token as the corresponding function/struct parameter.

Nested braces or exact bounded struct producers initialize storage subobjects
using recursive completeness and written evaluation-order rules. Producer entries
snapshot the complete source before that field's writes and later entries. Missing, duplicate or
unknown fields reject. There is no aggregate temporary, implicit zeroing, memcpy,
general whole-struct Value. STRUCT-COPY-1 adds dedicated concrete storage copy
contexts; STRUCT-ABI-1 adds [concrete native value boundaries](struct-values.md).

## Generic functions and capabilities

```astra
T first<T,U>(T a, U b) {
	Pair<T,U> p = { first = a, second = b };
	return p.first;
}

T min_pair<T>(T a, T b) where T : Ordered {
	Pair<T,T> p = { first = a, second = b };
	if (p.first < p.second) { return p.first; }
	return p.second;
}
```

Ordered authority belongs to T and survives the field projection. Pair<T,T>
itself gains no Ordered capability. Existing property, method and concrete
owned/borrowed object or resource operations may coexist with these locals. T
remains non-owning. Ordinary methods and property accessors can also declare
fully concrete generic struct locals.

## Concrete storage and pointers

Fully concrete applications materialize on demand into ordinary CoreStructs
before CFG. Unused valid definitions create no concrete struct or LLVM layout.
Repeated requests from roots, generic functions and nested structs share one
instance. A generic declaration itself has no size, alignment or physical type.

Concrete locals retain ordinary recursive leaf promotion. Box<int>, Box<f64>,
Box<i16<8>> and Bundle<f64> do not require aggregate memory solely because of their
origin. Vector fields retain one whole-vector value. Taking `&b` gives the one
selected root ordinary concrete memory storage; another same-type local may
remain scalarized.

```astra
Pair<int,f64> p = { first = 42, second = 3.5 };
Pair<int,f64>* pp = &p;
pp->first = 7;
```

Concrete generic Struct* uses existing nullable TypedPointerType semantics,
alias coherence, lexical lifetime checks, arrow access and null traps. Nested
`bundle_ptr->pair.first` follows the same recursive storage path. int/i32 pointer
applications canonicalize, while signed/unsigned pointees remain distinct.
Parameterized Pair<T,U>* and address-taking of a parameterized aggregate remain
deferred. Concrete Struct* parameters use one NABI PTR channel regardless of their
field types. No pointer result/lifetime rule, CABI/VAPI aggregate contract, ABI
profile or runtime metadata is added.

## Recursive layouts

Direct, mutual, argument-permuting and constant-collapsing by-value layout cycles
reject when a concrete instance is requested. For example:

```text
recursive generic struct layout: Flip<int,f64> → Flip<f64,int> → Flip<int,f64>
```

Function recursion can reuse an in-progress callable signature; struct re-entry
would require infinite storage and rejects. Cycle detection uses exact Core keys,
without backend layout. GEN-COPY-1 admits constructed arguments and bounds
completion at 1,024 combined instances and 256 active struct dependencies; plain-copy
application proofs have depth 256. Growing requests fail deterministically before CFG.

See [ADR 0059](../decisions/0059-generic-native-structs.md),
[IR](../ir/generic-structs.md), and qualification.

## Ownership transport boundary

Ownable remains separate from the expanded plain-copy domain. `Box<T>` rejects when T
requires Ownable because it does not carry GEN1_PLAIN_COPY. An owning parameter T
can coexist with a separate plain-copy U in Box<U>, or with concrete Box<int>.
A concrete generic struct instance is not Ownable. Owned generic fields and public
Copy/Move capabilities require separate designs. See [generic ownership](generic-ownership.md).

## Concrete whole copy

[Whole copy](struct-copy.md) uses the ordinary recursive rule for materialized
`Box<int>`, `Box<f64>`, `Box<i16<8>>` and `Bundle<f64>` storage. `Box<int>` and
`Box<i32>` share exact identity. Signed/unsigned, phantom and cross-definition
instances remain nominally distinct. Generic origin has no effect on copyability.
The source remains usable, all leaves snapshot before writes, and copy does not
force memory. A generic function may copy an unrelated concrete type in its body;
parameterized `Box<T>` copy is admitted under exact scoped plain-copy premises.
GEN1_PLAIN_COPY also admits eligible aggregate arguments, including
`identity<Box<int>>`. No source Copy/Move is introduced; Ownable remains distinct. Whole copy alone selects no newer ABI
profile. Concrete native boundaries use [aggregate-v7](../abi/native-aggregates-v7.md).

## Multi-source composition

Generic struct definitions and their canonical concrete instances are global to
the [source set](source-files.md). Two files demanding `Box<f64>` share one exact
materialization. Cross-file recursive layouts retain the existing MATERIALIZING
cycle rejection. Files neither namespace types nor permit partial declarations.
