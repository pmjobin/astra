# Borrowed C UTF-8 views: text-view-v3

The source form is executable Astra declaration syntax:

```astra
[CCode (cname = "inspect_text", cheader_filename = "reader.h", text_abi = "utf8-i32")]
extern(C) int inspect(borrowed string text);
```

The corresponding VAPI form omits `extern(C)`:

```vala
[CCode (cname = "inspect_text", cheader_filename = "reader.h", text_abi = "utf8-i32")]
int inspect(borrowed string text);
```

Both normalize to one CForeignMetadata transport mode, an ordinary C function,
canonical StringType and explicit BORROWED_NOESCAPE parameter. `cname` selects
physical identity; headers remain opaque metadata. Neither header text nor
symbol spelling supplies a promise. Source CCode supports these three keys;
VAPI also retains its established destroy_function ownership metadata. Metadata
literals retain the small quote/backslash/n/r/t escape vocabulary and reject
NUL, independently of runtime text's Unicode and embedded-zero escapes.

The physical prototype is:

```c
int32_t inspect_text(const unsigned char *data, int32_t byte_length);
```

Each logical string expands **in place** to adjacent PTR data and signed I32
byte count. For `(int tag, borrowed string a, f32 scale, borrowed string b,
f64 wide, void* token)`, the flat order is I32, PTR, I32, F32, PTR, I32, F64,
PTR. No extra source argument, struct, hidden result, size_t channel, pointer
encoding or implicit floating promotion appears. The previously legal int,
void, void*, f32 and f64 result channels remain ordinary C results. Existing
handle ownership contracts are unchanged. No vector, aggregate, narrow integer,
C bool, typed pointer, varargs or callback support follows from this mode.

Unannotated text, plain or owned foreign string parameters, string results,
exports, native-only annotations, unknown modes, duplicate keys and annotations
without text parameters reject. Existing duplicate-cname rules reject all
repeated external symbols, including consistent declarations. Matching raw LLVM
components cannot establish logical signature compatibility.

A C implementation promises to read only the declared immutable byte range,
only during the call. It must not mutate, free, invalidate the owner, retain
pointers or derived aliases after return, or return a borrowed address disguised
as another raw result. These obligations include other aliases and reentrant
activity. Keeping independently copied bytes is allowed. Other ordinary side
effects, including I/O, are allowed; this is not a purity annotation.

The compiler checks the declaration, argument lifetime and mapping. It cannot
prove arbitrary foreign machine code obeys the promise. A false annotation is
a broken foreign contract, not runtime protection against hostile C code.

Exact-size literal storage has no terminator. Embedded U+0000 is a byte of
content. Canonical empty is null plus zero; the reader must neither access a
byte nor require pointer arithmetic in that case. A nonempty view is readable
for exactly its count, never implicitly count+1. Outgoing UTF-8 validity comes
from native formation and borrowing; no rescan, strlen, allocation, refcount,
copy, pin or runtime borrow token is inserted. No raw text data API is exposed.

Literals, constants, verified STATIC_TEXT results and live bounded native views
can be forwarded. Copies, joins and reborrows preserve their existing origins;
the foreign call cannot extend lifetime or make a borrow static. Arguments are
captured once in source order before whole-view boundary expansion. If a
producer traps, later producers and C do not execute. Aliases are allowed.
Other argument domains keep their ordinary borrow-overlap and move-commit rules.
No readonly/readnone, noalias, nonnull-on-empty, speculative-read or whole-function
purity attributes are inferred from this annotation.

CABI's registry extends scalar-v0 / scalar-ptr-v1 / scalar-fp-v2 with
text-view-v3. Only text-bearing signatures select v3; scalar signatures retain
their old profile. Native profiles through text-v9 remain unchanged. The CABI
model owns a logical parameter group, independent channel roles/types,
logical/physical ordinals, mode, role and borrow contract. It neither retains
semantic graphs nor delegates C authority to NativeTextType. Independent
verification checks adjacency, order, signed I32 width, import role and mode;
boundary validation checks exact SSA callee and source-signature correspondence.
Core/CFG/SSA preserve the complete StringType value until LLVM expands it.

The initial emitted C text signature gate qualifies x86-64 Linux only. Unused
foreign declarations participate, as in prior CABI profiles. Native-only text
and text-free modules gain no gate. Mixed floating boundaries also retain the
separate C float/double representation gate. The provider asserts 8-bit octets
and exact signed I32; GCC and Clang observers qualify actual pointer/count and
scalar transport. A host-built adapter object is not portable across targets.

See [ADR 0074](../decisions/0074-borrowed-c-text-and-output.md),
[output](../library/text-output.md) and validation.
