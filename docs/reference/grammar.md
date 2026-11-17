# Grammar and parser boundary

R-GRAMMAR. Grammar edition 28-A2-R1.1 binds the current lexer, parser and typed
syntax model at source revision `d1eed151d63cf4dbebf2b819872c5cf482b7fc04`.
This is a versioned specification with independently testable productions and
explicit open qualification obligations. It is not yet a claim that every
historical foreign-policy/profile cross-product is a complete qualified grammar.
The original non-narrowed G2 obligation remains in force.

Terminals are quoted. A question mark means optional, star repetition, plus
nonempty repetition and a vertical bar alternatives. These are documentary
productions; only the existing Astra parser parses programs. Contextual and
semantic restrictions below are part of interpreting a production. Syntax
acceptance never supplies type, ownership, runtime or native-emission proof.

## Source and lexical productions

A source is validated UTF-8 bytes with no raw NUL. There is no BOM stripping or
Unicode identifier normalization. ASCII identifiers start with A–Z, a–z or
underscore and continue with those characters or decimal digits. Comments and
text payloads can contain Unicode. Spans are half-open byte offsets into their
retained source. Whitespace is ASCII space or byte 9 through 13.

```text
identifier := (ASCII-letter | "_") (ASCII-letter | digit | "_")*
line-comment := "//" bytes-before-CR-LF-or-EOF
block-comment := "/*" bytes-before-first-closing-marker "*/"
decimal-integer := digit (digit | "_" digit)*
hex-integer := "0" ("x" | "X") hex-digit (hex-digit | "_" hex-digit)*
binary-integer := "0" ("b" | "B") binary-digit (binary-digit | "_" binary-digit)*
exponent := ("e" | "E") ("+" | "-")? digit+
float := digit+ "." digit+ exponent? precision?
       | digit+ exponent precision?
precision := "f" | "F" | "d" | "D"
```

Hex/binary prefixes and integer separators require modern source. Integer
magnitudes must fit u64 at tokenization, then the contextual destination at
checking. Signs remain separate prefix expressions. A leading zero does not
select octal. Integer suffixes, missing prefix digits, adjacent/terminal
separators and floating separators are refused. A floating decimal point needs
a digit after it; this preserves the distinction between 1.0 and 1..end.

Comments do not nest. `///` is comment trivia with documentation association,
not a declaration production. Text uses a double-quoted token and the bounded
[decoder](../../compiler/syntax/text-decoder.astra); decoded NUL is payload, unlike
raw source NUL. Modern interpolation has separately retained fragments and holes,
with no nested interpolation and at most 64 operands. Escaped doubled braces
belong to fragments, not new holes.

The complete reserved token inventory is
[token.astra](../../compiler/syntax/token.astra), and exact keyword classification
is [keyword_kind](../../compiler/syntax/keywords.astra). Many context words,
including language, namespace, using, property, init, deinit, in, where, new,
shared and weak, remain identifier tokens. Recognizing one in its declaration
context does not reserve it globally or introduce an unrestricted annotation
mechanism.

## Units, declarations and types

```text
unit := profile? namespace? using* declaration* EOF
profile := "language" ("astra27b" | "legacy27a") ";"
namespace := "namespace" identifier ";"
using := "using" identifier ";"
qualified-type-name := identifier ("." identifier)?
ownership := "owned" | "borrowed"
function := attributes? ("extern" "(" "C" ")" | "export" "(" "C" ")")?
            "async"? ownership? type identifier type-parameters?
            "(" parameters? ")" throws-bound? where-clause* function-body
function-body := block | ";" | modern-expression-body
modern-expression-body := "=>" expression ";"
parameters := parameter ("," parameter)* modern-trailing-comma?
parameter := caller-information? ownership? type identifier
type-parameters := "<" identifier ("," identifier)* modern-trailing-comma? ">"
type-arguments := "<" type-argument ("," type-argument)* modern-trailing-comma? ">"
where-clause := "where" identifier ":" identifier ("," identifier)*
throws-bound := "throws" type
type := "nonnull"? type-core
type-core := "shared" type | modern-weak-type | qualified-type-name type-arguments? pointer-suffix? array-suffix?
modern-weak-type := "weak" type
pointer-suffix := "*"+
array-suffix := "[" "]" | "[" "slots" "]" | "[" expression "]"
record := "struct" identifier type-parameters? where-clause* "{" record-members "}"
class := class-policies? "class" identifier type-parameters? parent? where-clause* "{" class-members "}"
parent := ":" type
field := visibility? "readonly"? ownership? type identifier ";"
constructor := "init" "(" parameters? ")" throws-bound? base-initializer? block
base-initializer := ":" "base" "(" arguments? ")"
destructor := "deinit" "(" ")" block
enum := "enum" identifier type-parameters? "{" variant ("," variant)* ","? "}"
variant := identifier ("(" parameters? ")")?
```

