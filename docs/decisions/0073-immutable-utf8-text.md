# ADR 0073: Immutable UTF-8 text and bounded native views

Status: accepted and implemented by ASTRA-TEXT-1.

Astra has one canonical builtin `StringType` per semantic universe. `string` is
an ordinary builtin type name, subject to the scalar builtin replacement policy;
it is not a lexer keyword. Static backing, borrowing and ownership are contracts,
not alternative string type identities. TEXT-1 never creates a text owner.

A value denotes well-formed UTF-8 bytes encoding Unicode scalar values. The
native view is exactly base PTR followed by signed byte_length I32. Contents are
immutable; copying/rebinding a local copies this descriptor. Empty text is valid
and lowers to {null,0}; null itself is not a string. Local parameter copies carry
the incoming invocation-bounded origin. Fields, properties, collections,
addresses, mutable aliases, indexing and raw pointer access remain excluded.

Ordinary quoted literals accept raw UTF-8 and `\"`, `\\`, `\n`, `\r`, `\t`,
`\0`, four-digit `\u` and eight-digit `\U` scalar escapes. Surrogates, malformed
UTF-8, overlong forms, out-of-range scalars, raw NUL and physical newlines reject.
Noncharacters, unassigned scalars, embedded escaped zero and literal U+FEFF are
valid. No normalization, case folding, locale conversion or C-string semantics
occur. Native syntax does not change the independent VAPI/CCode grammar.

`byte_length` is the stored UTF-8 byte count. `==`/`!=` compare full byte content
and length, evaluating both operands once in source order. Text-producing
constant expressions are literals, constant references and parentheses; text
length and equality feed the existing scalar constant evaluator. Declarations
erase, but used text may require private read-only program data.

Plain and explicit borrowed native parameters select BORROWED_NOESCAPE, including
methods and constructors. Plain native string results are deliberately STATIC_TEXT
only. Every definition must verify all its return origins before the checked
program is published. Recursive calls impose the same definition obligation;
visible callers never establish static lifetime. Finite per-write origin equations
join branches and loop backedges; unknown or borrowed roots reject. No descriptor
scope extends the backing lifetime. Future owned/borrowed results need distinct
explicit contracts and must not weaken this result promise.

Core, CFG and SSA independently verify payload membership, exact types, UTF-8,
counts and static-result origins. A stage-neutral immutable TextBytes leaf owns
its bytes and no syntax, symbol, source or graph backlink. Source spans remain
stage-owned diagnostic provenance. StringType values form one indivisible text
group through copies, joins, calls and returns. This bounded extension reuses the
existing paired-view transport; it is not a general aggregate SSA abstraction.

The next unused native profile is text-v9, after buffer-v8. An independent
NativeTextType plan owns the exact PTR/I32 role and borrow/static contract. A
text-bearing signature uses v9; signatures without text retain their prior module
profile. A body containing text alone does not reprofile a scalar boundary.
LLVM uses a backend-only {ptr,i32} carrier without hidden result storage.

Literal pooling keys full explicit length and bytes with hash collision equality.
First emitted use in canonical function/block traversal assigns separate
module-local literal ordinals. Nonempty data is private constant exact-size byte
storage without a sentinel; empty text has no global. One generated internal
bounded equality helper is shared per module. Qualified LLVM's per-function
`no-builtins` plus `noinline` policy prevents optimizer-created libc dependencies
without altering numerical or ownership optimization policy.

Alternatives: raw C pointers lose bounds and embedded zeros; writable u8 slices
lose content immutability; heap/refcount strings add ownership not required by
static text; separate static/borrowed types conflate type and lifetime; arbitrary
aggregate SSA generalization exceeds this bounded representation need. The
selected design provides useful literals and native text while keeping those
choices open for explicit later campaigns.

No allocator, RC/GC, runtime metadata, Unicode database or external text runtime
is required by emitted text operations. C/VAPI/export text, text I/O, process
arguments, owned/generated text, concatenation, interpolation, scalar/grapheme
APIs, generic text transport and arbitrary compile-time calls remain excluded.

See [language](../language/text.md), [IR](../ir/text-values.md),
[native ABI](../abi/native-text-v9.md), and qualification.
