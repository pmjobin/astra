# The Astra Programming Language

Development edition 28-A2 · GNU/Linux x86-64 · LLVM 23.1.4.

Astra is a systems language with exact value types, checked ownership and an
explicit native compilation pipeline. This book teaches the implemented profile
through small working programs and a multi-file readings application. It assumes
basic familiarity with running a command in a terminal, but does not assume
experience with ownership types or compiler internals.

Read in order the first time. Each chapter starts with a problem, introduces the
needed language, then points to the [Reference](../reference/README.md) for its
precise bounds. Full program fences match the test-owned fixture bytes. Positive
programs return 42 to make execution observable in a test harness; this is a
deliberate teaching convention, not the usual zero-on-success application policy.
Programs marked as negative examples must fail compilation and are never executed.

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
