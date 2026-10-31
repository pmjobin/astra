# Allocator contexts

M17 completed its scoped runtime-composition qualification under ADR 0167.
The final qualification
records source identities, executed profiles and retained failures. Current M18
optimizer and release qualification remains a separate campaign.

Select `memory/contexts.vapi`, `memory/contexts.astra`, and explicitly link
`context-17.o` with pthread support. These hosted dependencies are opt-in.
Existing Classes and static allocation policies keep their current strategies.

```astra
[Allocator(kind="context",context="owned-concurrent")]
class Entry {
	private int number;
	init(int number) { this.number = number; }
	int read() { return this.number; }
}

owned Entry make_entry(borrowed ConcurrentAllocator arena, int number) {
	var entry = new (arena) Entry(number);
	return move entry;
}

int main() {
	var first = concurrent_allocator(AllocatorRegion, 32771, 17, 64);
	var second = concurrent_allocator(AllocatorPool, 40963, 19, 128);
	if (first == null || second == null) { return 1; }
	var a = new (first) Entry(17);
	var b = make_entry(second, 23);
	return a.read() + b.read() - 40;
}
```

The declaration records a lifetime/thread capability; the expression selects
the actual instance. Instances of the same type have independent backing,
identity, generations and counters. The Class remains uniquely owned, with
ordinary moves and deterministic destruction. A dynamic allocation prefix
retains its origin, extent, alignment and release token. Static allocations
retain their existing representation. There is no current-allocator global.

`scoped_allocator<ScopedAllocator>(backing, kind, slots)` introduces an exclusive
lexical loan of a named owned byte buffer. Both an ordinary owned `u8[]` and an
owned `ContextBytes<ConcurrentAllocator>` can supply the complete backing pair:

```astra
owned u8[] backing = new u8[8197];
{
	var context = scoped_allocator<ScopedAllocator>(backing, AllocatorRegion, 7);
	if (context == null) { return 1; }
	if (scoped_allocator_query(context, 7) != 1) { return 2; }
}
backing[0] = 17;
```

Synchronous scoped Class construction now accepts an exact named backing loan
or borrowed scoped-context parameter. `new(context)` and `try_new(context)` use
the selected storage. Source, Core, CFG and SSA must independently reconstruct
a complete function lifetime proof; unsupported operations refuse admission.
LLVM retains exact allocation, receiver, ownership and backing authority after
the higher representations are discarded.

```astra
[Allocator(kind="context",context="scoped-affine")]
class ScopedEntry {
	private int number;
	init(int number) { this.number = number; }
	int read() { return this.number; }
}
```

Within the backing block above, `var value = new(context) ScopedEntry(17);`
constructs a real caller-backed Class. Its destructor and allocation retire before
the context, which retires before the backing. Owners can move through supported
direct calls and owning records within that region. Inspect owning record fields
through a synchronous borrowed-record parameter. Returning an owner backed by a
local context, storing it in a longer-lived receiver, or entering a body with an
incomplete lifetime effect is rejected.

The executed scoped-Class witness covers scalar fields, two closed generic Class
layouts, separate same-type contexts, flat and closed generic owning-record
handoff, checked exhaustion and observed pool-slot reuse. Independent observers check actual allocation addresses
inside both original buffers, exact release tags, destructor-before-release and
context-before-backing retirement. Detached real-source construction controls also
cover local and borrowed context selection. Ordinary, checked and relayed synchronous factories can return a scalar-field
scoped Class tied to one original borrowed scoped context. The caller must keep
that exact context/backing alive until the result retires. Nullable checked
results distinguish real allocation absence from a discarded live owner. Two
closed generic result layouts retain their separate release tags. The later
sections describe the qualified owning-field, result, checked-construction and
task paths. Additional container/closure/frame graphs and fixed-array backing
still require their complete lifetime effects.

