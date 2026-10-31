# Exact named compile-time constants

A `const` declaration gives a name to an exact scalar or immutable text value determined before
executable lowering. It creates no runtime initialization, addressable slot,
owner, cleanup or allocation. Runtime immutable bindings remain undecided.
Ordinary explicitly typed locals and `var` retain their existing behavior.

```astra
const TILE_WIDTH = 8;
const int TILE_HEIGHT = 8;
const PIXELS = TILE_WIDTH * TILE_HEIGHT;
const f64 EPSILON = 1.0000000000000002;
const SCALE = 1.0d / 255.0d;

int example() {
	const u8 BYTE = 255;
	int[TILE_WIDTH] row = {0, 1, 2, 3, 4, 5, 6, 7};
	return row[7] + (BYTE as int);
}
```

## Declarations and types

```ebnf
constant := "const" [type] identifier "=" expression ";"
```

One name, initializer and semicolon are required. `const var`, ownership
qualifiers, multiple declarators and uninitialized declarations reject.

| Position | Support |
| --- | --- |
| Native top level | Whole-program name; forward references across files |
| Local statement, including method/generic bodies | Lexical name, visible after its declaration |
| Member, parameter, result, foreign/exported declaration | Excluded |

| Type | Constant value |
| --- | --- |
| bool | false/true |
| i8/u8/i16/u16/int/i32/u32 | Existing finite-width values; int and i32 are identical |
| f32/f64 | Exact binary32/binary64 bits |
| string | Immutable decoded UTF-8 bytes and explicit byte count |
| Pointer/null, Resource, Class, Slice, Array, Struct, generic Struct, vector/mask, unresolved T | Excluded |

An inferred declaration supplies no destination type: `1` defaults to int, `1.25`
and `1.25f` to f32, and `1.25d` to f64. Explicit declarations use precisely ordinary
initializer context: `const u8 BYTE = 255;` and `const f64 X = 1.0000000000000002;`
are valid. A suffix selects precision before rounding and cannot be overridden by
the declaration. Existing conversions remain explicit.

After definition the type is fixed. `const ONE = 1; u8 x = ONE;` rejects the same
int-to-u8 mismatch as an ordinary typed value. Write `ONE as u8` when that explicit
modulo conversion is intended. Generic call inference observes the fixed semantic
type; neither source spelling, magnitude nor a surrounding expected result type
changes it. Generic bodies may declare concrete constants, but no constant may
depend on unresolved type parameters or execute a generic function.

## Expressions and exact values

| Scalar operands | Accepted operators |
| --- | --- |
| Signed integers | Unary `+ - ~`; binary `+ - * / % & \| ^`; `<< >>`; `== != < <= > >=` |
| Unsigned integers | Same except unary `-` |
| bool | Unary `!`; `& \| ^ == !=`; lazy `&& \|\|` |
| f32/f64 | Unary `+ -`; `+ - * /`; `== != < <= > >=` |

Ordinary exact operand-type rules apply, including independent integer shift-count
types. Parentheses and accepted explicit scalar `as` conversions are allowed.
Integer identity casts remain accepted; float and bool identity casts remain
rejected under the existing conversion rules. No new operators or coercions exist.

Runtime bindings remain nonconstant even if initialized with literals. Reads of
parameters, locals, fields, memory or indices, calls/methods/properties, allocation,
assignment, moves, release, address-taking and dereference are excluded. BASELIB
`min`, `max`, `clamp`, classification and math functions are ordinary functions;
none can initialize a constant. An owned producer cannot initialize `const`.

Every integer operation wraps at its own width before the next operation. Signed
division truncates toward zero; remainder has the dividend's sign. MIN/-1 wraps
to MIN and MIN%-1 is zero. Required zero-divisor and invalid-shift operations
diagnose. Right shift explicitly fills the sign for signed types; the count's
mathematical value must be in 0..width-1.

