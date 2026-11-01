# Syntax component qualification

Run from the repository root with explicit external output paths:

```sh
python3 -B tests/selfhost-parser/run.py --compiler "$build/astrac" \
  --build "$build/parser-products" --runtime "$runtime/parser" \
  --corpus-base COMMIT
```

Meson registers `selfhost-parser` and `parser-component-check`. The current
production `astrac` remains Vala. This runner builds a separate Vala oracle
from the live syntax/source modules and an Astra syntax executable at O0/O2.
Native providers supply process, file, byte-string and diagnostic primitives;
all candidate grammar decisions, AST storage and traversal execute in Astra.
The source list, flags, compiler, tools, dynamic/link dependencies, provider
headers and product bytes participate in preparation identities. Only matching
compiled products are reused. Each invocation executes fresh tests and retains
its own immutable corpus, outcomes, commands, failures and timings.

`corpus.py` defines independent hand cases, boundary refusals and bounded
seeded expression generation. The runner adds every tracked Astra blob from
the selected Git base, arbitrary bytes and original multi-source groups before
executing any candidate. Baseline fragments that fail parsing remain negative
cases. Source identities are never filtered after observing results.

The default executable protocol batches independently parsed files, using the
logical source path `input`. Each result contains `OK` and the exact SyntaxDump,
or the first diagnostic with original byte offsets, followed by `AST` and the
typed projection, then `END`. Text and token data use hexadecimal bytes.
`--program` instead preserves actual paths and parses one ordered SourceSet.
`--native-interface` exercises generated prerequisites; `--inventory` traverses
typed declarations. The projection schema and ownership model are documented in
[the syntax component](../../compiler/syntax/README.md).

`ast-oracle.vala` walks actual Vala subclasses and fields. It does not consume
candidate output or reconstruct nodes from SyntaxDump. Positive cases compare
both independent traversals and exact dumps; negatives compare first messages,
source coordinates and spans. Hand-authored expectations cover acceptance,
precedence, byte layout and diagnostic coordinates. Real AST fault controls
change kind, child order, missing nodes, source identity, spans and diagnostics;
span/source controls preserve the dump while changing the projection.

Separate modes check CLI exit/stdout/stderr, failed speculative forks, survivor
ASTs, expired weak observers, cross-file declaration queues and generic filters.
Deep record initializers and long type suffixes check iterative paths, while
expression/block/type boundaries retain the reference limits. SourceSet scaling
checks sorting and retained source identities. Valgrind runs normal, failure,
deep, fork, duplicate and multi-file paths without suppressions at both profiles.

The ledger in `compiler/syntax/port.json` maps every live production, variant,
program rule and dump branch. Concrete variant witnesses come from executed
structural observations; branch mappings do not claim instrumented branch
coverage. Current counts, exact identities, costs and limitations belong in the
external report. This qualification makes no semantic, backend, Stage 1,
cross-platform or release claim.
