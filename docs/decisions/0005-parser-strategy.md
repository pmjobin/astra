# ADR 0005: Handwritten syntax frontend

Status: accepted in ASTRA-PARSE-1, on the ASTRA-CHARTER-1 foundation.

## Decision

Use an independently authored handwritten lexer, recursive-descent parsing for
declarations/statements, and a Pratt expression parser. One-token lookahead is
enough for the current grammar. Do not add a parser generator or its runtime.

The source layer owns exact bytes and reports half-open byte spans. Tokens hold
kinds and spans; spelling is obtained on demand. Syntax nodes preserve tokens,
parentheses, source order, and meaningful spans, with no semantic type objects.
A `ParseResult` carries either a complete unit or a diagnostic. Normal lexical
and syntax failures propagate explicitly; nodes are data and do not throw host
exceptions. The result boundary allows future diagnostic lists and recovery
without coupling either to syntax-node construction.

## Rationale and alternatives

- Handwritten code gives direct control over useful diagnostics and exact source
  spans for this small C/Vala-descended grammar.
- Recursive descent maps declarations, parameter lists, blocks, and returns
  directly to the implemented grammar without extra bootstrap dependencies.
- Pratt binding powers express precedence and associativity in one small table,
  allowing deliberate later additions without implementing future forms now.
- A generated parser would add tooling and integration costs without solving a
  current grammar problem. GLib arrays already meet the frontend's collection
  needs; libgee or another collection library is unnecessary.
- This is the compiler's current implementation strategy. It does not require
  future IDEs, formatters, or other language tooling to share this parser.

## Scope and consequences

`src/source/` and `src/syntax/` contain the frontend. Their Meson dependency
includes only the existing host GLib/GObject dependencies. Frontend unit tests
and `astrac` do not link LLVM or compile its bindings; the separate CHARTER-1
LLVM smoke executable remains unchanged. Source-to-syntax is not the checked
semantic model (ASTRA-I1, ASTRA-I4). Host Vala classes and their GLib allocation
costs establish no Astra-native object or runtime semantics.

The [implemented syntax](../language/syntax.md) documents ASCII identifiers,
UTF-8 validation, NUL diagnostics, and source-location conventions. Unicode
identifier policy remains open. The Stage-0 depth limit of 256 bounds parsing,
dumping, and syntax-tree destruction; flat declaration/statement/parameter lists
use iterative loops. These resource limits do not settle language semantics.

The ordinary system Vala 0.56.19 implementation exposed concrete host binding
details during this work. Two local mechanical GLib declarations preserve the
bounded `g_strndup` operation and correct `g_utf8_validate_len`'s const output
pointer; the stock VAPI marks `ndup` deprecated and makes that output mutable.
See the public [copy API](https://docs.gtk.org/glib/func.strndup.html) and
[validation API](https://docs.gtk.org/glib/func.utf8_validate_len.html). No GLib or
Vala implementation source was copied.

Vala targets the selected host GLib version so it emits the available type-init
API. GCC unused-parameter/variable warnings are disabled only for Vala-generated
frontend/CLI C, whose boilerplate contains unused callbacks and array lengths;
Vala's source warnings remain enabled. `VALA_STRICT_C` keeps C pointer checks
strict. Readonly string accessors and indexed generic-array access avoid actual
qualifier/type mismatches instead of suppressing them. The tests register plain
GLib callbacks and retain Vala closures locally to avoid the stock bound
`GTestDataFunc` callback's const mismatch. These are host integration details,
not new compiler stages, dependencies, or a replacement test framework.

CHARTER-1 already qualified Stage 0; a separate ASTRA-BOOT-1 milestone is not
needed. ASTRA-SEM-1 must introduce its own checked model without repurposing type
name tokens, literal spellings, or LLVM handles as semantic authority.
