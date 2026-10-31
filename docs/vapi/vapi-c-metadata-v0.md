# VAPI C metadata v0

RESOURCE-1 applies CCode metadata to [handle declarations](handle-types.md).
On a handle, destroy_function is required, cheader_filename is optional, and
cname is rejected. Empty values, duplicate keys and unknown keys retain the rules
below. Cleanup belongs to the nominal type; function-level destroy_function on a
handle result rejects. Headers never affect linking, layout or pointer lowering.

ASTRA-VAPI-META-1 adds C symbol aliases and descriptive header metadata to the
[scalar declaration format](vapi-scalar-v0.md). This is an Astra-defined subset,
not a promise to accept arbitrary Vala VAPI files.

```text
[CCode (
	cname = "astra_test_add_impl",
	cheader_filename = "helper.h"
)]
int add(int a, int b);
```

Astra calls `add(20, 22)`. CABI and LLVM declare/call `astra_test_add_impl`.
`astra_test_add_impl(20, 22)` is not an Astra callable unless independently
declared with that local name. The physical C implementation must match the
declared signed-32-bit parameter/result contract.

## Exact grammar

```text
vapi-file           := foreign-declaration* EOF
foreign-declaration := metadata-attribute? function-declaration
function-declaration := type-name identifier "(" parameter-list? ")" ";"
parameter-list      := parameter ("," parameter)*
parameter           := "borrowed"? type-name identifier
type-name           := identifier ("*")?
metadata-attribute  := "[" "CCode" "(" metadata-entry ("," metadata-entry)* ")" "]"
metadata-entry      := identifier "=" string-literal
identifier          := [A-Za-z_][A-Za-z0-9_]*
string-literal      := '"' (ordinary-character | escape)* '"'
escape              := '\"' | '\\' | '\n' | '\r' | '\t'
```

An ordinary character is any valid UTF-8 scalar other than `"`, backslash, NUL,
CR, or LF. Whitespace and comments may separate tokens as in scalar VAPI v0.
The attribute immediately precedes its declaration, apart from such trivia.
Empty `CCode`, omitted parentheses, repeated attributes, and trailing commas
are unsupported. The parser accepts identifiers as type syntax; semantic
analysis still allows int/void* parameters and int/void*/void results.

## Keys and strings

| Key | Meaning | Default |
| --- | --- | --- |
| `cname` | Exact physical C/linker symbol; does not rename the Astra callable | Local function name |
| `cheader_filename` | One opaque descriptive header name | No headers |
| `destroy_function` | Exact physical void(void*) cleanup for an owned void* result | Unmanaged result |

Attribute and key names are case-sensitive. Each key may appear once, in any
order. All values must be nonempty and contain no embedded NUL. External
symbols are not restricted to Astra identifiers; punctuation, spaces, and UTF-8
remain opaque to this frontend. Existing LLVM/toolchain symbol conflicts still
apply, including the executable entry wrapper and compiler-generated names.

The five escapes decode to quote, backslash, newline, carriage return, and tab.
Raw CR/LF inside a literal is an unterminated-string error. Unknown escapes,
including `\0`, hex, Unicode escape syntax, and escaped physical line breaks,
reject at the backslash. EOF after an opening quote or final backslash reports
an unterminated string at the opening quote. Whole-file SourceFile validation
rejects invalid UTF-8 and literal NUL before parsing, including inside strings
and comments. These literals exist only in VAPI metadata; Astra source has no
string literal type or new attribute syntax.

## Header policy

`cheader_filename = "this/header/does/not/exist.h"` is valid. Astra does not open,
parse, include, preprocess, or verify declarations against that name. Absolute
paths, relative paths, nonexistent paths, names without `.h`, and punctuation
are accepted. `"first.h,second.h"` means one opaque header entry. Header arrays
and multiple-header syntax are unsupported.

Header metadata never changes types, CABI channels, effects, evaluation order,
or LLVM IR. It does not select a library, infer an object, run a C compiler, or
link anything. Supply the implementation separately with `--link-object`.
Check/CABI/LLVM modes can succeed without an implementation; executable linking
then fails on the physical symbol. Missing headers themselves never cause failure.

## Normalized authority and lifetime

VapiFunctionDeclarationSyntax owns an optional VapiCCodeAttributeSyntax with
ordered VapiMetadataEntrySyntax objects. Each entry owns its key token and
decoded string token with exact source spans. VapiNormalizer removes that syntax
authority and constructs ForeignDeclarationInput with `Astra.Foreign.CForeignMetadata`.

CForeignMetadata owns `external_symbol`, optional `external_symbol_span`, and an
immutable ordered collection of CForeignHeader (name and optional span), exposed
through `header_count` and `header_at`. The collection is copied on construction;
no mutable collection is exposed. There are zero or one entries today. Declaration
and local-name provenance remain on ForeignDeclarationInput and each imported
function. Explicit field spans cover their quoted value, including escapes.

