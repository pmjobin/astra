# Astra semantics and completion: ASTRA-SLICE-1

[SLICE-1](slices.md) introduces canonical SliceType(element_type) and one borrowed
local view value with runtime int length. Explicit `slice(array)` and
`slice(array,start,count)` borrow direct fixed-array storage through existing
lexical regions. Subrange operands evaluate start then count before validation;
valid ranges satisfy `0 <= start <= N` and `0 <= count <= N - start`.
Copies/rebinding preserve view identity and obey stored-borrow lifetime rules.
Mutable aliases may overlap. Empty views are valid; null slices are not.
`len(array)` is an int constant; `len(slice)` evaluates one view and reads its
stored extent. A slice expression followed by an integer index produces
CheckedSliceElementPlace, with runtime bounds validation before load or RHS/store.
Array indexing remains ArrayElementPlace and vector indexing remains a Value.
Slices require initialization and remain local-only, with no pointer exposure,
implicit array decay, aggregate storage, ownership, equality or ABI channel.

[ARRAY-1](arrays.md) introduces exact canonical ArrayType(element_type, length)
for local contiguous storage only. Complete ordered initializers receive exact
element context and finish before the local becomes visible. Direct-local
`a[index]` produces CheckedArrayElementPlace; reads use CheckedLoadExpression and
writes use CheckedStore. Any scalar IntegerType supplies an exact mathematical
ordinal in `[0,N)`. Invalid constants reject; invalid dynamic indices trap before
memory access and before assignment RHS evaluation. Arrays never become whole
Values. Vector elements load/store whole vectors; subsequent lane extraction
remains a non-writable Value. No decay, element borrow, pointer array or ABI is added.

[BIT-1 bit/shift semantics](bitwise.md) add exact integer scalar/vector `& | ^ ~`,
eager bool/mask `& | ^`, and dedicated integer scalar/vector shifts. Same-domain
bit operations require exact types; a shift count is independently typed as any
scalar IntegerType and interpreted mathematically in `[0, element_width)`.
Invalid immediate counts reject; dynamic invalid counts trap after value/count
evaluation in order. Signed left shift retains low bits without overflow UB;
signed right shift equals floor division, unsigned right shift zero-fills.
`-3 / 2 == -1` while `-3 >> 1 == -2`. Bool remains separate from integers;
`!` complements bool/masks and `&&`/`||` remain scalar short-circuit operations.

[Lane primitives](vector-lanes.md) retain five exact checked value forms.
Splat contextualizes integer literals from an expected vector element and
evaluates its scalar once; extraction reads a constant lane from any vector value.
Insert evaluates vector then replacement and returns the same exact vector type
with untouched lanes preserved. Shuffle evaluates one source once and retains
its type/shape with exactly N immutable in-range selectors, including duplicates.
Select requires bool<N> and two identical VectorTypes, evaluates mask/true/false
in order, and never short-circuits. Bool data is valid; f32 lane values copy
exactly without arithmetic or rounding. Constant ordinals have provenance and
are never runtime expressions or Places. Writable/dynamic indexing and lane
addressability remain unsupported.

[Short vectors](vectors.md) add canonical `VectorType(element_type, lane_count)`.
`int<N>` and `i32<N>` share exact identity. CheckedVectorConstructExpression
retains exact contextual lane types in left-to-right order; locals become visible
only afterward. Whole-vector assignment, native parameters/results, and ordinary
Place promotion preserve one value. Shared unary/binary operators apply existing
scalar lane semantics; comparisons yield bool<N>. CheckedVectorReductionExpression
reduces a mask with ALL/ANY to scalar bool. Masks cannot directly control scalar
branches or short-circuit operations. There is no implicit broadcast/conversion,
vector field/addressability, C ABI support, or general generic instantiation.

[F32 semantics](f32.md) add canonical `F32Type` and `AstraF32Value` exact bits.
Every arithmetic operation rounds to binary32 nearest/ties-even; signed zero,
subnormals, infinities, and NaNs are preserved under the qualified execution
contract. Unary minus toggles the sign bit. Floating division by zero follows
IEEE results and does not trap. NaN makes `!=` true and every other comparison
false. There are no implicit integer/float conversions or float truthiness.
Decimal/scientific syntax resolves directly to binary32, independently of host
floating parsing and locale. NaN payload is not stable observable source data.

