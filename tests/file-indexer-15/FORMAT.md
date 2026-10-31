# File index format, version 1

The index describes identifiers in counted UTF-8 text. It scans the complete
text, including comments and quoted fragments; it does not parse Astra syntax.
An identifier matches `[A-Za-z_][A-Za-z_0-9]*`. Non-ASCII scalars delimit these
ASCII identifiers. Case and spelling are preserved. Numeric prefixes do not
prevent a later letter from starting an identifier.

Strict UTF-8 validation precedes indexing. Invalid UTF-8 and embedded NUL are
checked errors; input is never silently truncated. A truncated source-language
construct remains ordinary text. A missing or unreadable input produces `read`.
Errors do not publish a partial document or prevent later inputs from being
reported.

A byte offset starts at zero. Lines and columns start at one. LF advances the
line and resets the column; every other Unicode scalar, including CR, advances
the column by one. The line count is the number of LF bytes plus one for a
nonempty final unterminated line. Empty input has zero lines. Byte and scalar
counts are distinct; combining characters remain separate scalars.

The report is ASCII TSV with one LF after every record, including the last:

- `astra-index<TAB>1`
- `file<TAB>path<TAB>bytes<TAB>scalars<TAB>lines<TAB>occurrences<TAB>distinct`
- `word<TAB>path<TAB>identifier<TAB>frequency<TAB>first-byte<TAB>first-line<TAB>first-column`
- `error<TAB>path<TAB>read|invalid-utf8|embedded-nul`
- `summary<TAB>successful-inputs<TAB>errors<TAB>total-successful-bytes<TAB>total-occurrences`

Files are reported in argument order, including repeated inputs. Each successful
file's words follow it in ascending ASCII identifier order. Summary totals count
successful input requests; errors contribute no partial totals. Path labels
preserve the exact argument bytes: printable ASCII 0x21 through 0x7e is literal
except `%`; every other byte uses uppercase `%HH`. Thus spaces, tabs, arbitrary
UTF-8 filesystem names cannot break record boundaries. The current CLI uses the
hosted UTF-8 argument snapshot contract: invalid UTF-8 argument bytes are rejected
before entering Astra main. Such arguments are unsupported; they are never
silently truncated or reinterpreted as valid path text.

`oracle.py` specifies this external format using Python's strict UTF-8 decoder
and regular-expression scanner, independently of Astra parsing, ownership, cache,
callback or async implementation. It is a reference for application output, not
an implementation of the application's runtime machinery. Cache reuse,
replacement, extraction, checked callbacks and suspension/cancellation require
separate executed observations in the application qualification.

The authored Foundation, Analysis and CLI now implement this format. `build.py`
builds monolithic or opaque native variants; `qualify.py` compares their actual
output and cache/sink observations with the independent oracle. The default async batch entry implements this same multi-file protocol, retaining
owning argument snapshots, one cache and one checked callback environment across
actual producer suspension. Virtual and Linux timer providers are separate build
profiles; file transfers use the explicit synchronous POSIX adapter in both.
Cold, suspended and partial-batch cancellation have separate controls. The
original single-file prototype remains available with --async-entry=single.

The optional --read-fault-adapter is test-only transport injection. It delegates
to the real POSIX provider and can fail one read after a requested byte prefix;
Astra performs rollback and later retry. Default builds omit this adapter.

Full optimization/native graph matrices, external staging and the separate frozen
reconciliation challenge now have executed evidence. Final qualification remains;
these files do not establish milestone PASS.
