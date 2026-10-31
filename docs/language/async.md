# Native tasks and the virtual executor

A2-NATIVE-EXCEPTION-TASKS is approved. ASYNC-1 R1 implements the bounded native ownership/result/frame/loan subset; current validation scope describes its source and finite controls. Exact final qualification is tied to the external delivery receipts. [ADR 0091](../decisions/0091-native-exception-tasks.md) records actual approval provenance.

The explicit [L1 Linux timer provider](../platform/linux-uring-timers.md) reuses this task contract with `delay_ms` and host `wait`; its qualification is separate from these virtual semantics.

Select `base/errors.astra` and `async/virtual.astra` explicitly, and link the matching `async-virtual.o` support object. This opts the source program into one exact ordinary AsyncError class and Completed/Cancelled enum nomination. The runtime owns virtual queue/timer registration; generated native code owns source control flow, exception handling and frame destruction.

```astra
async int calculate(int seed) throws Error {
	await delay_ticks(1);
	int value = seed + 5;
	await delay_ticks(2);
	return value;
}

async void application() throws Error {
	int value = await calculate(17);
	if (value != 22) { throw new AsyncError("unexpected value"); }
}

int main() {
	try {
		var executor = VirtualExecutor.open(3);
		var status = executor.run(application());
		match (status) {
			case RunStatus.Completed(): { return 42; }
			else: { return 1; }
		}
	} catch (Error error) { return 2; }
}
```

Calling `calculate` evaluates its arguments and creates a cold unique task. `var child = calculate(17);` holds its consuming right; `var replacement = move child;` moves that right. A cold task drops at scope exit without entering its body. An ordinary await consumes a fresh call or `move child`. Task values have no ordinary field, parameter, returned-handle or foreign spelling in this subset.

`async` and `await` are reserved keywords. `capture`, `Result`, `Completion`, `start`, `cancel`, `run` and `delay_ticks` remain ordinary identifiers outside their checked operations. The inherited enum source test retains its unrelated identifier cases and replaces only its obsolete async/await admission with explicit keyword rejection checks.

Inside an async body, `start(child)` enrolls a child on the current executor and retains its unique local right. Every subsequent reachable exit must consume the started child. `cancel(child)` requests cancellation and retains that right. An explicit `await cancel_and_join(move child)` drains and discards success, exception or cancellation. Cancelled ordinary await propagates cancellation through the parent and bypasses Error catches.

An Error catch borrows the original dynamic exception. Its ordinary message view and copied local view can survive a suspension while the catch owner remains live. Bare `throw;` transfers the nearest catch owner. A replacement exception releases that owner once. Cancellation retains the catch/frame owners until descendants and external users drain, then destroys them at retirement.

`delay_ticks` takes an `int` or `u32`; negative signed ticks raise the nominated AsyncError. Admission and logical-time overflow are checked AsyncError effects. Declare or catch both child and runtime exception bounds. Starting failure retains the cold local. Consuming await admission failure destroys the consumed cold task.

Host operations are `VirtualExecutor.open(int)`, `executor.start(root)`, `executor.cancel(root)`, `executor.pump(u32)`, `executor.advance(u32)`, `executor.begin_shutdown()`, `executor.shutdown_complete()`, `executor.finish_shutdown()` and the consuming `executor.run(root_call)`/`executor.run(move root)`. The host root is void. Pumping never advances logical time; explicit advance never enters a body inline. Executor scope cleanup requires its obligations to be discharged; the bridge drains and observes its root. Manual execution/provider quiescence and root observation remain separate.

The frame path supports scalar/vector/mask values, copied records/enums, owned primitive/vector/mask/record arrays and owning enum success. Owned buffers and Resource arguments transfer to cold frames; fresh producers are supported at task creation. Late argument failure restores named reservations and destroys completed fresh captures in reverse order. Declared fixed arrays/records, active enums, Resource state and catch/message backing retain stable frame storage across suspension.

A fresh directly awaited child may borrow a slice constructed from a sealed fixed parent-local array. Its exact view and backing remain live through child/provider join. Stored or separately started borrowed tasks, incoming external borrows and uncontrolled stored aliases reject. This includes direct await with fresh owned captures; it does not introduce general escaping loans.

Published outcomes keep their original identity. A cancellation request after publication cannot change success or exception. External backing retention and queued callbacks block publication or retirement until legitimate observation. Executor tokens validate executor identity, slot and generation before accessing a task. No source Task C ABI is introduced.

| Historical proposal | Current approved disposition |
| --- | --- |
| ADR 0085/R3 three-way explicit completion proposal | Separate native success, exception and cancellation; ordinary await plus explicit drain/discard. Historical proposal retained. |
| Mandatory Result/Outcome/capture or prefix try drafts | Ordinary enum/Result values remain separate; native exceptions follow ADR 0090. |
| ERROR-1 synchronous exception implementation | Accepted baseline retained with its original qualification/interpreter disclosures. |
| Proposed Linux provider profile | ASYNC-IO-1 subsequent gate; this virtual executor introduces no real I/O. |