**Pre-release and evolving.** This document describes the checked meaning of
the [current grammar](syntax.md). Semantic checking produces a separate checked
model; it does not generate or execute code. The downstream Core and CFG layers
preserve semantic computation and validate reachable function completion.
SSA then promotes eligible reachable local storage, retains aliasable memory, and flattens remaining
expression trees without changing source validity or semantic types.
NABI, LLVM lowering, and host-native execution are independent downstream
stages; no Astra target runtime library is required.

## Built-in types

Scalar names `i8`, `u8`, `i16`, `u16`, `i32`, `u32`, `int`, `f32`, `bool`, and `void` resolve; `void*` and native `StructName*` are supported raw-pointer types. Base names remain lexer identifiers,
and type resolution is case-sensitive. Unknown names receive an `unknown type` diagnostic at the type name.
`IntegerType` supplies exact immutable width/sign/ranges for six canonical
identities. `int` and `i32` resolve to the same object, displayed as `int`.
See [integers](integers.md) for all ranges, contextual literals, and operations.

`int` is signed with exactly 32 bits of value representation on every target,
range -2147483648 through 2147483647. All occurrences in one checked program
resolve to one canonical compiler-owned type. Ordinary `+`, `-`, `*`, and unary
`-` wrap modulo 2^32; unary `+` is identity. Division truncates toward zero,
remainder follows the dividend, and zero divisors trap at runtime. INT_MIN/-1
wraps to INT_MIN, and INT_MIN%-1 is zero. Comparisons use signed values.
[Scalar semantics](scalars.md) freezes these Astra rules independently of
Vala/C/host/LLVM behavior. Physical layout and native/C ABI remain downstream.

`bool` is a distinct canonical `SemanticType(TypeKind.BOOL)` in the same type
universe. It defines semantic truth values only: no width, ABI, memory/register
representation, C `_Bool`, Vala bool, or LLVM type is implied. Boolean literals
retain `BooleanLiteral.TRUE/FALSE` as semantic payloads, independently of their
source spans; dumps print `true`/`false` without numeric encoding.

`void` has a distinct canonical identity and means a function returns no value.
It is permitted as a return type and rejected as a parameter or local type. Consequently
valid native parameters and scalar locals include every IntegerType, `bool`,
`void*`, native `StructName*`, and declared nominal handles.
Struct locals additionally carry a nominal StructType; structs are not function channels. `void` is not a value type
for the current expressions.

## Functions, parameters, and name resolution

A function symbol owns its resolved return type, ordered parameter symbols,
name, and declaration/name spans. A parameter symbol records its semantic type,
name, zero-based ordinal within that function, and declaration/name spans.

Function names occupy compilation-unit declaration scope. Any repeated function
name is an error at the later declaration, even if its parameters or return type
differ. **Overloading is not implemented**; this is a current restriction, not
Astra's permanent overloading policy. Parameter names must be unique within each
function, and duplicate diagnostics point at the later parameter name.

Expression names resolve to previously declared locals and parameters of the
current function. A checked reference retains the exact `LocalSymbol` or
`ParameterSymbol` through distinct expression kinds. Repeated uses share the
same declaration object; declarations in different functions remain distinct.
An unknown name is an error. Functions are not values, and local/parameter
scope does not leak between functions.

Type lookup, function declarations, and function-local value lookup have
separate authority. Thus this is valid in the current subset:

```astra
int int(int void) {
	return void;
}
```

There is no overload resolution or standalone block statement syntax. Nested
branch and loop scopes exist; no permanent general shadowing policy is established here.

## Initialized locals and assignment

`LocalSymbol` owns a name, semantic type, zero-based local ordinal, and
declaration/name spans. `CheckedFunction.locals` contains these exact symbols
in function-wide declaration traversal order. Each function body, branch, and loop
block has a `ValueScope` frame with an enclosing frame; parameters occupy the
outer frame. Lookup searches current locals, enclosing locals, then parameters.
Names cannot shadow any currently visible local or parameter. Sibling branch
scopes may independently declare the same spelling: they get distinct symbols
and monotonically increasing ordinals. Their locals are invisible to siblings
and after the block, but visible to subsequent statements and nested branches
within the block. This current conservative rule leaves general shadowing open.

