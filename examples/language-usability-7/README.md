# Language usability application corpus

Eight distinct A49–A56 programs are implemented and qualified here. Earlier
A01–A48 retain their declared historical scope; this is not a fresh full-56 run.

| ID | Source | Inputs and observable task |
| --- | --- | --- |
| A49 | `counted-record-scanner.astra` | One binary file. Each byte count 1–254 precedes that many unsigned bytes; zero is an empty record; 255 terminates scanning and leaves any tail unread. Reports nonempty record count, value count, i64 sum, consumed byte count (including count/terminator bytes), and empty records. Empty input succeeds; truncated/missing input returns 65. |
| A50 | `diagnostic-bag-report.astra` | Mode `all`, `first`, or `empty`. Renders severity ≥2 through readonly Bag foreach loans. Constructor/destructor output independently identifies traversal lifetime. `outside` deliberately indexes at count and must hit the occupied-slot fatal guard. |
| A51 | `nullable-boundary-processor.astra` | One label, `none` or `fail`. Refines optional owned input, calls a nonnull parameter, then transfers to a nonnull field and uses its promised receiver borrow. Reports acceptance and exact destructor order; checked refusal returns 65. |
| A52 | `ordered-policy-engine.astra` | A numeric string and `normal`/`fail`. Applies `0 <= measure < 100` with visible lower/middle/upper counters, proving one middle evaluation, skipped upper work, NaN/Inf behavior and checked measurement failure. |
| A53 | `scoped-config-renderer.astra` | A UTF-8 configuration-name file and mode `all`, `early`, or `fail`. Loads one owned receiver, renders a field and a property, observes nested receivers, and demonstrates cleanup before return or catch. Empty, invalid UTF-8 and missing input return 65. |
| A54 | `float-telemetry-report.astra` | Output path and one decimal string. Writes a two-width round-trip table with signed zero, smallest subnormal, finite extremes and canonical specials. Invalid/range input and file errors return 65 before successful publication. |
| A55 | `source-inspector.astra` | One or more UTF-8 source files. Reports physical line totals and byte-column diagnostics for leading spaces, trailing whitespace and NUL. LF/CRLF and empty files are supported. This is a hygiene inspector; grammar validation belongs to the compiler/formatter. Findings return 1; checked input errors return 65. |
| A56 | `diagnostic-transform-pipeline.astra` | Input/output paths. Parses nonempty decimal lines through a scoped policy into promised nonnull Measurement owners in an exact Bag, then readonly foreach writes an owned formatted report with accepted/outside/NaN counts. Composes U1–U4 and has actual U5 format/recompile parity. Invalid UTF-8/numbers, missing input or output failures return 65. |

The portable acceptance recipe is:

```sh
python3 tests/language-usability-7/apps-check.py /absolute/path/to/astrac /external/output/directory
```

Run from the actual repository. The harness uses public `astrac -O0`, `-O1` and
`-O2`, compiles the explicit GNU Linux provider sources with `cc`, and keeps
inputs, linked products and JSON source/compiler/product digests under the
external output directory. It executes exact output/error controls, unsuppressed
Valgrind, and expected fatal controls. A49 also checks descriptor cleanup. It
formats each source to a new external file, checks originals without editing,
and recompiles formatted sources at each optimization level to the same outputs.
Formatted variants and optimization variants are never counted as distinct apps.


The corpus currently qualifies 300 process commands, 57 exact file observations,
48 linked products (24 original and 24 formatted), and 75 clean unsuppressed
Valgrind runs. The A54 test-only GNU host initializer establishes and asserts
actual C/fr_CA numeric locales before entry; it is not a production dependency
of the application. All apps explicitly select the hosted text, arguments,
files, text-ops and floating-text providers (plus libm). There is no autolink.
