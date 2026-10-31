# Interop and async applications A33–A40

These eight programs combine explicit native ownership with a finite retained C
registrar, checked native closures, C POD values and Linux file payloads. Their
contracts are decisions [0113](../../docs/decisions/0113-retained-callback-quiescence.md),
[0114](../../docs/decisions/0114-owned-linux-file-payloads.md),
[0115](../../docs/decisions/0115-checked-native-closures.md) and
[0116](../../docs/decisions/0116-c-by-value-pod-records.md).
The qualification record determines
which source/compiler/provider combination actually passed. Source presence or
an application count does not establish completion.

| App | Program | Observable work and bounds |
| --- | --- | --- |
| A33 | [Deferred event subscriber](deferred-event-subscriber.astra) | An owned handler survives C registration return, receives two later dispatches, stops and observes quiescence. Includes refused admission, repeated stop/observation, zero dispatch and early-return cleanup. |
| A34 | [Weak document observer](weak-document-observer.astra) | A registered handler captures a Weak document. Delivery upgrades while live, sees expiry after last strong release, then retires its registration and weak control storage. |
| A35 | [Checked event transformer](checked-event-transformer.astra) | A nonthrowing C adapter owns a CheckedClosure, catches a deliberate error, stores an owned UTF-8 diagnostic and returns status. Native observation throws after C returns; later delivery succeeds. |
| A36 | [C record diagnostics](record-diagnostics.astra) | Integer, FP, mixed, padded and stack-classified structs cross actual C by-value parameter/result boundaries in both directions; the program checks a numeric report hash. |
| A37 | [Binary ingest](binary-ingest.astra) | Real async read, EOF check and async output of `BYTE_COUNT:CHECKSUM\n`; at most 65,536 input bytes. Bytes may contain NUL or invalid UTF-8. |
| A38 | [Segmented copy](segmented-copy.astra) | Real async reads and partial-write progress with explicit offsets; segment 1..512, input at most 1 MiB. The result must equal the input bytes. |
| A39 | [Cancellable scan](cancellable-scan.astra) | Cancellation before dispatch, after submission or after observed completion. A copied observer reports a scan only when native code actually resumes to compute it. |
| A40 | [Event diagnostic importer](event-diagnostic-importer.astra) | Real async input/spool transfer, validated UTF-8, retained checked callbacks, Shared/Weak state and `Bag<Utf8Message>` produce a file report with failed-record retry. Input at most 65,536 bytes; 512-byte transfers. |

All commands below run from the repository root in Bash. Use the coordinated
out-of-source compiler and put generated artifacts in task scratch:

```sh
astra_compiler="$HOME/Workspace/codex/work/astra/build/astrac"
astra_examples="$HOME/Workspace/codex/work/astra/runtime/native-current/manual-apps"
mkdir -p "$astra_examples"
```

## Retained handlers and checked delivery

Build the real C registrar and the separate output observer, then compile A33:

```sh
gcc -std=c11 -O2 -Wall -Wextra -Werror -c lib/astra/interop/retained.c \
    -o "$astra_examples/retained.o"
gcc -std=c11 -O2 -Wall -Wextra -Werror -c tests/interop-async-5/retained-observer.c \
    -o "$astra_examples/retained-observer.o"
"$astra_compiler" -O2 examples/interop-async-5/deferred-event-subscriber.astra \
    --link-object "$astra_examples/retained.o" \
    --link-object "$astra_examples/retained-observer.o" \
    -o "$astra_examples/deferred-subscriber"
"$astra_examples/deferred-subscriber"
```

Replace the source with `weak-document-observer.astra` to build A34. Both use no
command-line input. A33's trace ends in `event=8:18` and then the zero-dispatch
capture's `event=8:20`; A34 shows document destruction before the expired weak
notification, followed by observer teardown. The observer flushes each event so
it can be compared with native text output in delivery order.

A35 adds the ordinary checked-error and owned-text components:

```sh
gcc -std=c11 -O2 -Wall -Wextra -Werror -c lib/astra/platform/text-posix.c \
    -o "$astra_examples/text-posix.o"
"$astra_compiler" -O2 examples/interop-async-5/checked-event-transformer.astra \
    lib/astra/base/errors.astra lib/astra/text/utf8-message.astra \
    lib/astra/hosted/text.astra \
    --link-object "$astra_examples/retained.o" \
    --link-object "$astra_examples/retained-observer.o" \
    --link-object "$astra_examples/text-posix.o" \
    -o "$astra_examples/checked-transformer"
"$astra_examples/checked-transformer"
```

The deliberate `event rejected: negative payload` diagnostic follows
`event=35:1`, which is emitted after the C dispatch returns. A later successful
transformation proves that the caught failure leaves its registered capture
alive. Direct registration of a CheckedClosure is rejected.

