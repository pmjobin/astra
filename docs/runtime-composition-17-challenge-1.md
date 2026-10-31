# M17 frozen challenge 1: indexed range analytics cache

Selected after production freeze commit `d634240f072c967eecb0f82a87c1437da7386628`,
before authoring or compiling B. Selection time: `2026-10-28T16:27:37.964366+00:00`. Reproduction seed:
`987768583`. Production source: `38947c89710aaffb992004595a366c2c4c62b335`;
compiler SHA-256: `ab0f0fb52e3149598bda558b8638bb95d49c506b4d406578d9db7f309cd29a79`.

B is a read-only indexed range analytics/cache service. It receives independent
range queries from simultaneous TCP clients, reads the selected file ranges with
real io_uring, computes count/sum/extrema/checksum results on native workers,
retains bounded cache entries and returns typed per-query results. UDP exposes
cache/progress statistics. It serves an existing task-generated file; clients
cannot select arbitrary paths. Algorithms, cache policy, request handling and
shutdown are ordinary Astra code.

This differs from A's single incoming data stream, byte transformation and file
spooling. Cache hits must reuse an existing typed result and avoid an extra file
read/computation. Responses identify the actual query and its range. Independent
Python clients/oracles generate the dataset and check all query results without
sharing the implementation's algorithm generator.

Required variations include at least three simultaneous clients, nested result
records and a different closed generic shape, different request ordering and
buffer/queue/cache capacities, IPv4/IPv6 numeric endpoints and at least two
same-type allocator instances. A checked local scoped context must remain within
its borrowed backing lifetime. Persistent cache/result/frame storage must use
its selected transferable contexts.

A newly authored application provider must use the existing public custom
allocator contract with real per-instance user state and exact allocation/release
accounting. It may wrap owned backing and impose a bounded quota. It must remain
outside the frozen shared runtime/compiler and execute in the real product.

An opaque native library must carry real query/payload/result/context ownership
across its boundary, with its implementation absent during consumer compilation.
Exercise successful results, checked error propagation, cross-executor cancellation
and joined retirement. Independently check cache hits/misses, actual worker/IO
progress, bounded memory and final context/frame/buffer/descriptor/thread
conservation. Qualify public O0/O1/O2 and appropriate generated-code safety tools.

The compiler, shared runtime/libraries and A in the freeze manifest stay unchanged.
Application defects may be corrected within B. A valid public-contract failure
requiring production repair is a failed freeze: retain its minimal reproducer,
repair the general mechanism, refresh A/regressions, record a new freeze, then
choose a new structural variant. No passing frozen-challenge claim exists yet.
