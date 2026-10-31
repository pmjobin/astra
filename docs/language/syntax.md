# Current Astra syntax guide

This guide covers the delivered synchronous surface through OWN-SWAP-1. Use the
[capability matrix](capabilities.md) for exact domains and restrictions and the
[roadmap](../vision-and-roadmap.md) for Planned/Candidate work. Syntax acceptance
is distinct from semantic validity and executable entry requirements.
The current [parser](../../bootstrap/syntax/parser.vala),
[tokens](../../bootstrap/syntax/token.vala) and [lexer](../../bootstrap/syntax/lexer.vala)
are the syntax authority; applicable linked decisions settle meaning.
Grammar displays below are selected fragments, not an exhaustive grammar.
Code examples without an entry function are declaration/context fragments.

Later delivered forms are specified in the bounded guides for
[objects](objects.md), [methods](methods.md), [computed properties](properties.md),
[generic functions](generic-functions.md), [generic records](generic-structs.md),
[text](text.md), [owned arrays](owned-runtime-arrays.md),
[fatal allocation actions](allocation-failure.md), [caller information](caller-information.md)
and [buffer exchange](owned-buffer-exchange.md). These links do not promise
every C#/Vala construct or future spelling.

CONST-1 reserves lowercase `const` and admits `const NAME = expression;` and
`const Type NAME = expression;` at native top level and in local statement
position. Both require one name, an initializer and semicolon, without `var` or
ownership qualifiers. Ordinary TypeSyntax is checked against the scalar constant
type matrix. Fixed-array `T[expression]` extents now use expression syntax;
empty `[]` and literal vector lanes are unchanged. Parsing performs no lookup or
evaluation. See [constants](constants.md) and [ADR 0072](../decisions/0072-compile-time-constants.md).

SLICE-1 adds `SliceTypeSyntax`: `element-type "[" "]"` is distinct from
the fixed-array suffix. Reserved `slice` and `len` forms retain ordinary
expression operands in syntax; checking gives them bounded borrowing and length
semantics. Slice indexing accepts any slice expression and produces a writable
Place. Standalone braced blocks use the existing lexical region rules.
See [slices](slices.md) for exact types, effects, lifetimes and exclusions.

ARRAY-1 adds `ArrayTypeSyntax`, declaration-only `ArrayInitializerSyntax`,
`IndexExpressionSyntax` and `IndexedAssignmentSyntax`. Type position accepts
`element-type "[" length "]"`; CONST-1 extends length to a scalar constant
expression, bounded to integer 1..1024 by checking. `i16<8>[4]` composes vector element shape
with array length. Statement parsing distinguishes a bracketed type followed by
a declaration name from a bracketed assignment target. Postfix brackets now
parse expressions; exact checked type decides array/slice Place versus vector Value.
The legacy literal-bracket syntax node/dump spelling is retained for golden
stability and is not storage authority. Lane assignment/dynamic-vector indexing
now reject at checking. See [arrays](arrays.md) for supported elements and limits.

BIT-1 adds binary `& | ^ << >>` and unary `~`. Maximal munch keeps `&&`/`||`
and recognizes `<<`/`>>`; unary `&identifier` keeps its existing address grammar.
Shifts parse as binary syntax but receive dedicated checked nodes for independently
typed scalar counts. See [bitwise semantics](bitwise.md) for the type/count rules.
Nested generic closers use contextual `>>` splitting while consuming type closes;
ordinary expression shifts retain their token. See
[generic functions](generic-functions.md) and the current
[parser type-close operation](../../bootstrap/syntax/parser.vala).

VEC-LANE-1 adds reserved `splat`/`insert`/`shuffle`/`select` special forms and
postfix constant extraction, with `[` and `]` tokens. `VectorPrimitiveExpressionSyntax`
retains runtime operands separately from ordinal tokens;
`VectorExtractExpressionSyntax` accepts any expression base. No writable lane
semantics or dynamic vector indexing is added. See [vector lanes](vector-lanes.md).

