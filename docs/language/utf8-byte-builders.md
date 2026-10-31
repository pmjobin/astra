# Building counted bytes into UTF-8 messages

Select `lib/astra/text/utf8-byte-builder.astra` explicitly, with
`lib/astra/text/utf8-message.astra` and `lib/astra/base/errors.astra`. The concrete
`Utf8ByteBuilder` owns one mutable byte buffer protected by ordinary
[private fields](private-fields.md). It exposes no backing slice or string view.

| Operation | Contract |
| --- | --- |
| `new Utf8ByteBuilder()` | Empty unique owner, byte count and capacity zero |
| `byte_count()` | Live byte count, copied int |
| `capacity()` | Backing capacity, copied int |
| `reserve(int requested)` | False for negative input without mutation; otherwise ensure at least requested capacity; no shrink |
| `append_bytes(u8[] fragment)` | Borrow synchronously and copy exact raw bytes in order; false on unrepresentable total without mutation |
| `snapshot() throws InvalidUtf8` | Validate the full live prefix through Q19A and return a fresh `owned Utf8Message` |

Plain `u8[]` input is the existing noescape borrow. The caller keeps its owner,
and can mutate or retire its input after append returns. Fragments may be empty,
contain NUL, or split a UTF-8 scalar. Append does not claim they are text.

```astra
var builder = new Utf8ByteBuilder();
u8[1] first = {195}; u8[1] second = {169};
if (!builder.append_bytes(slice(first))) { return 81; }
try { var incomplete = builder.snapshot(); return 82; }
catch (InvalidUtf8 error) { /* the one byte remains intact */ }
if (!builder.append_bytes(slice(second))) { return 83; }
var message = builder.snapshot();
release builder;
if (message.text != "é" || message.text.byte_length != 2) { return 84; }
```

This fragment belongs inside a function that catches or declares the ordinary
checked InvalidUtf8 effect. The complete [application](../../examples/utf8-byte-builder/main.astra)
constructs two actual runtime fragments, preserves `a\0b`, grows both builder
and `Bag<Utf8Message>` from 2 to 3, and demonstrates independent snapshots and
normal/early/checked-error cleanup. Build from the repository root:

```sh
builder_run="$HOME/Workspace/codex/work/astra/build/examples/utf8-byte-builder"
mkdir -p "$builder_run"
cc -std=c11 -Wall -Wextra -Werror -c lib/astra/platform/args-posix.c -o "$builder_run/args.o"
cc -std=c11 -Wall -Wextra -Werror -c lib/astra/platform/text-posix.c -o "$builder_run/text.o"
"$HOME/Workspace/codex/work/astra/build/astrac" examples/utf8-byte-builder/main.astra lib/astra/text/utf8-byte-builder.astra lib/astra/text/utf8-message.astra lib/astra/collections/bag.astra lib/astra/base/errors.astra lib/astra/hosted/text.astra --link-object "$builder_run/args.o" --link-object "$builder_run/text.o" -o "$builder_run/example"
"$builder_run/example"
```

The portable [qualification recipe](../../tests/text-own-1b/verify.sh) uses the
same source/provider inputs and records exact native and independent O2 commands.

Counts are signed I32: `0 <= count <= capacity <= 2147483647`. Append checks
`incoming > INT32_MAX - count` before adding, allocating or mutating. Automatic
growth starts at one and doubles, using the checked required count when another
doubling would overflow. Explicit reserve grows to exactly the requested count.
Growth allocates a new zeroed buffer, copies live bytes, exchanges complete
owners, then frees the old backing once. Existing checked index/extent proofs
remain enabled; no `realloc`, pointer cast or new allocator is used.

No-growth append costs O(fragment length). Growth also zeroes the replacement
capacity and copies the live prefix. Automatic doubling amortizes over appended
bytes while doubling is representable. Above the I32 doubling cutoff, growth
uses the exact required count: repeated small appends can then require a full
copy each time. Repeated explicit reserve requests can also incur repeated full
copies. Snapshot allocates an exact-size temporary, copies the live prefix, then
uses Q19A's linear validation and independent immutable payload copy. Nonempty
snapshot therefore adds one temporary allocation beyond Q19A's message/payload
allocations; peak byte storage is roughly capacity + twice the live count.

Failed UTF-8 validation changes no builder state and publishes no message.
Appending missing continuation bytes can repair a truncated sequence before a
later snapshot. Permanently malformed bytes stay malformed; this API has no
clear/overwrite operation. Each successful snapshot has a distinct unique owner
and independently allocated nonempty payload. Later appends, reserve, owner
moves and destruction cannot affect completed messages. Q19A's shortest-form
validation, counted embedded NUL, checked error delivery and receiver-bound
immutable `.text` loans remain unchanged.

Normal/early/checked exits clean live temporaries, backing and message owners
deterministically. Hosted allocation exhaustion remains fatal and supplies no
unwind guarantee. This finite API adds no normalization, formatting, substring,
I/O, asynchronous buffer transfer, generic runtime or shared ownership facility.
Broader Q19/Q20/Q21 and Track C remain open.
