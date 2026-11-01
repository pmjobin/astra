# Astra source-language syntax frontend

The source manager, scanner, parser and typed syntax model execute in Astra.
The public production compiler remains the Vala C0, including its parser and
`--parse` / `--dump-syntax` dispatch. Semantic analysis, IR and backends remain
Vala. This component is a syntax frontend, with no Stage 1 or release claim.

Construct `lexer(move source)` from an owned shared `SourceBuffer`. It validates
encoding before any scan. `next_token()` returns an owned `Token`; inspect
`failed` first. On failure the returned EOF placeholder is ignored and the
first diagnostic's half-open offsets and counted message are authoritative.
Subsequent calls preserve the cursor/error. Valid EOF has an empty span at
source length and is repeatable. Bounds/allocation exceptions remain separate
from lexical diagnostics.

Tokens own their spelling, counted UTF-8 payload (including escaped NUL), and
`SourceSpan`. A span retains immutable backing, so tokens and `comment(index)`
results survive scanner destruction. `generated_token` retains the supplied
user span while storing distinct generated spelling. Kind has a typed enum
API through `kind()`; a private scalar stores its code because native class
fields/properties do not yet support sum-value storage. The decoder requires
validated source and a cursor immediately after an opening quote; callers
check its diagnostic before using its payload. Source validation rejects raw
NUL, while decoded text permits it.

Forks share backing and copy cursor/first-error state, starting with no prior
comments. Subsequent tokens, comments and failures belong to each scanner.
Comments are non-nesting. Numeric values are not evaluated; signs and contextual
`>>` splitting remain parser concerns. ASCII identifiers and existing keyword,
operator, suffix, escape and diagnostic policies follow the reference scanner.

Run the explicit compiler-selectable qualification from the repository root:

```sh
python3 -B tests/selfhost-lexer/run.py --compiler "$build/astrac" \
  --build "$build/lexer-products" --runtime "$runtime/lexer"
```

Meson exposes `lexer-component-check` and `selfhost-lexer`. The runner caches
products only after matching source/tool/flags/dependency and output hashes;
every invocation executes tests. The exact Vala decoder class is extracted
without modifications from its syntax/factory file to keep the oracle small.
Batch dumps list kind, start/end, hexadecimal spelling/payload, comments and
first error, followed by independent fork continuation. This is a development
interface, not a published ABI. Hand cases, bounded malformed input and all
tracked Astra sources exercise both O0/O2; Valgrind checks lifetime and failures
when available. Fresh attempts preserve previous failures and logs.

The parser library starts at `syntax_program(move sources)`. It consumes a
retained, sorted `SourceSet` and returns an owned `SyntaxProgram` with either
ordered compilation units or one first diagnostic. No source text is reparsed
by another compiler at execution time. Lexer failures keep their original
diagnostic; bounds and allocation failures retain their separate contracts.
The observation executable is named `astra-syntax-O0` / `astra-syntax-O2`.
It is a component witness, separate from production `astrac`.

`model.json` specifies all 93 reference node families, including 89 concrete
variants and four abstract categories. `model.astra` gives each concrete variant
a typed payload record; `SyntaxHeader` holds common node metadata. `SyntaxArena` stores concrete records in homogeneous
arrays with checked kind, child-category and list-element access. The records
contain distinct node/token/list/text/source index types, booleans and explicit
metadata; a textual dump is never their storage representation. Scalar policy
and dispatch codes have checked typed `policy` / `dispatch` accessors, following
the existing Token compatibility pattern. Constructors preserve the reference's
generated interface and UTF-8 factory nodes as real typed syntax.

The ownership alternatives were assessed against current C0 facilities:

| Representation | Assessment |
| --- | --- |
| An owned polymorphic Class graph | General heterogeneous Class storage/downcasts are outside the current finite native Class contracts; recursive child ownership also complicates failure disposal. |
| An owning sum at every recursive edge | Class field sum storage is not generally available, and recursive enum disposal would still need a depth argument. No language/ABI expansion was introduced. |
| Typed records indexed by one arena | Supported copyable record arrays; checked category access, stable indices, cheap annotations and iterative disposal. Selected. |

Indices are local to their owning arena, with zero meaning an absent reference.
A zero nonnullable list is its canonical empty representation; nullable lists
preserve absent versus present-empty state. Headers retain source identity,
half-open byte offsets and expression tree depth. SourceSet owns original
sources, the arena owns generated sources, and existing Tokens retain their
qualified source spans. Nodes store source indices instead of extra retained
source owners. Data records and child edges own no nodes: dense arrays and
lists dispose iteratively even after partial failure. No parent owning cycle,
escaped borrow, pointer identity conversion or runtime downcast is involved.
Future symbols/types can be separate tables keyed by stable node indices.

Payload arrays, list buffers and owner pools grow geometrically. Type spelling
uses an explicit work stack; the structural visitor uses a bounded breadth-first
queue and records each node once, preserving repeated typed edges. Parser
expression, block and type-application limits match the reference. Nested record
initializers use explicit parser/dumper stacks, preserving the grammar without
imposing an extra depth refusal. Expression/block dumping uses the parsed depth
limits; type spelling and node disposal are iterative.

Each speculative parser owns its lexer fork and token caches. A checkpoint
restores arena inventories and retires speculative token/text/list owners;
retained capacities are reused, and committed type applications stay untouched.
Only a type close splits `>>`, producing separate original-source spans.
Production parsing, semantic restrictions admitted by parsing, and lexical
error priority remain those of the live Vala reference.

`SyntaxProgram.declarations(kind)`, `foreign_classes()` and
`native_instances(include_generic)` expose ordered views of original nodes.
Pass the generic-filter flag explicitly. `inventory.astra` is an independent
typed consumer of declarations, namespace/imports, methods, owned fields,
properties and selected generic signatures. It performs no name resolution.

`projection.astra` defines the development observation `astra-ast-projection/1`.
`S` records identify original ordered sources and subsequently discovered generated
sources; `N` records give node kind/source/span/depth; `E`, `L`, `T`, `B`, `I`,
`X` and `C` records describe typed edges, lists, exact token spelling/payload,
booleans, enum codes, decoded text and concurrency metadata. Node ordinals follow
first breadth-first discovery, rather than allocator or construction order.
The Vala AST oracle walks actual subclasses independently and never reads the
candidate dump. SyntaxDump is a second, byte-exact debugging observation.
Neither observation is a public serialized AST ABI.

The maintained parser qualification is:

```sh
python3 -B tests/selfhost-parser/run.py --compiler "$build/astrac" \
  --build "$build/parser-products" --runtime "$runtime/parser"
```

The runner freezes its corpus before execution, builds under full tool/source/
dependency fingerprints, and batches source inputs inside each executable. It
compares both observations and first diagnostics at O0/O2, keeps independent
expectations and actual AST mutation controls, and runs Valgrind without broad
suppressions. `--corpus-base COMMIT` pins real source inputs; it defaults to HEAD.
Meson exposes `selfhost-parser` and `parser-component-check`. The detailed port
ledger is `port.json`; current execution evidence belongs in the external report.
The next compiler seam is declaration indexing and name resolution over these
typed records, followed by semantic checking. Production compiler replacement
requires its own qualification and authorization.