`CheckedWhile` owns a CheckedLoopTarget, an already bool-checked condition, and
a CheckedBlockStatement body. The condition is checked in the surrounding scope; checking the body
creates exactly one child frame. Every attempted iteration reevaluates the
condition in established left-to-right call/trap order. A false initial value
executes no body statements. Body initializations execute per iteration with one
declaration identity, and outer assignments preserve exact LocalSymbols.
No graph identities or loop-return analysis enter checked semantics. Completion
is checked from CFG, retaining false edges even for literal true conditions.
See [while loops](loops.md).

Each while target is a distinct object with keyword provenance and a zero-based
function-local ordinal assigned in source preorder. Semantic analysis pushes it
before checking the body and pops it even when body checking fails. Break and
continue bind the top of this explicit stack once; ValueScope frames do not
obscure the stack. An empty stack produces a deterministic keyword-span error:
`'break' is only valid inside a loop` or the corresponding continue diagnostic.
CheckedBreak/CheckedContinue hold GLib.WeakRef targets with nullable owned getters.
Targets have no parent backlink, so retaining a detached transfer cannot keep
its loop alive. Downstream stages translate identity, never nesting depth or
source spelling. See [loop control](loop-control.md).

For `int y = expression;`, analysis resolves the type, checks name availability,
checks the initializer without `y` in scope, requires an exact type match, then
creates and publishes the local symbol. Thus `int a = x; int b = a + 1;` can use
a parameter `x` and an earlier local, while `int a = a + 1;` and reading a later
local receive `unknown name` diagnostics. There are no uninitialized locals or
general definite-assignment dataflow rules. The same procedure applies to bool
locals and nested declarations.

`CheckedLocalDeclaration` retains the symbol and checked initializer.
`CheckedLocalReferenceExpression` retains the exact local read, independently
of parameter references. It is semantic binding, with no pointer/address field.
Downstream [Place lowering](../ir/place-storage.md) makes the read an explicit
load from that local's storage authority.

For `y = expression;`, analysis resolves the target before checking the RHS.
Only a visible LocalSymbol is assignable. `CheckedAssignment` stores that exact
target and the checked RHS; their semantic types must match without conversion.
Assignment is a statement and supplies no value to another expression.

Assignment to a parameter reports `assignment to parameter 'x' is not supported`.
This preserves the established parameter value semantics and does not freeze
permanent parameter immutability. Known function/type names receive
`name 'x' is not an assignable local`; absent targets receive
`unknown assignment target 'x'`. Value-scope declarations take precedence over
the independent type/function namespaces.

## Expressions

Every checked expression exposes its semantic type.

| Expression | Type rule | Checked meaning |
| --- | --- | --- |
| Decimal integer literal / direct signed literal form | Expected IntegerType, default int | Immutable `AstraIntegerValue`, exact type/bits, and source provenance |
| `null` | Contextual raw-pointer type, default `void*` | `CheckedNullPointerExpression` with no numeric payload |
| `true`, `false` | `bool` | `CheckedBooleanExpression` with semantic truth payload |
| Prefix `!` | bool operand/result | Semantic `NOT` operator |
| `<`, `<=`, `>`, `>=` | Exact same integer operands, bool result | Signed or unsigned mathematical ordering |
| `==`, `!=` | Same supported non-void operand type, bool result | Semantic equality operators |
| Parameter name | Declared scalar or raw-pointer parameter type | Direct parameter-symbol reference |
| Visible local name | Declared scalar or raw-pointer local type | Direct local-symbol reference; downstream read is a load |
| Parenthesized expression | Inner expression's type | Checked inner expression; grouping is already reflected in the tree |
| Prefix `+` or `-` | Integer operand/result of the same type; minus is signed-only | Identity or wrapping negation |
| Binary `+`, `-`, `*`, `/`, `%` | Exact same IntegerType operands/result | Wrapping arithmetic; signed/unsigned quotient and remainder |

Precedence and associativity established by parsing survive in the checked
structure. For example, `-(a + 2) * b % 3` has remainder at the root, with a
multiplication on its left and negation of the addition beneath that. Parentheses
do not require independent checked nodes; the inner node retains its source
span, and the syntax tree still contains the complete parenthesized spelling.

