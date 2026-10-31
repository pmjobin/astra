# Hosted concurrency

Surge 13 qualifies GNU Linux x86-64 native threads, atomic shared lifetimes,
protected Classes, a bounded threaded task executor, Actor mailboxes and actual
TCP/UDP. The [accepted lifetime decision](../decisions/0163-concurrency-lifetime-and-scopes.md)
and [Actor decision](../decisions/0164-bounded-actor-mailboxes.md) define the
observable rules. [Applications A109–A120](../../examples/concurrency-runtime-13/README.md)
are executable examples; qualification
records the finite tested domain.

## Owners and shared state

An ordinary Class remains unique and uncounted. `[Shared]` changes that Class's
normal owner into an intrusive shared owner. Assignment moves ownership;
`clone()` explicitly acquires another strong reference. `downgrade()` creates
a weak observer and `upgrade()` returns an owning reference or null.

```astra
[Shared, Monitor]
class Counter {
	private int value;
	init(int value) { this.value = value; }
	int add(int n) { this.value = this.value + n; return this.value; }
}
int main() {
	var root = new Counter(7);
	var second = root.clone();
	var observer = root.downgrade();
	release root;
	int result = second.add(2);
	release second;
	var expired = observer.upgrade();
	if (expired != null) { return 81; }
	release observer;
	return result - 9;
}
```

The equivalent nonintrusive form for an ordinary Class is
`shared Snapshot box = shared_acquire(move unique)`. Existing `Shared<Snapshot>`
and `Weak<Snapshot>` spelling remains supported. Boxing currently requires a
concrete supported Class; it does not introduce arbitrary scalar/record boxing.
Redundant lowercase `shared` on an intrusive `[Shared]` Class is refused.
Explicit boxes retain their three-word control block and exact payload cleanup;
intrusive inheritance/interface views retain one dynamic root and destructor.

Counts use system-scope, eight-byte-aligned atomic i64 operations: acquire
loads, monotonic initialization stores, and strong compare/exchange with
acquire-release success and acquire failure. Overflow/underflow are guarded.
Weak state includes a sentinel until last-strong payload destruction returns.
An upgrade cannot acquire from zero; the final weak release reclaims allocation
metadata. Existing pool-backed boxed payload provenance remains authoritative.
Intrusive policy Classes use the hosted heap; unsupported placement rejects.

Atomic lifetime does not authorize racing payload reads/writes. Conservative
structural checks examine owned children, records, closures, shared payloads
and known polymorphic descendants at each compiler stage. Raw pointers,
borrowed state and ThreadBound state cannot become worker captures. Mutable
shared state requires the qualified Monitor discipline. Shared cycles are not
collected; no blanket unsafe Send/Sync attribute is provided.

## Protected access, affinity and singleton scope

`[Monitor]` requires private state and synchronous methods returning copied
scalars, void, or supported owned snapshots. Properties cannot expose protected
borrows. Compiler-generated entry/exit guards cover normal and checked-error
paths; even a constant method has synchronization effects. Direct internal
`this` calls reuse the guard. Other reentry and cross-object nesting refuse;
there is no general ordered multi-monitor operation in this profile. A113
places both accounts under one transfer authority. Separate monitor objects
have independent locks and an executed concurrent-progress witness.

Suspension under the lock is unavailable. Async methods are excluded by the
existing source rules; free async functions cannot bypass protected access.
Unknown callback reentry is not made safe by a recursive mutex. Fatal contract
violations abort; checked native exceptions unwind through generated unlocks.

`[ThreadBound]` records the constructing thread and checks mediated access.
Direct and nested captures in workers, migrated tasks and retained callbacks
are refused. An ordinary local closure can still access same-thread state.
Foreign opaque pointers do not acquire transfer rights from this mechanism.

The selected singleton is exactly `[Shared, Monitor, Singleton]`, with copied
numeric fields and constructor inputs, one checked compilation unit and an
explicit initializer. `new Configuration(args)` elects one initializing caller.
A checked initializer failure frees unpublished scalar state, permits retry,
and does not run the successful payload destructor. Ready callers receive
another strong owner. Recursion aborts before self-waiting. Constructor arguments
are evaluated on every acquisition; the first successful initializer determines
the stored values.

