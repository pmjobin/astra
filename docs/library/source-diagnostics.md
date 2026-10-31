# Source-aware assertions

The four-file [record numerical client](../../examples/struct-elements/main.astra) exercises source-aware assertions around indexed fields and an indexed method with caller annotations. Its selected argument/output/diagnostic/math providers retain separate explicit interfaces; the compiler does not recognize assertion names.

Opting in can embed filenames, literal secrets and source comments in your
program's read-only data. Select this library explicitly when those diagnostics
are appropriate. Existing BASELIB assertions and providers keep their signatures
and costs.

`base/diagnostics.astra` supplies exactly two new public assertion functions:

```astra
void assert_that(bool condition, [CallerFilePath] string file, [CallerLineNumber] int line, [CallerArgumentExpression("condition")] string expression);
void assert_message(bool condition, string message, [CallerFilePath] string file, [CallerLineNumber] int line, [CallerArgumentExpression("condition")] string expression);
```

These signatures describe ordinary definitions with Astra bodies. True returns
normally; false invokes the selected nonreturning provider, with an empty message
for assert_that. Neither public name is a compiler keyword, macro or intrinsic.
An unrelated function with the same name receives no special treatment. User
checkers can request identical [caller information](../language/caller-information.md).

Assertions are always-on eager functions. Conditions evaluate once. Message and
explicit metadata expressions run even on true; a trap in an earlier argument
prevents later effects. Ordinary optimization may remove a proven unnecessary
operation only under existing effect rules. There is no NDEBUG, hidden lazy
message thunk, release stripping or exception recovery. Numeric expected/actual
reporting stays available through assert_equal_i32/f32/f64; this library does not
extract operands from equality syntax.

The example uses a real argument entry:

```astra
int main(string[] args) {
	assert_that(len(args) > 1);
	assert_message(args[1] != "", "input name must not be empty");
	return 0;
}
```

From the checkout, after a strict Meson build, use a fresh output directory:

```sh
mkdir -p build/diag-1/example-run
build/astrac examples/diagnostics/main.astra lib/astra/base/diagnostics.astra --link-object build/lib/astra/args-posix.o --link-object build/lib/astra/diagnostics-hosted.o -o build/diag-1/example-run/example
build/diag-1/example-run/example input
```

An `int main()` client needs no args provider. The hosted reporter itself needs
no text-posix.o. Applications can independently select ordinary output, legacy
assertions/equality and their respective providers. No names, sources, data,
imports or objects are autolinked.

The sole new hook uses existing import-only utf8-i32 C text views:

```astra
[CCode(text_abi = "utf8-i32")]
extern(C) void astra_diag_assert_fail_v0(borrowed string file, int line, borrowed string expression, borrowed string message);
```

Its exact physical signature is:

```c
_Noreturn void astra_diag_assert_fail_v0(const unsigned char *file, int32_t file_length, int32_t line, const unsigned char *expression, int32_t expression_length, const unsigned char *message, int32_t message_length);
```

The provider is a trusted bounded reader. It never retains, mutates or frees a
borrow, invalidates its lifetime or returns borrowed data. It **must not return**.
The C _Noreturn declaration does not grant source/LLVM attributes: native calls
remain ordinary conservatively effectful calls. There is no new ABI profile or
language nonreturn keyword.

| Explicit object | Behavior and dependencies |
| --- | --- |
| diagnostics-trap.o | Ignores values; qualified GCC/Clang x86-64 Linux trap, no runtime symbols |
| diagnostics-hosted.o | Bounded stderr rendering, relevant-stream flush and abort; hosted libc/stdio costs |

Choose exactly one for this interface. Missing and duplicate choices produce
normal linker failures, preserving a pre-existing requested output. Strong
symbols, linker order and repetition remain visible. No weak override, callback,
registry or environment selection exists. A separately required legacy provider
can coexist because astra_base_fail and equality reporter symbols are distinct.

The hosted provider attempts this exact five-line report, each line ending in LF:

```text
Astra assertion failed
  file: "<escaped file bytes>"
  line: <signed decimal int>
  expression: "<escaped expression bytes>"
  message: "<escaped message bytes>"
```

Every text field, including empty message, uses its explicit count, never strlen
or %s. Quote and backslash are escaped; LF/CR/TAB/NUL use `\n`, `\r`, `\t`, `\0`.
Other ASCII C0 bytes and DEL use uppercase `\u00HH`. Other bytes, including
well-formed non-ASCII UTF-8, are preserved exactly. `%s%n` is data. Signed line
formatting covers INT32_MIN through INT32_MAX, including explicit overrides.
No locale changes, normalization or UTF-8 rescans occur. This is ASCII control
framing, not complete Unicode bidi/display sanitization or atomic thread logging.

Observable negative counts and nonempty null views produce the fixed fallback
`Astra assertion failed: invalid diagnostic text view` plus LF before termination.
All shapes are checked before any field read. Arbitrary unreadable pointers are
not validated. Correct native calls already satisfy these contracts.

Only stderr is flushed. A failed write/flush still leads to abnormal termination;
there is no retry-until-success loop, exit-code protocol, signal-handler change or
atexit cleanup. A host signal may interrupt output; rejected sinks cannot promise
a complete report or one particular terminating signal. Hosted stdio may allocate
or retain storage: this is not heap-free, async-signal-safe or real-time bounded.

Failure adds no Astra unwinding. Live Resource/Class/buffer owners and an ARGS
snapshot remain live through reporting and are not cleaned by the fatal path.
On normal success, native cleanup runs before ARGS snapshot disposal as before.
A runtime message borrowed from args is neither promoted nor retained.

Meson installs diagnostics.astra in configured datadir/astra/base; the header
and two C sources in datadir/astra/platform; and qualified objects plus target.txt
in configured libdir/astra/x86_64-linux. Derive prefix/bindir/datadir/libdir from
Meson options; do not guess lib64. Qualification stages a DESTDIR, copies the
prefix and client elsewhere, and invokes the installed compiler from that client
directory with actual arguments and all 24 source permutations.

Ordinary full-byte/count text pooling reuses identical captures without making
addresses or labels semantic identity. Unused metadata may be optimized away,
but there is no zero-data-cost promise at O0 or for usually successful conditions.
See measured qualification for object sizes, dependencies,
failure bytes, output-sink failures, memory classifications and target limits.
