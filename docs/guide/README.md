# The Astra Programming Language

Development edition 28-A2 · GNU/Linux x86-64 · LLVM 23.1.4.

Astra is a systems language with exact value types, checked ownership and an
explicit native compilation pipeline. This book teaches the implemented profile
through small working programs and a multi-file readings application. It assumes
basic familiarity with running a command in a terminal, but does not assume
experience with ownership types or compiler internals.

Read in order the first time. Each chapter starts with a problem, introduces the
needed language, then points to the [Reference](../reference/README.md) for its
precise bounds. The opening three chapters follow five readings from a checked
sum to a loop and copied records, using exit 0 for successful checks. Full program fences and
source downloads match test-owned fixture bytes. Some older experiments and later
chapters deliberately return 42; follow their stated status checks rather than
treating that nonzero sentinel as ordinary command success. Examples marked as
compile failures are never executed; a deliberately failing runtime check is
labeled separately.

## Contents

- [Getting a first program running](getting-started.md)
- [Values, decisions and progress](values.md)
- [Records and small calculations](records.md)
- [Objects, owners and observers](objects.md)
- [Sequences without hidden costs](sequences.md)
- [Generic functions and matching](generics-match.md)
- [Text, failures and useful diagnostics](text-errors.md)
- [Calling native C code](ffi.md)
- [Hosted and freestanding calculations](profiles.md)
- [A multi-file readings application](application.md)
- [Documentation, tooling and migration](tooling.md)
- [Glossary, index and edition history](glossary.md)

These chapters provide real source and reproducible commands. They do not promise
every syntax feature represented by the parser. Current native refusals include
some constructs described in older project manuals; the [feature matrix](../reference/limits.md)
and the failure examples explain those differences before you depend on them.
The coverage ledger keeps remaining specification gaps visible. A readable book
and passing examples do not by themselves establish complete language acceptance.

The generated [library API](../api/library.html) and [compiler API](../api/compiler.html)
provide checked declarations. Use the complete-book HTML routes for browser Find
and printing. Canonical Markdown, offline HTML and print-friendly HTML are this
edition's products. Performance comparisons are 28-B, developer experience 28-C,
release qualification 28-D, and professional printed-book production a later task.
