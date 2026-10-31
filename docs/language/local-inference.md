# Local `var` inference

For eligible [record elements](struct-elements.md), `var saved = records[i];` infers the exact nominal struct and takes a complete value snapshot. `var records = new S[count];` infers the existing owned S[] contract. Neither form infers a structural record type or widens generic-function argument eligibility.

`var view = values;` infers exact `string[]` for a text-slice parameter and snapshots its current deep backing origin. `var text = values[index];` infers ordinary borrowed `string`, never a literal/static origin. This does not admit text slices as unconstrained generic arguments or make `len(values)` constant. See [process arguments](process-arguments.md).

`var` means infer once at declaration time. It does not mean dynamic, variant,
any, or changing type. Use it when the initializer already makes the local's
type and ownership responsibility clear:

```astra
var count = 10;
var ratio = 1.25d;
var lab = transform(input);
var samples = new f64[count];
var image = make_image();
var moved = move samples;
```

```ebnf
inferred-local = "var", identifier, "=", initializer, ";" ;
```

The initializer is an existing expression, direct ownership move, or existing
direct class constructor form. It is mandatory: `var count;` reports
`inferred local declaration requires an initializer`. A separate type beside
`var` is invalid. Braces such as `var x = {};` cannot supply their own type and
report `cannot infer local type from this initializer; write an explicit type`.

`var` is reserved, not contextual. Former identifiers named exactly `var` must
be renamed. This intentional compatibility break also forbids a type named
`var`; declaration interpretation never consults type-name lookup. Other
identifiers, including `Var` and `variable`, are unaffected.

## Exact types

The compiler checks the initializer without a declaration target type, then
uses that result unchanged. Inference introduces no implicit conversion.

| Initializer | Inferred type |
|---|---|
| `1` | canonical `int`, identical to `i32` |
| `1.0`, `1.0f`, `1.0F` | `f32` |
| `1.0d`, `1.0D` | `f64` |
| `1.0000000000000002d` | `f64`, exact bits `0x3ff0000000000001` |
| `1.0000000000000002` | `f32`, exact bits `0x3f800000` |
| `count as f64`, `coordinate as int` | `f64`, `int`, respectively |
| `true` | `bool` |
| standalone `null` | `void*`, the existing targetless default |
| existing raw/typed pointer expression | exact pointer type and existing lifetime |
| vector or mask expression | exact element type and lane count |
| copyable struct Place or native result | exact nominal concrete struct type |
| concrete `Box<f64>` producer | that exact generic-origin struct identity |
| `new f64[count]` or an owned `f64[]` result | canonical `f64[]` plus owning buffer contract |

All other existing scalar types infer exactly too. C/VAPI float and double
results are the ordinary Astra f32 and f64 identities. Scalar/value properties,
methods and specialized generic calls use their already-checked result types.
[Generic call inference](generic-inference.md) resolves `identity(42)` to int
before `var` selects the local type. Neither `var` nor an explicit local type
supplies generic arguments. Unresolved `T` is still rejected as an inferred local;
an outer generic body can write `T local = identity(value)`. There is no
cross-declaration inference.

The default for `null` does not imply any guess of Class, Resource or typed
pointer identity. Spell such a destination explicitly. Fixed arrays remain
explicit positional storage because ARRAY-1 supplies no whole-array value
initializer. Borrowed slices can infer from existing legal slice expressions;
their lexical storage and noescape restrictions remain unchanged. Implicit
receiver values (`this`) cannot be stored as ordinary locals.

## Ownership and lifetime

An initializer that already produces one exact ownership responsibility can
initialize an owner without repeating that contract locally:

```astra
owned f64[] explicit_samples = new f64[count];
var inferred_samples = new f64[count];

owned R explicit_handle = open_resource();
var inferred_handle = open_resource();
```

The two forms use the same cleanup, move, release, RAII replacement and lexical
cleanup order. Runtime arrays retain canonical SliceType identity and static
native-buffer-deallocate cleanup. Resource cleanup identity and Class
caller-provided ObjectStorage/result placement are unchanged. Direct class
construction, `var image = Image.init(...);`, creates the existing transferable
owned Class local contract.

Transfer from a named owner remains visible:

```astra
var second = move first;
```

For a Resource or buffer this transfers the exact contract and makes `first`
MOVED. `var second = first;` rejects for ownership-bearing named values. It never
silently creates a stored borrow. Local Class owner moves remain unsupported;
existing explicit transfers through owned parameters/results work normally.
Ordinary non-owning Class references and borrowed slice parameters retain their
existing legal local-copy/lifetime rules. Explicit borrowed Resource/raw-pointer
parameters still cannot be persisted as locals.

Reassignment never changes the inferred type or ownership domain:

```astra
var x = 1;
x = 2;       // ordinary int assignment
x = 2.0f;    // type error
```

Existing name ordering and shadowing rules apply, including rejection of
`var x = x;`. Ordinary nested scopes and loop bodies accept `var`; there is no
new loop grammar or branch-assigned-later inference.

## Reviewability and explicit boundaries

For a CAD body, the explicit locals

```astra
owned f64[] weights = new f64[count];
f64 fw = width as f64;
f64 epsilon = 1.0000000000000002d;
Lab lab = transform(input);
```

can be written as

```astra
var weights = new f64[count];
var fw = width as f64;
var epsilon = 1.0000000000000002d;
var lab = transform(input);
```

Each initializer states a complete type or uses an explicitly typed function
contract. `move` still marks named-owner transfer; persistent borrowed
relationships are never invented. Fields such as `owned f64[] samples;`,
parameters such as `void consume(owned R value)`, and results such as
`owned f64[] make(int count)` remain explicit. A reviewer need not inspect a
function body to learn its API contract. `Lab lab = transform(input);` remains
equally valid when spelling the type improves reviewability.

[CONST-1](constants.md) specifies `const` as an exact named compile-time value.
Its inferred form has the same targetless scalar defaults as `var`, but requires
a bounded constant expression and creates no runtime binding or owner. Runtime
immutable bindings remain undecided. PARAM-BORROW-1 separately
defines [plain native parameter borrowing](parameter-borrowing.md); local inference
does not infer public parameter or result relationships.

## Text views

`var label="ready";` infers the canonical StringType and its static backing origin.
`var copy=parameter;` copies an incoming string borrow without ownership or lifetime
extension. Reassignment changes the descriptor; previously copied views keep their
original backing. Static-result verification follows each write and control-flow
join. This bounded immutable-text exception does not broaden other stored-borrow
rules or generic capability admission. See [text](text.md).