There is no general constant folding, conversion, numeric promotion, or operator
overloading. `1 + 2` remains an addition; `!false` remains an operation. Direct
`-0007` forms a checked integer constant -7. Parentheses do not obstruct signed
formation: `-((2147483648))` forms INT_MIN, while positive `2147483648` fails.
The outer negation in `-(-2147483648)` remains an operation.

The analyzer checks decimal magnitude against the contextual type maximum
(positive) or the magnitude of its signed minimum (negative formation) before
every digit accumulation. Expected types flow through arithmetic from locals,
assignments, returns, calls, and fields. A declared operand supplies symmetric
context to literals in `x + 1` and `1 + x`; literal-only trees default to int. Out-of-range literals
receive `integer literal is out of range for 'TYPE'` with their source span.
The historical huge-literal fixtures now fail here, before Core construction;
syntax still preserves their full spelling. `1 / 0` and `1 % 0` remain explicit
operations with defined runtime trap semantics, without compile-time diagnosis.

`CheckedIntegerExpression.value` is immutable AstraIntegerValue authority. It
contains an exact IntegerType and bounded bit pattern, never numeric text.
Unsigned unary minus rejects, including direct negative literals. Mixed integer
types reject without conversion. Existing int behavior is unchanged. SourceSpan
retains exact spelling: `00042` dumps as `(integer 42 : int)` but provenance
recovers `00042`. Core, CFG, and SSA carry the value directly without reparsing.
See [ADR 0013](../decisions/0013-scalar-semantics.md).

## Blocks and returns

Function-body and branch blocks check declarations, assignments, conditionals,
and returns in source order. `CheckedIf` holds a bool-checked condition and
then/optional else `CheckedBlockStatement` bodies. `if (1) {}` is invalid: no
implicit integer truthiness or conversion exists. `if (a < b) {}` is valid for
ints. Each block is checked by the same recursive analyzer, with exact symbols
retained in checked declarations/references. No CFG identity enters these nodes.

| Function return type | Statement | Result |
| --- | --- | --- |
| `void` | `return;` | Accepted |
| `void` | `return expression;` | Rejected at the expression |
| `int` | `return;` | Rejected at `return` |
| `int` | `return expression;` | Accepted only for an `int` expression |
| `bool` | `return;` | Rejected at `return` |
| `bool` | `return expression;` | Accepted only for a `bool` expression |
| `void*` | `return;` | Rejected at `return` |
| `void*` | `return expression;` | Accepted only for a `void*` expression, including `null` |

There are no implicit conversions. An expression's checked type must be the
function's return type. Return shape is checked before checking its expression.

The **semantic analyzer does not perform definite-return analysis**:
`int empty_for_now() {}` still produces a valid checked model and structured Core.
Downstream CFG flow validation rejects its reachable `FunctionEnd` because an
int, bool, or void* function must return a value on every reachable completion path.
Full-return conditionals validate; partial-return conditionals fail if a join
reaches FunctionEnd. Constant conditions retain both structural successors, so
`if (true) { return 1; }` alone does not establish definite return. Reachable
void function ends are valid and remain distinct from explicit `return;`.

Statements after a return are still type/name checked, so two valid returns are
accepted, but a later return of an unknown name still fails. CFG preserves later
statements, including initialization and mutation, in disconnected unreachable
blocks, without unreachable-code warnings or operation removal.
See the [control-flow layer](../ir/cfg.md) for the separate reachability and
function-completion rules.

## Analysis results and diagnostics

Analysis first collects and checks all function signatures in source order,
then checks all bodies in source order. Therefore a signature error in a later
function is reported before a body error in an earlier one. Bodies use the
established declarations and lexical value frames, populated only by parameters
and successfully initialized locals.
Expression operands are checked left to right. Hash-table iteration order is
never used to select diagnostics or emit the checked model.

`SemanticResult` contains either a complete `CheckedProgram` or one `Diagnostic`.
Normal semantic errors use explicit result propagation, not host exceptions.
Failed analysis exposes no partial checked program. Diagnostics use the existing
source infrastructure, with half-open byte spans and 1-based line/scalar-column
locations. For example:

```text
test.astra:1:1: error: unknown type 'Mystery'
test.astra:1:18: error: duplicate parameter 'x'
```

