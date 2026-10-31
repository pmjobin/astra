# Owned Linux file payload suspension

The opt-in Linux provider adds `await payload_io(owner)` to a nominated
`linux-io-uring` async body. Its operand is an exact live unique `LinuxPayload`
with the imported `astra_linux_payload_close` destruction contract. Borrowed
parameters, raw pointers, unrelated handles, virtual providers and moved or
released owners cannot grant suspension authority.

`payload.vapi` exposes an opaque Resource. The provider owns one fd and one
zero-initialized stable byte allocation, bounded to 1 MiB. Opening a read or
write owner is fallible; write mode creates/truncates the selected file. No fd,
mutable view or buffer address leaves the API. Paths are counted, reject NUL,
and are copied only for `open`. Ordinary programs acquire no liburing dependency.
Allocation failure keeps the existing fatal policy.

The async frame owns the resource throughout suspension. Checked/Core/CFG
retain the provider operation and exact lexical owner. SSA requires an
immediately associated live-owner READ event; native resume states copy the
payload definition and owner ordinal and require the provider cleanup identity.
The source-to-native validator independently reconstructs those associations.
LLVM emits the real provider call with that stable pointer and the exact task
and resume pc, checking that the frame still holds that exact live owner before
submission, then returns to the scheduler. A READ witness preserves the cleanup
obligation; it cannot disarm the frame's ownership flag. The existing task cancellation
and frame cleanup protocol keeps the frame alive until provider release.

READ and WRITE extend the existing timer provider's bounded operation slots.
The same monotonically unique target/cancel IDs, full executor/slot/generation
token, SQ publication accounting and checked CQ ingress remain authoritative.
Nonnegative payload CQE results are byte counts and cannot exceed the requested
count. Zero is EOF for reads. The API records the actual count and errno;
checked async failure uses the existing nominated `AsyncError` channel after
observed retirement. It never parses payload bytes as text.

Each resource is idle, in flight, or idle after observed completion. Admission
sets in-flight before SQ publication. Every accessor, mutation and destructor
fails closed while in flight. A generated but undrained CQE grants no access.
The target CQE and any prepared cancellation-command CQE must both be observed
before access is restored or the scheduler may retire the frame. Cancellation
success does not stand in for the target event; `ENOENT`/`EALREADY` cancellation
results also require observing the target. A task cancelled before dispatch
creates no SQE. A cancelled task may have a successful target result without
publishing that result as a second task completion.

Configuration specifies buffer offset/count and an explicit nonnegative i64
file offset. Checked wrappers reject invalid ranges. A short write returns its
actual progress; applications must advance both buffer and file offsets and
retry the remainder. The examples reject zero write progress. A completed read
allows access only to its returned interval. Reconfiguration clears the prior
result and access interval before a new operation. `payload_finish` reports close
failure and consumes the fd once; the lexical destructor frees storage and
closes an unfinished fd. Linux close is never retried after EINTR.

Provider transport integrity failure preserves the existing bounded-drain then
process-stop policy. It never unwinds or frees an exposed request with unknown
kernel ownership. This contract has no registered buffers, multishot, zero-copy,
sockets, cross-thread scheduling or implicit cancellation timeout guarantee.

Qualification is in `tests/interop-async-5/payload-proof.vala`,
`payload-runtime.c` and `payload-check.py`. The runtime controls include a real
regular-file short write using a temporary per-process file-size limit, actual
EOF/error completions, a blocking-file cancellation and separate copied CQE
identities. Injected malformed events are explicitly separate from real kernel
evidence. Optional test observers see copied IDs and results only and cannot
replace CQ ingress or release authority. The underlying liburing dependency
remains separately installed (upstream LGPL-2.1-or-later library, MIT helper
header portions); no dependency binary or source copy is bundled here.