Trusted C calls with primitive results and primitive inputs or borrowed allocator
inputs have no owner-transport effect. Their implementations must honor that
borrow, including no retirement or retention of the context or its derived
ownership. Pointer, ordinary Resource, aggregate, callback and owning-result
transport require additional effects and remain incomplete in this analysis.
The controller must be a direct named `var` or `owned ScopedAllocator` binding
in synchronous code. It can enter synchronous borrowed parameters, including
opaque native-unit helpers. It cannot move, alias, rearm, return, enter a field
or retire through explicit `release`. Automatic scope cleanup destroys the
context before its backing owner. A refused factory conservatively keeps the
loan until that cleanup. Zero-size or invalid configuration returns null.

While the loan is live, the backing cannot be read, written, borrowed, moved,
replaced, released or supplied to another context. Configuration argument
evaluation also reserves it. Normal and early exits, loops and separate
same-type contexts retain this ordering. Native plans preserve exact buffer
and cleanup identities; LLVM checks actual factory, backing access and
destruction order. It also checks emitted controller uses against the live loan
and refuses stored/returned aliases, pointer casts, indirect calls through the
controller and unregistered retirement. Queries 0–5 share the existing counters; scoped queries
6, 7 and 8 report reserved allocation bytes, borrowed backing and threading
mode. This hosted scoped controller has affine threading mode 0.

An owned allocation keeps its backing alive after the last context handle is
dropped. Dropping that handle closes admission; outstanding allocations still
destroy and release normally. Explicit close/reset refuse live allocations.
Generations never reset. A failed selected allocation never falls back to the
system heap. Ordinary `new` preserves fatal allocation failure; `try_new`
retains the currently admitted checked-construction restrictions.

`nested_allocator(parent, kind, capacity, slots, alignment)` creates an owned
concurrent region or pool whose actual backing comes from `parent`. The parent
must be an owned concurrent context. The factory acquires a separate allocation
lease before its borrowed input ends; the child owns that lease. Child objects,
frames and weak control storage can therefore outlive every admission handle in
the ancestry. Final child retirement releases the original parent allocation
after child payloads and metadata have retired. No parent/child lock is held
while recursively releasing an ancestor. Sizes and slot budgets remain values;
metadata is separate host overhead, as for other context families.

Only fresh-child construction is supported, so an existing context cannot be
adopted as its own ancestor. Nesting depth is bounded at 256 child edges. Invalid,
closed, exhausted or incompatible parents return null without fallback or loss
of the caller's handle. Scoped, affine and transferable parents cannot produce
a concurrent child through this API. Their source lifetime/transfer routes remain
part of the pending work below.

An owned context policy admits an initializer with a checked `throws` bound.
After allocation admission, its owned inputs are consumed. If initialization
throws, unconsumed inputs and the actually initialized fields retire exactly
once, unpublished backing is released, and the original error reaches the
caller. The initializer's own destructor runs only after successful completion.
This uses the existing checked-constructor field/record/slot retirement protocol.
`try_new` supports that checked exception channel with copied values, exact
nullable named Class/Resource inputs, complete owned buffers and named whole
owning records. Refusal skips the initializer, returns null
and leaves the original inputs in their caller slots. Admission transfers the
payloads and leaves those slots empty, including when initialization throws.
Buffer restoration keeps its original pointer, length and allocator authority
together; admission empties that pair even if initialization subsequently throws.
Constructor buffer arguments require an explicit move from a named owner.
Owning-record restoration preserves every original field and buffer pair;
admission empties its owning leaves together and preserves copied leaves.
Nonnull and borrowed constructor inputs still require further admission
contracts. These recoverable construction sites remain synchronous.

`ContextBag<T>` in `collections/context-bag.astra` supports instance-selected
backing. Its storage grows through the container's original context. Each
element retains its independent origin. Replacement storage is acquired before
old slots are moved and retired. Failed growth preserves storage, owners,
length and capacity. Moving a slot never relocates the referenced Class.