Bool makes the existing exact-type guards observable in source: `bool x = 1;`,
assigning int to bool, arithmetic on bool, and int/bool equality all fail.
Void comparisons are unsupported; there are no void-valued source expressions.
`&&`/`||` are deferred because their evaluation requires additional control flow.
The checked model has no SSA or physical representation. Downstream scalar
promotion preserves these rules; no constant folding or ownership is introduced.

## Developer modes and checked dump

```sh
astrac --check FILE...
astrac --dump-semantics FILE...
```

Each mode takes one or more [source files](source-files.md) contributing to one
global checked program. `--dump-semantics` parses every file independently and
analyzes the complete declaration universe, then prints the checked model on
success. `--check` also constructs/verifies Core, CFG, SSA, ABI plans and LLVM;
it exits 0 silently on success. Both exit 1 with a diagnostic on stderr and no partial stdout on
file-read, encoding, lexical, syntax, or semantic failure. `--check` also rejects
control-flow errors. Parse diagnostics are preserved unchanged. Incorrect mode
arity exits 2. In particular, an empty int function has a successful semantic
dump but fails the complete `--check` pipeline.

`--help`, `--version`, `--parse`, `--dump-syntax`, `--dump-core`, `--dump-cfg`, and `--dump-ssa`
remain available. Core dumps stop before flow validation, while CFG dumps require
complete flow validity. SSA dumps additionally project reachable blocks and
promote scalar Places; CFG dumps retain unreachable source structure. SSA
internal invariant failures use the compiler-internal error path, not a new
source diagnostic. Syntax-only modes still accept syntactically valid
unknown types/names. Plain `astrac FILE...` compiles one host-native executable;
check and semantic/IR dump modes do not emit objects or executables.

The semantic dump is an **internal debugging/test representation**, not a stable
serialization format. It uses tab indentation, LF line endings, source-order
functions/parameters/locals/statements, Astra type names, and semantic operator spellings.
Parameter and local declarations/references show matching ordinals, scoped by their
enclosing function. There are no object addresses, LLVM types, or host type names.
For `int identity(int x) { return (x); }`:

```text
(program
	(function "identity" -> int
		(parameters
			(parameter #0 "x" : int)
		)
		(block
			(return (parameter-ref #0 "x" : int))
		)
	)
)
```

The checked model retains types, symbols, and source spans independently of the
analyzer and syntax tree. See [ADR 0006](../decisions/0006-semantic-model.md) for
the ownership and frontend/backend boundary decision.
The [local-storage decision](../decisions/0009-place-storage.md) records scope,
explicit loads, initialization versus replacement, and downstream Place identity.
[ADR 0010](../decisions/0010-conditional-control-flow.md) extends that foundation
with lexical branch scopes, boolean semantics, and structured conditionals.
See the [mutation golden](../../tests/place/fixtures/mutate.semantics) for local
declarations, local reads, and assignment targets. There are no physical storage,
SSA semantics in the checked model. OWN-1 adds explicit
owned-result categories and local cleanup obligations.

## Direct calls

[Direct-call semantics](calls.md) add positional exact arguments, forward calls,
self/mutual recursion, and call statements. The analyzer resolves call syntax
only through the complete compilation-unit function table. Bare identifiers
retain lexical value lookup, including permitted function/value name collisions.

CheckedCallExpression holds a GLib WeakRef to an exact DirectCallableSymbol
(FunctionSymbol with NATIVE domain or CFunctionSymbol with C domain), ordered
checked arguments, and the non-void return type. CheckedCallStatement holds the
callee and arguments, allowing either return shape and discarded non-void
results. CheckedProgram owns native symbols through CheckedFunctions and owns
CFunctionSymbols in a separate c_functions array; calls never own their callees.
The Core boundary rejects out-of-program or expired targets.

Current operand and argument evaluation is left-to-right, with each call after
its arguments. This is observable semantics. Calls are conservatively effectful
and are neither removed nor reordered. A void call cannot supply a value.
Semantic signatures imply no native/C ABI, callable values, ownership channel,
or physical int/bool/LLVM representation. See [ADR 0012](../decisions/0012-direct-call-semantics.md).

## Short-circuit bool checking