These core productions describe the source shapes used by the current books.
They do not grant every modifier in every context. A namespace directive is one
identifier, not an arbitrary dotted package path. It precedes usings; directives
precede declarations, and a source profile precedes all of them. A second or
misplaced profile is refused. Each explicit source retains its own profile.

Empty generic lists are refused. Modern source admits the selected trailing
commas; legacy source does not acquire that policy from its caller. A where
clause requires a permitted generic declaration, a unique subject and unique
capabilities. Its capabilities still need the [concrete semantic rules](generics.md).
Only designated Fn/Closure/CheckedClosure type-argument positions accept ownership
channel qualifiers. Repeated nonnull and unsupported nested array/slice/pointer
suffix combinations are refused. A scalar type followed by a literal lane
application has the separate vector representation; it is not a nominal generic.

Properties have permitted get/set bodies, including modern expression bodies.
The actual parser also represents interface, foreign declaration and policy
forms. Their declaration-specific ordering, key sets, accessor restrictions and
native availability must be read with the source consumers. A generic attributes
production cannot make all known policy names legal on every declaration.
This wider policy cross-product remains an explicit grammar qualification duty.

## Statements and initializers

```text
block := "{" statement* "}"
statement := block | local | assignment | call ";" | if | while | foreach
           | for | match-statement | return | break | continue | try-catch
           | throw | release | swap | with | await-statement
local := ("var" | ownership? type) identifier "=" initializer ";"
assignment := destination "=" owned-expression ";"
            | modern-destination compound-operator expression ";"
initializer := expression | record-initializer | array-initializer
record-initializer := "{" field-initializer ("," field-initializer)* modern-trailing-comma? "}"
field-initializer := identifier ("=" owned-expression)?
array-initializer := "{" initializer ("," initializer)* modern-trailing-comma? "}"
if := "if" "(" expression ")" control-body ("else" control-body)?
while := "while" "(" expression ")" control-body
foreach := "foreach" "(" "var" identifier "in" expression ")" block
return := "return" owned-expression? ";"
break := "break" ";"
continue := "continue" ";"
try-catch := "try" block catch-clause+
catch-clause := "catch" "(" type identifier ")" block
throw := "throw" owned-expression? ";"
release := "release" identifier ";"
swap := "swap" "(" destination "," destination ")" ";"
control-body := block | permitted-simple-statement
compound-operator := "+=" | "-=" | "*=" | "/=" | "%=" | "&=" | "|=" | "^=" | "<<=" | ">>="
```

A simple unbraced control body is restricted to return, break, continue,
assignment, field/index/dereference assignment or call. Declarations, nested
control, throw and compound assignment require braces. The formatter asks the
real parser before eliding braces; visual indentation supplies no scope proof.
An initializer is checked before inserting its new binding.

Record field shorthand requires modern nominal record syntax and an actual
same-named value. It is not a permission to omit a required field. Moves retain
their actual source owner; projected moves have context-specific restrictions.
General for, with, release, await and historical control protocols have parser
representations but no blanket current native promise. The concrete native
refusals and supported alternatives remain in [Control](control.md) and
[Limits](limits.md). No finally production is established by try/catch support.

