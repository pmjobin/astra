# Source component

This is the first reusable Astra compiler component, compiled by the repaired
Vala C0. It is not C1 or evidence of a self-hosted fixed point.

`source.astra` owns input bytes and normalized filenames, calculates line starts,
validates bounded UTF-8 (including NUL rejection), exposes checked byte ranges and
locations, retains source instances in spans, and renders diagnostic locations.
Offsets are zero-based byte offsets and spans are half-open. Lines and columns
are one-based; columns count non-continuation bytes, excluding CR/LF, rather than
display width. Tabs count once. CR, LF and CRLF each end one line. EOF is a valid
location. Invalid UTF-8 reports the leading byte of the first malformed sequence.

Path normalization removes empty and `.` components, preserves `..`, case and
Unicode bytes, and performs no filesystem access or symlink resolution.
`source-set.astra` owns, sorts and deduplicates normalized path snapshots by UTF-8
byte order. It uses a simple selection sort for this initial facade.
Source identity uses the existing typed borrowed Class comparison described in
[shared identity](../../docs/language/shared-identity.md), independently of paths.
`cover` retains its source once for the new span; comparison acquires no owners.

The Vala `SourceFile` byte/line/encoding contracts, `SourceSpan` coverage and
`Diagnostic.format` are implemented here. API differences are explicit: byte
slices are owned raw-byte snapshots, paths and diagnostics are owned UTF-8
snapshots, and invalid byte/range/cover requests throw `SourceBoundsError` where
the Vala reference asserts. The span constructor still asserts valid bounds.
The native-interface input flag is retained. File loading is a caller primitive.

The `SourceSet.files` object collection, nonempty-set constructor policy and
path-bearing duplicate error text remain unported; the facade returns normalized
paths and a typed duplicate error. No SourceSet IDs or global source registry are
introduced. Lexer/parser callers and their diagnostic integration are next;
semantic analysis, IR, native-unit interfaces and LLVM lowering remain Vala.

Run the component with an explicit compiler and external output directories:

```sh
build="$HOME/Workspace/codex/work/astra/build/selfhost-foundation-1"
runtime="$HOME/Workspace/codex/work/astra/runtime/source-component"
python3 tests/selfhost-foundation/run.py --compiler "$build/astrac" \
  --build "$build/source-component" --runtime "$runtime"
```

The script builds the unchanged Vala oracle separately and compares it with Astra
O0/O2 and independent Python byte arithmetic. Existing C providers only supply
file/process/text-byte primitives. Source algorithms execute in Astra. The Meson
`source-component-check` target runs this same entry point; `qualification_runtime`
can select the external receipt directory. Requires hosted POSIX, Vala and a C
compiler. Valgrind is used when available and its presence is recorded.
