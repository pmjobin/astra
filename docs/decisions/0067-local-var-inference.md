# ADR 0067: local type and ownership inference

Status: accepted for ASTRA-INFER-1.

## Decision

Reserve `var` and admit exactly `var identifier = initializer;` in local
statement position. The initializer is mandatory and is checked without a
declaration target type. Its exact semantic result and existing storage and
ownership contracts determine the local. `var` means infer once at declaration
time. It does not mean dynamic, variant, any, or changing type.

Both explicit and inferred local declarations are first-class. The purpose is
to remove redundant implementation detail while keeping meaningful API and
lifetime boundaries visible. Fields, properties, parameters, function results,
generic parameters and foreign declarations remain explicitly typed. There is
no `:=`, `let`, `final`, or `const` feature.

## Reserved spelling and compatibility

NUM-CONV-1 accepted `int var = 1; var = var + 1;` and `struct var { int value; }`.
The section 77 review trigger was raised and resolved by an explicit policy
decision: this is an intentional source-compatibility break. `var` is now a
normal reserved lexer token. All ordinary Astra identifier uses of that exact
word reject; mechanically rename them. No escape syntax or compatibility alias
is introduced. Case and other identifier spellings are unchanged.

A contextual keyword with type-name precedence was rejected. Otherwise the
same text, `var result = make();`, could mean either inference or a declaration
of a user-defined type named `var`. Declaration grammar must not depend on
symbol tables, type lookup, declaration order, or scope contents. The first
token now unambiguously identifies the inferred-local grammar.

## Semantic boundary

`SemanticAnalyzer.check_inferred_local` is the bounded local inference
authority. It checks the initializer before inserting the local name, retains
exact canonical/nominal identity, and constructs existing LocalSymbol and Checked
declaration/storage nodes. It never rechecks an expression against its newly
inferred type. The shared call checker resolves explicit generic arguments and
checks argument/result contracts once. Struct Places and COPY_VALUE call
producers keep their existing separate storage domain.

Fresh buffer allocations and exact owned Resource/Class/buffer results carry
their existing cleanup responsibility into an ordinary owner local. A direct
class constructor creates an owned local over the same LexicalObjectStorage.
`move` remains required for transfer from a named Resource or buffer owner.
Local Class owner moves remain deferred by OBJ-OWN/OBJ-RET; moving a Class
through an existing owned call boundary remains supported. A named owner without
`move` never becomes an owner copy, hidden transfer, or persistent borrowed alias.

An ordinary explicitly bounded borrow may infer only if existing local storage
and noescape rules permit it. Fixed arrays still require explicit complete
positional initialization; whole-array values/copies remain unsupported.
Unresolved type parameters cannot become inferred locals. Concrete specialized
generic results and concrete generic-origin struct producers remain supported.
No new generic argument inference or parameter borrowing is added.

## Literal and ambiguous-result policy

Integer literals retain canonical `int`/`i32`; unsuffixed reals retain f32.
`f`/`F` fixes f32, `d`/`D` fixes f64, before the unchanged exact decimal rounding.
`1.0000000000000002d` yields `0x3ff0000000000001`; the unsuffixed spelling yields
f32 `0x3f800000`. Conversion expressions infer their exact result type and add
no implicit conversion. Call argument contexts retain their normal meaning.

The baseline already gives a targetless `null` the exact standalone type
`void*`; `var p = null;` preserves that result under INFER-1 section 43's
exception. It never guesses a typed pointer, Resource or Class. Braced
initializers needing a target reject with an explicit-type diagnostic. Missing
generic arguments and duplicate overload declarations retain existing errors;
there is no overload-driven or bidirectional inference.

## Erasure and cost

Only syntax carries a dedicated inferred declaration node and keyword span.
Checked locals have exact types, storage, ownership and declaration/name spans.
There is no semantic VarType, AutoType, or InferredType. Equivalent explicit and
inferred declarations have identical canonical semantic/Core/CFG/SSA/NABI/CABI/
LLVM dumps. All production stages below semantics are unchanged. Inference has
zero runtime cost and adds no ABI profile, runtime metadata, performance policy,
or production dependency.

## Deferred decisions

`const` semantics remain intentionally unresolved after INFER-1. A later
milestone must decide compile-time constant versus immutable binding, whether
those are separate concepts, initializer requirements, type inference,
constant-expression authority, embedded/freestanding behavior, storage
elimination, address-taking, and C/VAPI constant interoperability.

The separate agreed parameter direction is that plain ownership-bearing
parameters should normally imply bounded borrowing, while consuming ownership
remains explicit. INFER-1 does not implement it. Generic inference, multi-file
compilation and standard-library work are also outside this decision.

See [language rules](../language/local-inference.md) and
qualification.
