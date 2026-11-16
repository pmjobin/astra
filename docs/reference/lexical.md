# Lexical structure

R-LEXICAL. Complete source buffers are validated UTF-8 before tokenization.
Malformed encoding and raw NUL bytes fail. No normalization or BOM stripping
is part of this source language. ASCII identifiers begin with a letter or
underscore, followed by letters, underscores or digits. Unicode text in a
comment does not establish Unicode identifier support.

ASCII whitespace separates tokens. `//` comments end at a line boundary or EOF.
`/*` comments end at the next `*/` and do not nest. `///` participates in API
documentation association; ordinary comments do not declare symbols. Unterminated
comments and quoted text diagnose a source span rather than ending silently.

R-LITERALS. Integer spelling has no type suffix. Leading zeroes remain decimal.
Modern source adds `0x` hexadecimal and `0b` binary. Separators must occur between
digits: empty prefixes, adjacent separators and terminal separators are invalid.
Context supplies an exact integer type, whose representability is checked before
lowering. Signs remain prefix expressions. Direct signed-minimum literals have
special contextual checking; enclosing arithmetic does not excuse an invalid
positive operand.

Floating spelling has digits on both sides of a decimal point, or an integer
significand followed by an exponent. Optional `f`/`F` and `d`/`D` select precision.
There is no general hexadecimal floating literal or `nan`/`inf` source keyword.
Modern integer separators do not imply floating separator support.

This negative program demonstrates contextual range checking, independently of
physical instruction width. Both target optimization modes must refuse it:

```astra example=negative-literal
language astra27b;
int main() {
	u8 reading = 256;
	return reading as int;
}
```

## Text and locations

Text literals retain counted UTF-8, including escaped NUL. A decoded `\0`
payload differs from an illegal raw NUL in the source buffer. The bounded text
decoder checks escapes rather than inserting replacement characters. Typed
interpolation is specified in [Text](text.md).

R-SPANS. Source spans are half-open byte ranges into retained backing. The
current native driver reports `path:start:end` byte offsets for semantic
diagnostics, rather than display columns or character counts. Some historical
tools render line/column locations; that presentation is not this driver's
contract. Retained tokens and spans must survive destruction of a temporary
scanner. Validation, token spelling and decoded payload remain distinct facts.
