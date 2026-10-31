# Fixed-lane short vectors and masks

All supported numeric vectors and bool masks are admitted
[generic-function arguments](generic-functions.md). `identity<i16<8>>(value)`
uses contextual `>>` splitting for the two type closes, while ordinary shifts
retain their meaning. Signed and unsigned vector identities produce distinct
instances. Whole-vector transport/SSA/NABI remains unchanged. Type constructors
involving T and const generics are deferred; existing F64 exclusions remain.

[SLICE-1](slices.md) also supports every numeric VectorType as a slice element.
`i16<8>[]` borrows whole vector objects. `view[i]` is a writable SliceElementPlace;
`view[i][2]` is a whole-vector Load then a non-writable VectorExtractValue.
Use `view[i] = insert(view[i],2,x)` for updates. Slice ranges count vector objects,
not lanes. No LanePlace or bool-vector slice is introduced.

[ARRAY-1](arrays.md) permits every numeric VectorType as an array element:
`i16<8>[4]` contains four whole i16<8> objects. `blocks[i]` is a writable
whole-vector Place; reading it yields one whole-vector Value. `blocks[i][k]`
loads the vector then extracts a constant lane Value, and cannot be assigned.
Use `blocks[i] = insert(blocks[i],k,x)` for whole-vector read/modify/write.
VEC-MEM adds no LanePlace, bool-vector array or pointer decay. STRUCT-AGG-1
subsequently permits supported vector fields in native structs.

DPTR-1's [scalar typed pointers](typed-data-pointers.md) can carry scalar input or
output for vector computation: `*out = dot(a,b)` uses f32* with vector-v4
arguments and existing PTR transport; dot_wrap can likewise write an exact
integer pointee. [VEC-MEM-1](vector-memory.md) admits numeric VectorType* and
`&vector_local` through the same TypedPointerType and
[DereferencePlace hierarchy](../ir/dereference-places.md). `*p` loads/stores one
whole vector; `(*p)[k]` remains value extraction. Only address-taken locals cease
promotion. Bool-vector pointers and writable lanes remain unsupported.

[BIT-1](bitwise.md) adds same-VectorType integer `& | ^ ~`, eager bool<N>
`& | ^`, and integer-vector shifts with one scalar IntegerType count. Every lane
reuses the exact scalar authority. Validate the count once against element width,
not vector width, before producing a result. Invalid counts trap; per-lane counts
reject. `!` remains mask complement, `&&`/`||` reject masks. Composed comparison
masks feed select; bit/shift results feed shuffle, DSP and dot/MAC without type,
ownership, memory or ABI changes. Each operation remains one whole SSA value.

[Whole-vector dot/MAC](vector-dot.md) returns one scalar from two exact same
vectors: integer wrapping `dot_wrap`/`mac_wrap` or ordered non-fused f32
`dot`/`mac`. Vectors remain whole semantic/SSA operands. Backend-private widened
vectors do not enlarge the legal source shapes below.

[Vector DSP special forms](vector-dsp.md) now add integer saturation,
half-vector widening, wrapping/saturating packing and fixed low/high interleave.
They use existing VectorType shapes and remain whole semantic/SSA values.
Saturation and conversion use scalar integer authorities; interleave supports
integer, f32 and bool lanes with no arithmetic. Numeric vector memory composes through [ordinary typed pointers](vector-memory.md).

A vector is one trivially copyable value containing a fixed number of exact
scalar elements. It supports arithmetic as a unit and retains its complete
shape through assignment, function calls, and control-flow merges. It is not
an array or addressable sequence and does not promise a hardware SIMD register
or one machine instruction per operation.

## Types and supported shapes

```text
vector-type       := vector-element "<" lane-count ">"
vector-element    := "i8" | "u8" | "i16" | "u16" | "i32" | "int" | "u32" | "f32" | "bool"
lane-count        := decimal-integer-literal
```

