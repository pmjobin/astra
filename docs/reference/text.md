# Text and formatting

R-TEXT. `string` is counted validated UTF-8. Its byte length is not a Unicode
scalar count or a grapheme count. Escaped NUL remains part of its payload;
passing counted text to C does not silently create a terminated C string.
An owned `Utf8Message` retains text backing. `Utf8ByteBuilder` provides explicit
mutable byte construction with checked capacity/failure behavior. Their source
implementations and provider objects must be selected explicitly.

R-FORMAT. Modern `$"...{expression}..."` constructs a typed formatting plan for
an admitted immediate consumer. `format_into(builder, plan)` writes through a
stable named borrowed builder and returns success/failure. `format_text(plan)`
materializes an owned `Utf8Message` under the explicit recoverable-error runtime.
A formatting plan is not an owned string and may not escape as an arbitrary
local, function result or stored closure.

Operands evaluate once in written order. Supported scalar and text categories
are selected by checked formatting signatures. The implementation requires
the actual runtime definitions, not merely helpers with matching names. Text
and message operands retain their borrowing constraints; temporary-message and
unsupported-object forms have negative tests. Curly-brace escaping and malformed
interpolation are validated by the interpolation parser rather than a general
string substitution pass.

## Costs and failures

An adequately reserved sink can format without another owned-text allocation;
constructing or growing the builder may allocate. Materializing owned text is
an explicit different cost. “No allocation” must therefore identify its exact
measured interval and capacity, not describe every use of `format_into`.
The broader format tests wrap allocators and observe operand/error cleanup.

The native scalar formatting helpers use deterministic bounded representations.
Floating formatting in these typed helpers includes exact hexadecimal forms;
the older hosted decimal format/parse provider has its own distinct historical
qualification. This Reference does not promise shortest decimal output, locale
independence for arbitrary C formatting or a scientific text ecosystem.

R-UTF8-BOUNDARY. Invalid UTF-8 and formatting failure do not become successful
text by truncation. The Guide's [text program](../guide/text-errors.md) checks
exact resulting strings and handles the declared error. Unicode normalization,
grapheme segmentation and regular expressions are not implied by validated
UTF-8. Read the generated [library API](../api/library.html) for declaration-derived
contracts; a handwritten duplicate of an API signature is not authoritative.

## Bounded plans and exact scalar text

R-FORMAT-DOMAIN. The current interpolation parser admits at most 64 operands
and refuses nested interpolation. Fragment and hole boundaries are independently
reconstructed from original UTF-8 bytes. A plan has no storable user type and
must be the immediate argument of its admitted formatting consumer. Labels,
extra generic arguments and arbitrary receivers do not substitute for that
signature. `format_into` requires a stable named builder; text/message operands
must retain their specified borrowing roots.

Signed and unsigned integers use decimal digits without grouping or locale
selection. Bool is `true` or `false`. Finite floats use exact hexadecimal text:
a sign when negative, 0x, a leading 0 or 1, a point and fraction, then p and an
explicit signed binary exponent. Trailing fractional zeroes are removed while
retaining a fraction digit. Negative zero, subnormals and extrema preserve their
IEEE bits. NaN and infinity fail this helper instead of silently becoming text.
The [scalar implementation](../../lib/astra/text/scalar-format.astra) is distinct
from the historical hosted decimal formatting provider.

Formatting a plan evaluates each source operand once in written order before
emitting the fragments. The sink operation can fail, and the owned-text path
uses its declared Error runtime and cleanup. No atomic rollback of a partially
written builder is promised. Reserve enough capacity when a measured no-growth
interval matters, and check the boolean result. Valid UTF-8 describes encoding;
it does not establish normalization, scalar indexing or grapheme boundaries.
