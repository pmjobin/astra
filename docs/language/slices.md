# Bounded borrowed slices

[Record slices](struct-elements.md) add eligible concrete structs to the same canonical SliceType. They remain mutable bounded borrows, distinct from owned transfer and deep read-only string slices. Indexed roots support recursive fields, methods/properties and complete by-value snapshots; no new source address-taking or persistent owner alias follows.

ARGS-1 adds a read-only descriptor subset for canonical `string[]`: native parameters (plain or explicit `borrowed`), local view copies/rebinding, runtime length, checked reads and forwarding. Both table and payloads are deeply borrowed. Numeric element writes are unchanged. There is no text-array producer, owned text slice, field, subrange or result. See [process arguments](process-arguments.md) and [text-slice IR](../ir/text-slices.md).

PARAM-BORROW-1 preserves plain `T[]` parameter borrowing and slice-v5 exactly,
and extends the same source default to native Resource/Class domains. This does
not make scalar, vector or struct parameters borrows. See
[parameter borrowing](parameter-borrowing.md).

BUFFER-1 adds [owned runtime arrays](owned-runtime-arrays.md) over this same
canonical SliceType. `T[]` parameters now imply the existing borrowed/noescape
contract, and `borrowed T[]` remains accepted. An owning `owned T[]` binding or
field implicitly supplies a bounded view in these contexts. No data is copied,
no cleanup responsibility belongs to the view, and ownership remains separate
from type identity. Persistent owner-derived slice aliases remain rejected.

F64-1 adds `f64[]` using the existing exact SliceType, full/subrange construction,
copy, alias and indexing rules. `borrowed f64[]` uses the unchanged slice-v5
SLICE(PTR,I32) boundary and exact double element loads/stores. Its element type
does not introduce an F64 channel; only a separate by-value f64 parameter/result
selects fp64-v6. F64 vector slices and C/VAPI slice channels remain unsupported.

[Native struct methods](methods.md) accept the same plain or explicit `borrowed T[]`
parameters as free functions. `accumulator.sum(slice(array))` evaluates the
receiver first, then the slice argument. The callee receives one mutable,
non-owning SliceValue with ordinary runtime bounds and lexical noescape rules.
Receiver PTR is a separate first NABI channel; the slice follows as grouped base
PTR and length I32 under existing slice-v5. Overlapping aliases, forwarding,
recursion and owned Resource argument/result integration keep their existing
semantics. No new slice or method ABI profile is added.

A slice is one non-owning, mutable view over contiguous array element storage.
It carries an exact element type, a runtime length, and a lexical lifetime proof.
It is distinct from a fixed array, a typed pointer, and an arithmetic vector.

| Form | Meaning | Index result |
| --- | --- | --- |
| `T[N]` | Owning fixed local storage; no whole-array value | ArrayElementPlace |
| `T[]` | Borrowed bounded view value; runtime extent | SliceElementPlace |
| `T*` | Nullable borrow of one exact object; no extent | Indexing unsupported |
| `T<N>` | Arithmetic value with fixed lanes | VectorExtractValue |

## Grammar and types

```ebnf
slice-type       := slice-element-type "[" "]"
slice-element-type := integer-type | "f32" | "f64" | "bool" | "void*" | numeric-vector-type | mask-type | eligible-concrete-struct-type
integer-type     := "i8" | "u8" | "i16" | "u16" | "int" | "i32" | "u32"
numeric-vector-type := (integer-type | "f32") "<" decimal-integer-literal ">"
mask-type        := "bool" "<" decimal-integer-literal ">"
slice-local      := slice-type identifier "=" expression ";"
slice-parameter  := [ "borrowed" ] slice-type identifier
slice-full       := "slice" "(" array-local-identifier ")"
slice-subrange   := "slice" "(" array-local-identifier "," expression "," expression ")"
length           := "len" "(" (array-local-identifier | slice-expression) ")"
slice-access     := slice-expression "[" expression "]"
slice-assignment := slice-access "=" expression ";"
```

`slice` and `len` are reserved special forms. Supported vector shapes are exactly
the [BUFFER-1 element inventory](owned-runtime-arrays.md): canonical numeric
scalars/vectors, bool/masks and opaque void*. Typed pointers, resources, structs,
arrays and slices remain excluded as elements. Nested slices, slice pointers,
nonowning slice fields and fixed arrays of slices are unsupported. Explicit
`owned T[]` class fields are separate ownership contracts over this type. `int[]` and `i32[]` have the same canonical SliceType.
Different signedness, element types or vector shapes have different identities.
Length is part of the value, never the type.

## Construction, length and empty views

```astra
int[8] storage = {0, 1, 2, 3, 4, 5, 6, 7};
int[] all_elements = slice(storage);
int[] middle = slice(storage, 2, 4);
int[] empty = slice(storage, 8, 0);
int extent = len(middle); // 4
int capacity = len(storage); // 8
```

For explicit `slice(...)` construction, the source must be a direct fixed-array local. `int[] s = storage` rejects;
there is no decay. No pointer-plus-length construction, slice-from-slice,
array expression, or implicit element-address borrowing is available.

Start and count may each be any scalar IntegerType. Using exact mathematical
values, require `0 <= start <= N` and `0 <= count <= N - start`. Evaluate start,
then count, once each, before any validation. An invalid start still allows the
count expression to run before trapping. Proven invalid direct constants reject
statically; other invalid ranges trap before any physical element address forms.