`ContextMap<K,V>` and `ContextCache<K,V>` are supplied alongside `ContextBag`.
The Map's selected origin governs its slot storage. Its constructor takes an
owned `ConcurrentAllocator` for entry objects and an exact key comparator;
each value keeps its own origin. A Cache takes an explicitly constructed Map.
Removing an entry returns its whole owner, including its value and backing
authority, so it can outlive the Map and all admission anchors. A free generic
factory retains the same allocation policy as a closed Class application.

A closure bound from a context-allocated environment puts its actual carrier
in that same context. The environment may own values from other contexts;
their release authority follows those values independently.

Closed [owning generic records](generic-structs.md) can own selected Classes or
allocator handles and nest other owning records. Whole-record moves, function
results and storage inside another selected Class retain every independent
origin. Their opaque native-unit exports carry the exact closed declaration and
cleanup contract. This is a storage composition checkpoint; broader owning type
arguments and the remaining checked-allocation paths still require work.

`new (context) u8[count]` allocates the actual zeroed byte storage from that
instance and returns an owned `ContextBytes<AllocatorType>`. Its pointer/length
pair retains the exact allocator capability and original release authority:

```astra
owned ContextBytes<ConcurrentAllocator> make_bytes(int count) {
	var context = concurrent_allocator(AllocatorRegion, 16387, 11, 128);
	var bytes = new (context) u8[count];
	return move bytes;
}
int byte_count(borrowed ContextBytes<ConcurrentAllocator> bytes) {
	return len(bytes);
}
```

The returned buffer outlives the factory's admission handle through its own
backing lease. An empty buffer acquires no allocation lease. Whole-owner moves,
results, Class and closed owning-record fields preserve that origin. Concurrent
buffers may cross the checked worker bridge and return through async results;
affine or transfer-capable buffers cannot enter a worker merely because they
use the same physical pointer/length representation. Affine and transfer-capable
buffers currently execute on their home thread; graph transfer remains pending.
`ContextBytes` is distinct from an ordinary owned `u8[]`; ownership conversion
cannot erase or exchange its allocator contract. Existing `new u8[count]` retains
its default allocation/release strategy and has no context-runtime dependency.

A named owned `ContextBytes` buffer can enter a synchronous nonescaping `u8[]`
parameter as a temporary view. This includes the ordinary socket methods and
explicit C `buffer_abi="u8-i32"` parameters. The callee sees the actual selected
storage and may modify it within the declared range; no copy or new allocation
occurs. The caller keeps its complete context-bearing owner and original cleanup.
The view cannot become a persistent slice, an ordinary buffer owner, or a retained
async borrow. Borrow and consumption of the same owner in one unfinished call
remain incompatible. Broader scoped/retained buffer loans are still pending.

An explicit `else action(args)` allocation-failure clause evaluates only after
refusal. Its owned arguments transfer to the action at that point. A checked
throw propagates through the ordinary exception channel; a normally returning
action reaches the enforced fallback trap. Refused storage is never published.
This differs from nullable `try_new` admission, which preserves its supported
owned constructor inputs with the caller on refusal. Selected
byte allocation currently supports `u8` elements and owned allocator contexts;
scoped backing still requires the lifetime proof described below.

`task_in(context, async_function(args))` constructs a cold typed task whose
actual suspended frame uses the selected context. The ordinary task ownership,
start, await and cancellation rules still apply. A worker frame requires
concurrent backing; affine selected frames remain on the cooperative/Linux
profile. The selected context must be a named owned handle or a synchronous
borrowed parameter. Constructor arguments cannot consume that anchor while
placement borrows it. The actual frame allocation holds backing through final
retirement, even when the anchor is dropped before the task starts.

`checked_task_in(context, async_function(args))` uses the same frame placement
and capture contract, with recoverable admission. Refusal raises the target
runtime's nominated Error before publishing a Task. Exact nullable named
Class/Resource captures and complete owned buffers retain their original payload
and release authority; admission leaves those caller slots empty. Buffer
restoration keeps the pointer, length and allocator contract together. Catch or declare the runtime error
at creation; the task body's own checked errors remain deferred until execution.
The existing `task_in` keeps ordinary fatal allocation behavior. Whole named
owning-record captures also recover their complete original field graph on
refusal. Successful admission empties every owning field together while
preserving copied leaves. These records remain usable as whole owners after
either outcome; use a bounded synchronous record borrow to inspect their fields.

