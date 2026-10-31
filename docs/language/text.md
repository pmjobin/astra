# Immutable UTF-8 text

ERROR-1 adds readonly class string snapshots and receiver-bounded property reads with local owner/extent loans: see [native exceptions](exceptions.md). It does not change literals, output or complete general owned text and substring lifetimes.

Q19A adds the opt-in [validated UTF-8 message factory](utf8-messages.md):
`utf8_message(u8[]) throws InvalidUtf8` constructs a unique concrete Class with
an independent immutable snapshot and receiver-bound `.text` view. Byte/string
assignment remains unsupported. General owned strings and substrings remain open.


`string` denotes immutable, well-formed UTF-8 text. It is a builtin type name,
like `int`, not a reserved lexer keyword. User-defined types cannot replace it;
unrelated function, local and member names follow their existing namespaces.

This example is exercised in [the installed BASELIB consumer](../../examples/base/text.astra):

```astra
const APP_NAME = "Astra";
bool is_application(string name) { return name == APP_NAME; }
string default_name() { return APP_NAME; }
int main() {
	var name = default_name();
	assert(is_application(name));
	assert(name.byte_length == 5);
	return 0;
}
```

`assert` is ordinary BASELIB source. Build the complete tested consumer with
explicit sources and exactly one failure provider (paths assume the development
build and repository root):

```sh
build/astrac examples/base/text.astra lib/astra/base/contracts.astra lib/astra/base/order.astra lib/astra/base/classify.astra lib/astra/base/clamp.astra --link-object build/lib/astra/failure-trap.o -o build/text-1/text-consumer
```

## Literals and encoding

Double quotes delimit ordinary single-line literals. Raw content must be valid
UTF-8. Physical LF/CR and raw source NUL reject. Adjacent concatenation, prefixes,
raw/multiline forms, interpolation and character literals are unsupported.

| Escape | Value |
| --- | --- |
| `\"`, `\\` | Quote, backslash |
| `\n`, `\r`, `\t`, `\0` | LF, CR, tab, U+0000 |
| `\uHHHH` | Exactly four hex digits denoting one scalar |
| `\UHHHHHHHH` | Exactly eight hex digits denoting one scalar |

Unknown/incomplete escapes and `\x` reject. Surrogates U+D800..U+DFFF reject,
including a pair of surrogate escapes; use a raw supplementary scalar or `\U`.
Overlong UTF-8, stray continuation bytes, truncated sequences and scalars above
U+10FFFF reject. Unassigned scalars and noncharacters remain valid. U+FEFF inside
a literal is content. The existing source-file BOM policy outside literals stays
unchanged. These rules follow [RFC 3629 sections 3–4](https://www.rfc-editor.org/rfc/rfc3629#section-3).
No normalization, case folding or locale-dependent interpretation occurs.

Decoded bytes have an explicit signed-I32 maximum length. The CLI's existing
source limit is stricter: the entire input file must be smaller than INT_MAX
bytes, including quotes and escapes. Compiler checks occur before narrowing;
forged oversized lower-stage counts are tested without gigabyte allocations.

## Views, bindings and lifetimes

`var message = "ready"; message = "done";` copies/rebinds a pointer/count view;
it does not allocate or copy the bytes. Contents remain immutable. A `const`
binding cannot be reassigned; an ordinary `string`/`var` local can. Empty `""`
is valid. Null, pointers and byte slices do not convert to or compare with text.
Standalone `var value = null;` retains its accepted void* meaning.

Plain `string` and `borrowed string` parameters are equivalent bounded noescape
borrows. Their bindings retain the existing parameter immutability rule. Bytes
must remain readable, well-formed UTF-8 and stable during the borrow; lengths
are nonnegative. Empty views may have null bases. Calls do not rescan UTF-8.
Two inputs may alias, and local copies/nested forwarding are permitted. This
exception for immutable text does not broaden Resource/object/buffer borrowing.

Plain string results are static-only in this version. Literals, constants,
verified string results, and local selections exclusively derived from those
sources may return. Branch/loop selections among static texts work. A copied
static view can outlive the inner descriptor's block. Returning a parameter,
its local copy, or a static/borrowed join rejects even if every caller supplies
a literal. Rebinding an original local does not change a previously copied
view. No hidden copy or lifetime extension occurs.

## Length, equality and constants

`value.byte_length` is read-only `int`, evaluated from one receiver evaluation.
It counts bytes, not Unicode scalars or grapheme clusters. The following are
executed by [basics.astra](../../tests/text/fixtures/basics.astra):

```astra
"Astra" == "\u0041stra"       // true
"a\0b" != "a\0c"             // true, content after NUL matters
"a\0b".byte_length == 3
"é".byte_length == 2
"e\u0301".byte_length == 3
"é" != "e\u0301"              // distinct normalization forms
```

Both equality operands evaluate exactly once in source order, including unequal
lengths and identical addresses. Surrounding `&&`/`||` remain lazy. Equality has
content-dependent cost; byte length is a stored count, not a scan.

`const NAME="Astra"; const string OTHER=NAME; const N=NAME.byte_length;`
and `const SAME=NAME==OTHER;` are supported locally and across files, with the
ordinary CONST-1 dependency, cycle, exact-type and erasure rules. Only literals,
constant references and parentheses produce constant text. Length/equality can
feed the scalar evaluator and 1..1024 fixed-array bounds; zero is still invalid.
Calls, arbitrary properties and runtime local/parameter reads remain excluded.
An erased constant can still require private literal bytes, never an exported
constant-name data symbol.

There is no ordering, truthiness, arithmetic, conversion, indexing, slicing,
mutable data, address-taking, string pointer, string field/property, general text collection,
owner qualifier or move. String is outside GEN1_PLAIN_COPY, Ownable and generic
capability admission, including Eq; inference identifies the exact string
candidate and reports the unsupported domain. Concrete text operations inside
otherwise admitted generic bodies work through normal specialization.

TEXT-IO-1 adds an explicit outbound [C/VAPI borrowed text contract](../abi/c-text-views.md)
and an ordinary opt-in [output library](../library/text-output.md). Both metadata
`text_abi = "utf8-i32"` and explicit `borrowed string` are required at foreign
parameters. Forwarding a view never consumes it, extends its backing lifetime,
or upgrades it to STATIC_TEXT. Native StringType and text-v9 stay unchanged.
ARGS-1 adds [borrowed text slices and validated process arguments](process-arguments.md)
with an explicit private snapshot producer. Foreign text results/exports, general
foreign incoming text, C-string adapters, formatting and owned/generated text
remain deferred. This entry does not weaken StringType validation or lifetimes.