`bool && bool -> bool` and `bool || bool -> bool` are exact signatures without
coercion or integer truthiness. CheckedShortCircuitExpression owns a distinct
ShortCircuitOperator, checked children, bool type, and provenance. Both children
are analyzed before construction, including a RHS skipped by a literal left
value. Unknown functions and out-of-range literals there remain errors.
Zero division remains a runtime trap. The left always evaluates; AND skips its
RHS on false, OR on true, and otherwise the result is the RHS bool. This semantic
identity survives Core. See [the complete rules](short-circuit.md).

## Explicit foreign signatures

`extern(C)` is the explicit semantic C contract. CFunctionSymbol retains
ForeignAbi.C, exact source/external names, ordered ParameterSymbols, return type,
and provenance. DirectCallableSymbol exposes an explicit domain rather than
requiring the backend to infer an ABI. Signatures for both domains are collected
before any native body is checked; duplicate names reject across domains.
Imported declarations have no checked body and imported main is not an entry.

C parameters are exactly int/void* and results int/void*/void; foreign bool rejects before
body checking. Calls retain ordinary exact argument/result checks and effect
order. No physical CABI data becomes semantic type authority. External
[VAPI input](vapi.md) creates the same CFunctionSymbol model through span-backed
ForeignDeclarationInput records. All supplied files are parsed and normalized
before native body checking; external signatures are validated with the analyzer's
canonical types, then merged after source declarations. Import order is source
externs first, then CLI VAPI file order and declaration order within each file.
Duplicate names reject against native functions, exported definitions, source
externs, and other VAPI inputs, including identical signatures/repeated paths.
One diagnostic points at the later conflicting declaration in that merge order.
VAPI type/parameter errors retain their VAPI file and location. SourceSpan
provenance never changes call identity or semantics. See [C interop](c-interop.md).

## Export attachments

`export(C)` validates int/void* parameters and int/void*/void results on an ordinary native
definition. Bool boundary types reject with source diagnostics; bool body
expressions and local variables retain ordinary native semantics. A body is
mandatory, and extern/export combinations reject during parsing.

CheckedProgram owns CExportSymbol attachments independently of CheckedFunction
bodies. Each attachment records ABI C, the exact source-spelled external symbol,
source-order export ordinal, provenance, and a GLib WeakRef to its FunctionSymbol.
The native symbol remains owned through CheckedFunction. Neither function nor
callable lookup acquires an export identity or a backreference. Astra calls and
recursion retain native DirectCallableSymbol targets. Later stages copy metadata
and map exact targets once, allowing checked symbols and exports to be reclaimed.
See [C exports](c-exports.md) and [ADR 0021](../decisions/0021-c-scalar-exports.md).

## Nullable unmanaged raw-pointer values

Each BuiltinTypes universe canonicalizes one RawPointerType(TypeKind.RAW_POINTER)
per exact supported pointee: its canonical void type or a native StructType. This independent semantic identity has no
width or host/LLVM representation. CheckedNullPointerExpression owns the exact
`null` source span and contextually selected pointer type, with no integer
payload. Dumps include that type. Initializers, assignments, calls, and equality
supply context; uncontextualized null defaults to void*. Ordinary pointer values
never acquire an implicit conversion.

Pointer assignments, calls, and returns require exact identity. `==`/`!=` accept
matching raw-pointer operands and yield bool; a null literal contextualizes
to the other pointer type. Arithmetic, ordering, truthiness, mixed equality,
pointer/integer casts, general address-of, and whole dereference reject.
C bool and typed native pointers remain unsupported at foreign boundaries.
Every pointer is nullable; indirect native field access explicitly traps on null.
Copies and destruction have no pointee effects. See [raw pointers](raw-pointers.md) for examples and diagnostics.

## Native local structs

[Structs](structs.md) introduce nominal type-name authority separate from direct
functions and values. Analysis collects every StructSymbol and canonical
StructType before resolving scalar fields or checking signatures/bodies. Each
StructFieldSymbol has an exact weak containing symbol, scalar type, declaration
ordinal, and declaration/name provenance. Identical field shapes do not make
types equal. Builtin/duplicate type names, empty types, and unsupported fields reject.

CheckedStructLocalDeclaration retains an ordinary LocalSymbol and ordered
CheckedFieldInitializers. It validates every field exactly once with exact types,
preserving written initialization order. No local symbol is published until all
initializer expressions have been checked. CheckedFieldReferenceExpression and
CheckedFieldAssignment bind the exact local and exact field. Bare aggregate reads,
whole assignments/copies/equality, and struct function channels reject before IR.

