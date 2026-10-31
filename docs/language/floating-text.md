# Floating-point text

Select `lib/astra/text/float-format.astra`, `lib/astra/text/utf8-message.astra`,
and `lib/astra/base/errors.astra`. Link the explicit
`lib/astra/platform/float-text-posix.c` provider object and `--link-library m`.

```astra
try {
	var report = format_f64(1.25);
	f64 restored = parse_f64(report.text);
	var small = format_f32(0.5f);
	f32 restored_small = parse_f32(small.text);
} catch (Error error) {
	// Normal checked cleanup retires every acquired message.
}
```

The format functions return owned UTF-8 messages. They use 9 significant digits
for f32 and 17 for f64, preserving finite round-trip bits and signed zero.
They produce `nan`, `inf`, and `-inf` for nonfinite values. NaN payloads/signs are
not preserved. These are round-trip strings; shortest formatting is not promised.

Parsing accepts an optional sign, decimal digits/point, and an optional exponent,
or exactly `nan`, `inf`, `+inf`, `-inf`. It rejects whitespace, trailing bytes,
comma separators, hex, and NaN payloads. Overflow and nonzero values rounding to
zero raise `NumericTextError`; representable subnormals succeed. The `reason`
property distinguishes the error codes documented in
[ADR 0124](../decisions/0124-hosted-scalar-floating-text.md).

The optional provider isolates the C numeric locale. It requires nearest rounding
and returns a checked error for another rounding mode without changing it.
The qualified host is GNU x86-64 Linux, IEEE binary32/binary64.
