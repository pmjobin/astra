# Hosted application runtime prototype

This opt-in source library composes decimal scalars and counted UTF-8, searches,
splits and parses text, and reads/writes real files on GNU Linux x86-64 LP64.
See the [policy and costs](../decisions/0103-hosted-application-runtime.md) and
actual qualification. It is a bounded
prototype, not a complete standard library or release qualification.

From the repository root, build and qualify with the installed toolchain:

```sh
export PM_CODEX_BUILD_DIR="$HOME/Workspace/codex/work/astra/build"
export PM_CODEX_RUNTIME_DIR="$HOME/Workspace/codex/work/astra/runtime/native-current"
sh tests/application-runtime-1/verify.sh focused
```

This recipe verifies external build routing, selects debug/Werror,
`b_pch=false`, `linux_async=false`, compiles serially and executes the actual
applications at native and independently optimized LLVM O2. These are test
profile choices; product defaults are unchanged. Add `regressions` to rerun
the selected existing ownership/text/error suites.

For a small file-to-formatted-output program, save this source as
`$PM_CODEX_RUNTIME_DIR/file-report.astra`:

```astra
int main(string[] args) {
	if (len(args) != 3) { return 64; }
	try {
		var bytes = read_file(args[1]);
		var b = new Utf8ByteBuilder();
		require_text(append_text(b, "input bytes="));
		require_text(append_int(b, bytes.byte_count()));
		require_text(append_text(b, "\n"));
		var message = b.snapshot();
		write_text_file(args[2], message.text);
		return 0;
	} catch (FileError error) {
		println_stderr("file I/O while processing input/output paths:");
		println_stderr(args[1]); println_stderr(args[2]);
		return 2;
	} catch (Error error) { return 3; }
}
```

Compile explicit providers and sources, then run the same executable on any
two paths. Output files are truncated, so choose a task-owned destination:

```sh
run_dir="$PM_CODEX_BUILD_DIR/examples/application-runtime"
mkdir -p "$run_dir"
for provider in args text text-ops files; do
	cc -std=c11 -Wall -Wextra -Werror -c \
		"lib/astra/platform/$provider-posix.c" -o "$run_dir/$provider.o"
done
"$PM_CODEX_BUILD_DIR/astrac" "$PM_CODEX_RUNTIME_DIR/file-report.astra" \
	lib/astra/text/scalar-format.astra lib/astra/hosted/text-ops.astra \
	lib/astra/hosted/files.astra lib/astra/text/utf8-byte-builder.astra \
	lib/astra/text/utf8-message.astra lib/astra/collections/bag.astra \
	lib/astra/base/errors.astra lib/astra/hosted/text.astra \
	--link-object "$run_dir/args.o" --link-object "$run_dir/text.o" \
	--link-object "$run_dir/text-ops.o" --link-object "$run_dir/files.o" \
	-o "$run_dir/file-report"
"$run_dir/file-report" README.md "$run_dir/report.txt"
cat "$run_dir/report.txt"
```

Substitute any corpus source for `file-report.astra`, adding
`examples/application-runtime/support.astra`. Multi-source input here uses the legacy global whole-program mode. Opt-in
namespace/import directives are described in [the module guide](modules.md).

