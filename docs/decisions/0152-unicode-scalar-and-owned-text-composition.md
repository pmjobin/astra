# Unicode scalar and owned text composition

The opt-in `text/unicode-scalars.astra` library adds scalar count, scalar-to-byte
offset, Unicode scalar value, scalar-based owned slicing and an owning
`Vector<Utf8Message>` split result. The implementation is ordinary Astra using
the existing counted read-only byte observer and validated UTF-8 snapshot
factory. No new byte-to-text cast, mutable text view or compiler representation
is introduced.

A `string` already has the strict validated UTF-8 invariant. Scalar algorithms
can therefore walk leading-byte widths and decode the exact scalar without
validating an untrusted byte array a second time. Untrusted bytes still enter
through `utf8_message` or builder snapshot validation. U+0000 is an ordinary
counted scalar, combining marks count separately, and U+10FFFF is accepted.
There is no normalization, grapheme segmentation or locale policy.

Scalar indexes are zero based; the count denotes the valid end offset, but not
a scalar value. Negative/out-of-range indexes and overflowing slice ranges
throw `ScalarRangeError`. Scalar slices map both ends to checked byte offsets,
then use the existing owned validated segment operation. Byte search/segment
APIs keep their explicit byte units and split-sequence checks. Empty split
delimiters throw `TextDelimiterError`; leading, trailing and adjacent delimiters
preserve empty fields. Each field owns a new snapshot, and the returned generic
container retires it exactly once. Inputs are borrowed unchanged.

Public witnesses return an owning record combining original text, a generic
field container and scalar metadata, move out its owned fields, and inspect the
container through the normal scoped readonly foreach helpers. They execute at
O0/O1/O2 against Python's independent Unicode and byte encodings with
unsuppressed Valgrind. Strict numeric tokens exercise both int limits and
recoverable parse errors. Separate counted-byte witnesses include embedded NUL,
invalid UTF-8 classes, attempted byte-boundary splitting, unchanged original
owners and a builder that fails a truncated snapshot, then successfully appends
the missing continuation bytes. Older snapshots stay unchanged after mutation.
Invalid-source controls reject mutable backing access, an owning record copy
and implicit byte-slice-to-string reinterpretation at all public checked stages.

This library selects existing hosted text operations, their legacy Bag
declaration, the general Vector declaration and the explicit read-only byte
provider. Their recipes remain explicit; no regex provider or dialect is
selected. There is no mandatory regex, JIT, GObject or io_uring dependency.
Allocation exhaustion retains the existing fatal allocator policy; the checked
range/parse/encoding errors do not imply recoverable allocation failure.
