# VAPI scalar declaration format v0

RESOURCE-1 extends this format with `vapi-declaration := handle-declaration | function-declaration`.
The exact [handle grammar](handle-types.md) adds required type-level cleanup,
`owned` handle results and borrowed handle parameters. All imported type
identities are collected before signatures; function order never gates type
availability. The scalar and legacy void* formats below remain compatible.

ASTRA-VAPI-1 adds external function declaration input to the existing C scalar
import model. ASTRA-VAPI-META-1 extends it with optional
[C symbol/header metadata](vapi-c-metadata-v0.md). This document versions the
declaration subset, not the host C ABI.

## Grammar

```text
vapi-file           := foreign-declaration* EOF
foreign-declaration := metadata-attribute? function-declaration
function-declaration := type-name identifier "(" parameter-list? ")" ";"
metadata-attribute  := "[" "CCode" "(" metadata-entry ("," metadata-entry)* ")" "]"
metadata-entry      := identifier "=" string-literal
parameter-list      := parameter ("," parameter)*
parameter           := "borrowed"? type-name identifier
type-name           := identifier ("*")?
identifier          := [A-Za-z_][A-Za-z0-9_]*
```

```text
int astra_test_add(int a, int b);
int astra_test_identity(int value);
void astra_test_reset();
```

A file implies C imports. Explicit `extern(C)`, `export(C)`, and `export`
declarations reject. Bodies, unnamed parameters, trailing commas, complex declarators,
ellipses, and extra punctuation are outside the grammar. Empty files are valid.
Type names are identifiers syntactically, including bool and unknown names.
Semantic collection permits int/void*/Handle parameters and int/void*/Handle/void results. Void
parameters, foreign bool, unknown types, and duplicate parameter names reject
with a diagnostic at their VAPI span.

## Lexical and input policy

SourceFile validates the complete byte allocation as UTF-8 and rejects embedded
NUL, including bytes in comments and after otherwise valid declarations. There
is no independent Unicode or encoding implementation in the VAPI frontend.
Identifiers are ASCII; non-ASCII characters are accepted in comments and
metadata strings. Quoted UTF-8 metadata values support `\"`, `\\`, `\n`, `\r`,
and `\t`; raw CR/LF and unsupported escapes reject. These are VAPI literals
only. See the [exact string grammar](vapi-c-metadata-v0.md#exact-grammar).
Whitespace is space, tab, CR, LF, vertical tab, or form feed. `//` ends at CR, LF,
or EOF. `/* ... */` ends at the first closing delimiter and does not nest.
An unterminated block comment reports its opening delimiter deterministically.
SourceFile handles CR, LF, CRLF, and Unicode scalar columns in diagnostics.

`--vapi PATH` reads bytes directly, without a shell. The conventional extension
is `.vapi`; explicitly supplied paths with any extension, spaces, or punctuation
are equally valid. Repeating a path reads it as another declaration input. Read
errors say `cannot read VAPI file`; parse/semantic errors include filename,
line, and column. Failure prevents semantic/IR/LLVM output and output publication.

## Normalization and authority

`src/vapi/` contains dedicated token, lexer, syntax, parser, and normalizer files.
`VapiFileSyntax` owns the whole-file span, ordered function declarations, and EOF.
`VapiFunctionDeclarationSyntax` owns its complete declaration span, return type
syntax, name token, optional VapiCCodeAttributeSyntax, and ordered parameter
syntax. Each parameter retains its
type/name syntax and span; tokens carry kind and span. Punctuation need not
survive as separate nodes because the declaration span retains its exact bytes.

`VapiNormalizer.normalize` structurally copies declarations to the semantic
boundary's `ForeignDeclarationInput`, carrying declaration/name/result-type spans
and ordered ForeignParameterInput spans plus immutable generic CForeignMetadata.
The record implicitly means C import. Its local name controls Astra lookup;
metadata supplies the external symbol (defaulting to the local name) and zero
or one descriptive header entries. No ABI selection facility is introduced.
SemanticAnalyzer validates all external
signatures using its own canonical BuiltinTypes and creates CFunctionSymbol and
ParameterSymbol objects. It then merges them into the unified callable namespace
before native body checking. No VAPI syntax object is passed to that analyzer.

Source externs retain their existing collector. Equivalent declarations produce
the same
semantic class, ABI C, signature, external symbol, and call identity. Existing
semantic dumps therefore show ordinary `(extern-function ... (abi C) ...)`
entries for VAPI imports. Optional `(headers ...)` stanzas appear only when
headers exist; ordinary source/default dumps remain stable. No explicit origin
enum is
stored; SourceSpan supplies provenance. Syntax, tokens, parser, and input records
can die while the semantic model remains usable. SourceSpan may keep SourceFile
alive for diagnostics; this does not retain the frontend tree.

Imports are ordered as source extern declarations first, followed by CLI VAPI
file order and declaration order within each file. Export ordinals remain
independent. Every callable name must be unique across all input sources, even
if signatures match. The later conflicting declaration in this merge order gets
one error. Calls resolve after the complete merge, including forward calls.

Existing CoreCFunction → CfgCFunction → SsaCFunction → CAbiFunction → LLVM C
import identity mapping and LLVM lowering remain unchanged; each imported
declaration retains normalized metadata. CABI alone validates physical symbol
uniqueness across imports and exports, independently of local-name uniqueness.
There are no VAPI-specific IR nodes, physical
types, call instructions, or backend branches. CABI SCALAR_V0 supplies I32
parameters and I32/absent result; pointer signatures select SCALAR_PTR_V1 with
additional PTR channels. NABI remains native-only. LLVM imports use
external linkage and ccc, while native recursion remains internal/fastcc.

## Deliberate limits

VAPI supplies no object code, library, link flags, pkg-config module, object path,
header parsing, or C compiler invocation. Unresolved symbols are a link-time
failure; declaration checking and LLVM dumping can succeed without an
implementation. Actual implementations must match the declared scalar contract.

Only `cname` and `cheader_filename` metadata are supported, with unknown or
duplicate keys rejected explicitly. There are no header includes/parsing,
link metadata, source extern/export aliases, packages, namespaces,
modules, constants, enums, macros, C globals, C bool, typed/deep pointers, arrays, strings,
structs, unions, callbacks, variadics, ownership/nullability metadata, array lengths, GIR,
typelib, GObject, generated headers, or VAPI exports. Later features must feed
the existing normalized foreign model and preserve CABI's physical authority.

See [ADR 0022](../decisions/0022-vapi-foreign-declarations.md),
[C scalar imports](../abi/c-scalar-import-v0.md), and [usage](../language/vapi.md).

## PTR-1 extension

This declaration grammar now accepts `void*` in results and parameters. Scalar
v0 C ABI programs retain their frozen profile; the declaration extension selects
[C pointer v1](../abi/c-pointer-v1.md) when needed. Spaces/comments around the
single type star are lexical trivia. Extra stars are collected for deterministic
unsupported-depth diagnostics, with no typed/deep-pointer semantics. `null` is
an Astra expression only. All current void* values are nullable and unmanaged;
no pointer-specific metadata or header-derived type authority exists.

OBORROW-1 reserves `borrowed` as a parameter qualifier. `borrowed void*` or an exact `borrowed Handle`
is valid; invalid qualified types are rejected during semantic collection.
The contract is behavioral, and all physical signatures remain unchanged.
See [borrowed parameters](borrowed-parameters.md).
