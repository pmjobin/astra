# ADR 0074: Explicit borrowed C text views and hosted output

Status: implementation and qualification for ASTRA-TEXT-IO-1.

The accepted baseline is `fb6386bb217bbb29f9173265348505da74221dfc`.
Its CABI registry is `scalar-v0`, `scalar-ptr-v1`, `scalar-fp-v2`; native
profiles through `text-v9` are unchanged. Source `extern(C)` declarations had
no CCode attribute plumbing. VAPI accepted callable `cname`, opaque
`cheader_filename`, and `destroy_function` metadata. Both routes already
produce ordinary semantic C function symbols, copied into Core/CFG/SSA.
Imported C parameters and results previously had one scalar channel each.
Duplicate external symbols are rejected, including identical declarations.
The existing C floating representation gate qualifies x86-64 Linux; native
floating/vector and hosted-buffer gates remain separate.

We add callable `text_abi = "utf8-i32"` metadata and require explicit
`borrowed string` on every foreign text parameter. Source callable CCode
plumbing carries only `cname`, `cheader_filename`, and this transport mode.
VAPI retains its existing grammar and ownership metadata. Both normalize
to the same immutable foreign metadata and parameter contracts. Headers
are descriptive; the compiler never reads one to infer a safety promise.

One logical string expands in place to `const unsigned char *` followed by
`int32_t`, independently of the native ABI. CABI owns a grouped parameter
plan, exact channel roles and physical/logical ordinals. `text-view-v3` is
the next CABI profile; only text-bearing signatures select it. The model
verifies without upstream graphs. LLVM expands a captured whole view after
ordinary logical argument evaluation. No text result or export is admitted.
Emitted foreign text signatures require the dedicated x86-64 Linux gate.
Mixed floating signatures also retain the C floating gate.

C is a trusted borrower: it may read only the supplied range during the call.
It must not modify, free, invalidate, retain the pointer or derived aliases,
or return a borrowed address disguised as a raw result. This includes other
aliases and reentrant invalidation. Independently copied bytes may be kept.
Output and other ordinary side effects are permitted. The compiler verifies
the declaration, caller lifetime and physical mapping; it cannot establish
that arbitrary foreign machine code honors the annotation. A false annotation
breaks the foreign contract and does not form a safe interface to hostile C.

StringType remains canonical. Exact-size immutable UTF-8 literal arrays have
no terminator. Embedded zero is content. Canonical empty text is null plus
zero, with no dereference or pointer arithmetic required. No rescanning,
copy, pin, allocation, ownership acquisition or runtime borrow token occurs
at the boundary. Native STATIC_TEXT and BORROWED_NOESCAPE rules are unchanged;
copying or forwarding a bounded view never extends its backing lifetime.

The ordinary opt-in `hosted/text.astra` source implements `print`, `println`,
`print_stderr`, and `println_stderr`. One explicitly selected POSIX provider
uses write/errno and returns status through the existing C I32 channel. The
compiler recognizes neither these names nor stdout/stderr. The provider is
separate from failure providers, buffers and libm. Installation preserves
explicit source/object selection and the target identity.

Alternatives rejected: C strings cannot preserve exact bounds and embedded
zeros without allocation; a C struct changes the physical calling convention;
reusing NativeTextType makes native planning C ABI authority; erasing groups
into raw arguments loses correspondence and independent verification; a
print intrinsic privileges one consumer instead of supplying a reusable
boundary. A grouped CABI extension plus ordinary library code solves the
outbound use without general aggregate ABI or attribute-language machinery.

Incoming C text, argv/process entry, text C exports, c_str adapters, raw data
access, owned/generated/mutable strings, fields/collections, generic string
transport, formatting/interpolation, source-aware assertions, cancellation,
async output, stream objects, integer widths/size_t, modules and automatic
library selection remain deferred. Input needs independent validation and
lifetime contracts.

See [C transport](../abi/c-text-views.md), [output](../library/text-output.md),
and qualification.