The registration owner is the linear Closure. `retained_register(handler, 0)`
returns zero on admission; mode 1 exercises refusal before publication.
`retained_dispatch` is a later provider step. `retained_revoke` stops future
steps, and `retained_observe` returns one only after actual quiescence. Cleanup
also revokes and observes before destroying captures. Consume these intrinsic
results in value expressions, as the examples do. One owner has at most one
attachment; the selected provider has 64 live slots. Callback contexts remain
opaque to C. There is no arbitrary foreign-library, threaded or reentrant
callback guarantee.

## By-value C records

A36 uses a separately compiled C provider. The same source also supports the
public object route into a C client:

```sh
gcc -std=c11 -O2 -Wall -Wextra -Werror -c tests/interop-async-5/record-provider.c \
    -o "$astra_examples/record-provider.o"
"$astra_compiler" -O2 examples/interop-async-5/record-diagnostics.astra \
    --link-object "$astra_examples/record-provider.o" -o "$astra_examples/record-diagnostics"
"$astra_examples/record-diagnostics"
"$astra_compiler" -O2 -c examples/interop-async-5/record-diagnostics.astra \
    -o "$astra_examples/record-diagnostics.o"
gcc -std=c11 -O2 -Wall -Wextra -Werror tests/interop-async-5/record-client.c \
    "$astra_examples/record-provider.o" "$astra_examples/record-diagnostics.o" \
    -o "$astra_examples/record-client"
"$astra_examples/record-client"
```

The standalone app prints `record-diagnostics hash=1426`. The C client compares
1,280 by-value roundtrips with its independent expected values. The foreign
profile is GNU x86-64 SysV LP64: one to three 64-bit numeric fields, singleton
f32 or padded f32/f64; at most two logical parameters. Sixteen-byte records use
INTEGER/SSE channels; 24-byte records use actual SysV byval/sret. Packed,
nested, pointer-bearing, owning, generic, union and variadic records are outside
this profile. The previous borrowed POD-pointer route remains distinct.

## Real Linux payload applications

A37–A40 require an existing matching liburing >=2.15 header/archive pair and a
successful unprivileged ring/opcode probe. The scripts record the selected
paths/hashes, actual kernel observations and every public `astrac` command.
They neither install dependencies nor substitute virtual completions. With a
different existing private installation, set `ASTRA_LIBURING_PREFIX` explicitly.
Exit 77 denotes an unavailable provider and cannot qualify these apps.

```sh
export ASTRA_LIBURING_PREFIX="$HOME/.local/opt/liburing-2.15"
python3 tests/interop-async-5/payload-check.py "$astra_compiler" "$astra_examples/payload"
python3 tests/interop-async-5/importer-check.py "$astra_compiler" "$astra_examples/importer"
```

These build ordinary public O0/O1/O2 binaries. For a separate manual input and
output, after the qualification succeeds:

```sh
python3 - "$astra_examples/sample.bin" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(bytes((i * 37) & 255 for i in range(8193)))
PY
"$astra_examples/payload/binary-ingest-O2" "$astra_examples/sample.bin" "$astra_examples/checksum.txt"
"$astra_examples/payload/segmented-copy-O2" "$astra_examples/sample.bin" "$astra_examples/copy.bin" 257
cmp "$astra_examples/sample.bin" "$astra_examples/copy.bin"
"$astra_examples/payload/cancellable-scan-O2" "$astra_examples/sample.bin" 0
"$astra_examples/payload/cancellable-scan-O2" "$astra_examples/sample.bin" 1
"$astra_examples/payload/cancellable-scan-O2" "$astra_examples/sample.bin" 2
```

A39 modes 0/1/2 mean cold, submitted and completed cancellation respectively.
Target and cancel command CQEs are separate observations. Buffers, descriptors
and task frames survive until required release events are observed; a
generated but undrained CQE grants no access. The finite payload owner supports
one operation at a time; applications advance returned short-transfer counts.
No sockets, multishot, zero-copy, registered buffers or cross-thread scheduler
are implied.

A40 accepts `INPUT SPOOL OUTPUT`. The spool is a real byte-exact async copy;
the output is the generated text report. Keep these three paths distinct:

```sh
python3 - "$astra_examples/import.txt" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text("1|first\nbad\n2|next\n", encoding="utf-8")
PY
"$astra_examples/importer/A40-gcc-O2" "$astra_examples/import.txt" \
    "$astra_examples/spool.bin" "$astra_examples/report.txt"
```

This input produces `rows=2 rejected=1`, followed by the two accepted
`code=... message=...` rows. A malformed record advances to the next record;
malformed UTF-8 or I/O failure follows the checked failure path. Write owners
create/truncate their destination. A37/A38/A39 use exit 64 for invalid argument
bounds, 2 for checked setup/task errors and separate invariant-failure exits;
A40 uses 64 for arity and 3 for caught failure.

Run `sh tests/interop-async-5/verify.sh` for the registered integration recipe.
The [feature inventory](../../tests/interop-async-5/features.json) names the
applications and proof suites. Public commands, source/product hashes, exact
outputs and unsuppressed memory results belong to the current qualification
receipt; previous A01–A32 acceptance remains historical unless explicitly rerun.
