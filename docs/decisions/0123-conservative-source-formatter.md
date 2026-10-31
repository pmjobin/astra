# ADR 0123: source formatter version 1

Status: implemented; Surge 7 integrated qualification in progress.

`astrac --format FILE` writes formatted source to stdout. `--format --check FILE`
returns 0 only for an already formatted source, 1 for a formatting difference or
source error, and 2 for invalid options or output I/O failure. `--format --version`
identifies formatting version 1; `--format --help` describes the public modes.
`-o NEW_FILE` exclusively creates a new output; it refuses existing files,
including the input or symlink aliases. `--in-place` explicitly opts into replacing
the selected source. An unchanged in-place invocation does not rewrite the file.

Version 1 normalizes leading indentation outside literal/comment contents to
actual hard TAB characters. Brace depth controls indentation; an open multiline
parenthesis/bracket group adds one continuation level. Blank layout-only lines
become empty. Intra-line spacing, token spellings, comments, literal contents,
line endings, declaration order, imports, and existing line numbers are preserved.
A missing final line ending gains a newline. This is intentionally a conservative
indentation formatter; version 1 does not reflow statements or align columns.

The actual parser validates the complete input before any output is written.
The lexer now exposes exact comment trivia spans in addition to ordinary tokens.
The formatter uses those existing SourceSpan identities to protect multiline
comments and literals. It uses no second grammar, text-replacement compiler, or
source-location system. A fresh independent lex/parse pass over the output checks
every token kind/spelling and every comment's exact text before publishing it.
Failures retain the normal source-aware line/column diagnostics.

Qualification covers every explicitly selected library source, the owned-state
application corpus, selected closure/shared applications, and new loop/chain
sources. Each is formatted twice, checked for idempotence, re-parsed, compared by
syntax dump, and audited for unchanged original bytes and metadata. Additional
controls exercise Unicode/NUL/TAB spellings, braces inside comments/literals,
multiline continuation, exclusive output, explicit in-place operation, malformed
input, exact diagnostic positions, and public O0/O1/O2 execution before/after.
No legacy source is reformatted as a side effect.

The formatter accepts the live supported parser grammar, including subsequently
added grammar. Remaining Surge 7 constructs still require their own real source
and integration tests before U5's campaign-level gate can close.
