# 0022: VAPI declaration input for the existing foreign C model

Status: accepted for ASTRA-VAPI-1.

VAPI supplies external typed declarations to the existing C import boundary.
It adds a declaration frontend; it adds no callable domain or ABI implementation.

The frozen decisions are:

1. VAPI is an external declaration source for the existing foreign C semantic
   model. A completed import is the same `CFunctionSymbol` as source `extern(C)`.
2. VAPI provenance survives in `SourceSpan`, including file, line, and column.
   Provenance is diagnostic information, never foreign-call semantic identity.
   No origin enum or downstream origin branch is needed in VAPI-1.
3. VAPI-1 is import-only. Exports remain `export(C)` attachments to Astra-native
   definitions; VAPI has no bodies or export contracts.
4. Files implicitly describe C ABI imports. They do not spell `extern(C)`;
   explicit extern/export syntax is rejected.
5. The scalar subset is exactly int parameters and int or void results, matching
   CABI-1. Type names parse as identifiers. Normalization into semantic signatures
   rejects void parameters, foreign bool, and unknown types before body checking.
6. Parameter names are mandatory, ordered, and unique within each declaration.
   They supply diagnostics, provenance, and the existing ParameterSymbol data.
7. Imports participate in the same direct-call namespace as native definitions
   and source externs. An exported native definition occupies its native name.
8. Duplicate declarations across source and VAPI, within a VAPI file, across
   files, and through repeated identical paths are errors, even with identical
   signatures. There is no declaration merging or path deduplication.
9. Every supplied VAPI file is parsed and structurally normalized before semantic
   analysis. The analyzer validates external signatures, collects all source
   signatures, collects external C symbols, and validates the unified namespace
   before checking any native body. A bad input produces no downstream output.
10. Declaration order never determines whether a source call resolves. CLI
    position relative to the Astra source also cannot change name resolution.
11. Import order is source externs in existing source order, then VAPI files in
    CLI order, then declarations in each file's order. Parameter order is lexical.
    Export ordinals retain their independent existing source-order policy.
12. The dedicated handwritten lexer/parser and `VapiFileSyntax` /
    `VapiFunctionDeclarationSyntax` own VAPI syntax. Astra Syntax classes are not
    a VAPI syntax authority. No parser generator or external runtime is added.
13. The frontend reuses SourceFile, SourceSpan, and Diagnostic. SourceFile owns
    UTF-8 validation, embedded-NUL rejection, and locations. Identifiers use
    `[A-Za-z_][A-Za-z0-9_]*`; comments accept valid UTF-8. Line and non-nesting
    block comments have the same lexical meaning as Astra comments.
14. `VapiNormalizer` copies span-backed spellings and ordered parameters into
    `ForeignDeclarationInput`. SemanticAnalyzer resolves those spellings with
    its canonical BuiltinTypes and constructs ordinary CFunctionSymbol objects.
    Input records and symbols retain no VAPI token, parser, or syntax object.
15. Downstream compilation must not branch on declaration origin. CoreCFunction,
    CfgCFunction, SsaCFunction, and their existing C-call nodes remain authoritative.
    VAPI syntax never becomes IR identity.
16. CABI remains the physical C-call authority under SCALAR_V0: imports have exact
    external symbols, ordered I32 channels, and optional I32 results. Completed
    CABI remains independently usable without VAPI or SSA state. NABI remains
    exclusively native and unchanged.
17. LLVM uses the same SsaCFunction → CAbiFunction → external declaration mapping
    and ccc calls. Native functions/calls and C export wrappers are unchanged.
18. Repeatable `--vapi PATH` is declaration-only input for check, semantic/IR/ABI/
    LLVM dump, and executable modes. The `.vapi` suffix is a convention, not a
    parser gate. Syntax-only modes keep their existing single-source policy.
19. VAPI files imply no linker inputs, libraries, objects, header parsing, or C
    compiler invocation. `--link-object` remains independent. External symbol
    availability is a link-time concern; check and dump modes do not resolve it.
20. A VAPI declaration's Astra call name equals its C external symbol. Alias/cname,
    header/include, and link metadata remain future work, as do richer foreign
    types, ownership, packages/modules, constants/globals, GIR, and GObject.
21. Source extern(C) remains a supported first-class path. Future VAPI metadata
    must enrich the same normalized foreign model instead of replacing or
    forking semantic identity, the IR pipeline, or CABI physical authority.

The alternatives were to normalize both source externs and VAPI immediately,
or preserve the accepted source path and add a narrow external input collector.
The latter preserves source diagnostics and ordering without rewriting export
signature checking, which shares the existing source collector. Both paths use
one analyzer's canonical types and construct the same CFunctionSymbol class;
exact differential tests constrain their semantic and physical equivalence.
The input record has implicit C-import meaning and one name, avoiding speculative
ABI selectors, alias fields, and origin metadata.

See [language usage](../language/vapi.md), [format contract](../vapi/vapi-scalar-v0.md),
and qualification.