## Expressions, precedence and ambiguity

```text
primary := literal | identifier | "(" expression ")" | call | construction
         | modern-record | modern-match | modern-lambda | modern-comprehension
         | modern-interpolation | modern-move | admitted-historical-primitive
modern-record := type "{" field-initializer ("," field-initializer)* ","? "}"
modern-move := "move" identifier
modern-lambda := identifier "=>" expression
modern-comprehension := "[" "for" "(" "var" identifier "in" expression ")" "=>" expression "]"
call := callable type-arguments? "(" arguments? ")"
arguments := argument ("," argument)* modern-trailing-comma?
argument := (identifier ":")? owned-expression
modern-match := "match" "(" expression ")" "{" expression-arm+ "}"
expression-arm := "case" enum-pattern "=>" owned-expression ";"
enum-pattern := qualified-variant "(" (binding-or-nested-pattern ("," binding-or-nested-pattern)*)? ")"
conditional := expression "?" expression ":" expression
range := expression (".." | "..=") expression
postfix := indexing | member-selection | permitted-receiver-call
```

R-PRECEDENCE. Higher binding power binds more tightly. Ordinary binary RHS
parsing uses the operator power plus one, producing left association. Ordering
chains have a separate representation. Modern conditional selection is parsed
only at minimum power zero; its branches recursively admit conditionals, giving
right-nested selections. Prefix operands use minimum power 30. Calls, indexing
and member operations attach through their source-specific postfix paths.

| Power | Operators |
| --- | --- |
| 0 | logical OR |
| 1 | logical AND |
| 2, 3, 4 | bitwise OR, XOR, AND |
| 5 | ==, != |
| 6 | <, <=, >, >= |
| 7 | <<, >> |
| 8 | modern .. and ..= |
| 10 | +, - |
| 20 | *, /, % |
| 25 | as |
| 30 | prefix operand boundary |

Thus addition belongs inside each range endpoint; a range does not silently
change integer type. In modern source two adjacent dots form a range only when
they are not part of a run of three or more dots. Legacy range-looking spelling
retains separate dot tokens. A decimal point followed by a digit still belongs
to the floating token. The lexer verifies these distinctions before parsing.

Generic-call recognition speculatively parses a nonempty type argument list
followed by a call opener. Modern nested type closure can split >> into two
closing tokens; expression shifts remain shifts. The conversion parser also
uses following expression context to distinguish pointer stars from multiplication.
These are context-sensitive parser decisions, not a license to replace the
compiler with the EBNF notation.

Named labels must be unique and have an operand. Positional arguments may
precede labels but may not follow them. A lambda is selected by identifier =>;
a function expression body uses its declaration context. Enum expression patterns
require parentheses even for zero payloads and a semicolon on every result arm.
A statement match's block arms are a distinct context. A literal index is represented
by VectorExtractExpressionSyntax even for an ordinary array; representation
names alone must not be interpreted as native SIMD support.

## Qualification and the complete representation inventory

The [grammar corpus](../../tests/books/grammar.json) includes 476 explicitly
expected current-parser cases, including all 269 inventoried source units,
book syntax and 125 protected historical syntax goldens. Both actual compiler
host profiles must match the goldens byte for byte. The
[typed consumer](../../tests/books/grammar-consumer.astra) runs the unchanged
production syntax source, observing actual emitted family codes at O0/O2 with
strict returning memory. Its [recipe](../../tests/books/grammar.py) records
missing concrete families; it does not equate inventory presence with a test.

The [inventory](../books/inventory.json) classifies all 100 actual families,
with parser source identities, selected constructor/routine and surface/context
notes. Four abstract bases have no independently emitted source production.
Actual constructor observations, syntactic acceptance, semantic admission and
native execution remain four different evidence levels. In particular constants,
for, comparison chains, vectors, typed-pointer examples and retained views keep
their disclosed native refusals.

Remaining grammar obligations include exact
accepted/rejected boundaries for the foreign-policy and historical profile
cross-products, and independent ambiguity controls beyond the protected corpus.
These obligations cannot be discharged by this catalogue's row count or by a
successful typed-consumer build. See the current [status](../books/STATUS.md).

