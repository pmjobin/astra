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