Ordinary cold-frame capture and async success support whole closed owning
records, including nested records with selected Class, allocator-handle and
`ContextBytes` fields. Each field keeps its own origin. Async locals preserve
these obligations across suspension; cold disposal, body errors, joined
cancellation and discarded published results retire the complete initialized
graph in reverse acquisition order. Worker captures and results require the
full record graph to satisfy Send.

The version 17 task factory transports parent, allocator descriptor and context
as separate compiler-owned ABI channels. Native units export a separate checked
factory role with the same channels and an unpublished nullable result; the
compiler converts refusal into the checked error before Source publication.
Default construction passes null backing
channels and keeps the ordinary heap path. The common task core has no mandatory
context-provider dependency. `async-composed.o` supplies one core for worker,
cooperative and separately linked Linux providers; legacy `async-threaded.o`
and `async-virtual.o` are standalone entry recipes. Select one of these core
objects per executable. Compiler-emitted constructors now use distinct
`astra_async_threaded_open` and `astra_async_virtual_open` symbols.

`ConcurrentAllocator` and Classes whose declared context capability is
`owned-concurrent` can enter qualified worker ownership graphs. Every nested
field/capture is checked. An enclosing marker does not grant transfer to an
affine child. The native ABI retains a distinct context descriptor containing
nominal name, capability and exact backing-release symbol; it does not erase
that authority to an undifferentiated pointer.

An intrinsic `[Shared,Monitor]` Class may select an `owned-concurrent` context.
Its intrusive control storage remains in that actual allocation through the
final weak release. Payload destruction still occurs at the final strong
release, and later weak upgrades fail. Default-backed boxed control storage
keeps its separate default allocation contract. Affine and static backing
remain refused in worker shared/weak graphs.

The C provider contract in `runtime/context-17.h` admits an external stateful
allocator with its own backing. A versioned descriptor supplies allocation,
release and final-state disposal callbacks. The runtime checks observable
extent, alignment, overlap, origin and generation before publication. C remains
responsible for actual pointer validity, nonoverlap, code/state lifetime and
its declared threading behavior. Callbacks cannot unwind or reenter mutation
of the same context. Provider code is statically linked for the current profile.

The substrate additionally implements affine/transfer context state. Scoped
Class/record paths enforce their derived-owner escape proofs, and the affine
home-retirement witness observes foreign worker notification followed by actual
owner/frame destruction on the service thread. Exclusive cross-thread transfer
of a complete affine graph remains unsupported. Collection, buffer and checked
input admission require their exact contracts described here; broader shapes do
not inherit permission from sharing a physical layout. The context SDK uses
`runtime-units/6`; see [native units](native-units.md). Explicit inter-executor
submission is described in [executor composition](executor-composition.md).
Selected-frame witnesses check actual context storage; ordinary task creation
retains default backing. Final source-bound application/SDK and complete-registry
qualification remain required.

Portable focused qualification from the repository root:

