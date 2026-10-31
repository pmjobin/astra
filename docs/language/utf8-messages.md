# Validated immutable UTF-8 messages

For incremental raw-byte assembly before validation, select the concrete
[UTF-8 byte builder](utf8-byte-builders.md). It reuses this factory unchanged.

Q19A adds one explicit compiler-backed factory supplied by the opt-in
`lib/astra/text/utf8-message.astra` library. Its declaration is:

```astra
[Utf8MessageFactory]
owned Utf8Message utf8_message(u8[] bytes) throws InvalidUtf8;
```

The annotation is a bounded native compiler facility. It nominates exactly the
canonical library signature and ordinary message/error Class shapes. It does
not make a user-written validator, a similarly named function or a byte slice
into trusted text. Other native functions still require bodies. There is no
new static-method feature, default library import or public foreign text ABI.

The complete [example](../../examples/utf8-message/main.astra) writes a mutable
byte array during execution, constructs a message containing `a\0b`, changes and
retires the original bytes, and verifies an unchanged three-byte snapshot:

```astra
var message = utf8_message(bytes);
bytes[0] = 120;
release bytes;
{
	var view = message.text;
	if (view != "a\0b" || view.byte_length != 3) { return 81; }
}
release message;
```

These statements occur inside the example's `try` with an `InvalidUtf8` catch.
Build from the repository root, using the external development build:

```sh
"$HOME/Workspace/codex/work/astra/build/astrac" examples/utf8-message/main.astra lib/astra/text/utf8-message.astra lib/astra/base/errors.astra -o "$HOME/Workspace/codex/work/astra/runtime/utf8-message-example"
```

Select the existing `base/errors.astra` ExceptionRoot, or a compatible ordinary
application Error root, explicitly. InvalidUtf8 is an ordinary checked Class
exception derived from that root. Catch it or declare the checked effect through
the existing ERROR-1 rules. Its diagnostic content is exactly `invalid UTF-8`;
no offending-byte excerpt or error offset is promised. The existing Error root
owns a snapshot of that static diagnostic, so error delivery can allocate.

The synchronous call borrows a valid native `u8[]` through return. It checks
the count and nonempty backing relation, validates all bytes, and only then
constructs a fresh unique heap Class and copies its readonly snapshot. It
retains neither caller memory nor its mutable slice descriptor. Equal inputs
produce distinct owners with independent cleanup. A caller may mutate, replace
or release its byte storage after successful return. The ordinary
`new Utf8Message(string)` constructor also remains available for already-valid
text; it performs the existing independent snapshot copy.

Counts range from zero through 2,147,483,647 bytes. Empty input is valid and
creates a distinct non-null message, even though its empty payload can be
`{null,0}`. Embedded U+0000 is ordinary counted content; use equality,
`byte_length` and counted string consumers, never C-string length. The factory
accepts strict shortest-form Unicode scalar UTF-8 and rejects invalid leads,
continuations, truncation, overlong sequences, surrogate encodings and scalars
above U+10FFFF. Combining marks, noncharacters and distinct normalization forms
are preserved. The factory performs no normalization or locale interpretation.
The separately selected [Unicode scalar library](unicode-scalars.md) adds scalar
indexing and owned slicing; grapheme segmentation remains outside this profile.

Validation is linear, followed by an independent counted copy and the existing
allocator's zero initialization. The concrete owner and nonempty payload have
separate allocation/retirement responsibilities; empty payload storage can be
skipped. Invalid encoding allocates no message or temporary payload. Checked
failure cleans ordinary surrounding owners; no partial message is published.
Allocation exhaustion on either the success or error path retains the existing
fatal contract and supplies no checked recovery or fatal-path unwind guarantee.

`message.text` returns the established receiver-bound immutable `string` view.
It owns no bytes and extends no lifetime. Local copies retain the exact receiver
and lexical loan. A view cannot escape, become STATIC_TEXT, or survive a move,
release or replacement of its owner. End the view's inner scope before such an
operation. The message can inhabit an existing concrete owned child-Class slot.
The general [Vector container](generic-class-bags.md) can own snapshots, and
[owning text splitting](unicode-scalars.md) composes it with scalar operations.
Implicit `string = u8[]` still rejects.

See [ADR 0099](../decisions/0099-validated-utf8-message-factory.md) and
[focused qualification](../../tests/text-own-1a/README.md) for the approved
contract, phase-specific authority, mutation controls and executable evidence.