Shared tasks, arbitrary escaping task handles, cross-thread execution, broad loans, Class/Resource success, Class captures, async methods/generics, cancellation recovery, arenas and nonvoid roots remain extensions. LAZY-1 is near-term and PERF-01 is unscheduled.

## Selected Linux file payload extension — 2026-10-17

The virtual subset above remains dependency-free. The separately selected
Linux provider now supports real file payloads under
[ADR 0114](../decisions/0114-owned-linux-file-payloads.md), in addition to its
earlier qualified timer operations. Select `linux.astra`, `payload.astra` and
`payload.vapi`, and link the explicit virtual/Linux support objects with an
existing matching liburing >=2.15. The default `linux_async=false` compiler
build does not require that dependency.

An async function owns an exact `LinuxPayload`. Configure its byte range and
nonnegative i64 file offset, then use `await payload_io(payload)`. Opening a
payload chooses read or write mode and a stable buffer of at most 1 MiB. The
actual completion count distinguishes short progress and read EOF; applications
advance offsets and retry incomplete writes. Bytes become text only through
existing UTF-8 validation. Checked wrappers report open/range/byte/close errors,
and provider failure uses the nominated AsyncError channel.

The frame retains its fd/buffer owner through actual observed target completion
and any prepared cancellation-command completion. During flight, access,
mutation and close are forbidden. A generated but undrained CQE grants no access;
cancel-command success alone cannot grant release. Borrowed, moved, released or
unrelated owners, and virtual-provider payload suspension, reject at compile
time. There are no exported raw buffer/fd views, sockets, registered buffers,
multishot or cross-thread guarantees. See the
[public A37–A40 recipes](../../examples/interop-async-5/README.md) and
current qualification for actual host and
cancellation evidence. Historical LAZY Q4 remains HELD.

## Explicit hosted composition — M17 implementation checkpoint

The opt-in `virtual-composed`, `posix-threaded-composed` and
`linux-io-uring-composed` nominations share task ABI 17 and the same nominated
error type. Import `async/composition.vapi` and link one `async/composed.c` core;
link the Linux provider and matching liburing separately when selected. The
ordinary standalone virtual and worker entries remain separate build choices.

An owned `WorkerPool` comes from `worker_pool(count)`. Inside a service async
body, `await pool.submit(cold_call(...))` or `await pool.submit(move child)`
consumes a cold worker task and observes its original result/error/cancellation
on the service executor. `await pool.cancel_and_join(move cold_child)` discards
and retires a cold worker task. The pool remains a named owner in the awaiting
parent. A started service child which is awaiting worker submission can itself
be cancelled and joined; that observation includes its target's retirement.
Worker-to-service bridges and cycles remain refused in this implementation.

Worker cancellation is cooperative. Active Astra code retains its captures and
selected frame until its native resume returns. Cancelling an already published
task preserves its original success or checked error. Pool close joins its
workers; `pool.request_shutdown()` only publishes a shutdown request and leaves
observation/join responsibility with the owner. User callbacks and frame allocator
callbacks execute outside the scheduler metadata lock.

Concrete closed owning records can move into cold frames, occupy async locals,
and return as owning successes. Their Class, Resource and owned-buffer fields
retain their individual allocation origins through suspension. Typed record
initialization from `await` takes the whole success; dropping an unobserved
published success destroys its complete field graph. Cold disposal, checked
errors and joined cancellation retire only initialized fields, in reverse
acquisition order. Worker capture and success require transitive Send authority;
borrowed record captures remain refused.

With `memory/contexts.vapi`, `task_in(context, async_call(...))` selects the actual
frame backing. Worker admission requires concurrent backing and a compatible
transitive capture graph. Closing the last context handle stops new allocations;
accepted frames and captures retain its backing through final release.
`checked_task_in(context, async_call(...))` instead raises the target runtime's
nominated error if frame admission fails, before a Task is published. Nullable
named Class/Resource captures, complete owned buffers and named whole owning
records stay with the caller
on refusal; successful admission transfers them and empties those caller slots.
The original pointer, length and allocator authority remain one buffer owner.
Record restoration preserves the whole field graph; admission empties its
owning fields together and retains its copied leaves.
Creation must catch or
declare this immediate effect, independently of the deferred task-body errors.
The qualified profiles include virtual and real workers, actual pool/header
refusal, cold disposal, body failure, and restoration inside a suspended parent.
Scoped captures and selected frames retain their complete caller lifetime
obligations through observation and joined cancellation. The affine home-retirement
witness also checks actual foreign worker notification and owner/frame release on
the original service thread. These paths do not grant arbitrary cross-thread
transfer of an affine graph. See [allocator contexts](allocator-contexts.md) and
the live qualification for the exact
supported shapes and remaining full-campaign gates.