```sh
project_build="$HOME/Workspace/codex/work/astra/build"
project_product="$project_build/runtime-composition-17"
python3 tests/runtime-composition-17/scoped-classes.py "$project_build/astrac" "$project_product/scoped-classes"
python3 tests/runtime-composition-17/scoped-owning.py "$project_build/astrac" "$project_product/scoped-owning"
python3 tests/runtime-composition-17/scoped-graphs.py "$project_build/astrac" "$project_product/scoped-graphs"
python3 tests/runtime-composition-17/scoped-constructor-rollback.py "$project_build/astrac" "$project_product/scoped-constructor-rollback"
python3 tests/runtime-composition-17/scoped-owned-rollback.py "$project_build/astrac" "$project_product/scoped-owned-rollback"
python3 tests/runtime-composition-17/scoped-child-rollback.py "$project_build/astrac" "$project_product/scoped-child-rollback"
python3 tests/runtime-composition-17/scoped-deep-rollback.py "$project_build/astrac" "$project_product/scoped-deep-rollback"
python3 tests/runtime-composition-17/scoped-heap-rollback.py "$project_build/astrac" "$project_product/scoped-heap-rollback"
python3 tests/runtime-composition-17/contexts.py "$project_build/astrac" "$project_product/contexts"
python3 tests/runtime-composition-17/context-owners.py "$project_build/astrac" "$project_product/context-owners"
python3 tests/runtime-composition-17/context-collections.py "$project_build/astrac" "$project_product/context-collections"
python3 tests/runtime-composition-17/context-associative.py "$project_build/astrac" "$project_product/context-associative"
python3 tests/runtime-composition-17/context-weak.py "$project_build/astrac" "$project_product/context-weak"
python3 tests/runtime-composition-17/context-workers.py "$project_build/astrac" "$project_product/context-workers"
python3 tests/runtime-composition-17/context-frames.py "$project_build/astrac" "$project_product/context-frames"
python3 tests/runtime-composition-17/context-bytes.py "$project_build/astrac" "$project_product/context-bytes-direct"
python3 tests/runtime-composition-17/context-bytes.py "$project_build/astrac" "$project_product/context-bytes-worker" worker
python3 tests/runtime-composition-17/context-byte-units.py "$project_build/astrac" "$project_product/context-byte-sdk"
```

The recipes retain exact commands, file/compiler hashes and failed attempts.
Emitted-code sanitizer runs instrument both the generated LLVM memory
operations and the C runtime/provider. The pthread conservation observer
calibrates sanitizer initialization before its baseline; no race suppression
or thread-count exclusion is used. The independent pthread-only reproducer
and earlier failed observation remain part of the evidence history.

Scoped Classes may also own ordinary heap Class children whose complete owning
graph is scope-free. Their constructor must transfer each declared child exactly
once; their destructor must retire those children before releasing the scoped
parent storage. Checked allocation refusal preserves the original child owners.
The scoped parent retains its own exact context, Class tag, extent and alignment.
`tests/runtime-composition-17/scoped-owning.astra` exercises a direct heap child
and a heap node with another owned child, two contexts and actual pool reuse.
Factories may construct and return these parents through one exact borrowed
scoped context. Checked refusal destroys factory-local heap children and returns
absence; caller-provided inputs in direct checked placement remain with the caller
on refusal. Owning input forwarding and consumption preserve the parent's origin.
A scoped parent may own an acyclic tree of eligible scoped, ordinary heap and
owned-context Class children. Every scoped descendant keeps its original context
independently of the backing selected for each ancestor. Ordinary heap roots use
their exact external free operation; context-backed roots retain their tagged
release authority. Both must discharge their child graph before backing release.
Constructor admission transfers their owner handles into checked field slots;
child retirement precedes parent backing release. Read-only methods may borrow
the exact child field without exporting its owner. Ordinary and checked placement
and closed generic parent fields use the same proof. Checked refusal preserves
caller-owned children. An owning function may forward one complete scoped graph unchanged. Its result
publishes the same original owner, and the caller transfers the parent handle
while preserving every checked child field, its context and backing lifetime.
The ordinary and checked/generic parent witnesses exercise this forwarding.
A synchronous owning function may also consume one such heap graph. Its emitted
parent destructor must discharge the opaque child obligation before parent
backing release or function exit. The caller then retires the same checked child
allocations and parent carrier. The public witness consumes both ordinary and
closed-generic parents and observes empty original contexts when the calls return.
Mutating whole graph contracts, caller-provided Class value carriers, inheritance
and polymorphic graph roots, buffer/record fields, fresh multi-origin graph results
and scoped payloads in constructor exceptions still require additional proofs.