StructType retains no symbol or syntax backlink. Core/CFG create independent
field descriptors and [exact storage projections](../ir/field-places.md).
Physical layout and C/VAPI struct interoperability remain unspecified/unsupported.

## Typed borrows and indirect storage

[TPTR-1](typed-struct-pointers.md) allows exact native Struct* parameters and
initialized locals, but rejects typed pointer results and fields. The distinct
result diagnostic explains the missing lifetime/escape capability; void* results
are unchanged. C imports/exports and VAPI reject typed native pointers.

CheckedAddressOfStructExpression binds one exact visible struct local and
canonical Struct* type. BORROW-1 accepts it as a general expression and marks
LocalSymbol.address_taken for the entire checked function, including unreachable
uses. Each CheckedBlockStatement owns an exact LexicalRegion; its GLib.WeakRef
parent links the lexical tree. LocalSymbols own their declaration regions and
native parameters receive the function-body region.

BorrowProvenance.for_expression is defined only for checked Struct* values:
NULL has no finite requirement; addresses use pointee-local regions; parameter
references use the invocation root; pointer-local reads use their own storage
regions. Initializers and assignments require exact type identity followed by
source.outlives(destination), using object equality or lexical ancestry.
Same-scope late assignment and outer to inner stores pass; inner to outer stores
fail before Core, including conservative pointer copies and loop escapes.
Ordinary declaration visibility proves the local has begun its lifetime.

Borrow regions are semantic proof objects with no downstream lifetime graph.
Optional `SemanticDump.format(program, true)` annotations show deterministic
per-function preorder IDs and local borrow requirements; default dumps are
unchanged. No runtime checking, ownership, or exclusivity is introduced.
Typed-pointer returns require future return-lifetime contracts; fields and C/VAPI
channels remain prohibited. See [borrows](borrows.md) and
[ADR 0027](../decisions/0027-lexical-borrow-regions.md).

CheckedIndirectFieldReference and CheckedIndirectFieldAssignment retain the
exact local/parameter pointer reference, exact field, and provenance. A read
checks null and loads at its expression point; an assignment evaluates its RHS
first, then checks null and stores. Typed pointers can alias and own nothing.
Null access traps deterministically; short circuit may suppress it. See
[storage authority](../ir/addressable-storage.md) and
[ADR 0026](../decisions/0026-typed-struct-pointers.md).

## OWN-1 ownership responsibility

[Owned foreign locals](ownership.md) add an independent ownership dimension to
canonical void*. CheckedCallExpression retains the normalized owned-result
contract and advertises OWNED(cleanup) or UNMANAGED. CheckedOwnedLocalDeclaration
retains the exact local, initializer, cleanup, and existing LexicalRegion. Successful
return arms one responsibility, including null; visibility follows initialization.

Expression contexts explicitly permit acquisition only at the direct owner
initializer and owner observation only in equality/inequality with literal null.
All raw capture, discard, copy, reassignment, call-argument, and return escapes
reject. Parentheses preserve category checks. There is no general owned-to-raw
conversion. Core receives an independent obligation; CFG inserts reverse lexical
cleanup on normal exits after return-expression evaluation. Traps do not unwind,
and BORROW-1's Struct* provenance rules remain independent.

## MOVE-1 responsibility transfer

[Move syntax](moves.md) is exactly `move identifier`, only as the direct
initializer of a fresh owned void* local. CheckedOwnershipMove retains the exact
source LocalSymbol, its cleanup contract, void* result type and original span.
The destination inherits that contract by identity; no name lookup creates one.
Parentheses around a move reject, while OWN-1's grouped producer calls remain valid.

Semantic analysis resolves syntax, identity and capability restrictions. Definitive
OWNED/MOVED/MAYBE_OWNED validation belongs to reachable CFG, after exact events
are lowered and before SSA. Joins ignore unreachable/terminated predecessors;
loops iterate to a fixpoint. Compiler cleanup is legal for all three states.
The source is physically cleared to null after transfer but remains semantically
unusable. Actual-null owners can move. BorrowProvenance and LexicalRegion rules
are unchanged; there is no shared borrow/ownership lattice.
