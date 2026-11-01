# Astra lexical frontend

This reusable scanner executes in Astra using the retained source component.
The public full compiler remains the Vala bootstrap; parser/AST, semantic
analysis, IR and backends are unported. No Stage 1 equivalence is claimed.

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