Source `extern(C) int foo();` and unannotated VAPI `int foo();` both produce
external symbol `foo`, no explicit symbol-value span, and no headers. The source
collector canonicalizes these defaults immediately in CFunctionSymbol. VAPI
normalization supplies defaults or overrides before ordinary semantic collection.
No VAPI nodes/tokens or origin branches survive in CFunctionSymbol, CoreCFunction,
CfgCFunction, SsaCFunction, CAbiFunction, or LLVM.

Each stage retains generic metadata on the imported declaration. Calls follow
exact function-identity maps. Completed CABI can dump names, headers, and physical
signatures after SSA/frontend destruction. Completed LLVM retains neither CABI
nor header/provenance objects. Native NABI and C export source-name policy remain
unchanged. Imported calls remain conservatively effectful and follow Astra's
left-to-right, short-circuit, and loop rules.

## Uniqueness and diagnostics

Semantic collection checks local Astra names across native/exported definitions,
source externs, and all VAPI inputs. Different `cname` values cannot rescue a
duplicate local name. CABI separately checks external symbols across imports
and exports, even when local names differ. Import order is source externs, CLI
file order, then declaration order; aliases do not affect ordinals. CABI visits
imports in that order followed by exports in source order, reporting the later
claim. An explicit alias's value span supplies its collision location; otherwise
the declaration's name span does. Earlier stage dumps only validate their own
stage; `--check`, `--dump-cabi`, `--dump-llvm`, and compilation reach this check.

```text
bindings.vapi:4:17: error: C external symbol 'physical' is declared more than once
```

Parser diagnostics include unknown attribute, expected attribute name or `(`,
expected metadata key, unknown key, duplicate key at the later occurrence,
expected `=`, expected string literal, unterminated string, invalid escape,
empty `cname`, empty `cheader_filename`, and missing `)` or `]`. Every diagnostic
retains the VAPI filename/line/Unicode-scalar column and exposes no partial syntax.

## Inspection and limits

Semantic/Core/CFG/SSA dumps show ordinary foreign declarations with `(symbol ...)`
and optional `(headers ...)`. CABI shows:

```text
(import #0
	(name "add")
	(symbol "astra_test_add_impl")
	(headers
		"helper.h"
	)
	(signature
		(parameters
			(parameter #0 I32)
			(parameter #1 I32)
		)
		(result I32)
	)
)
```

Headers are omitted when absent. Ordinary source-extern/unannotated VAPI dumps
remain stable. LLVM has `declare i32 @astra_test_add_impl(i32, i32)` and the exact
corresponding C call, with no header data. NABI stays native-only/internal/fastcc.

Unknown future keys (ownership transfer, nullability, array metadata, library, pkg-config)
are errors. No typed pointers, strings as types, arrays, structs/unions, callbacks,
variadics, C bool, packages/namespaces, header parsing, source extern aliases,
export aliases/headers, or GIR/GObject support is introduced. Future foreign
features must enrich this normalized model; see [ADR 0023](../decisions/0023-vapi-c-metadata.md).

## Orthogonal pointer extension

PTR-1 adds `void*` result/parameter types through the same normalized declaration
path. A `cname` still changes only physical C symbol identity; header names remain
descriptive and may be nonexistent. No header parsing, pointer layout authority,
ownership metadata, or VAPI-specific downstream node is introduced. Type spelling
normalizes token boundaries independently of provenance, including spaces/comments
before the star. Native and C pointer ABI profiles remain separate. See
[C pointer v1](../abi/c-pointer-v1.md) and [ADR 0024](../decisions/0024-opaque-raw-pointers.md).

## OWN-1 extension

`destroy_function` is the only new key. It requires a nonempty string and exactly
a void* result. [Owned-result normalization](owned-results.md) adds immutable
CForeignOwnedResultContract/CForeignCleanupContract, interned during semantic
collection across all supplied files. Core creates independent cleanup identities
and copies descriptive metadata without retaining semantic ownership objects.

CABI validates cleanup symbols first, then ordinary imports and exports; all
cross-category collisions reject. Shared destroyers have one exact interned
contract and one physical declaration. Downstream dumps use owned-result/cleanup
terminology. Existing programs without this key retain their prior dumps.

## Borrowed parameter contracts

OBORROW-1's `borrowed void*` qualifier is independent of CCode metadata. It
coexists with cname, descriptive headers and destroy_function, normalizing into
an origin-independent BORROWED_NOESCAPE parameter contract. It neither changes
result ownership nor labels compiler cleanup parameters as borrowed. See
[borrowed parameters](borrowed-parameters.md) for the binding author's promise.
