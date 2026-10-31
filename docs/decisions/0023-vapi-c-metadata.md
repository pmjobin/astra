# 0023: Normalized C symbol and header metadata

Status: accepted for ASTRA-VAPI-META-1.

## Context and decision

ASTRA-VAPI-1 already normalizes external declarations through
ForeignDeclarationInput and ordinary CFunctionSymbol objects. Local and external
names are distinct fields downstream, but both previously received the same
spelling. META-1 makes that distinction useful without adding another call path.

1. C external symbol identity and Astra source-call identity are separate authorities.
2. Source `extern(C)` currently defaults the external symbol to its source name.
3. VAPI may override that symbol using explicit `CCode` metadata.
4. Header metadata describes foreign API provenance/integration; it does not alter language semantics.
5. VAPI metadata normalizes into generic, origin-independent C foreign metadata.
6. No downstream IR, ABI, or backend concept is specific to VAPI.
7. CABI remains the physical foreign-call authority.
8. C external-symbol uniqueness is validated in CABI, independently of Astra callable-name uniqueness.
9. A header name does not imply reading, including, or preprocessing a header.
10. A header name does not imply an object, library, or other linker input.
11. Missing or nonexistent headers do not invalidate META-1 compilation.
12. `cname` changes physical C identity only; Astra calls continue to use the declaration's local name.
13. Imported foreign calls remain conservatively effectful, including discarded results.
14. Metadata never changes Astra evaluation order, short-circuiting, loops, transfers, or traps.
15. Native NABI remains completely unaffected and native-only.
16. C exports retain their existing source-name external-symbol policy, with no header metadata.
17. Import/export external-symbol collisions remain CABI errors.
18. This is an Astra-defined VAPI subset inspired by familiar conventions, not wholesale Vala compatibility.
19. Unknown metadata keys fail explicitly; they are never ignored.
20. Duplicate metadata keys fail explicitly at the later key.
21. Future pointer/ownership metadata must enrich this same normalized foreign declaration model.

## Representation and alternatives

`Astra.Foreign.CForeignMetadata` in `src/foreign/c-foreign-metadata.vala` owns
the exact external symbol, optional symbol-value SourceSpan, and an immutable
ordered collection of CForeignHeader entries (name and optional SourceSpan).
The collection is copied on construction and exposes only count/index reads.
The shared model depends on source provenance and GLib, with no syntax, semantic
type, IR, ABI, or LLVM dependency. META-1 creates zero or one header entry.

ForeignDeclarationInput carries that metadata alongside its existing spans and
parameters. Source extern collection creates the same default metadata in
CFunctionSymbol immediately. VAPI defaults use the declaration name; explicit
values replace only the metadata fields. The same immutable metadata can be
retained through CFunctionSymbol → CoreCFunction → CfgCFunction → SsaCFunction →
CAbiFunction without keeping any earlier declaration or parser object alive.
Declaration/name spans remain on each stage's declaration. Calls retain their
existing exact target identities and never own header metadata.

Keeping VAPI syntax downstream would couple every stage to one declaration
origin. Copying separate mutable symbol/header fields at every boundary would
create redundant authorities and mutation risks. A shared immutable data object
preserves stage independence while making provenance and retention explicit.

Core/CFG/SSA formerly rejected duplicate physical symbols as malformed IR.
With aliases, two valid local call targets can intentionally reach the physical
validation boundary with the same external spelling. Those three verifiers now
check nonempty symbols, ABI, signatures, ordinals, and exact identities; CABI
alone checks physical uniqueness across ordered imports, then ordered exports.
This also allows precise user diagnostics instead of premature internal IR
errors. Tests now prove these inputs pass structural IR verification and fail
at CABI. Local-name uniqueness remains semantic analysis's responsibility.

## Bounded syntax and consequences

The optional attribute is exactly `[CCode (key = "value", ...)]`, with at least
one entry, no trailing comma, and at most one attribute per function declaration.
Only case-sensitive `cname` and `cheader_filename` are supported. Both values must
be nonempty and NUL-free. UTF-8 strings permit only `\"`, `\\`, `\n`, `\r`, and
`\t` escapes; raw CR/LF and malformed strings reject deterministically. Symbols
and headers are otherwise opaque. Commas inside a header string do not split it.
See the [complete metadata contract](../vapi/vapi-c-metadata-v0.md).

Semantic, Core, CFG, SSA, and CABI dumps show local/external names and optional
`headers`, never VAPI key names. Unannotated import dumps stay byte-for-byte
stable. LLVM lowering is unchanged: CABI supplies the declaration's exact
physical name, and calls follow object-identity maps. Headers have no LLVM
effect and no link behavior. The existing backend guards for native implementation
symbols and executable `main` still apply.

No new production dependency, general source attribute framework, source extern
alias, export annotation, pointer/rich type, C bool, ownership/nullability,
header parser/preprocessor, library metadata, pkg-config, or GIR work is included.
