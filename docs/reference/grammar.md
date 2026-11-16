# Grammar and parser boundary

R-GRAMMAR. This grammar summarizes the admitted book forms and identifies the
larger parser inventory separately. Terminals appear in quotes; `?` means
optional, `*` repetition and `|` alternatives. This notation is documentary and
never parses Astra for compilation. Exact syntactic authority remains the
versioned parser, lexer and typed syntax model, authenticated in the rule ledger.
The generated [source inventory](../books/inventory.json) enumerates every live
compiler/library input and syntax family for coverage review.

```text
unit       := profile? namespace? declaration* EOF
profile    := "language" ("astra27b" | "legacy27a") ";"
namespace  := "namespace" qualified-name ";"
declaration := function | record | class | enum | foreign-function
function   := ownership? type name type-parameters? "(" parameters? ")"
              throws-bound? (block | "=>" expression ";")
parameter  := ownership? type name
ownership  := "owned" | "borrowed"
record     := "struct" name "{" field+ "}"
field      := "readonly"? ownership? type name ";"
class      := "class" name "{" (field | init | deinit | method | property)* "}"
enum       := "enum" name "{" variant ("," variant)* ","? "}"
variant    := name ("(" parameters? ")")?
block      := "{" statement* "}"
statement  := block | local | assignment | call ";" | if | while
              | foreach | return | try-catch | throw
local      := ("var" | ownership? type) name "=" initializer ";"
if         := "if" "(" expression ")" block ("else" block)?
while      := "while" "(" expression ")" block
foreach    := "foreach" "(" "var" name "in" expression ")" block
return     := "return" owned-expression? ";"
throw      := "throw" owned-expression ";"
call       := receiver? name type-arguments? "(" arguments? ")"
argument   := (name ":")? owned-expression
record-expr := type "{" name ("=" expression)?
               ("," name ("=" expression)?)* ","? "}"
range      := expression (".." | "..=") expression
lambda     := name "=>" expression
match-expr := "match" "(" expression ")" "{"
              ("case" enum-pattern "=>" owned-expression ";")+ "}"
enum-pattern := qualified-name "(" (name | enum-pattern)
                ("," (name | enum-pattern))* ")" | qualified-name "(" ")"
comprehension := "[" "for" "(" "var" name "in" expression ")"
                 "=>" expression "]"
```

R-PRECEDENCE. The actual Pratt parser assigns these binary powers. Greater
numbers bind more tightly. RHS parsing uses the current power plus one, giving
ordinary binary operators left association. Comparison chains are represented
specially; their current native refusal is documented separately.

| Power | Tokens |
| --- | --- |
| 0 | logical OR |
| 1 | logical AND |
| 2 / 3 / 4 | bitwise OR / XOR / AND |
| 5 | equality and inequality |
| 6 | ordering comparisons |
| 7 | shifts |
| 8 | modern half-open and inclusive range |
| 10 | addition and subtraction |
| 20 | multiplication, division and remainder |
| 25 | as conversion |

Postfix indexing, calls and member selection bind more tightly. Conditional
expressions have a separate low-precedence selection path. Named labels, contextual
`>>` type closing, trailing-comma policies and owned initializers have dedicated
parser routines; this summary does not replace them with a second grammar engine.

## Wider surface and qualification

The parser also represents constants, general `for`, vectors, pointers, foreign
framework policies, async declarations and other historical constructs. Their
presence in the exhaustive syntax-family inventory grants no native execution
promise. [Limits](limits.md) distinguishes directly refused forms from unproven
ones. A complete parser grammar independent of those routines is not presently
qualified; this documentary summary must not be advertised as one. The source
inventory keeps that coverage obligation visible instead of silently counting
all syntax families as proved rules.
