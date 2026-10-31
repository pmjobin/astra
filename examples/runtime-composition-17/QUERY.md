> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# Paired-range query service: retained B2 regression

This useful second application exposed the failed production freeze 2. Its current
end-to-end runs are regression evidence for the general compiler repair. They do
not retroactively pass that freeze. See
the failure record.

From the repository root, build with explicit compiler and output paths:

```sh
python3 examples/runtime-composition-17/build-query.py \
  --compiler <historical-private-path> \
  --uring-prefix <historical-private-path> \
  --output <historical-private-path> \
  --optimization 2
```

The executable accepts a numeric bind address, family `4` or `6`, and a read-only
input file smaller than 16 MiB. It prints its chosen TCP/UDP ports as JSON, accepts
three TCP clients and shuts down after all three terminate their request streams.
Use an authorized local address. The supplied peer uses IPv4 or IPv6 loopback and
creates its own deterministic input file:

```sh
python3 tests/runtime-composition-17/query-peer.py \
  --product <historical-private-path> \
  --output <historical-private-path> \
  --receipt <historical-private-path> \
  --family 6
```

`query-service.astra` owns sockets, file payloads, queues, cache and the worker
pool. Two file ranges per request are read through io_uring into a selected-context
`Block`. `query-workers.astra` hands that owner to two real worker lanes using
selected parent/child task frames. `query-model.astra` computes a joint histogram,
quantiles and cross-range distance, then returns an owned cache entry carrying the
actual histogram buffer. Nested `Reply<Distribution>` records encode the response.
The independent Python oracle calculates cross-distance from frequency products,
while the Astra implementation compares individual source bytes.

Local request checks allocate two objects in a scoped context over named borrowed
backing and return before any suspension. Persistent input, result and frame
contexts are separate instances. The custom provider stores authority in private
callback state with its own synchronized ledger, quota and 64-byte allocation
guards. Its quota covers actual rounded backing plus guards; provider state and
slot metadata are additional bounded allocations. Cache entries retain the result
contexts after their original handles close. Finish telemetry checks that all
tickets and entries retire and every custom context is disposed with exact releases.

TCP requests contain six little-endian 32-bit integers: identity, first offset and
count, second offset and count, and mode. Each integer must fit 24 bits; each count
is 1–3071. Identity zero terminates the stream. Mode zero queries; mode one requests
a real checked analysis refusal. Invalid ranges return status 1, and the checked
analysis refusal returns status 2. A stream admits at most 64 nonterminal requests.

Responses contain 20 little-endian integers: marker 82, identity, status, cache-hit
flag, generation 2, both offset/count pairs, total count, sum, energy, cross-distance
modulo 65521, minimum, lower quartile, median, upper quartile, maximum, frequency of
zero, and frequency of 255. Failure responses retain marker/identity/status and
zero all other fields. UDP `Q` returns marker 82, hits, misses, cache size, rejected
requests and completed clients. Other datagrams are discarded.

The launcher chooses `ASTRA_QUERY_QUEUE` (1–9, default 3), `ASTRA_QUERY_CACHE`
(1–9, default 5), `ASTRA_QUERY_WORKERS` (2–6, default 3), and `ASTRA_QUERY_QUOTA`
(65537–1048573 bytes per ordinary custom context, default 131071). The frame
contexts use twice that quota. Invalid configuration returns 64 before opening the
service. The supplied cache-hit oracle uses capacity at least three. `SIGINT` and
`SIGTERM` request cancellation followed by joined retirement; they do not release
in-flight backing early.

`query-regression.py` runs O0/O1/O2 over both endpoint families, independent complete
results, cache hits, checked errors, unsuppressed Valgrind, and actual emitted-code
ASan/UBSan and TSan. `query-provider.py` separately checks private quota refusal,
distinct same-provider origins, last-lease disposal and simultaneous native callback
allocations. These are bounded observations, not a claim about arbitrary foreign
callbacks or all concurrent schedules.