`singleton_shutdown(root)` returns null while other strong owners prevent
quiescence. At quiescence it closes acquisition, detaches the anchor and returns
one normal owner. Release both `root` and the returned owner. Weak observers
expire after final strong release. Subsequent acquisition aborts. There is no
implicit exit teardown; OOM remains the existing fatal allocation path.

## Workers and migrated tasks

`thread_bind(move environment, function)` creates an exact typed native carrier
with compiler-generated C entry. `thread_start(carrier, int)` launches one real
worker; `thread_join(carrier)` observes its result. The carrier owns its capture
until joined retirement. `thread_cancel` requests cooperative cancellation,
observed through the explicit C import `astra_worker_cancelled()`. There is no
detach/abandon operation.
Signatures, heap origins and structural transfer are checked through native ABI
and verified LLVM calls; an ordinary closure or Actor sender cannot substitute
for this carrier despite superficially matching scalar arguments.

`lib/astra/async/threaded.astra` selects `ThreadedExecutor.open(1..8)` and
`posix-threaded`; the existing cooperative source model and parent tree remain.
The provider admits at most 256 live registrations, tracks generations, and
serializes scheduler metadata while running native frame bodies concurrently
outside its scheduler mutex. Owned transferable Classes can move into and
through awaited child frames. Lexical owners and unsafe suspension loans refuse.
Ordinary task moves, checked errors, `start`, `await`, `cancel_and_join`, cold
cancellation, outstanding shutdown and join retain their cleanup obligations.
Cancellation is cooperative; it does not asynchronously unwind a worker.
Pool construction reports checked invalid-count/allocation/thread-start failure.

## Mailboxes and sockets

`[Actor]` owns a receiver with one synchronous nonthrowing handler. For example,
`actor_bind(move receiver, handle, 8, "worker")` creates a bounded FIFO with a
dedicated named executor. Capacity is 1..1024; the printable name is 1..15 bytes.
Producers explicitly clone `ActorSender<Receiver,Message>`. Supported messages
are all thirteen numeric/bool scalar types with exact bits, or owned transferable
native Classes. Borrowed, affine, unsafe shared and cyclic sender captures refuse.
`actor_send` consumes an owned message on success, full, or closed rejection.
Full/closed admission reports a checked error. `actor_cancel` destroys queued
messages; active work finishes or observes the explicit C import
`astra_actor_cancelled()`.
`actor_shutdown` joins execution and pending queued-message destruction before
receiver teardown. Actor/Monitor composition and synchronous self-join refuse.

`lib/astra/hosted/network.astra` supplies owning TcpSocket/UdpSocket Classes
and bounded byte operations over the explicit POSIX provider. Sockets use
nonblocking kernel I/O and task polling with checked deadlines. Accept/connect,
partial reads/writes, EOF, backpressure, refusal/busy endpoints, datagram endpoint
metadata, empty/max/truncated packets and cancellation are exercised. Buffers
remain owned/pinned by the active frame until completion or joined cancellation.
This is loopback qualification on the host, not DNS, TLS, remote service or
portable Windows networking. There is no claim of io_uring socket completion.

## Linking and foreign boundaries

Providers are explicit link inputs and optional Meson support objects behind
`-Dhosted_concurrency=true`. Link the required `threads-13`, `monitors-13`,
`singletons-13`, `actors-13`, `async/threaded`, `text-posix`, or `network-posix`
objects, plus pthread where needed. `applications.py` records exact recipes.
The cooperative/liburing profile remains separate; never link both async
providers' competing ABI symbols into one product. Unused pure and no-OS
programs gain no mandatory concurrency/network/foreign dependency.

The qualified foreign callback path retains exact compiler-owned thread-carrier
contexts in C, calls the generated C thunk from four workers, catches native
errors before returning to C, and joins before retirement. The older general
`retained.c` registrar keeps its established single-threaded protocol. Neither
path grants arbitrary C callbacks, foreign object agility, COM/GObject export,
or exception unwinding through C. See the Surge 14 handoff.