The lane literal is positive decimal, with optional leading zeroes. It is not
an expression, named constant, or generic const parameter. Spaces/comments may
separate tokens as usual. This constructor is used in type positions; expression
`a < b` remains a comparison. `all`, `any`, `splat`, `insert`, `shuffle`, and
`select` are reserved expression keywords.

| Element | VEC-1 lane counts |
| --- | --- |
| i8, u8 | 2, 4, 8, 16 |
| i16, u16 | 2, 4, 8 |
| int/i32, u32, f32 | 2, 4 |
| bool | 2, 4, 8, 16 |

Numeric payloads are currently bounded to 128 bits. This is a milestone
qualification limit, not a permanent maximum or hardware-width guarantee.
Masks have one semantic bool per lane; no packed bit/byte storage width is
specified. Void, pointers, Resource handles, structs, nested vectors, and
unsupported counts/payloads reject deterministically.

VectorType identity is the exact scalar element identity plus the exact count:
`i16<4> != i16<8>`, `i16<4> != u16<4>`, and `int<4> == i32<4>`.
Canonical dumps use `int<N>`, while syntax dumps preserve the written spelling.
Vectors have no ownership contract. Assignment copies the whole value.

## Contextual local initialization

```text
vector-initializer := "{" expression ("," expression)* "}"
local-declaration  := vector-type identifier "=" vector-initializer ";"
```

Exactly N lanes are required; empty lists and trailing commas are unsupported.
Each expression must have the exact element type. Integer literals receive
integer element context, including signed minima and exact unsigned ranges.
F32 elements require f32 expressions: `1` is not implicitly converted to `1.0`.

```astra
u8<4> bytes = {0, 1, 254, 255};
f32<4> floats = {0.0, 1.0, -0.0, 3.14159265};
bool<4> mask = {true, false, true, false};
u8<4> copy = bytes;
copy = bytes;
```

Lane expressions evaluate left-to-right, exactly once, including calls, reads,
short-circuit expressions, and traps. The local becomes visible only after all
lanes finish. `{record(1), record(2), record(3), record(4)}` records **1234**.
A trap in an earlier lane prevents effects in subsequent lanes.

Positional braces require a vector local type. Named `{x = ..., y = ...}` braces
continue to mean struct initialization. VEC-1 supplies no general brace literal:
`return {...}`, `f({...})`, and `v = {...}` reject. Initialize a local first.

## Arithmetic and comparisons

| Element | Arithmetic | Unary | Comparisons and result |
| --- | --- | --- | --- |
| Signed integer | `+ - *` | `+ -` | `== != < <= > >=` → `bool<N>` |
| Unsigned integer | `+ - *` | `+` | `== != < <= > >=` → `bool<N>` |
| f32 | `+ - * /` | `+ -` | `== != < <= > >=` → `bool<N>` |
| bool | none | `!` | `== !=` → `bool<N>` |

Binary operands require exactly the same vector type. Shape changes, element
conversions, scalar broadcast, and splat are never implicit. Thus `v + 1`,
`1 + v`, mixed shape/element arithmetic, and assigning a scalar to a vector
reject. Unsigned unary minus and integer vector division/remainder reject.

Integer operations apply the [existing integer rules](integers.md) per lane:
addition, subtraction, multiplication, and signed negation wrap at element width.
Comparisons preserve element signedness. For example, signed i8 lanes containing
-1 compare below 1, while unsigned u8 lanes containing 255 compare above 1,
even though both use the same eight physical bits.

F32 operations apply [exact F32-1](f32.md) per lane: binary32 nearest/ties-even,
rounding after each operation, signed zero, gradual underflow/subnormals,
infinities, and NaNs. `(a * b) + c` has two rounding points and cannot contract.
There is no reassociation, fast math, FTZ/DAZ permission, or excess precision.
For NaN lanes equality is false, inequality true, and relational comparisons
false. Positive and negative zero compare equal but division observes their signs.
F32-1's foreign floating-environment contract applies unchanged.

## Masks and explicit reductions

```astra
bool<4> less(i16<4> a, i16<4> b) { return a < b; }
bool equal_vectors(i16<4> a, i16<4> b) { return all(a == b); }
bool differ(i16<4> a, i16<4> b) { return any(a != b); }
```