Scoped Classes with scalar constructor inputs may use checked exceptions with
ordinary `new(context)` or nullable `try_new(context)`. Allocation refusal skips
the constructor. After admission, constructor failure unwinds initialized fields
and releases the unpublished backing before the exception reaches the caller.
The failed object never runs its user destructor. A successful construction
retains the ordinary owner and cleanup obligation. Complete lifetime summaries
must prove that neither the normal result nor the exception retains the receiver;
the native signature and emitted constructor body remain checked independently.
The rollback recipe observes four caught failures, two successful objects, one
refusal and exact address reuse in one caller-backed pool slot at O0/O1/O2.
Checked constructors may also take owned ordinary heap Class graphs whose
descendants are scope-free. Their exact native initialized-field unwind plan is
mandatory. On admission, failure retires initialized fields and remaining input
owners before releasing the unpublished parent backing. Allocation refusal keeps
the caller's original inputs. The owning rollback recipe covers empty, partial
and complete initialized prefixes, a nested heap child, repeated loop generations
and both ordinary and nullable placement.
Acyclic scoped Class child trees also participate in checked construction. Each child keeps its original allocator context. On
failure the constructor retires remaining inputs and the initialized field stack
before releasing its unpublished parent backing. Its exception must retain no
scoped inputs. The child rollback recipe uses two contexts, 20 scoped placements,
nested heap children, four prefix failures and retained caller inputs on refusal.
The deeper rollback recipe adds a third backing context and a closed generic
scoped node. Successful field transfer delegates each input graph separately;
failure must prove nested destruction before releasing its original root. A
nullable handle emptied by a move stays separate from actual backing absence.
Its selected null branch cannot retire or erase a live descendant allocation.
The heap rollback variant places an ordinary heap node between the scoped parent
and generic scoped node. It observes 20 scoped placements, 14 heap roots, 28 heap
children and four prefix failures. Whole-root forwarding, nonretaining borrowing
and exact field transfer preserve the scoped leaf authority through that node.
The same recipe separately executes all three existing owned allocator modes as
intermediaries at O0/O1/O2 with allocation/release conservation and Valgrind.

Scoped Classes may own ordinary numeric or vector buffers. Each field retains
one complete pointer/length owner with its original ordinary cleanup strategy;
the scoped context allocates the Class backing. Constructor arguments transfer
both buffer channels together. Nullable allocation refusal preserves the original
caller buffers, while admission empties their caller slots. Checked initialization
failure retires the remaining inputs and initialized fields before releasing the
unpublished Class backing. A failed object never runs its user destructor.
These rules require actual lexical buffer storage extents, exact native element
plans and independently sealed emitted constructor/destructor bodies. Context
buffers, record elements containing owners and standalone buffer companions to
scoped-owner functions still require their separate complete authority proofs.
Whole-root forwarding and consumption may preserve an eligible acyclic scoped
child graph alongside those buffer fields. The graph proof follows each scoped
child; numeric/vector buffer ownership remains governed by its complete pair and
sealed lifecycle. Physical storage admits only the original receiver, declared
field, exact PTR/I32 layout and ordinary nonvolatile, nonatomic accesses. The mixed
rollback recipe checks child and buffer retirement before parent backing release,
and separately executes default heap and all three owned allocator modes on their
home thread. This does not establish cross-thread transfer of an affine graph.

Scoped Classes may also own inline move records whose declared owners are eligible
scope-free Class graphs. Nested and closed generic records retain their exact
copied leaf and cleanup plans. Constructor arguments move one complete record;
nullable refusal restores its original caller ownership, while admission leaves
its owning fields empty. Checked failure retires each initialized record and
remaining input before releasing the unpublished Class backing. Ordinary borrowed
operands retain their unchanged-storage checks. Record fields containing scoped
descendants still require a deeper emitted field-path proof; owning Resource
field extraction retains its existing Source restrictions.

A consuming owner argument or tagged runtime release must prove that every null
alternative represents allocation absence. Selecting null while the original
allocation remains live does not transfer or retire its backing obligation.
The detached nullable-argument controls exercise both boundaries; they never
execute the adversarial modules.
Mandatory scoped lifecycle and method receivers enforce the same null-transport
rule. A selection proven to preserve the live receiver remains valid; an unknown
selection that may substitute null while its backing stays live is refused.
Looped nullable publications retain the null alternative selected by their
current incoming edge, independently of older retired allocation generations.

