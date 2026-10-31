# Streaming transform and spool

M17 application A receives a bounded framed TCP stream, transforms chunks on
two native worker lanes, and writes their original positions through real
io_uring completions. A UDP endpoint reports progress concurrently. Application
algorithms, queues, ownership, computation and shutdown are written in Astra.
`stream-host.c` supplies CLI port configuration, signal notification and logging.

Build from the repository root using the existing installed liburing:

```sh
project_build="$HOME/Workspace/codex/work/astra/build"
python3 examples/runtime-composition-17/build-stream.py \
	--compiler "$project_build/astrac" \
	--uring-prefix "$HOME/.local/opt/liburing-2.15" \
	--output "$project_build/runtime-composition-17/stream-product" \
	--optimization 2
"$project_build/runtime-composition-17/stream-product/stream-spool-O2" \
	127.0.0.1 4 "$project_build/runtime-composition-17/stream-product/output.bin"
```

Arguments select the numeric bind address, family (`4` or `6`) and output file.
The service accepts one TCP session and overwrites that output. The default TCP
port and UDP status port are kernel-selected; the first JSON line reports both.
`ASTRA_STREAM_PORT` selects a TCP port from 0–65535. `ASTRA_STREAM_EVENTS` enables
event logging. SIGINT/SIGTERM request cooperative cancellation and joined cleanup.
Successful completion returns 0, stopped operation returns 130, and checked
failure returns 1. An unsuccessful stream can leave a partial output file.

The launching client can configure the following environment variables. Invalid
values return 64 before opening sockets or the output file. The service passes
the chosen contexts and queue capacities to its libraries.

| Variable | Default | Accepted values |
| --- | ---: | --- |
| `ASTRA_STREAM_CAPACITY` | 2 | 1–8 entries per queue |
| `ASTRA_STREAM_WORKERS` | 2 | 2–8 native worker threads |
| `ASTRA_STREAM_CONTEXT_BYTES` | 262147 | 131071–1048576 bytes per control/input context |
| `ASTRA_STREAM_FRAME_BYTES` | 524309 | 524309–2097152 bytes for the worker-frame region |
| `ASTRA_STREAM_CHUNK_LIMIT` | 4093 | 31–4093 bytes per input record |
| `ASTRA_STREAM_ALIGNMENT` | 128 | 64, 128 or 256 bytes |

The pipeline has two concurrent CPU lanes; the configured pool can have more
threads, and lanes can migrate among them. The nested child-frame region uses
half the selected parent size minus seven bytes. Both queue depth and reserved
capacity stay within the configured limit. Qualification records actual queue
limits/peaks, distinct worker identities, per-context memory peaks and exact
retirement.

Each TCP record starts with a four-byte little-endian byte count. Counts 1–4093
carry data; zero terminates the stream. At most 64 records are admitted. The server
also enforces the selected chunk limit and validates the complete header before
allocating payload storage. Its final reply
contains four little-endian u32 values: protocol marker 17, record count, byte
count and aggregate digest modulo 65521. A one-byte UDP query `Q` requests the
same progress tuple for completed writes. Empty, unknown and oversized UDP
queries are discarded; the next valid query still receives a reply.

For record sequence `s`, the CPU digest starts at `s + 17` and performs 2,000,003
steps of `(digest * 19 + input[i % length] + i % 251) % 65521`. Each output byte
is `(input_byte + s % 31 + 17) % 256`. Workers may finish out of order; explicit
file offsets preserve input order. The independent Python peer calculates both
the digest and complete expected output from the protocol definition.

Two monitored queues each hold at most the configured number of chunks. Their actual slot backing,
shared control objects and byte owners use explicit concurrent contexts. Each
chunk keeps its original byte origin. Worker-frame storage uses an owned region
and a nested backing lease for the two suspended lanes. Cooperative service
frames retain their ordinary default backing. The writer copies transformed
bytes into the existing unique LinuxPayload buffer, then retains that owner
through every accepted file request and partial-write continuation. This product
makes no zero-copy claim.

The native SDK compiles `stream-pipeline.astra` and `stream-factories.astra` as
separate opaque libraries. SDK consumers receive their interfaces/objects and
the explicit C host VAPI; neither producer implementation is present or opened.
The remaining application stages compile normally against those declarations.
Qualification also replaces the producer's byte transformation bias while
keeping its complete public ABI and reusing the original consumer and factory
objects. The independent IPv6 peer requires the changed output bytes.

Focused qualification:

```sh
python3 tests/runtime-composition-17/stream-spool.py \
	"$project_build/astrac" "$HOME/.local/opt/liburing-2.15" \
	"$project_build/runtime-composition-17/stream-qualified"
python3 tests/runtime-composition-17/stream-sdk.py \
	"$project_build/astrac" "$HOME/.local/opt/liburing-2.15" \
	"$project_build/runtime-composition-17/stream-sdk"
python3 tests/runtime-composition-17/stream-failures.py \
	"$project_build/astrac" "$HOME/.local/opt/liburing-2.15" \
	"$project_build/runtime-composition-17/stream-failures"
python3 tests/runtime-composition-17/stream-safety.py \
	"$project_build/astrac" "$HOME/.local/opt/liburing-2.15" \
	"$project_build/runtime-composition-17/stream-safety"
python3 tests/runtime-composition-17/stream-configuration.py \
	"$project_build/astrac" "$HOME/.local/opt/liburing-2.15" \
	"$project_build/runtime-composition-17/stream-configuration"
```

Current baseline evidence covers real two-worker execution, overlapping network
reads and CQEs, exact file bytes, original allocation/release, actual selected
frames, and final FD/thread conservation. Failure tests cover truncated and
oversized frames, file-open refusal and SIGINT after an actual file completion
while workers remain active. All four profiles also execute with emitted-code
ASAN/UBSAN and TSAN. Valgrind checks the complete normal pipeline; its serialized
thread execution makes it unsuitable for the native overlap assertion. The
Valgrind profile still checks both worker identities, ownership and conservation.

`tools/qualification/runtime-composition-17-stream-peer.py` repeats the integrated
workload across the specifically approved fresh private veth topology. It must
only run with that permission and takes explicit product/compiler/output/receipt
paths. The ordinary native overlap assertions remain mandatory there. Its
independent peer uses separate IPv4/IPv6 TCP and UDP sockets and verifies the
entire file. This is isolated namespace evidence.

Final source-bound campaign qualification remains required. This is not a
production freeze or completion of M17.