| Source/API | Contract |
| --- | --- |
| `text/scalar-format.astra`: `append_int`, `append_u32`, `append_bool` | Decimal ASCII, no locale/format strings; bool append success, no mutation on capacity refusal. Fixed stack scratch 11/10/5 bytes. No new C provider. |
| `hosted/text-ops.astra`: `append_text` | Copies all counted bytes, including NUL, into builder; prechecks total I32 length. Builder bytes validate at snapshot. Requires `text-ops-posix.o`. |
| `text_byte(text,index)` | Checked byte index, result octet as int. Counts/indices are signed I32. |
| `text_find(text,needle,start)`, `text_contains`, `text_starts_with`, `text_ends_with` | Exact UTF-8 byte matching; no folding/normalization. Empty needle matches a valid start. Missing match is -1. Invalid start throws `TextRangeError`. |
| `text_segment(text,start,count)` | Checked byte range; both endpoints must be scalar boundaries, even for an empty segment. New validated independent `Utf8Message`. |
| `text_split(text,delimiter,fields)` | Appends copied fields to supplied `Bag<Utf8Message>`; preserves empty/adjacent/terminal fields. Empty input gives one empty field. Empty delimiter returns false. Previous fields remain on failure. |
| `parse_int(text)` | ASCII `-?[0-9]+`, leading zeros allowed; no plus, whitespace or NUL. I32 range checked before arithmetic; malformed/overflow throws `IntegerParseError`. |
| `read_file(path)` | Returns unique `FileBytes`; arbitrary binary, bounded I32 length, Astra geometric growth and final exact copy. |
| `FileBytes.byte_count`, `.byte_at`, `.decode`, `.write` | Copied observations; byte index checked; explicit Q19A decode; write borrows owned storage. No escaping mutable array view. |
| `write_file(path,u8[] bytes)` | Borrows caller counted buffer for synchronous write; flushes/closes; payload unchanged. |
| `write_text_file(path,string text)` | Writes counted UTF-8 through text observer; no NUL truncation or encoding conversion. |

Builder snapshots retain the existing two-copy validation path. Text observation
makes a bounded C call per byte; prefix/suffix cost O(m), naive search O(nm),
parse/copy O(n). Splitting scans and copies fields, grows owner slots and
validates each copied field. File transfer uses bounded bulk syscalls, with Astra retaining progress loops,
O(n) copying and O(n) live storage. See the [counted C buffer guide](c-byte-buffers.md)
and systems qualification for measured counts. `FileBytes.decode` makes another independent copy. Fatal allocation
failure does not promise cleanup. Counts above I32_MAX are unsupported.

`FileError.operation` is 1=open, 2=read, 3=write, 4=flush, 5=close, 6=range/size.
`status` is negative Linux errno for OS failures; operation 6 uses -1. Error
message is `file I/O`; the caller retains input/output path context, as in the
example. Reopening a live `FileHandle` reports -EBUSY; repeated close is harmless.
Destructor close ignores errors, whereas successful whole-file APIs check close.
Open/read/write/fsync retry EINTR. Linux close disarms and never retries.
Zero-byte write becomes EIO. EOF is distinct from read error.

Paths must be source-valid UTF-8 without embedded NUL. POSIX permissions/umask
apply; creation uses mode 0666. Writes are synchronous, truncate on open and
can leave partial output. `fsync` does not guarantee atomic replacement or
directory durability. Reading/writing the same path works only insofar as the
caller first finishes reading; there is no transactional or race-free path API.
No symlink rejection policy, raw filename bytes, streaming API, async transport,
float formatting, regex, grapheme indexing or Unicode numeric parsing is claimed.

| Corpus ID | Program and behavior |
| --- | --- |
| A1 | `format-matrix`: I32/U32 bounds, booleans, multibyte/NUL fragments |
| A2 | `text-ops`: byte search, split, scalar-safe extraction and checked parse |
| A3 | `copy-bytes`: real binary read/write, no decoding |
| A4 | `io-errors`: real missing file and counted NUL-path refusal |
| B1 | `diagnostic-transform`: pipe-separated severity, signed code and payload to `line:severity[code] text`; info/warning/error only, LF/CRLF, blank lines ignored, remaining pipes are payload; Bag grows 2→3 and beyond |
| B2 | `kv-config`: ASCII alphanumeric/underscore key `=` signed decimal; SP/TAB trim, whole-line `#` comments, LF/CRLF, blank lines ignored, duplicates retained in order |
| B3 | `line-stat`: arbitrary byte count, LF count and trailing-LF flag; CR is ordinary data |
| B4 | `owner-log`: insertion-order snapshots, meaningful early return and checked parse failure |

Required apps are compiled independently. B1/B2 delay output open until parsing
succeeds; invalid input leaves an existing output untouched. Successful empty
input produces an empty output. Binary copy and line-stat never require UTF-8;
text applications reject malformed ingress via Q19A.

Public `astrac -O0/-O1/-O2` and object emission are described in the
[systems guide](compiler-systems.md). This predecessor test harness retains its
independent external `opt`/`llc` route. The new systems harness separately reruns
these same application oracles through the actual public O2 option.