Both `slice(storage,0,0)` and `slice(storage,N,0)` are valid. An empty view has
length zero and valid lifetime provenance, but no valid element index. A slice
has no null state: `int[] s = null` rejects. There is no equality or truthiness;
use `len(s) == 0` to test emptiness. There is no `.length` property.

`len(array)` has no runtime effect. `len(slice-expression)` evaluates the
expression exactly once and returns the captured length. Both return exact
`int`. Fixed-array sources have at most 1024 elements; BUFFER-1 owning sources
accept nonnegative `int` counts through INT_MAX. Sources exceeding INT_MAX
require a future explicit size-type review.
`len` does not accept vectors or pointers.

## Borrowing, copying and aliases

All slice locals require initialization. An exact-type copy/rebinding copies
the view and extent, retaining the same backing storage. Slices have no ownership,
move, release, rearm or cleanup operations. Multiple mutable slices may alias,
including overlapping subranges; writes remain coherent with direct array access.

```astra
int[6] storage = {1, 2, 3, 4, 5, 6};
int[] a = slice(storage, 0, 4);
int[] b = slice(storage, 2, 4);
int[] copy = a;
a[2] = 99; // b[0], copy[2], and storage[2] now read 99
```

Construction borrows the backing array's lexical region. The existing
[BORROW rules](borrowing.md) allow storage in the same region or a descendant;
an inner array cannot supply an outer slice local. Reads of stored slice locals
conservatively advertise that local's region, just like typed-pointer reads.
Consequently copying an inner slice into an outer local rejects even when the
inner slice originally borrowed an outer array. Bare blocks and if/while bodies
use the same lexical rule. Borrowing ensures lifetime safety, not exclusivity.

## Indexing and effects

Any SliceType expression may be indexed, including `slice(a,start,count)[i]`.
The index may be any scalar IntegerType, interpreted mathematically; valid
indices satisfy `0 <= index < len(s)`. Negative, length-equal, larger unsigned,
and all empty-view indices trap. Even a constant index checks runtime extent.

A read evaluates the view, then the index, validates bounds, and loads the exact
element. An assignment evaluates view, index, bounds, RHS, then store. Invalid
bounds suppress the RHS. One access captures one whole view before index effects;
its base and length cannot come from different evaluations.

Slice indexing produces a writable SliceElementPlace. RHS type must match
exactly, with ordinary integer-literal context and explicit `as` conversions
when needed. `i >= 0 && i < len(s) && s[i] > 0` can skip the access;
eager `&` evaluates it and can trap. Every evaluated access retains its own check.

For vector elements, start/count/index count whole vector objects, never lanes
or bytes. `view[i]` loads or stores one whole vector Value. `view[i][2]` loads
the vector then extracts a lane Value. Lane assignment remains invalid; use:

```astra
view[i] = insert(view[i], 2, replacement);
```

The two written index expressions are separate evaluations. Use an index local
when one evaluation is desired. Vector BIT/DSP/dot/mac operations and scalar or
vector typed pointers coexist with slices. No LanePlace, pointer extraction,
`.data`, `&view[i]`, pointer arithmetic, or implicit slice/pointer conversion exists.

## Native borrowed parameters

```astra
int sum(borrowed int[] values) {
	int result = 0;
	int i = 0;
	while (i < len(values)) {
		result = result + values[i];
		i = i + 1;
	}
	return result;
}
```

SLICE-BOUND-1 introduced explicit `borrowed` at a native parameter boundary;
BUFFER-1 also permits plain `T[]` with that same contract.
`sum(slice(a))`, `sum(slice(a,start,count))` and `sum(local_slice)` all pass one
exact SliceValue. Arrays of different extents call the same function with
different runtime lengths. Arrays and pointers never implicitly adapt to slices.
An owned runtime array supplies an implicit bounded view. An `owned int[]`
parameter instead uses the distinct [buffer-v8 ownership boundary](../abi/native-buffer-v8.md).

The callee may read length, mutate elements, make local copies and forward to
compatible borrowed parameters, including recursively. Borrowing is neither
readonly nor exclusive; overlapping mutable parameters are permitted. The caller
retains the view and backing array, without a move, cleanup or ownership change.
The parameter's authority lasts for the function lexical region, and local copies
obey the same lexical rules as other slices. The noescape contract forbids making
the view survive the call.

Arguments evaluate left-to-right. A direct subrange argument evaluates start,
count and validation before the next argument. A failed check prevents later
arguments and the call. The same ordering applies alongside owned arguments;
physical ownership commit remains after all successful argument evaluations.

Borrowed slice results, C/VAPI exposure and exports remain unsupported. A borrowed
result needs an explicit signature lifetime relationship that Astra cannot yet
express. Owned buffer results transfer responsibility under buffer-v8.
[Native slice-v5](../abi/native-slices-v5.md) is a compiler-owned physical
group and provides no stable external ABI promise.
See [ADR 0046](../decisions/0046-bounded-borrowed-slices.md),
[ADR 0047](../decisions/0047-native-borrowed-slices.md),
[slice values](../ir/slice-values.md), and [slice places](../ir/slice-places.md).

GEN-SLICE-1 admits [generic borrowed slice algorithms](generic-slices.md): direct
function T[] formals derive exact mutable element-storage premises. Collections
remain borrowed while plain T parameters/results retain independent value copying.
No concrete element domain or ownership/lifetime rule is enlarged.
