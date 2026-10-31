# Unicode scalar operations

Select `lib/astra/text/unicode-scalars.astra` with the standard Error root,
`text/utf8-message.astra`, `text/utf8-byte-builder.astra`,
`hosted/text-ops.astra`, `collections/bag.astra` and
`collections/vector.astra`. Link the existing `platform/text-ops-posix.c`
read-only byte observer for the qualified hosted GNU Linux x86-64 LP64 profile.
The Bag declaration is an existing dependency of hosted text operations;
`text_split_owned` returns the general Vector container.

```astra
int inspect(string input) throws Error {
	int bytes = input.byte_length;
	int scalars = text_scalar_count(input);
	int first = text_scalar_at(input, 0);
	int second_byte = text_scalar_offset(input, 1);
	var prefix = text_scalar_segment(input, 0, 1);
	var fields = text_split_owned(input, "|");
	return scalars;
}
```

| Operation | Units and result | Recoverable failure |
| --- | --- | --- |
| `text_scalar_count(text)` | Number of Unicode scalars | None; `string` is already validated |
| `text_scalar_offset(text, index)` | Byte offset at a scalar index; count gives the end | `ScalarRangeError` |
| `text_scalar_at(text, index)` | Integer Unicode scalar value | `ScalarRangeError`, including end index |
| `text_scalar_segment(text, start, count)` | Fresh owned `Utf8Message` | Invalid or overflowing scalar range |
| `text_split_owned(text, delimiter)` | Owned `Vector<Utf8Message>` snapshots | Empty delimiter or existing checked text/capacity error |

For `"λ🙂é"`, byte length is 9 and scalar count is 4. The combining accent is
its own scalar; these APIs do not count grapheme clusters. Scalar offsets are
0, 2, 6, 7 and 9. Embedded NUL contributes one byte and one scalar and does not
terminate the text. No normalization or case folding occurs.

`text_find` returns byte offsets and `text_segment` accepts byte ranges. A byte
range that splits a UTF-8 sequence throws `TextRangeError`; scalar slices choose
valid boundaries automatically. `parse_int` keeps strict signed-decimal syntax
and checked range errors, including rejection of trailing bytes, embedded NUL
and non-ASCII digits. The existing floating parser has its separately documented
provider and policy.

Splitting preserves empty fields, including one empty field for empty input.
Every result owns fresh immutable text. Input owners and prior snapshots remain
unchanged after checked failures. Borrowed `.text` views retain their normal
receiver lifetime; they cannot escape owner retirement or expose builder backing.
Untrusted bytes must still pass `utf8_message` or builder snapshot validation.
No regex facility is selected by this profile.

See [ADR 0152](../decisions/0152-unicode-scalar-and-owned-text-composition.md) and
the [public byte/scalar oracles](../../tests/language-generalization-10/unicode.py).
