# Astra source layout

Use hard TAB indentation, tab stops 4, and LF in ordinary authored source.
Opening braces attach to declarations/control statements. Attach `} else {`,
`} catch (...) {` and `} finally {`; an intervening comment stays in place.
Keep independent operations and nontrivial bodies on separate lines. There is
no column limit and no forced call/prototype wrapping. Preserve identifiers,
types, ownership, parentheses, imports, directives, literal and comment bytes.

Run from any directory:

```sh
python3 -B tools/format/source.py --check
python3 -B tools/format/source.py --apply bootstrap compiler
```

`--check` returns 1 for pending changes and 2 for unavailable/unqualified tools,
unsafe inputs or failed preservation. `--apply` computes and validates all selected
outputs first, then replaces each changed file atomically, preserving its mode.
Unchanged files are never rewritten. Concurrent source changes are refused.
Selections are tracked files or directory prefixes; explicitly selecting a
protected file is an error. Symlinks and path escapes are refused.
`--receipt EXTERNAL_FILE.json` records per-file hashes, guards and tool/config pins.

Meson exposes `format-check` and `format-apply`. The normal test registry includes
the read-only check and formatter guard tests. Builds, installs and distributions
never apply formatting. No Git hook is installed.

Developer dependencies and exact qualified binary identities are recorded in
`format/toolchain.json`. Set `ASTRA_FORMAT_UNCRUSTIFY` (or `--uncrustify`) to the
qualified release executable and `ASTRA_FORMAT_ASTRAC` (or `--astrac`) to the
qualified compiler. Other tools resolve through PATH. Missing tools or a changed
binary fail with an actionable error: repeat the representative/adversarial
pilots and record the new identity before accepting a different binary.
There is no dependency on an ENVIC checkout. Do not use the Fedora debug
Uncrustify 0.82 build: it refuses source beyond 10,000 lines.

The locally qualified release formatter is built without a system installation:

```sh
cmake -S UNCRUSTIFY_0_78_1_SOURCE -B EXTERNAL_BUILD -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build EXTERNAL_BUILD -j 4
export ASTRA_FORMAT_UNCRUSTIFY=EXTERNAL_BUILD/uncrustify
```

Vala/VAPI use Uncrustify's VALA mode and the derived ENVIC profile. A token-aware
prepass expands multistatement accessors; a postpass attaches clause boundaries
without moving comments. Exactly two normalization passes and one stability probe
are run; bare Uncrustify is not claimed idempotent. Tokens, continued directives,
comments and literal spellings are independently checked at each pass.

C/C++ use clang-format with no width limit, sorting, comment reflow, brace edits,
qualifier sorting or literal splitting. Directives are temporarily shielded with
formatter control comments that are removed before the guard; original source
directives are retained byte-exact. Source-observable line/stringizing sites are
protected. JavaScript uses the same tool plus exact template/regex/token checks
and Node's actual parser. This is a conservative lexer, not a universal JS parser.

Python uses a bounded indentation-only adapter driven by tokenize, preserving
every intra-line byte and multiline payload. The guard compares exact tokens,
INDENT/DEDENT structure and ASTs with type comments. Meson uses its installed
lexer/parser with an indentation-only adapter and independent AST/token checks;
its general formatter rewrites commas/layout even without a practical width cap.
Shell uses shfmt with tabs and an AST comparison retaining comments and heredocs.
Astra uses the public baseline `astrac --format`, an indentation-only formatter
that preserves line count/intra-line layout and checks its own lexer/parser.

`format/scope.json` classifies every tracked source candidate. Update it explicitly
when adding/removing code. Do not include untracked work. Golden companions,
negative syntax/metadata inputs, templates, imported references, immutable source
snapshots and uncommon byte-sensitive executable formats have explicit exclusions
and original hashes. Exclusions do not authorize weakening tests or changing old
receipts. Editors must respect those boundaries even where a tab preference is
shown. Do not globally trim whitespace or format docs/data/generated bindings.

For a fresh external qualification build, `tools/format/build_registry.py`
builds the existing products in batches with explicit `--build`, `--runtime`
and `--jobs` paths/options. Supply `--min-free-bytes` and `--max-build-bytes`
for the task-owned build leaf; these explicit limits are checked before each batch. It retires only its just-built private intermediate
directories, preserving binaries, logs and compiler generated C. Use
`meson test --no-rebuild` afterwards. This does not replace ordinary Meson usage.
`tools/format/compare_compilers.py` compares two compilers on identical inputs
read from an explicit Git base, including native behavior and exact typed dumps.