`!mask` inverts every bool lane. Mask equality/inequality is itself lane-wise
and produces another mask. Bool masks do not support relational comparison,
arithmetic, `&&`, or `||`; those last two remain scalar short-circuit operators.

```text
vector-reduction-expression := "all" "(" expression ")"
                             | "any" "(" expression ")"
```

Both forms require `bool<N>` and evaluate their operand once. `all(mask)` returns
scalar true iff every lane is true; `any(mask)` returns true iff at least one is
true. There are no zero-lane vectors. Scalar bool, numeric vectors, and numeric
scalars are invalid operands. No generic builtin-function overloading is involved.

`if (a < b)` rejects because its condition is a mask. `if (all(a < b))` and
`if (any(a != b))` are valid scalar control flow. Mask/vector locals can be
assigned in either branch and carried through loops as whole values.

## Boundaries and future extensions

Native parameters/results use one [vector-v4 channel](../abi/native-vectors-v4.md).
Non-address-taken vector locals remain whole-value promotable Places. Numeric
vector locals may be addressed and loaded/stored through typed pointers; there
is no lane Place. Alignment is guaranteed by construction and numerically owned
by the backend. STRUCT-AGG-1 permits vector struct fields, including bool-vector fields; bool-vector
pointers and arrays remain deferred. C imports/exports and VAPI vectors remain unsupported.

LLVM realizes fixed vectors and may preserve, split, or scalarize them in target
legalization. Default x86-64 Linux execution is qualified; other native vector
target configurations reject pending qualification. [VEC-LANE-1](vector-lanes.md) adds explicit splat, constant
extraction, value insertion, one-source same-shape shuffle and eager mask select.
Splat and shuffle evaluate their source once; select evaluates mask/true/false
in order. Duplicate selectors are allowed. Extraction has no Place or address.

Dynamic/writable indexing, swizzles, two-source/shape-changing shuffle, widening multiply, grouped/mixed/saturating dot, FMA, scalable vectors,
and 256/512-bit families remain unsupported. Concrete VectorTypes are ordinary exact generic-function type arguments, as in
`identity<f32<4>>(value)`. Generic structs such as `Box<T>` remain deferred; no
const-generic system is a prerequisite. [ADR 0037](../decisions/0037-short-vectors.md) freezes this scope.

## Explicit generic capabilities

Every admitted numeric vector and boolean mask remains a GEN1_PLAIN_COPY generic
argument, but satisfies none of Eq, Ordered, Numeric, Bitwise or Shift. Vector
equality returns bool<N>, whereas Eq requires scalar bool; arithmetic operator
sets also differ by element family. Vector capabilities and associated output
types remain deferred. See [generic capabilities](generic-capabilities.md).

## Recursive struct fields

Native struct fields may hold every supported VectorType shape. Nested fields such
as `o.inner.vector` load/store one whole vector; lane reads extract Values and lane
writes remain unsupported. Use `o.inner.vector = insert(o.inner.vector, 2, x)`.
Nesting alone does not force memory. Class vector fields remain rejected.
See [nested fields](nested-struct-fields.md).

## Generic native structs

GEN-STRUCT-1 Box<T> accepts every supported VectorType: 20 numeric shapes and 4 boolean masks. A vector-bearing concrete instance uses the same whole-vector field, leaf SSA and memory semantics as an ordinary struct. Box<i16<8>> and Pair<i16<8>,bool<4>> reuse contextual generic/vector closes without changing expression shifts. No Vector<T>, generic const parameter or LanePlace is introduced. See [generic structs](generic-structs.md).

## Whole struct copy leaves

All 24 accepted numeric and mask vector shapes are [copyable struct
leaves](struct-copy.md). Each field snapshots and stores as one whole VectorType
Value, including in recursively nested and concrete generic structs. Copy never
expands vectors into lane Places. Writable lanes, vector shape policy and vector
ABI remain unchanged; local struct copy adds no aggregate ABI.
