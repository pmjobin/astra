# Caller information

Caller information can embed filenames and source snippets, including literal
secrets and comments, in program read-only data. APIs opt in explicitly through
their parameter declarations. Existing functions and assertions acquire nothing
without those declarations.

```astra
void check_value(bool condition, [CallerFilePath] string file, [CallerLineNumber] int line, [CallerArgumentExpression("condition")] string expression) {
	// These are ordinary parameters, usable by ordinary Astra code.
}
```

| Native parameter annotation | Exact type and value when omitted |
| --- | --- |
| `[CallerFilePath]` | plain/borrowed string; invocation SourceFile's normalized label |
| `[CallerLineNumber]` | int/i32; one-based called-name line |
| `[CallerArgumentExpression("condition")]` | plain/borrowed string; original written argument for the resolved parameter |

The names are ordinary identifiers elsewhere. Each parameter accepts one
annotation, before any ownership qualifier and type. File/line accept no payload,
including empty parentheses. Expression accepts exactly one string literal;
its decoded bytes must match an earlier required non-annotated parameter name.
Escapes within that literal follow existing string rules. It is resolved once
to a parameter ordinal, never used for later source lookup. Unknown names, self,
another annotated parameter, this, and member/path expressions reject.

Annotated parameters form a trailing suffix in any declared order. Explicit
default initializers are forbidden. Unknown, malformed, repeated or conflicting
annotations and mismatched types reject. File/expression parameters remain
BORROWED_NOESCAPE; owning/static-only modes are not added. A line parameter does
not accept other numeric types through conversion.

With K required and N total parameters, supply K through N positional arguments:

```astra
check_value(condition);
check_value(condition, supplied_file);
check_value(condition, supplied_file, supplied_line);
check_value(condition, supplied_file, supplied_line, supplied_expression);
```

Every supplied value binds in order, uses ordinary exact typing and lifetime
checking, and may be a runtime expression. Omitted suffix positions alone are
synthesized. All N parameters remain in the native signature. Ordinary unannotated
functions retain their exact arity and existing diagnostics. Duplicate declarations
retain existing rules; annotations do not define an overload or another value type.

The mechanism covers native free functions, generic functions, struct/class
methods and constructors using existing `Class.init(...)` syntax. It adds no
static methods or new callable family. Annotations on fields, results, locals,
properties/setters, implicit receivers, destructors, C imports/exports and VAPI
parameters reject. Calls inside accessors and deinit bodies work normally. Hosted
main signatures remain exactly the existing zero-argument or borrowed string[]
forms; annotations do not make other entry signatures acceptable.

SourceFile normalization removes redundant separators and `.` components,
retaining relative/absolute form, case, `..` and symlink spelling. Thus
`./sub//file.astra` captures `sub/file.astra`, while `left/same.astra` and
`right/same.astra` remain distinct. There is no realpath or build-directory
prefix. Explicit absolute names remain absolute. Relocation under identical
relative labels preserves captured bytes exactly.

Lines belong to the called name: `member` in `value.member(...)`, `init` in
`Class.init(...)`, or `name` before `<T>` in a generic call. Supported CRLF and
per-file newline accounting are preserved. Written-expression capture starts at
the first non-trivia token and ends after the last token. Parentheses, casts,
numeric suffixes, interior comments, spaces and newlines remain byte-for-byte;
outside trivia, commas and call parentheses are excluded. A const reference
captures its identifier, not its definition. Nested calls retain their written
syntax. Source spelling `"a\0b"` contains a backslash and zero in the capture,
independently of the evaluated string's embedded NUL.

Capture copies owned parsed bytes into immutable TextBytes with explicit counts;
changing/deleting the original file after parsing has no effect. Missing required
source ranges, invalid UTF-8 labels or unrepresentable counts/lines diagnose when
needed. Full explicit calls need no additional source evidence. Existing source
resource limits apply; no value is silently narrowed or replaced with line zero.

Written arguments evaluate once, left to right, before invocation. Capture is
syntax inspection and does not execute or move anything. Supplied metadata and
messages are eager even when an assertion succeeds. A preceding trap prevents
later arguments, and an enclosing short circuit can skip the call. Existing
transactional inference/ownership proof staging and final transfer commits apply.
Generated strings are static values at the call, but the callee's parameters stay
bounded borrows: returning one through a STATIC_TEXT result rejects.

```astra
void check_ready(bool ready, [CallerFilePath] string file, [CallerLineNumber] int line, [CallerArgumentExpression("ready")] string expression) {
	assert_that(ready, file, line, expression);
}
```

Explicit forwarding preserves the outer call's values. Replacing the inner call
with `assert_that(ready)` captures that inner source location and `ready`.
There is no stack inspection or inferred wrapper intent. Explicit labels, lines
and expressions may be synthetic or inaccurate; this is not authenticated data.

Generic arity validation uses the same K..N contract before inference. Only the
existing supported written direct-T/owned-T observations infer type arguments.
Concrete string/int metadata does not infer phantom T, use result context, admit
string as T or relax GEN1_PLAIN_COPY. Explicit/inferred calls share specialization
keys. An inner call in a generic body captures its definition site before
monomorphization; forwarding ordinary metadata can instead carry an outer site.
Captured bytes, values, paths and lines never distinguish instances.

After semantic completion, calls contain ordinary full argument lists. Core,
CFG, SSA, ABI plans and LLVM contain no caller-info evaluator, runtime metadata
object or source scanner. Syntax and semantic dumps show annotated declarations;
executable dumps match a fully explicit program with the same final arguments.