Floating operations round nearest/ties-even at **each** operation, preserve both
zeros and subnormals, and never fuse or reassociate. Overflow may produce infinity;
zero division and invalid floating arithmetic follow the ordinary IEEE contract,
including valid infinity/NaN results. Newly generated constant arithmetic NaNs use
positive `0x7fc00000` / `0x7ff8000000000000`. Runtime arithmetic still has its existing
NaN payload freedom. Unary sign operations preserve other bits; format conversions
use the existing conversion policy.

Integer-to-floating conversions round nearest/even (all current integers fit f64
exactly). Floating-to-integer conversions truncate toward zero then range-check;
nonfinite or out-of-range evaluated inputs diagnose at the conversion with the
constant context. Integer-to-integer conversions retain modulo destination width.
Outside constant contexts the existing runtime trap behavior is unchanged.

## Static checks and short-circuit values

```astra
const SAFE = false && ((1 / 0) == 0); // false; division is not evaluated
```

Both operands still receive name, type and subset checks. A skipped unknown name,
type error or call rejects. A separate `const BAD = 1 / 0;` rejects even when unused
or referenced only from a skipped operand. All local declarations are checked and
evaluated even after a return or inside a runtime-unreachable branch.

Top-level dependencies include every constant reference, even in a skipped
operand. Thus `const X = false && X;` is a cycle and rejects. Forward acyclic chains
are evaluated once per declaration; references use exact symbol identities and
memoized values. Cycles report the involved declaration locations deterministically.

## Scope, storage and dimensions

Top-level constants share the existing whole native source program; file names
create no namespaces. Canonical normalized source order stabilizes diagnostics,
while CLI input order changes neither lookup nor values. Duplicate constants and
same-name native/imported callables reject. Existing type/member namespaces remain
separate.

Locals follow lexical scope and declaration-before-visibility. Initializers cannot
see their new binding; local forward references, escaping block names and hiding a
visible binding reject. Sibling blocks may independently reuse a local spelling.
Ordinary locals and parameters cannot hide a visible global constant.

Constants are not Places. Assignment, address-taking, release and move reject.
No hidden local/global slot, runtime lookup or public data symbol is emitted.

`T[expression]` admits the same constant expressions, including local/top-level
names, arithmetic and explicit conversions. Every admitted integer type can
provide a dimension with mathematical value 1..1024. Bool, float, zero, negatives,
excessive, nonconstant and trapping dimensions reject. Dimensions resolve before
ArrayType construction; exactly N initializers are still required. Empty `[]`
continues to denote slices. Runtime buffer counts still require int/i32 even if a
value of a different type is named by a constant. Vector lane counts remain literal
syntax; no value parameters or symbolic aggregate dimensions are introduced.

## Migration and exclusions

Exact lowercase `const` is now reserved in native Astra source, like `var`.
`Const` and `CONST` remain ordinary identifiers. No keyword escaping is added;
independent VAPI grammar and foreign C symbol strings are unchanged.

No strings, runtime immutable bindings (`let`, `final`, `readonly`), aggregate or
member constants, enum members, constant parameters/results, exported C objects,
automatic C macros, attributes, const generics, compile-time function execution,
modules or new ownership semantics are implemented.

## TEXT-1 extension

Text constants use literals, references and parentheses: `const NAME="Astra";`
and `const string ALIAS=NAME;`. `NAME.byte_length` and string `==`/`!=` are exact
constant operations; their int/bool results use the same scalar evaluator.
This builtin member does not admit user properties or calls. Embedded zero bytes
participate in full length and content equality. No normalization occurs.

A text byte count may be a 1..1024 array extent. `const EMPTY="";` is legal,
but `int[EMPTY.byte_length]` rejects. Existing skipped-operand checks and dependency
cycles apply across files. String is the only new constant type.

Constant names/bindings still erase before Core. A referenced text value can
require private read-only literal data; it has no exported constant-name symbol,
mutable global, addressable const binding or runtime initializer. Unused text
constants need not emit bytes. Scalar constant erasure is unchanged. See
[text](text.md) and [the tested consumer](../../examples/base/text.astra).
