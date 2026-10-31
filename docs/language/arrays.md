# Fixed local arrays: ARRAY-1

[Struct elements](struct-elements.md) extend this storage model to eligible
concrete records, including concrete generic-origin records. Their complete
positional entries may be bounded struct producers or named field storage
initializers. Whole-array value/boundary exclusions remain unchanged.

[Owned runtime arrays](owned-runtime-arrays.md) use `owned T[]` and `new T[count]`
for dynamic, zero-initialized, uniquely owned storage. They remain distinct from
ARRAY-1 fixed `T[N]` storage. CONST-1 extends the length grammar to bounded
[constant expressions](constants.md); element eligibility, full initialization,
layout and slice construction remain unchanged.

F64-1 adds `f64[N]` under the existing length, initialization and dynamic-index
rules. Elements use ArrayElementPlace<f64> and LLVM `[N x double]` storage,
preserving special values without arithmetic rounding. This does not admit
f64 vector elements or whole-array value/boundary operations.

A fixed array is explicit contiguous local storage. Its mutable elements have
Places; the array itself has no whole-value form. An array is distinct from an
arithmetic vector, a typed pointer, and a bounded borrowed slice.

## Type and declaration grammar

```ebnf
array-type        := array-element-type "[" array-length "]"
array-element-type := integer-type | "f32" | "f64" | numeric-vector-type | eligible-concrete-struct-type
integer-type      := "i8" | "u8" | "i16" | "u16" | "int" | "i32" | "u32"
numeric-vector-type := (integer-type | "f32") "<" decimal-integer-literal ">"
array-length      := constant-expression
array-local       := array-type identifier "=" array-initializer ";"
array-initializer := "{" array-entry ("," array-entry)* "}"
array-entry       := expression | struct-storage-initializer
array-access      := identifier "[" expression "]"
array-assignment  := array-access "=" expression ";"
```

The length is a scalar constant expression, resolved before ArrayType construction.
It may use local or top-level named constants and arithmetic. Every admitted integer
type can supply a mathematical value in 1..1024 inclusive; this is dimension
extraction, not an implicit expression conversion. Bool/float, negative, zero,
excessive, nonconstant and trapping extents reject. The bound limits accidental
automatic storage and is not a permanent Astra maximum. Literal bounds keep their
existing behavior; leading zeros remain decimal. Empty `[]` is still slice syntax.
Runtime `new T[count]` retains BUFFER's int/i32 count requirement.

Canonical `ArrayType(element_type, length)` uses exact element identity and
length. `int[16]` and `i32[16]` share identity. Signed and unsigned elements,
different lengths, and scalar versus vector elements remain distinct.

| Element | Supported vector element shapes |
| --- | --- |
| i8, u8 | `<2>`, `<4>`, `<8>`, `<16>` |
| i16, u16 | `<2>`, `<4>`, `<8>` |
| int/i32, u32 | `<2>`, `<4>` |
| f32 | `<2>`, `<4>` |

Each scalar in the table is also an element type by itself. `i16<8>[4]` means
four i16<8> vector objects, with no new multidimensional vector shape.

```astra
u8[4] bytes = {0, 1, 254, 255};
f32[4] samples = {0.0, 1.0, -0.0, 2.5};
i16<4> a = {1, 2, 3, 4};
i16<4> b = {5, 6, 7, 8};
i16<4>[2] blocks = {a, b};
```

Every local requires exactly N initializers. Each receives the exact element
expected type: integer literals contextualize, while decimal floating literals convert directly to the expected f32/f64 type.
There is no implicit numeric/vector conversion, implicit zero fill, default
initialization, or trailing comma. Vector elements use existing vector
expressions, locals, or splat; nested brace vector expressions are not introduced.

Initializers execute left-to-right, each value captured before the next
expression. The new name is invisible until all initializers finish, so
self-reference rejects. A trap terminates execution under the existing
non-unwinding rules; there is no observable partial array afterward.

## Indexing and effects

An array access must use a direct ArrayType local as its base. Any scalar
IntegerType index is valid: i8, u8, i16, u16, int/i32, or u32. The index is an
ordinal with its exact mathematical integer meaning; it is not converted to the
element type. A valid index satisfies `0 <= index < N`.

Known invalid direct integer constants reject statically, including obvious
negative constants. General compile-time expression evaluation is not required.
Other indices are checked dynamically. Negative, length-equal and larger values
trap before any physical element address or memory access; u32 max does not wrap
or become a negative valid ordinal. There is no unchecked indexing operation.

```astra
int[4] a = {10, 20, 30, 40};
int sum = 0;
int i = 0;
while (i < 4) {
	a[i] = a[i] + 1;
	sum = sum + a[i];
	i = i + 1;
}
```

Reading scalar/vector `a[i]` constructs ArrayElementPlace and loads one exact
element Value. A struct element is an indexed storage Place consumed by the
existing bounded struct snapshot/copy/result machinery.
Writing `a[i] = rhs` evaluates the index once, validates it, evaluates the RHS,
and stores its exact value. A bad LHS suppresses all RHS effects. Explicit
conversions compose normally, such as `bytes[2] = x as u8`.

Short-circuit `i >= 0 && i < 4 && a[i] > 0` skips the access when an earlier
condition fails. Eager `&` evaluates both operands and may trap. The access
retains its built-in bounds contract even under a manual guard; no frontend
flow-sensitive proof removes that authority.

## Vector elements

`vector[k]` remains constant lane extraction into a Value, with no writable
LanePlace. `blocks[i]` is a whole-vector Place. Thus `blocks[i][2]` loads the
whole vector and then extracts lane 2; `blocks[i][2] = x` rejects.

```astra
blocks[i] = insert(blocks[i], 2, replacement);
```

This performs whole-vector read/modify/write. If an effectful index expression
is written twice, it runs twice; no assignment-place memoization is implied.
Store the index in a scalar local to evaluate it once. Loaded elements compose
with bitwise/shift operations, DSP, strict dot/mac and existing scalar/vector
pointer code. Arrays do not grant pointers to their elements.

## Storage and deferred features

All N elements are one contiguous sequence of properly aligned T objects in
ascending index order, independent of target byte endianness. The backend
chooses alignment and physical stride. Astra exposes no byte stride, sizeof,
byte addresses or pointer arithmetic. Arrays stay explicit memory through Astra
SSA; backend SROA or vector legalization does not change that semantic model.

An array identifier alone is not a Value: return, argument passing, copying,
assignment and equality of whole arrays reject. Array parameters/results,
arrays in structs, C/VAPI arrays, `&a`, `&a[i]`, `T[N]*`, pointer indexing,
array decay, `.length` and nested/multidimensional arrays remain
unsupported. [Owned runtime arrays](owned-runtime-arrays.md) use their separate
allocation and ownership operations over SliceType; they are not fixed-array values.

Named fixed arrays also support [copied foreach iteration](iteration.md),
including recursively copyable record elements.

Standalone bool and bool-vector fixed arrays remain outside this local-array
domain; those leaves are supported inside eligible records and owned runtime arrays.
Typed pointer arrays require embedded provenance and Resource arrays require
element ownership/cleanup; those element domains remain deferred. Eligible struct
arrays use bounded storage producers and recursive leaf snapshots without general
aggregate values. [SLICE-1](slices.md) explicitly borrows existing
array storage with `slice(a)` or checked `slice(a,start,count)`. `len(a)` returns
the exact int constant N. Slices carry runtime extent and the backing array
region; their mutation remains coherent with array indexing. Arrays still never
decay, and neither operation turns an array into a whole Value.
