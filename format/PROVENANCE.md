# Formatter provenance

`vala.cfg` derives from ENVIC R98's profile (source freeze
`ddeb5df6209b7b8a6142d864a60731e62f70883d`), supplied in
ASTRA-SOURCE-FORMAT-1-SUBMISSION.zip. Original SHA-256:
`fe30d5af4bbced001b0e836042b89f56a753e7d2568f224658398e250c917302`.
All original profile options retain their values. Two appended options adapt it:

* `cmt_indent_multi=false` preserves internal multiline comment whitespace.
* `indent_relative_single_line_comments=true` prevents unbounded padding growth
  before an inline comment when a compound one-line statement expands.

`tools/format/lexical.py` adapts the packet's conservative
`vala_lexical_guard.py` (SHA-256
`2129fbbd2be9dbcd4f95fadb2e69761b52a8328f5fbd9e5553c3b4cf1d2cfee3`).
It adds positioned tokens, full continued directives, unknown-character refusal,
focused JavaScript payload handling and whitespace-only accessor/clause adapters.
The packet's preserve-only exception helper is not copied: Astra attaches all
adjacent clause tokens, preserving intervening comments. No ENVIC product rules,
inventories or absolute checkout paths are used. No license notices were removed.

Uncrustify release source: upstream tag `uncrustify-0.78.1`,
https://github.com/uncrustify/uncrustify/archive/refs/tags/uncrustify-0.78.1.tar.gz .
The downloaded archive and build log are retained in the task runtime directory.
Archive SHA-256:
`ecaf4c0adca14c36dfffa30bc28e69865115ecd602c90eb16a8cddccb41caad2`.
The approved task-local release build resolves the installed Fedora debug 0.82
build's hard 10,000-line refusal. Actual binary pins, including local shfmt's
empty version string and its RPM identity, are in `toolchain.json`.

Guards supplement actual compilation, preprocessing and behavior comparisons.
Equality of conservative tokens alone is not a semantic-equivalence proof.