VEC-1 adds dedicated `VectorTypeSyntax`, positional direct-local initialization,
and `VectorReductionExpressionSyntax` for reserved `all`/`any` keywords.
`i16<8>` is a type constructor; expression `a < b` remains a comparison.
One-token lookahead distinguishes named struct fields from positional lanes.
See [vectors](vectors.md) for supported shapes and exact typing.

F32-1 adds `FloatLiteralExpressionSyntax`, preserving token spelling and span.
The [f32 grammar](f32.md#literals) requires digits on both sides of a decimal
point, or an exponent following integer digits. `1e3` is one float token;
`-1.0` is unary minus applied to a float node. `p.x` remains member access.
`.5`, `1.`, hex floats, separators and NaN/infinity keywords remain unsupported.
The delivered f/F and d/D suffixes follow
[floating-literal precision rules](floating-literals.md) and
[ADR 0066](../decisions/0066-explicit-numeric-conversions.md).
The spelling `f32` remains an identifier resolved as a builtin type.

**Pre-release and evolving.** Parsing establishes syntactic structure,
not program validity or executability. The separate
[semantic layer](semantics.md) checks types/names/returns; code generation from
source is available through the separate native execution pipeline.

## Source and lexical rules

Source is UTF-8. The compiler validates the complete byte buffer before lexing;
malformed encoding is diagnosed rather than replaced or reinterpreted. NUL bytes
are explicitly rejected, including inside comments; they never truncate source.
No normalization or byte-order-mark stripping occurs. A UTF-8 BOM outside a
comment is consequently diagnosed as an unsupported non-ASCII character.

Offsets and spans are byte-based, with half-open ranges `[start, end)` in one
source file. Diagnostics display `path:line:column`, using 1-based lines and
Unicode-scalar columns. A tab counts as one column, not an expanded display tab.
LF and CRLF each advance one line; standalone CR is also a line break. EOF has
a zero-width span at the byte length of the source.

Whitespace is ASCII space, horizontal tab, vertical tab, form feed, LF, and CR.
Comments are `//` through the next line ending or EOF, and `/*` through the next
`*/`. Block comments do not nest. An unterminated block comment points at its
opening `/*`. Valid non-ASCII text is allowed in comments. Elsewhere, characters
outside the current ASCII token grammar receive a lexical diagnostic.

| Token | Spelling |
| --- | --- |
| Identifier | `[A-Za-z_][A-Za-z0-9_]*`, except the keywords below |
| Decimal integer literal | `[0-9]+` |
| Decimal floating literal | `[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?[fFdD]?` or `[0-9]+[eE][+-]?[0-9]+[fFdD]?` |
| Keywords | `const` `var` `owned` `move` `release` `swap` `borrowed` `struct` `class` `this` `new` `extern` `export` `return` `true` `false` `null` `if` `else` `while` `break` `continue` `all` `any` `splat` `insert` `shuffle` `select` `slice` `len` `as`; DSP forms `dot_wrap` `mac_wrap` `dot_f32` `mac_f32` `sat_add` `sat_sub` `widen_low` `widen_high` `pack_wrap` `pack_sat` `interleave_low` `interleave_high` |
| Delimiters | `(` `)` `{` `}` `[` `]` `,` `:` `;` `.` |
| Operators and assignment punctuation | `+` `-` `!` `*` `/` `%` `<` `<=` `>` `>=` `==` `!=` `&` `\|` `^` `~` `<<` `>>` `&&` `\|\|` `->` `=` |
| EOF | End of the complete byte buffer |

`i8`, `u8`, `i16`, `u16`, `i32`, `u32`, `int`, `f32`, `f64`, `bool`, `void`, and other type spellings are
identifiers. **Unicode identifier policy remains open**; the present ASCII subset
is not a permanent language decision. Decimal literals retain their exact
spelling, including leading zeroes and arbitrarily long digit sequences within
the input-size limit. The lexer/parser assigns no width, signedness, range, or
value. There is no integer literal suffix syntax; floating suffixes retain the
[existing precision rules](floating-literals.md). Semantic analysis separately enforces
[contextual integer representability](integers.md): leading zeroes remain decimal.
Integer literals default to int without stronger integer context; u32 context admits
4294967295. Direct unary minus may form the signed minimum of the expected
width, including `i8 x = -((128));`. `int` and `i32` are one semantic type;
syntax preserves each written identifier. `uint` is not a builtin alias. Signs and
parentheses remain separate syntax nodes even when checked semantics forms one
signed constant. Huge integer literals still parse and dump exactly; every semantic
CLI mode rejects an out-of-range integer magnitude before constructing downstream IR.

## Declarations and statements

The selected grammar below shows ordinary declarations and control flow.
Class/member/generic, inferred local, text and allocation forms use the linked
guides above; this display is not their exclusion list. It follows
[parser declarations and statement dispatch](../../bootstrap/syntax/parser.vala).

```text
compilation-unit     := (constant-declaration | struct-declaration | function-declaration | foreign-function-declaration | exported-function-definition)* EOF
constant-declaration := "const" type-name? identifier "=" expression ";"
struct-declaration   := "struct" identifier "{" struct-field-declaration+ "}"
struct-field-declaration := type-name identifier ";"
function-declaration := type-name identifier "(" parameter-list? ")" block
foreign-function-declaration := "extern" "(" identifier ")" type-name identifier "(" parameter-list? ")" ";"
exported-function-definition := "export" "(" identifier ")" function-declaration
type-name            := identifier ("*")? | vector-type ("*")? | array-type | slice-type
array-type           := array-element-type "[" expression "]"
array-element-type   := concrete-numeric-element | eligible-record-type
slice-type           := supported-slice-element "[" "]"
vector-type          := vector-element "<" decimal-integer-literal ">"
vector-element       := "i8" | "u8" | "i16" | "u16" | "i32" | "int" | "u32" | "f32" | "bool"
parameter-list       := parameter ("," parameter)*
parameter            := caller-information? ("borrowed" | "owned")? type-name identifier
caller-information   := "[" "CallerFilePath" "]"
                      | "[" "CallerLineNumber" "]"
                      | "[" "CallerArgumentExpression" "(" string-literal ")" "]"
block                := "{" statement* "}"
statement            := block | release-statement | swap-statement | return-statement | constant-declaration | local-declaration | assignment | indexed-assignment | if-statement | while-statement | break-statement | continue-statement | call-statement
if-statement         := "if" "(" expression ")" block ("else" block)?
while-statement      := "while" "(" expression ")" block
break-statement      := "break" ";"
continue-statement   := "continue" ";"
release-statement    := "release" identifier ";"
swap-statement       := "swap" "(" expression "," expression ")" ";"
return-statement     := "return" expression? ";"
local-declaration    := ordinary-local-declaration | owned-local-declaration
ordinary-local-declaration := type-name identifier "=" local-initializer ";"
owned-local-declaration := "owned" type-name identifier "=" owned-initializer ";"
owned-initializer    := expression | move-expression
move-expression      := "move" identifier
local-initializer    := expression | struct-initializer | vector-initializer | array-initializer
array-initializer    := "{" expression ("," expression)* "}"  # exactly N, declaration-only
vector-initializer   := "{" expression ("," expression)* "}"
vector-reduction-expression := ("all" | "any") "(" expression ")"
splat-expression     := "splat" "(" expression "," lane-count ")"
conversion-expression := expression "as" type-name
index-expression     := expression "[" expression "]"  # highest-precedence postfix
indexed-assignment   := index-expression "=" expression ";"
slice-expression     := "slice" "(" identifier ("," expression "," expression)? ")"
length-expression    := "len" "(" expression ")"
# Checking: array base must be a direct local; slice base may be any SliceType expression.
# Vector index must be a literal lane-index; the resulting Value is not writable.
insert-expression    := "insert" "(" expression "," lane-index "," expression ")"
shuffle-expression   := "shuffle" "(" expression ("," lane-index)* ")"  # exactly N selectors
select-expression    := "select" "(" expression "," expression "," expression ")"
lane-count           := unsuffixed-positive-decimal-integer-literal
lane-index           := unsuffixed-non-negative-decimal-integer-literal
struct-initializer   := "{" field-initializer ("," field-initializer)* "}"
field-initializer    := identifier "=" expression
field-access         := supported-place "." identifier
indirect-field-access := identifier "->" identifier  # may extend through eligible record fields
address-expression   := "&" identifier
assignment           := (identifier | field-access | indirect-field-access) "=" expression ";"
call-statement       := call-expression ";"
call-expression      := identifier "(" argument-list? ")"
argument-list        := expression ("," expression)*
```

Struct declarations are top-level only, without a closing semicolon. The parser
retains empty declarations for semantic rejection. Struct initializers have at
least one named entry and no trailing comma; they are contextual local syntax,
not general expressions. Nested record initializers and bounded copied/call-result
entries follow [record copy](struct-copy.md) and
[generic copyable values](generic-copyable-values.md), under
[ADR 0078](../decisions/0078-generic-copyable-values.md).
Supported array/slice elements follow [arrays](arrays.md),
[record collections](struct-elements.md) and the distinct readonly
[string[] contract](process-arguments.md).

Exact lowercase native `swap` is reserved for
[owned buffer exchange](owned-buffer-exchange.md). Its two normally parsed
operands must designate eligible initialized owner storage. It has no expression
value and synthesizes no caller information. Other case spellings, foreign cname
strings and the independent VAPI grammar are unchanged. `swap_elements` remains an
ordinary library function.

An empty file, empty block, or bare `return;` is accepted. Parameter lists have
no trailing comma. Foreign declarations require explicit `extern(C)` and a
semicolon, and reject bodies. Native definitions still require a block;
`int f();` is invalid. The ABI name stays an identifier; semantic analysis
requires exactly `C`. `export(C)` prefixes a native definition and requires its
body; it cannot combine with `extern(C)` in either order. See
[C exports](c-exports.md). A standalone braced block introduces a lexical region
and cleanup scope, using the same lifetime rules as conditional and loop bodies.
Both conditional arms require braces. `else if` has no special grammar; use
`else { if (...) { ... } }`. Branch and while bodies may contain nested
conditionals and loops. While requires both parentheses and a braced body.
Break and continue are statements with mandatory semicolons and no operands.
They parse outside loops; [semantic loop-control rules](loop-control.md) reject
that usage. Labels, numeric/multi-level targets, and expression forms are unsupported.
Every local declaration requires an initializer: `int x;` is invalid syntax.
After an initial identifier, another identifier or a type star selects a local declaration;
`=` selects a local assignment; `.` or `->` selects a field assignment; `(` selects a direct call statement. Type names
remain ordinary identifiers, so unknown local types parse and are rejected
by semantic analysis.

Assignment is a statement, not an expression. `=` has no expression binding
power. `return x = 3;`, `a = b = 4;`, and `int a = b = 4;` are rejected. There
are no arbitrary expression statements, compound assignments, or increments.
INFER-1 adds the reserved local grammar `var identifier = initializer;`.
The initializer is mandatory and no explicit type may accompany `var`.
`var` cannot name an identifier/type or infer a field, parameter, property,
function result or foreign declaration. Parsing never consults type names.
See [local inference](local-inference.md). No `let`, `mut`, `final`
semantics or `:=` declaration grammar is introduced.

```astra
int add(int a, int b) {
	int result = a + b;
	result = result * 2;
	return result;
}

void noop() {
	return;
}
```

## Expressions

Primaries include direct identifier calls, decimal integer/floating and text
literals, `true`, `false`, `null`, identifiers, supported field/member forms,
vector/slice/length forms, bounded array allocations, typed-pointer dereferences,
narrow `"&" identifier` addresses and parentheses. Exact admissibility follows
the [parser](../../bootstrap/syntax/parser.vala) and bounded guides above.
Bool remains a semantic type name, not a keyword.
Parentheses remain explicit syntax nodes. Prefix operators bind more tightly than
infix operators. The parser uses these binding powers:

| Form | Operators | Binding power | Grouping |
| --- | --- | --- | --- |
| Field access | supported Place/member path | Primary/postfix, above prefix | Exact record/Class/indexed receiver rules; [nested fields](nested-struct-fields.md) |
| Indirect field | `identifier->identifier` | Primary, above prefix | Typed struct pointer base; eligible recursive field paths |
| Address borrow | `&identifier` | Primary, above prefix | Bounded direct-local native borrow; [typed data pointers](typed-data-pointers.md) |
| Mask reduction | `all(expression)`, `any(expression)` | Primary, above prefix | bool<N> operand, scalar bool result |
| Vector primitives | `splat(...)`, `insert(...)`, `shuffle(...)`, `select(...)` | Primary, above prefix | Reserved value forms with ordinary operand order |
| Bounded view / length | `slice(...)`, `len(...)` | Primary, above prefix | Explicit array borrowing; array/slice length |
| Storage indexing | `expression[index]` | Postfix, above prefix | Array local or slice expression, checked mutable Place |
| Lane extraction | `expression[decimal-index]` | Postfix, above prefix | Any vector value, constant in-range index, never an assignment target |
| Direct call | `identifier(...)`, explicit generic application or supported receiver method | Primary, above prefix | Resolved direct target; no function-value callee |
| Prefix | `+` `-` `!` `~` | 30 | Nested prefixes associate inward |
| Numeric conversion | `expression as type-syntax` | 25 | Left associative; [exact scalar conversion rules](numeric-conversions.md) |
| Infix multiplicative | `*` `/` `%` | 20 | Left associative; RHS power 21 |
| Infix additive | `+` `-` | 10 | Left associative; RHS power 11 |
| Shift | `<<` `>>` | 7 | Left associative; RHS power 8; scalar count |
| Infix relational | `<` `<=` `>` `>=` | 6 | Left associative; RHS power 7 |
| Infix equality | `==` `!=` | 5 | Left associative; RHS power 6 |
| Bitwise/eager AND | `&` | 4 | Left associative; RHS power 5 |
| Bitwise/eager XOR | `^` | 3 | Left associative; RHS power 4 |
| Bitwise/eager OR | `\|` | 2 | Left associative; RHS power 3 |
| Logical AND | `&&` | 1 | Left associative; RHS power 2 |
| Logical OR | `\|\|` | 0 | Left associative; RHS power 1 |

Thus `1 + 2 * 3` has addition at its root and multiplication on its right;
`(1 + 2) * 3` has multiplication at its root with a parenthesized left operand.
`8 / 2 * 3` groups as `(8 / 2) * 3`, and `-x * +2` preserves both prefix operators.
`a + 1 < b * 2` compares sum and product; `a < b == true` groups as
`(a < b) == true`. Maximal token matching distinguishes `=`/`==`, `!`/`!=`,
`<`/`<=`/`<<`, `>`/`>=`/`>>`, `&`/`&&`, `|`/`||`, and `-`/`->`. Equality is never parsed as assignment.

`a > b & c > d` groups as `(a > b) & (c > d)`. Existing relative
operator precedence, including unary and `as`, is unchanged. Shift grammar is
`expression ("<<" | ">>") expression`, at the shift binding level.

## Developer modes and diagnostics

```sh
astrac --parse FILE...
astrac --dump-syntax FILE...
```

Each mode takes one or more file operands and is used separately from other
modes. The filename extension is not checked. `--parse` exits 0 with no output
on success. Each file is parsed independently. `--dump-syntax` preserves the
single-file tree; several files print an escaped source wrapper in canonical
path order, with each tree in its original declaration order. Both modes exit 1
on lexical, syntax, or file-read failure, with a diagnostic on stderr and no
partial dump on stdout. Missing or duplicate normalized source operands exit 2.
`astrac FILE... -o OUTPUT` compiles one host-native executable through the complete
pipeline; executable compilation requires native `int main()` or
`int main(string[] args)`. The latter needs the explicit argument provider;
see [process arguments](process-arguments.md), [source files](source-files.md)
and [driver entry validation](../../bootstrap/main.vala).

The dump is an **internal debugging representation**, not a stable serialization
format. It uses tab indentation, LF line endings, quoted exact token spellings,
and explicit `parenthesized`, `prefix`, and `binary` forms. For example, a return
of `1 + 2 * 3` includes:

```text
(return (binary "+" (integer "1") (binary "*" (integer "2") (integer "3"))))
```

Diagnostics stop at the first encoding or lexer/parser failure. Tokens identify
the smallest offending range; an expected missing token at EOF uses its empty
span. For example:

```text
test.astra:3:1: error: expected ';' after return statement
```

Stage 0 caps expression recursion/tree depth at 256 nodes, including literals,
parentheses, and call nodes, and diagnoses larger trees. This bounds recursive
dumping
and destruction of long left-associative chains. It is a host resource limit,
not a permanent grammar rule. Block nesting is also limited to 256, including
the function body, to bound recursive branch parsing/dumping/destruction. The file reader rejects byte lengths at or above
`INT_MAX`; byte offsets use Vala `int`. No particular input size is guaranteed to
fit the host's available memory.

## Syntactic acceptance and current non-goals

Unknown type names, unknown expression names, duplicate function/parameter names,
`1 / 0`, and literals beyond machine integer widths all parse. The syntax layer
has no name binding, scope or symbol table, type meaning, or constant evaluation.
Parsing does not check return values against return type spellings or infer
control flow. The checked semantic layer assigns meaning separately, and Core
and CFG preserve storage operations. SSA promotes eligible scalar Places.
[Owned foreign locals](ownership.md), nominal Resource owners, owned Class
contracts and owned buffers follow their separate current transfer/producer rules;
see [ownership boundaries](owned-functions.md) and
[buffer ownership](owned-runtime-arrays.md). Explicit scalar [C imports](c-interop.md)
have semantic signature checking and a separate CABI physical authority; NABI
remains native-only. LLVM consumes both downstream.

Current restrictions include uninitialized locals, assignment/arbitrary expression
statements, labeled/multi-level loop transfers, for/foreach/do loops, callable-value
indirect calls, general rvalue-member projection, pointer casts, bitcasts,
conditional expressions, async, module imports and explicit hardware intrinsics.
Supported standalone blocks, indexing, scalar numeric casts, objects, computed
properties and generics are described by their bounded guides and
[current matrix](capabilities.md). The
[parser dispatch](../../bootstrap/syntax/parser.vala) and
[token surface](../../bootstrap/syntax/token.vala) delimit current syntax; future
async/control/readability work is [Planned or Candidate](../vision-and-roadmap.md).

Direct-call arguments have no trailing comma. `f(1, g())` is valid syntax;
`(f)()`, `f()()`, and expression callees are not. Resolved direct function and
supported method calls can be statements; `f() + 1;` is invalid. See [calls](calls.md) for
function authority, exact positional arguments, and evaluation order.

Logical pairs use maximal matching. Single `&` has the narrow prefix address form
and the eager binary bitwise/boolean form; single `|` is also eager binary syntax.
See [bitwise operations](bitwise.md),
[ADR 0042](../decisions/0042-bitwise-and-shift-semantics.md) and
[lexer matching](../../bootstrap/syntax/lexer.vala).
`a || b && c` groups as `a || (b && c)` and `a == b && c != d || e` as
`((a == b) && (c != d)) || e`. ShortCircuitExpressionSyntax and the `short-circuit`
dump form remain separate from eager BinaryExpressionSyntax. See
[short-circuit expressions](short-circuit.md).


## External declaration syntax

`--vapi PATH` supplies a separate [VAPI declaration file](vapi.md), parsed by its
own handwritten frontend. It implicitly describes C imports and never adds
nodes to the Astra syntax tree. Astra source still requires `extern(C)` for
imports; VAPI files reject that redundant syntax and all exports/bodies. Syntax-only
`--parse` and `--dump-syntax` accept multiple source files but cannot use `--vapi`,
as enforced by [the driver](../../bootstrap/main.vala). The VAPI
grammar and UTF-8/comment policy are [specified separately](../vapi/vapi-scalar-v0.md).

## Current native pointer syntax

The optional type star precedes the declaration name. `void*`, `void *`, and
`void    *` are equivalent; ordinary comments may also separate the tokens.
Native/extern/export return types, parameters, and initialized locals use this
same type syntax. There are no declarators attached after names or C complex
function-pointer declarators. Source `null` is a primary expression keyword.

Both independent parsers retain a sequence of extra star tokens for semantic
unsupported-depth diagnostics. Thus parse-only inspection can show `int*` or
`void**`, but current native typed pointers also support the qualified scalar,
numeric-vector and record pointees listed in
[typed data pointers](typed-data-pointers.md). Extra pointer depth still rejects.
Prefix `*` and direct-local `&identifier` follow those lifetime/Place rules;
general address-of and pointer casts remain excluded. `p->field` has a typed
pointer identifier base and permits eligible nested record paths under
[recursive field rules](nested-struct-fields.md). See
[ADR 0043](../decisions/0043-typed-data-pointers.md),
[typed struct pointers](typed-struct-pointers.md) and the
[source type predicates](../../bootstrap/semantic/types.vala).

## Owned local qualifier

`owned` may qualify supported local, parameter, result and class-field contracts.
The concrete void*/Resource, Class and array domains have different permitted
producers and transfer rules. See [nominal Resources](resource-handles.md),
[owned Class bindings](object-ownership.md), [owned results](object-results.md),
[owned arrays](owned-runtime-arrays.md) and [generic ownership](generic-ownership.md).
Move is not an ordinary copyable expression; named moves use the bounded
consuming positions in [owned boundaries](owned-functions.md).
The [parser](../../bootstrap/syntax/parser.vala) and
[semantic signature/field checks](../../bootstrap/semantic/analyzer.vala) retain the
exact accepted domains, even where a diagnostic still quotes an older milestone.

`borrowed` is parameter-only. Plain eligible native Resource/Class/slice
parameters already resolve to bounded noescape borrowing; explicit qualifiers
follow [default parameter borrowing](parameter-borrowing.md) and
[ADR 0068](../decisions/0068-default-parameter-borrowing.md).
Raw void* remains unmanaged unless its explicit supported contract says otherwise.

`release` is a keyword used only by `release identifier;`. It is not an expression,
call or producer-result consumer. [Release semantics](release.md) and
[buffer release](owned-runtime-arrays.md) require eligible definitely owned
named storage. This does not permit Class release or explicit field release;
see [Class borrowing limits](parameter-borrowing.md).

`as` follows the delivered [explicit numeric conversion](numeric-conversions.md)
contract, under [ADR 0066](../decisions/0066-explicit-numeric-conversions.md).
A complete `<decimal>` suffix in a cast destination is a vector type; otherwise
`<` remains comparison. `*` followed by an expression starter is multiplication;
a terminal `*` remains pointer type syntax for rejection. Unary operators bind
before conversion, so `-1 as u8` converts the already-typed negative int.
