# ADR 0076: Caller information and source-aware assertions

Status: accepted for ASTRA-DIAG-1.

Native explicit parameters may request `[CallerFilePath]`, `[CallerLineNumber]`
or `[CallerArgumentExpression("parameter_name")]`. These names have meaning only
in the native parameter annotation position. CCode and VAPI keep independent
grammars. This is a bounded source call-completion contract, with no general
attribute classes, optional/default expressions, macros, reflection or overloads.

Annotated parameters form a trailing suffix. With K required and N total
parameters, K through N positional arguments are accepted. Every supplied value
is checked and evaluated normally. Only the omitted suffix is completed. File
and expression parameters are exact plain/borrowed string, canonicalized to
BORROWED_NOESCAPE; line is exact int/i32. No explicit initializer is admitted.
An expression target is one literal naming an earlier required non-annotated
parameter, resolved once to its exact ordinal. Native free/generic functions,
struct/class methods and constructors use the mechanism. Fields, results,
locals, properties, receivers, destructors and foreign/exported signatures do not.

SourceFile owns the bytes. The existing lexical path normalization, per-file
newline accounting and expression spans are sufficient: ParenthesizedExpression
already includes both parentheses. Captures copy the first through last written
token bytes, preserving interior comments, whitespace, escapes and CRLF. No new
parallel written-span representation or source reopening is needed. The line is
the called name token, including a member name or init. Missing required evidence
or unrepresentable UTF-8/I32 data diagnoses; full explicit calls need no new call
provenance. Spans and immutable TextBytes have separate ownership.

Semantic checking uses the exact declaration, validates minimum/maximum arity
through the existing generic path and prepares ordinary constants without
evaluating arguments. Existing inference observations, proof staging, moves,
borrows, eager evaluation and trap order remain authoritative. A generic inner
call captures its definition site before specialization; metadata never enters
GenericInstance identity. Explicit wrapper forwarding preserves outer values.
An unforwarded wrapper reports its own inner call. Explicit metadata is freely
supplied data, not authenticated provenance.

The semantic contract records kind, optional target ordinal and declaration
provenance. Semantic validation and the independent semantic-to-Core boundary
validate it. All checked calls are fully populated; metadata declarations erase
before executable Core. No new operation, runtime metadata object, ABI profile,
entry signature or backend caller-name authority exists.

`base/diagnostics.astra` defines ordinary eager, always-on `assert_that` and
`assert_message`. False invokes the single borrowed utf8-i32 hook
`astra_diag_assert_fail_v0`; a conforming provider never returns and does not
unwind. Explicit alternative `diagnostics-trap.o` and `diagnostics-hosted.o`
implement this hook. Existing assertions/providers remain separate and unchanged.
Missing/duplicate choices fail through the linker. There is no autolinking.

The hosted provider attempts a fixed five-line stderr report with bounded byte
escaping, flushes stderr, then aborts even on output failure. It validates
negative-count/nonempty-null shapes before reading, trusts readable pointers,
does not rescan UTF-8, and may incur hosted stdio storage/allocation. GCC/Clang
x86-64 Linux objects are qualified; the trap object has no runtime dependency.
Neither provider adds cleanup on fatal paths, including a live ARGS snapshot.

Paths and snippets may disclose secrets, comments and build layout in read-only
program data. Inclusion is explicit. Overrides can shorten labels; there is no
automatic privacy scrub, release elision, prefix map or source obfuscation.
Ordinary byte/count pooling and optimization apply, with measured costs rather
than a zero-overhead promise.

The alternative of assertion-specific compiler recognition would not support
ordinary checkers or explicit wrappers. General optional arguments would add
evaluation and inference semantics unnecessary here. Runtime source recovery
would lose stable provenance and introduce dependencies. The selected design
uses the existing syntax/source and text/ABI boundaries instead.

See [language contract](../language/caller-information.md),
[library/provider contract](../library/source-diagnostics.md) and
qualification. CallerMemberName/columns/stacks,
formatting, interpolation, owned text, recoverable failures and automatic operand
value extraction remain deferred.

References: [C# caller information](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/attributes/caller-information)
provides naming precedent, without importing its optional-parameter rules;
[GCC trap](https://gcc.gnu.org/onlinedocs/gcc/Other-Builtins.html),
[POSIX abort](https://pubs.opengroup.org/onlinepubs/9799919799/functions/abort.html),
[fwrite](https://pubs.opengroup.org/onlinepubs/9799919799/functions/fwrite.html) and
[fflush](https://pubs.opengroup.org/onlinepubs/9799919799/functions/fflush.html)
describe platform facilities. Actual emitted objects and subprocess bytes are
qualification authority for the installed toolchains.
