# Proposed first Linux async profile

Current successor: the user-authorized [L1 implementation](linux-uring-timers.md) and ASYNC-IO-1 validation select explicit NO_SQARRAY and capacity 1..16, and record actual runtime qualification separately. The original proposal and its earlier observations below remain historical.

**ASTRA-ASYNC-CONTRACT-1 R3, 2026-10-03. Proposed / user review required.**
Native-kernel-first direction, including justified upstream RC dependencies, is
user-approved. The operation set, exact floor, boundary and source semantics
below remain proposals. The [portable contract](../architecture/async-contract.md)
is authoritative for tasks and lifetimes; Linux layouts/errno never enter it.
The evidence ledger records exact rows,
access dates and limits. No Linux runtime or production dependency is added.

## Selected path and dependency derivation

Recommend **one-shot io_uring timers plus cancellation by integer user_data**,
on the hosted GNU LP64 x86-64 Linux target. Select upstream **Linux v7.2** as
the precise proposed first supported source baseline, with CONFIG_IO_URING=y
and the runtime checks below. A vendor release string alone is not sufficient.
Later releases/backports need capability and behavior qualification; an RC can
be selected with a pinned upstream identity if a required facility/fix justifies
it. No RC is needed for the presently inspected set.

The concrete reason to require a modern timeout path is
`IORING_TIMEOUT_IMMEDIATE_ARG`: store a checked nanosecond value in the SQE,
eliminating a user-memory timespec's submission-lifetime obligation. The
[timeout manual, Description/Notes](https://man7.org/linux/man-pages/man3/io_uring_prep_timeout.3.html)
dates it to 7.1. The
[v7.1 UAPI](https://raw.githubusercontent.com/torvalds/linux/v7.1/include/uapi/linux/io_uring.h)
exposes it, but v7.1 implementation retrieval failed. The earliest **sufficiently
source-inspected baseline in this campaign is v7.2**:
[timeout.c](https://raw.githubusercontent.com/torvalds/linux/v7.2/io_uring/timeout.c)
`io_parse_user_time`, `__io_timeout_prep`, `io_timeout_fn`, `io_timeout_extract`
and `io_timeout_cancel` cover value parsing, accepted flags, expiry and timer
cancel races. Choose v7.2 rather than claim the uninspected v7.1 implementation
or a moving latest kernel is qualified. This is an audit floor, not proof that
7.1 is faulty. The earliest introducing/fixing commit and complete stable-fix
lineage remain unresolved. No specific fix is asserted without evidence.

Required behavior is verified at the selected source revision; actual compiled
kernel behavior is pending. If later provider qualification finds a necessary
fix, revise the proposed floor to that exact version/commit with evidence. Never
weaken quiescence to preserve this proposal. The minimum is grounded in the
selected immediate-value path and inspected cancel/overflow contracts, not a
generic compatibility range or a claim about kernel age/performance.

Only two first-provider paths were compared:

| First timer path | Fit and cost | Recommendation |
| --- | --- | --- |
| io_uring one-shot timer/cancel | One ring per executor; independent target/cancel CQEs map directly to registration drain; immediate argument avoids a pointer descriptor; requires explicit ring synchronization and availability checks | Prefer for the completion contract and later completion-provider route. No speed claim. |
| timerfd + epoll readiness | Legitimate native mechanism; descriptor lifecycle plus readiness/read/disarm bookkeeping; one timerfd per operation or a timer heap/multiplexer if reducing descriptors | Not selected first: adds readiness-to-result and descriptor identity machinery without simplifying the chosen completion contract. No automatic fallback. |

The alternative's primitives are supported by the
[timerfd description](https://man7.org/linux/man-pages/man2/timerfd_create.2.html)
and [epoll_wait description](https://man7.org/linux/man-pages/man2/epoll_wait.2.html).
Readiness is permission to attempt a read, not the task's terminal result.
This comparison does not reject epoll for later native readiness integration.

## Required set and native boundary

Required facilities are `io_uring_setup`, shared-ring `mmap`/unmap/close,
`io_uring_register(IORING_REGISTER_PROBE)`, `io_uring_enter` for submission and
explicit wait, `IORING_OP_TIMEOUT` with only `IORING_TIMEOUT_IMMEDIATE_ARG`,
and `IORING_OP_ASYNC_CANCEL` with flags=0 keyed by exact timeout user_data.
Use 64-byte SQEs and 16-byte CQEs, initialized reserved fields, setup flags
`IORING_SETUP_CQSIZE | IORING_SETUP_SINGLE_ISSUER`, SQ=32 and CQ=64 for this first
bounded provider. Require returned `IORING_FEAT_NODROP`. No SQE link or
CQE-suppression flag is selected. UAPI fields/opcodes are checked against the
[v7.2 header](https://raw.githubusercontent.com/torvalds/linux/v7.2/include/uapi/linux/io_uring.h).
Configuration authority is
[v7.2 init/Kconfig, IO_URING](https://raw.githubusercontent.com/torvalds/linux/v7.2/init/Kconfig).

Recommend a **thin C liburing-assisted boundary**, with the inspected
**liburing-2.15** tag as the proposed helper source floor, matching bundled headers
and library. This is a revised dependency proposal, not a production dependency
or runtime qualification. Linux v7.2 remains the separate kernel source-audit
floor. Astra owns credits, tokens, CQ classification, task scheduling and lifetime.
The helper owns low-level mapping/submission/CQ ordering; it supplies no GLib loop
or scheduler. No library was installed or compiled.

R3 corrects the prior flag-absence premise. The
[2.14 UAPI timeout block](https://raw.githubusercontent.com/axboe/liburing/liburing-2.14/src/include/liburing/io_uring.h)
lacks IMMEDIATE_ARG; the separately inspected
[2.15 UAPI block](https://raw.githubusercontent.com/axboe/liburing/liburing-2.15/src/include/liburing/io_uring.h)
positively defines it at displayed zero-based L333. L17's earlier assertion was
incorrect; the old retrieval retained no complete external bytes to reconcile
byte-for-byte. Historical content remains at 7674514. The new evidence retains
bounded observations, tag URLs and line ranges, without claiming peeled commits,
full-file hashes or uncached retrieval. Container raw download failed DNS.

The [2.15 preparation/data64 interfaces](https://raw.githubusercontent.com/axboe/liburing/liburing-2.15/src/include/liburing.h)
carry flags and integer identities. The timeout helper still accepts a timespec
pointer: initialize the SQE, prepare with a null placeholder/count=0, then assign
checked nanoseconds to `addr` and the named immediate flag to `timeout_flags`
before submission. Never encode nanoseconds as a fake pointer. Cancel64 uses
separate target identity and flags; set a different data64 command identity.
CQ fields require operation-specific interpretation before advancing the CQ.
These are inspected interfaces, not a compiled helper combination.

| Boundary | Maintenance / dependency / ordering requirements | Proposed choice |
| --- | --- | --- |
| liburing-assisted | Matching 2.15 headers/library add a build/deploy dependency; maintained ring helpers reduce Astra's synchronization surface; still audit exact setup, partial submit, credits and CQ interpretation | Prefer after this source correction; source-inspected floor only, later compile/runtime qualification required |
| Direct UAPI | Existing libc/syscall toolchain and pinned UAPI avoid helper deployment; Astra then owns mapping, synchronization and target/compiler maintenance in addition to the same task protocol | Allowed with an independently justified deployment/maintenance constraint; flag absence no longer supplies that argument |

The [2.15 mapping/setup implementation](https://raw.githubusercontent.com/axboe/liburing/liburing-2.15/src/setup.c)
shows that the convenience initializer tries NO_SQARRAY. Preserve the exact
selected setup by using explicit setup and queue_mmap, with identity SQ-array
initialization, instead of adaptive initialization. Check returned parameters
before accepting tasks; exit the ring only after drain. This narrow adapter does
not handwrite shared-ring barriers.

The [2.15 submission implementation](https://raw.githubusercontent.com/axboe/liburing/liburing-2.15/src/queue.c)
distinguishes ordinary syscall submission from SQPOLL publication. Its non-SQPOLL
path writes the tail before entering the kernel; SQPOLL uses release publication.
Use the selected non-SQPOLL path, with submission counts/errors preserved, rather
than assuming every helper path has identical barriers. CQ acquire/release
interfaces use the [2.15 C atomic helpers](https://raw.githubusercontent.com/axboe/liburing/liburing-2.15/src/include/liburing/barrier.h).
One user thread does not make shared kernel memory synchronous. No handwritten
assembly or lock-free claim is required. Reverify exact bytes, ABI and behavior
before provider implementation; no minimum-compatible-version survey is claimed.

Optional later complementary facilities: epoll for readiness sources and eventfd
for deliberately designed host-loop wake integration. Deferred: signalfd (needs
thread/signal-mask policy), pidfd/process waits, cross-thread posting, networking,
multishot, zero-copy, registered buffers/files and streams. No later facility is
a required first import. SQPOLL, IOPOLL, DEFER_TASKRUN, SQ_REWIND, mixed CQE/SQE
sizes and aggressive submission flags are not selected. This keeps CPU/power,
task-work progress and CQ parsing choices deliberate; no runtime framework is
silently substituted on failure.

## Clock, outcome and cancellation mapping

Use relative CLOCK_MONOTONIC elapsed durations: system suspend time is excluded;
wall-clock changes do not redefine a delay. The initial source `delay_ms(int)`
accepts 0 through INT_MAX milliseconds, converts with checked widened arithmetic
to nanoseconds, and rejects a negative/unsupported range as portable InvalidDuration.
Zero remains a real timer operation and can finish before the first pump.
No absolute deadline, clock selection or 64-bit source integer feature is required
first. A host extension can later expose those with explicit range/clock semantics.

The selected timeout SQE uses opcode TIMEOUT, fd=-1, len=1, off=0 (no completion
count trigger), addr=checked duration nanoseconds, timeout_flags=IMMEDIATE_ARG,
and a unique integer operation ID in user_data. Default CLOCK_MONOTONIC and
`-ETIME` expiry are defined by the timeout manual above. Map expiry to source
Success(void), `-ECANCELED` to the drained cancellation path, and other terminal
errors to portable ProviderError with raw diagnostic detail. A flags=0 one-shot
has no nonterminal MORE event. Unexpected positive/zero results or MORE are
protocol diagnostics for this selected path, not ordinary successful delay.
Rejecting raw negative CQE results generically would misclassify expiry.

Cancel has a **distinct command identity** and targets the timeout's integer ID.
Its result does not own the timeout's result slot or the frame. The
[cancel manual, Errors/Notes](https://man7.org/linux/man-pages/man3/io_uring_prep_cancel.3.html)
distinguishes success, absent target and too-late cancellation. Retain the target
until its terminal CQE is observed even when the command reports 0, ENOENT or
EALREADY. Wait for the command's own CQE too before retiring the identity.
[v7.2 cancel.c](https://raw.githubusercontent.com/torvalds/linux/v7.2/io_uring/cancel.c)
`io_cancel_req_match`, `io_try_cancel`, `io_async_cancel_prep` and
`io_async_cancel` establish matching and the separate command completion path.
Do not claim synchronous bounded cancellation from a request submission.

Immediate-value timers expose no user payload pointer to the kernel. The frame's
buffer owner still survives its own suspended computation and cancellation
cleanup. Target CQE drain permits timer quiescence; outstanding cancel-command
CQEs and local token references delay registration retirement; queued ready work
delays frame release; source result consumption may transfer the owner past frame
release. Closing a ring or a timed-out process is not the selected join proof.

For deferred compatibility tests, the
[multishot manual](https://man7.org/linux/man-pages/man3/io_uring_prep_multishot_accept.3.html)
uses MORE to distinguish continuing notifications. The
[zero-copy send manual](https://man7.org/linux/man-pages/man3/io_uring_prep_send_zc.3.html)
separates transfer result from a later NOTIF permitting buffer reuse when MORE
indicates that notification will follow. The portable proposal waits for release
before delivering owned payloads. These facts justify abstract model distinctions;
they do not qualify any socket/zero-copy implementation or introduce streams.

## Availability and pressure

Startup first records the exact running identity and declared profile. Initialize
the ring with the exact setup flags, require the returned feature bit, probe
TIMEOUT and ASYNC_CANCEL, then exercise a bounded immediate-value timeout and
cancellation/drain witness during **later provider qualification**. Opcode probing
alone cannot prove timeout flag support. A future startup compatibility self-check
may test the exact flag on a zero timer before accepting application work.
Unsupported version/config/op/flag, environment denial, resource exhaustion and
unexpected provider protocol behavior have distinct errors. No automatic fallback.

`EPERM` alone does not identify an administrator's io_uring policy. The
[kernel sysctl documentation, io_uring_disabled/io_uring_group](https://www.kernel.org/doc/html/latest/admin-guide/sysctl/kernel.html#io-uring-disabled)
documents one possible restriction; seccomp or other controls may also deny
creation. Record available read-only observations and actual errno, with unknown
cause left unknown. Never adjust policy, install packages or require privileges
automatically. Setup failure must unwind only adapter resources actually acquired.

Admission bounds: at most 8 enrolled tasks and 16 live timer registrations, each
with at most one target and one cancel command. Reserve cancel-submission space
and two CQ credits per accepted timer before publication; accepted+undrained
target/command credits may never exceed 32, below CQ=64. A credit is returned
only after decoding/draining that CQE; a retired ID does not erase undrained
evidence. The first profile has no unbounded multishot producers. Prepared SQEs
are retained until SQ consumption/known acceptance; partial submit counts do not
authorize reissuing accepted operations. On transient SQ pressure, retain a
bounded intent or return QueueFull before acceptance. Source tasks whose operation
has been accepted retain their obligations regardless of subsequent submit error.

Each `pump(task_budget, completion_budget)` requires both budgets positive,
performs bounded CQ intake and pending submission, then FIFO cooperative turns;
it refills capacity-excluded dirty tasks using a rotating cursor. Queued CQ
records are copied/validated before CQ head advancement. CQ overflow or a
no-drop failure stops admission and drives drain; missing ownership evidence is
a fatal provider-integrity failure, not permission to release an unknown live
payload. The
[setup manual, NODROP and SINGLE_ISSUER](https://man7.org/linux/man-pages/man2/io_uring_setup.2.html)
describes these feature contracts and overflow limits. A finite task/completion
budget bounds user dispatch, not every kernel syscall's latency.

Use nonblocking submission/reaping in pump, with enter GETEVENTS/min_complete=0
when needed to service pending kernel work/overflow without waiting. `wait` is
distinct: submit accepted intents and enter GETEVENTS/min_complete=1 only when
there is pending external work and no runnable task. With no tasks/operations,
return Idle rather than wait for nonexistent completion. EINTR preserves all
intents/obligations; report or retry at the host boundary. Completion intake,
cancellation and shutdown receive service every pump even with a continuously
ready task. Hosted run is one convenient explicit driver; manual pumping is
part of the same design. No hard real-time or thread-safety claim follows.

## Qualification recorded now

Read-only host inspection found `7.2.8-200.fc44.x86_64`, the immediate-timeout
flag in installed UAPI, GCC 16.2.1, io_uring_disabled=0 and io_uring_group=-1.
The executing sandbox has NoNewPrivs=1 and Seccomp=2. liburing headers/pkg-config
metadata were unavailable. These observations do **not** prove setup is permitted,
CONFIG_IO_URING matches a supplied source tree, or a timer/cancel path works.
No diagnostic kernel probe was run; no kernel/source clone, install, sysctl,
security or package mutation was made. Direct network retrieval from the shell
failed DNS; primary pages were inspected through the browsing tool.

Required source behavior at v7.2 is verified with this stated scope. Introduction
and full fix history, runtime availability, exact built-source identity, native
memory ordering implementation and eventual-provider performance remain untested
or unresolved. `LINUX_PROFILE_REVIEW_READY=YES` means this definite bounded
proposal has grounded requirement rows, not that `REAL_ASYNC_IO_QUALIFIED` is YES.
ASYNC-IO-1 must reverify sources and qualify exact headers, compiler, kernel,
setup denial paths, real elapsed timer, cancellation orderings, manual pump,
pressure and safe shutdown before delivering the selected provider.
