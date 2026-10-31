# Hosted executor composition

M17 completed scoped qualification of the common core, selected frames and public
worker bridge, including source-bound integration, opaque SDKs and its fourth
frozen challenge. See the final qualification
for exact profiles and retained failures. M18 requires fresh qualification of its
final compiler/runtime together; earlier receipts do not establish that result.

Select `async/composition.vapi` for the unique `WorkerPool` resource. Create it
with `worker_pool(1..8)`, check for null, then move it into the owning service
task. Its destructor joins the native workers. Explicit composed nominations
allow a cooperative or Linux service to await a worker task in another namespace.
Both nominations must bind the same nominal runtime error Class.

For example, put the service nomination and shared error in one source:

```astra
class BridgeError : Error {
	init(string message) : base(message) {}
}
enum Status { Completed, Cancelled }
async runtime IoExecutor throws BridgeError returns Status
	provider "linux-io-uring-composed";

async void serve(owned WorkerPool pool) throws Error {
	int answer = await pool.submit(CPU.answer(35));
	if (answer != 42) { throw new Error("worker result"); }
}

int main() {
	var pool = worker_pool(2);
	if (pool == null) { return 1; }
	try {
		var executor = IoExecutor.open(8);
		var status = executor.run(serve(move pool));
		match (status) { case Status.Completed(): {} else: { return 2; } }
	} catch (Error error) { return 3; }
	return 0;
}
```

The worker source has its own nomination:

```astra
namespace CPU;
enum WorkerStatus { Completed, Cancelled }
async runtime WorkerExecutor throws BridgeError returns WorkerStatus
	provider "posix-threaded-composed";
async int answer(int seed) throws Error {
	await delay_ticks(1);
	return seed + 7;
}
```

`virtual-composed` selects cooperative logical time instead of Linux service
time. Existing provider spellings retain their original compatibility rules.
Normal `start`, `await` and `cancel_and_join` remain within their nominated
provider. Cross-provider submission is explicit:

```astra
var cold = CPU.answer(35);
int answer = await pool.submit(move cold);
var abandoned = CPU.answer(0);
await pool.cancel_and_join(move abandoned);
```

Submission consumes a fresh or moved cold typed task. The parent retains the
pool and the child obligation through observation. It resumes on its original
executor with the typed result or original checked exception. Worker task bodies
may start multiple worker-local children. Their transitive owner, context and
result graphs must satisfy worker capabilities. Worker-to-service submission
is refused, preventing an executor ownership cycle in this profile.

Native backing uses the task's exact provider requirement, executor identity,
registration slot and generation. A bounded source bridge count and target slot
table control admission. Admitted frames keep their original parent responsibility;
no pending frame is rebound. Cancellation drains children and accepted provider
access before frame destruction. `request_worker_pool_shutdown(pool)` publishes a
shutdown request without joining; normal parent observation and final owner
destruction complete retirement and joins. The native request path likewise
routes Linux cancellation to the ring owner.

The Linux creator alone submits and drains its SINGLE_ISSUER ring. Worker
publication writes a nonblocking eventfd, and the owner polls it alongside CQ
readiness. Cancellation from another thread queues a copied generation token.
The owner performs the actual provider operation. The 100 ms poll backstop permits
transport retry; notifications provide ordinary progress even with no active I/O.
Cooperative composition waits on the publication condition when no logical timer
can advance. The starting global metadata mutex remains; user code and allocator
callbacks execute outside it. No speedup or lock-free claim is made.

Link exactly one common-core entry object. `async-composed.o` provides worker and
cooperative execution and accepts the separately linked Linux provider. The
standalone `async-virtual.o` and `async-threaded.o` preserve their legacy entry
recipes. Constructors have distinct emitted symbols. The installed source closure
includes `task-core17.c`, `task-api17.c` and `worker17.c`; rebuilding an entry
requires those files. Composed worker clients without Linux acquire no liburing
or context-provider dependency. Context-selected tasks additionally link
`context-17.o`; see `allocator-contexts.md` for `task_in`.

The version 17 cold factory carries parent, optional frame allocator descriptor
and context, plus exact provider admission. Native callable contracts retain the
composition effect. Stale task interfaces require rebuild. Current native schema `runtime-units/6` carries the versioned ownership and
runtime effects. Producer and consumer must use the same compiler fingerprint.
The final complete legacy compatibility refresh remains a campaign obligation.

Portable focused qualification:

```sh
project_build="$HOME/Workspace/codex/work/astra/build"
project_product="$project_build/runtime-composition-17"
uring_prefix="$HOME/.local/opt/liburing-2.15"
python3 tests/runtime-composition-17/bridge-virtual.py "$project_build/astrac" "$project_product/bridge-virtual"
python3 tests/runtime-composition-17/bridge-protocol.py "$project_build/astrac" "$uring_prefix" "$project_product/bridge-protocol"
python3 tests/runtime-composition-17/bridge-public.py "$project_build/astrac" "$uring_prefix" "$project_product/bridge-public"
```

The public witness computes in Astra over owned inputs read by real io_uring,
returns an owned result through the bridge, and writes it with real io_uring.
Its two worker jobs process bounded chunks with explicit suspension points;
independent observers require file submission and completion during active work,
then check exact destruction, descriptor closure and worker retirement. Python
independently computes the result and compares the output bytes. This is a runtime
composition witness; the streaming network application remains separate work.