A graph-consuming function may receive a checked placement result without a
separate caller null guard. The verifier distinguishes an absent parent with empty
fields from a retired parent that previously owned children. Consuming absence
leaves the caller's refused constructor inputs untouched. Constructor/carrier
aliases must reach their complete fixed point before a graph call is admitted.
Arbitrary null selections that could discard live storage remain rejected.

An ordinary cooperative task can now capture an eligible scoped Class owner,
retain it across suspension, move it into a child task and retire it on cold drop,
joined success, checked body error or joined cancellation. Eligible plain and
closed generic records with scoped Class leaves use the same copied physical
authority. The original backing remains borrowed until the captured task is
observed or dropped. Moving the owner into a cold task does not release that
backing obligation. Each captured owner keeps its own allocator instance, including
when several instances have the same allocator type.

The public recipes `scoped-task-captures.py` and `scoped-record-task-captures.py`
exercise these paths. Scoped captures remain affine and cannot enter worker
ownership graphs. Ordinary task success can return eligible owning records while
preserving every original scoped leaf. Separate native producers may export
scoped factories, constructors and capture-bearing tasks; the consumer retains
the exact imported context, ownership and deferred-outcome effects. The public
`opaque-scoped-tasks.py` profiles cover scalar and owning-record results. Additional
borrowed-context capture shapes require their complete emitted lifetime proofs.

`checked_task_in` now preserves scoped Class captures and whole plain or closed
generic records on frame refusal. Catch the runtime's nominated Error and reuse
the original caller input. Successful admission empties those caller slots and
keeps each original allocation/context obligation in the task until observation
or drop. Region and pool recipes force refusal with a blocking frame, release that
frame, then admit and run the same owner. A fieldless nominated Error uses the same
ownership contract. See `checked-scoped-task-captures.py` for these public examples.

A task error may own an original scoped capture through its nominated exception
root. Host observation or an ordinary `await` transfers that error and its backing
obligation to the catcher. A catcher may read it, rethrow it, or retain it across
another cooperative suspension while the original context remains alive. Discard
and joined cancellation retire the payload instead. Runtime admission errors may
use a derived exception whose constructor initializes every owning base field to
null; their verified cleanup carries no captured payload.

These error paths also work across opaque native units. Export the scoped Class,
exception root, runtime error Class and async function through the ordinary native
unit options. The consumer uses its own runtime nomination and imports the exact
versioned effects and nominal descriptors. Both units must match the current
compiler and `runtime-units/6` ABI. See `opaque-scoped-errors.py` for host, await and
suspended-catch SDK examples.

An eligible direct, nonthrowing Class method can replace its scoped owning fields
with exact incoming owners. Its complete effect must describe every owning field
replacement. The old fields retire before publication; each replacement retains
its own original allocator instance. Physical field cells track successive owner
generations, including branch-selected calls and repeated replacement. A pointer
loaded before replacement cannot become valid again when the cell or allocation
is reused. Unproved joins of such field snapshots remain refused.

The containing Class may use default backing or a selected scoped context.
An initializer can first leave an owning field empty through a direct owned
null-result factory; the emitted constructor must prove its actual null stores.
Later replacement acquires the field's new owner. These mutation effects also
cross opaque native-unit boundaries. See `mutable-scoped-fields.py` and
`mutable-scoped-field-units.py` for exact context/destructor counters, empty
initialization and hidden-producer SDK examples. A checked exception root may start with verified null owning fields, acquire
its exact incoming owner through a proved replacement, and publish either empty
or filled outcomes of the same nominal type. Actual coroutine null/value cells
retain their original initialization and allocation identity. The
`same-nominal-errors.py`, `same-nominal-error-units.py` and `same-nominal-sync.py`
recipes cover direct, host and awaited observation, including a catch held across
another suspension. These paths retain the original scoped context debt.
