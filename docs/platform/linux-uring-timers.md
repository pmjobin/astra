# Linux io_uring timers

L1-LINUX-URING-TIMERS implements the explicit provider authorized by ASYNC-IO-1. The validation record separates real kernel execution, deterministic injection, instrumentation and final qualification. [ADR 0092](../decisions/0092-linux-uring-timers.md) records the selection; [the private boundary](../abi/linux-uring-timers.md) describes retention and completion evidence.

Select `base/errors.astra` and `async/linux.astra` explicitly. That support nominates the ordinary AsyncError class and Completed/Cancelled enum with:

```astra
async runtime LinuxExecutor throws AsyncError returns RunStatus provider "linux-io-uring";
```

`provider` is contextual here and remains an ordinary identifier elsewhere. Omitting the clause selects the established virtual provider. Each compilation has one exact runtime nomination; its checked identity survives renaming and lowering.

```astra
async void application() throws Error {
	await delay_ms(20);
	await delay_ms(0);
}

int main() {
	try {
		var executor = LinuxExecutor.open(2);
		var status = executor.run(application());
		match (status) {
			case RunStatus.Completed(): { return 42; }
			else: { return 1; }
		}
	} catch (Error error) { return 2; }
}
```

`delay_ms(int_or_u32)` evaluates once and submits a relative CLOCK_MONOTONIC one-shot timer. Negative signed values raise AsyncError before admission. Widened checked conversion uses nanoseconds; zero follows the same completion handshake. Count-zero `-ETIME` means success. A terminal operation error reaches the existing Error handler on generated resumption after provider retirement. Cancellation follows the established separate propagation/discard path.

Linux host operations are `open(int capacity)`, `start`, `cancel`, `pump(u32 turn_budget)`, `wait`, `run`, `begin_shutdown`, `shutdown_complete` and `finish_shutdown`. Capacity is 1..16 associated tasks. `pump` performs bounded cooperative turns and two completion batches of at most 32 each; pending target/cancel SQEs remain bounded by the sixteen records. It never deliberately waits. `wait` dispatches no user body and blocks only with external work and no ready task. An empty or ready executor returns without waiting for nonexistent work. `run` explicitly drives this same scheduler and consumes the void-root observation right. Scope destruction does not hide a blocking drain.

Linux rejects `advance` and `delay_ticks`; the virtual provider rejects `wait` and `delay_ms`. The existing ownership, caught exception/message views, parent-local suspension loans, start/join obligations and published outcomes described in the [task guide](../language/async.md) apply unchanged. Parent cancellation drains its subtree while unrelated tasks continue. A cancel command result cannot retire its target.

The first platform is single-threaded hosted GNU LP64 x86-64 Linux, with Linux v7.2 as the selected source-audit floor and matching liburing headers/library at least 2.15. Runtime setup requires SQ=32, CQ=64, CQSIZE|SINGLE_ISSUER|NO_SQARRAY, 64-byte SQEs, 16-byte CQEs, NODROP, and TIMEOUT/ASYNC_CANCEL support. Setup, dependency, capability and operation failures retain typed stage/errno diagnostics. No security policy is changed and no fallback is selected. A release string and opcode probe alone do not qualify immediate timeout behavior; deployment must exercise the actual profile.

Build the optional provider with the existing Linux/GCC support-object configuration and `meson setup build -Dlinux_async=true -Dpkg_config_path=/your/private/liburing/lib/pkgconfig`, using matching headers and library. Unsupported selected configurations fail explicitly. Default builds do not require liburing. The installed compiler and ordinary virtual/nonasync clients retain their existing dependencies. An installed Linux consumer explicitly links the target support inputs:

```sh
astrac errors.astra linux.astra application.astra --link-object async-virtual.o --link-object libastra-async-linux.a --link-object liburing.a -o application
```

The first object contains the shared scheduler, including its virtual implementation; the optional archive adds the Linux provider. These are explicit consumer paths, and the liburing license notices accompany a private redistribution. No absolute campaign path is required by the installed consumer.

This provider exposes timers and cancellation. File/socket transfers, threads, multishot, zero-copy, hard real-time behavior and general lifetime extensions remain outside L1. LAZY-1 remains near-term; PERF-01 remains unscheduled.