## Syntax family catalogue

The table classifies source shapes. It is not a runtime-support table. Its
complete identities and open obligations live in the inventory linked above.

| Typed family | Source shape / representation |
| --- | --- |
| AddressOfExpressionSyntax | & named-place |
| ArrayInitializerSyntax | { element initializers } in an array destination |
| ArrayStructInitializerSyntax | record initializer used as an array element |
| ArrayTypeSyntax | type [ constant extent expression ] |
| AssignmentStatementSyntax | named destination = owned initializer ; |
| AsyncRuntimeSyntax | async runtime name throws type returns type [provider text] ; |
| AwaitExpressionSyntax | await operation, or await move named task |
| AwaitStatementSyntax | await expression ; |
| BinaryExpressionSyntax | Pratt binary expression, including modern range operators |
| BlockStatementSyntax | { statement* } lexical region |
| BooleanLiteralExpressionSyntax | true or false |
| BreakStatementSyntax | break ; with separate loop identity |
| BufferAllocationSyntax | new/try_new optional context then element [ count ] |
| CCodeEntrySyntax | metadata key = text within a whitelisted declaration attribute |
| CallExpressionSyntax | named/qualified/member call with type arguments and owned arguments |
| CallStatementSyntax | call ; or source-marked signal emission |
| CallableChannelTypeSyntax | owned/borrowed type in a permitted callable argument position |
| CallerInformationSyntax | CallerFilePath/CallerLineNumber/CallerArgumentExpression parameter annotation |
| CatchClauseSyntax | catch ( exception type binding ) block |
| ClassDeclarationSyntax | class/interface header and permitted policies, parent and members |
| ComImportSyntax | COMImport interface header, metadata and members |
| ComparisonChainSyntax | at least two adjacent ordering comparisons |
| CompilationUnitSyntax | optional source profile, namespace/usings, declarations and EOF |
| ConstantDeclarationSyntax | const binding = constant expression ; |
| ConstructorInitializerSyntax | constructor : base ( arguments ) before its body |
| ContinueStatementSyntax | continue ; with nearest lexical loop identity |
| ConversionExpressionSyntax | expression as type at power 25 |
| DereferenceAssignmentSyntax | * named pointer = expression ; |
| DereferenceExpressionSyntax | * operand as prefix |
| DspExpressionSyntax | finite saturating/widen/pack/interleave primitive and its exact arity |
| EnumArmSyntax | case pattern with block or modern => result ; |
| EnumBindingSyntax | payload binding or nested variant pattern |
| EnumDeclarationSyntax | enum name { variants } |
| EnumPayloadSyntax | typed named variant payload |
| EnumVariantSyntax | variant name with optional parenthesized payload declarations |
| ExpressionSyntax | abstract expression base, no emitted concrete source production |
| FieldAccessExpressionSyntax | source receiver and member projection |
| FieldAssignmentStatementSyntax | receiver field path = initializer ; |
| FieldInitializerSyntax | field = initializer, or modern same-named shorthand |
| FloatLiteralExpressionSyntax | decimal float token with exponent/precision suffix |
| ForStatementSyntax | for ( initializer ; condition ; step ) body |
| ForeachStatementSyntax | foreach ( var binding in expression ) body |
| ForeignPolicySyntax | context-specific C/COM/GObject/member/channel attribute and whitelisted keys |
| FunctionDeclarationSyntax | function header, generics/effects and body or external terminator |
| GenericTypeApplicationSyntax | nominal type < nonempty type arguments > |
| HeapObjectConstructionSyntax | new nominal type ( arguments ), optional admitted context |
| IfStatementSyntax | if ( condition ) control body [else control body] |
| IndexExpressionSyntax | container [ expression ]; literal index uses VectorExtract subtype |
| IndexedAssignmentSyntax | container [ index ] [field path] = initializer ; |
| InferredLocalDeclarationSyntax | var binding = initializer ; |
| IntegerLiteralExpressionSyntax | unsigned magnitude token; sign remains a prefix expression |
| LifecycleDeclarationSyntax | init/deinit declaration, optional base initializer and body |
| LocalDeclarationSyntax | explicit typed local and initializer |
| MatchStatementSyntax | match (scrutinee) { case pattern blocks; permitted else arm } |
| MoveExpressionSyntax | move named owner, with context-specific projected initializer rules |
| NameExpressionSyntax | identifier requiring lexical binding |
| NativeInstanceDeclarationSyntax | abstract native declaration base, no independent concrete node |
| NonNullTypeSyntax | nonnull type, with exact-reference semantic restrictions |
| NullPointerExpressionSyntax | null without implied owner acquisition |
| OwnerSlotsTypeSyntax | type [ slots ] private storage syntax |
| ParameterSyntax | optional ownership, type and name with permitted caller metadata |
| ParenthesizedExpressionSyntax | ( expression ) preserves grouping/source span |
| PointerTypeSyntax | pointer suffix on generic/vector type; simple stars may live in TypeName |
| PrefixExpressionSyntax | unary + - ! ~ and separately admitted prefix forms at power 30 |
| PropertyAccessorSyntax | get/set body or modern expression body |
| PropertyDeclarationSyntax | property header and checked accessor clauses |
| ReleaseStatementSyntax | release named owner ; |
| ReturnStatementSyntax | return [ owned expression ] ; |
| SharedTypeSyntax | shared type, modern weak type and normalized weak shared form |
| ShortCircuitExpressionSyntax | left && right or left  /  /  right with selected RHS execution |
| SliceTypeSyntax | type [ ] counted view/buffer spelling with contextual responsibility |
| StatementSyntax | abstract statement base, no emitted concrete source production |
| StructDeclarationSyntax | struct name, optional parameters and declared fields/members |
| StructFieldDeclarationSyntax | declared nominal field with qualifiers |
| StructInitializerSyntax | { named field initializers } in a known record destination |
| StructLocalDeclarationSyntax | explicit typed local with legacy record initializer |
| SwapStatementSyntax | swap ( owner slot , owner slot ) ; |
| SyntaxNode | abstract typed root, no source token or operation |
| TextLiteralExpressionSyntax | decoded counted UTF-8 token, original spelling/span retained |
| TextMemberExpressionSyntax | special text byte_length projection |
| ThrowStatementSyntax | throw [expression or move owner] ; |
| TryStatementSyntax | try block and catch clauses; no general finally implied |
| TypeNameSyntax | identifier, optional one namespace qualifier and simple pointer stars |
| Utf8FactoryExpressionSyntax | parser-created validation/conversion for nominated UTF-8 factory |
| VectorDotExpressionSyntax | dot/dot_wrap/mac/mac_wrap finite primitive |
| VectorExtractExpressionSyntax | literal index subtype also used for ordinary arrays; not SIMD proof |
| VectorInitializerSyntax | brace initializer in vector destination |
| VectorPrimitiveExpressionSyntax | splat/insert/shuffle/select finite operands and indices |
| VectorReductionExpressionSyntax | all/any finite vector reduction |
| VectorTypeSyntax | scalar type < literal lanes >, separate lane/native admission |
| WhereClauseSyntax | where parameter : capability (, capability)* |
| WhileStatementSyntax | while ( condition ) control body |
| WithStatementSyntax | with header/body, no general native admission asserted |
| RecordExpressionSyntax | modern nominal type { named initializers } |
| ConditionalExpressionSyntax | modern condition ? expression : expression |
| CompoundAssignmentSyntax | modern prepared destination op= RHS, including shifts |
| MatchExpressionSyntax | modern match (scrutinee) { case pattern => result ; ... } |
| LambdaExpressionSyntax | modern binding => expression in finite callable context |
| InterpolationExpressionSyntax | modern interpolated fragments/holes, at most 64 operands, no nesting |
| ComprehensionExpressionSyntax | modern [ for ( var binding in expression ) => element ] |
