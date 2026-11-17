# The Astra Programming Language

Development edition 28-A2 · GNU/Linux x86-64 · LLVM 23.1.4.

Five readings arrive: 2, 4, 6, 8 and 10. Their total is thirty. By the end of this
book, you will have built a native program that reads those values from a file,
checks its input, computes a summary in Astra and reports it through a real C
provider. More importantly, you will be able to explain who owns its storage,
which failures it handles, and how to change the calculation.

This Guide is for an experienced programmer learning Astra. Familiarity with
variables, functions and terminal commands is enough to begin. Ownership,
counted text and the language's exact-type rules are introduced when the program
needs them; compiler internals are not prerequisites.

## What you need before starting

This is a development checkout edition. The first lesson requires the existing
authenticated Astra compiler products, their manifests, the exact LLVM 23.1.4
toolchain, Python 3.11 or later, and a host C compiler/linker. Later lessons use
the existing hosted provider objects; the final link experiment also uses `nm`
and `readelf`. The recipes use the established `~/Workspace/astra` checkout and
external `~/Workspace/codex/work/astra` directories.

A clone alone does not supply the compiler, seed, external toolchain or provider
artifacts. [Getting started](getting-started.md#prepare-the-development-environment)
checks those prerequisites before compiling. If they are missing, resolve that
environment first; there is no one-command installer hidden elsewhere in this
book. [Tooling](tooling.md) explains the existing contributor build routes.

## Follow the readings

Read in order the first time and keep the first lesson's terminal environment.
The program grows one decision at a time:

- [Getting a first program running](getting-started.md): compile, link and check a sum.
- [Values, decisions and progress](values.md): generate, count and filter readings.
- [Records and small calculations](records.md): group related values and copy a record.
- [Objects, owners and observers](objects.md): acquire, borrow and transfer a lifetime.
- [Text, failures and useful diagnostics](text-errors.md): reject input and report real text.
- [Sequences without hidden costs](sequences.md): choose storage, views and deferred work.
- [Generic functions and matching](generics-match.md): reuse an operation and handle alternatives.
- [Calling native C code](ffi.md): connect a declaration to an actual counted-byte provider.
- [A multi-file readings application](application.md): assemble the file-processing tool and modify it.
- [Documentation, tooling and migration](tooling.md): inspect its API and repeat an edit/check cycle.
- [Hosted and freestanding calculations](profiles.md): choose the program's runtime dependencies.
- [Glossary, index and edition history](glossary.md): revisit a term and choose a next project.

## How to use the examples

Predict the result before running a program, then try the exercise before reading
its complete answer. Full Astra/C fences and downloads are exact fixture sources.
Commands put generated files outside the checkout. Deliberate compilation and
link failures are identified before their commands; they are lessons in finding
the failing boundary, not programs to execute.

Most new examples return 0 after checking their results. A silent program's exit
status is different from its stdout; when the shell prints a success message,
the text says so. Some preserved experiments, including the final file application,
use exit 42 as a test sentinel. Their recipes capture that status explicitly.
It is not an ordinary success status or printed output.

Use the [Reference](../reference/README.md) for precise supported rules and the
[library API](../api/library.html) for checked declarations. The
[compiler API](../api/compiler.html) is available for further exploration.
These books cover the implemented native scope, not every syntax form in older
manuals. The [edition note](glossary.md#edition-28-a2-changes) keeps formal coverage
and release limitations separate from the learning path.

The complete-book HTML supports browser Find and printing without JavaScript.
Canonical Markdown, local HTML and print styles are the reading formats here.
Begin with [the first six-line calculation](getting-started.md).
