> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# Triple-range sequence-alignment cache

This is the third frozen challenge, selected after production freeze
`b53fd2fa3f4327f2665fc866702d132d726726e4`, with seed `2575218845`.
The compiler, shared libraries/runtime and earlier applications remain unchanged.
Earlier failed freezes remain recorded separately. This application's bounded
results do not establish completion of the milestone's final integration gates.

Build from the repository root with explicit paths:

```sh
python3 examples/runtime-composition-17/build-sequence.py \
  --compiler <historical-private-path> \
  --uring-prefix <historical-private-path> \
  --output <historical-private-path> \
  --optimization 2
python3 tests/runtime-composition-17/sequence-peer.py \
  --product <historical-private-path> \
  --output <historical-private-path> \
  --receipt <historical-private-path> \
  --family 6
```

The build recipe verifies every frozen source, compiler and host-dependency hash
before compiling. Its outputs live outside the source tree. The executable accepts
a numeric bind address, family `4` or `6`, and an existing read-only file smaller
than 16 MiB. It prints chosen TCP/UDP ports, accepts three TCP clients and serves
bounded requests until each client terminates or shutdown is requested.

`sequence-service.astra` owns network sockets, the real io_uring file owner, queues,
cache and worker pool. Each query reads a reference range and two comparison ranges.
Scoped validation objects borrow named local backing and finish before suspension.
`sequence-setup.astra` creates selected-context input blocks and tickets.
`sequence-workers.astra` hands them to two native worker lanes using actual selected
parent/child frames. `sequence-model.astra` performs ordinary in-place LCS dynamic
programming on two selected byte-buffer rows. Each row stores the complete score
frontier against all reference prefixes. An owned cache entry retains these actual
rows; successful replies read both endpoint scores and interior samples from them.

Copied results use `Reply<Alignment>`, `Box<Alignment>` and `Layer<Alignment>` across
the opaque native SDK. The independent peer uses bit-parallel LCS set arithmetic,
checking complete replies and prefix samples without sharing the implementation's
algorithm. Cache hits avoid file reads and recomputation. Checked model refusals
travel through the opaque processing boundary and become protocol status 2.

`sequence-provider.c` owns a separate aligned arena per callback-state instance.
A synchronized sorted extent ledger finds reusable gaps, preserves exact release
sizes/alignment and checks private 32-byte footers. Released adjacent gaps admit
larger subsequent allocations. Disposal frees the whole backing only after its
last lease retires. The reported arena capacity is physically reserved on creation;
live-byte peaks count active callback extents and guards. State and bounded ledger
metadata are additional allocations. Telemetry never authorizes allocator lookup.
Cached result backing survives its original allocator handle.

Configuration belongs to the launcher: `ASTRA_SEQUENCE_QUEUE` (1–9, default 3),
`ASTRA_SEQUENCE_CACHE` (1–9, default 5), `ASTRA_SEQUENCE_WORKERS` (2–6, default 3),
and `ASTRA_SEQUENCE_QUOTA` (65537–1048573, default 131071 bytes per arena). Frame
arenas use twice that capacity. Invalid configuration returns 64 before opening
the service. The independent cache-hit workload requires capacity at least three.
Each stream admits at most 64 nonterminal requests, with range counts 1–3071.

Requests contain eight little-endian integers: identity, reference offset/count,
left offset/count, right offset/count, and mode. Integers must fit 24 bits. Identity
zero terminates; mode zero queries and mode one requests a checked analysis refusal.
Responses contain 20 integers: marker 83, identity, status, cache flag, generation 3,
layer ordinal 3, the three offset/count pairs, total bytes, byte sum, byte energy,
left LCS length, right LCS length, the left frontier at one-third of the reference,
the right frontier at two-thirds, and reference length plus one. Invalid ranges
return status 1. Failure replies zero fields after status. UDP `Q` returns marker,
hits, misses, cache size, refusals and completed clients; malformed packets are
discarded.

`sequence-application.py` covers public O0/O1/O2 and both endpoint families,
unsuppressed Valgrind, and actual emitted-code ASan/UBSan and TSan.
`sequence-sdk.py` covers all eight O0/O2 producer/setup/consumer combinations and
O1. Producer paths are renamed away before every consumer compile; `strace` checks
that neither original nor hidden implementation is opened.
`sequence-operation.py` varies capacities and workers, observes native identities,
real io_uring completions, selected frame origins and exact allocation retirement,
and checks descriptor/thread inventories after joined shutdown. Real signals cancel
while a worker executes or after I/O submission. Task-owned bad descriptors and
truncated files exercise actual checked provider failures. The same cases execute
under emitted-code ASan/UBSan and TSan. Deterministic lifecycle gates are observers
around real operations; they do not fabricate completions or drive tasks.
`sequence-provider.py` separately tests quota refusal, exact origins, larger-gap
reuse, simultaneous native callbacks and last-lease disposal.

These checks cover bounded workloads and the current kernel/liburing environment.
They do not prove arbitrary foreign callbacks, all race schedules or universal
allocator portability.

The default build keeps verifying the original freeze 3. After a general compiler
repair, `--regression` explicitly runs this historical application without frozen
challenge credit. Registered application/SDK/operation tests pass the corresponding
`regression` profile and record that status; the original frozen receipts remain
tied to their qualified revision.
