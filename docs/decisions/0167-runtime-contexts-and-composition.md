# ADR 0167: allocator contexts and coexisting hosted execution

Status: accepted by the user in the native M17 session, 2026-10-24 UTC
(“Approve ADR 0167 and implement”). The separate peer topology was also
approved; see `docs/runtime-composition-17-peer-plan.md`.

## Starting point and scope

Baseline: `f3b221aff54a963df51c8928892f306d6b082369`, branch `astra-lazy-1`.
The allocation substrate has a real domain pointer, checked origin and monotonic
generations, but LLVM supplies static domain globals. The worker implementation
includes a renamed copy of `virtual.c`, changes the private frame layout and
exports the same public symbols. The Linux provider uses the cooperative core.
The socket substrate constructs IPv4 loopback addresses unconditionally.

Implement dynamic allocation authority, a single task protocol, explicit worker
handoff, real file completions and numeric endpoints. This decision covers G0–G10
of ASTRA-RUNTIME-COMPOSITION-17. It does not reduce any required gate. Application
A, opaque native SDK, a separately authored frozen application B and independent
verification remain required before a successful report.

## 1. Allocation authority and source operations

Introduce ordinary typed allocator context values, with distinct scoped and owned
backing contracts and explicit thread capabilities. Use `new (context) T(args)`
and `try_new (context) T(args)` for explicit instance selection; the latter returns
a nullable owner on allocation refusal. Existing `new T(args)`, `try_new T(args)`
and declaration policies retain their accepted behavior. An instance selection
cannot silently override an incompatible declaration policy.

Contexts support system heap, runtime-sized region/pool backing, a borrowed
caller buffer and an external context-bearing provider. Sizes, slot capacities
and configuration are values. Two same-type instances have separate identity,
backing, synchronization and counters. No process-global or thread-local current
allocator selects an object's origin.

Every dynamically placed allocation retains exact context identity, extent,
alignment, generation and destructor/release authority. Preserve ordinary unique
Class ownership. An explicit context backing lease, rather than a shared reference
to every Class, keeps owned backing and provider state alive. A compiler-proven
static origin may omit dynamic metadata. Static/no-OS allocation paths retain
their current representation and dependency closure.

An owned context handle may move or be explicitly cloned as backing authority;
closing its admission handle prevents new allocation, while accepted leases keep
backing alive until retirement. Explicit finish/reset reports live allocations
instead of invalidating them. Final backing release follows final allocation,
frame, callback and weak/control release. Parent context leases support nested
contexts; an owner cannot become its own context anchor. Reject ownership cycles.

A scoped context borrows caller backing and introduces a checked lifetime region.
Derived owners, containers, closures and tasks may move within that region, but
cannot escape through returns, fields, native exports, retained callbacks or
unjoined work. Context reset/destruction refuses live allocations. Uniqueness and
region proofs prevent stale aliases; generation counters never wrap or reset.

Container backing and its growth inherit the container's selected context.
Elements retain their own independent origins. Closure environment and carrier
placement use explicit context authority. Explicit context task construction
allocates the actual suspended frame through that authority, including stored
owners and cancellation cleanup. These are checked compiler operations, not
decorative allocations or ambient changes to unrelated allocations. The public
helpers expose context-bound closure/task construction with inferred result and
capture types; implementation spelling may follow existing parser conventions
without changing these contracts.

Allocation refusal leaves owned constructor inputs with the caller. After
admission, checked initialization failure rolls back exactly the initialized
prefix, destroys consumed inputs once and releases unpublished storage. Preserve
ordinary fatal `new` OOM. Checked allocation distinguishes exhaustion, overflow,
unsupported alignment, bad origin/generation and closed admission. Failed growth
preserves old storage, length, capacity and all owners. Replacement acquires new
storage before retiring old storage and never relocates a referenced Class.

## 2. Foreign allocator trust and threading

The versioned C provider descriptor carries an opaque typed state pointer,
allocation/release callbacks, backing-disposal callback, declared threading mode
and ABI size/version. Allocation receives checked extent/alignment and returns a
pointer with a checked status. Release receives the original pointer, size,
alignment and token. Provider code/state remain pinned by the backing lease.
Callbacks cannot throw, unwind or reenter mutation of the same context.

Foreign callbacks are a deliberate trust boundary: C must return valid, aligned,
nonoverlapping storage of the promised lifetime and honor its declared threading
contract. Runtime checks validate representable extents, alignment, tracked live
overlap, origin, generation and exact release pairing; they cannot prove arbitrary
foreign memory validity. Safe tests reject malformed descriptors/tokens before
unsafe access and never execute fabricated pointers or double frees.

Capabilities distinguish affine, exclusively transferable and concurrent contexts.
Affine storage remains on its home execution context. Exclusive transfer requires
the entire backing/owner graph to be transferable and no competing live lease.
Concurrent contexts synchronize their metadata and require a compatible provider.
Worker admission checks actual transitive captures, nested owners and contexts.
Atomic shared-object counts do not grant allocator or mutable payload safety.

For an affine context, foreign-thread retirement is published to a home executor
which explicitly retains the obligation and acknowledges actual destruction and
release. Shutdown cannot finish while that queue remains unobserved. Do not call
user destructors or allocator callbacks under the scheduler metadata lock. An
affine value without a valid retirement route is refused at the source boundary.
Default-backed shared/weak control storage remains explicitly default-backed;
any context-backed control allocation holds its lease through the final weak
release, independently of payload destruction and strong expiration.

## 3. One task ABI and explicit execution handoff

Replace the renamed duplicate core with one versioned task/frame implementation.
Executor instances identify cooperative, worker or Linux service behavior through
checked instance state and backend hooks. Constructors have distinct symbols;
common ownership, registration, cancellation and observation symbols have exactly
one definition and one layout. Preserve old source facades through compatible
wrappers and explicit build recipes. No weak symbol or multiple-definition remedy.

The hosted composition API provides an explicit worker submission/await operation
for a cold typed task, retaining its result/error/cancel contract. Source code
transfers typed owners and tasks, never frame pointers. A bridge registration
records source executor, target executor, both generations and parent observer.
The submitting parent retains responsibility until the target outcome and transfer
are observed. Reverse result/error transfer resumes the parent on its original
executor. An admitted/pending frame cannot be rebound to another provider.

The ring's creating/owning thread alone submits and drains the existing selected
SINGLE_ISSUER profile. Worker tasks execute real Astra code independently. A worker
request crosses a bounded publication queue to the ring owner when required; no
worker directly submits to that ring or hides blocking file I/O. Multiple worker
and Linux executor instances have independent state. Explicit cooperative/virtual
execution remains available in the same runtime protocol.

Queue publication/observation uses documented mutex/condition or release/acquire
edges. Notifications wake the owner/workers; timed waits remain a measured safety
backstop. Claim a resume exactly once, retain executing frames, reject stale events
and avoid holding scheduler locks across user code or blocking provider waits.
Record the starting coarse-lock costs before changing its synchronization model.

Cancellation is a request. Queued worker work may retire without running; running
work cooperates and retains its captures until it returns. The original checked
result/error is published once according to the cancellation linearization rule.
For io_uring, target and cancel-command identities/completions are separate ledger
entries; observe all accepted kernel/queue/parent access before reclaiming storage.
Bridge cancellation propagates once and its acknowledgment includes target
retirement. Reused FDs/task slots never identify earlier work.

Joined shutdown stops admission, requests child cancellation, observes target and
cancel completions, drains cross-executor and affine-retirement queues, joins
workers, releases frames/context leases and closes provider resources. A worker
cannot join itself: a non-owner shutdown request routes to the proper owner and
is completed there. Cyclic executor shutdown dependencies are rejected.

## 4. Numeric endpoints and network behavior

Provide an ordinary copied `NetworkEndpoint` value: family (4 or 6), 16 address
bytes in network order, host-order port and IPv6 scope ID. IPv4 uses four bytes
with canonical zero padding. Constructors/parsers validate family, byte length,
octets, port and supported scope; equality and formatting use the same canonical
representation. IPv6 formatting brackets addresses when combined with ports.
Explicit wildcard construction is separate from loopback convenience construction.

Typed socket operations take the supplied endpoint for bind/connect/send-to and
produce actual local/peer endpoints for accept/get-address/receive-from. Support
IPv4 and IPv6 sockets explicitly; preserve the old loopback helpers as wrappers.
No address, family or test port becomes a compiler/runtime whitelist.

Keep nonblocking partial progress, EINTR/EAGAIN, SO_ERROR connection completion,
monotonic deadlines, cancellation, TCP EOF/half-close and SIGPIPE avoidance.
Datagram results distinguish an empty message, truncation, produced length and
source endpoint. Validate offsets/capacity before syscalls. Synchronous borrowed
views never escape the call; accepted asynchronous operations retain their owning
buffer lease until observation. Each descriptor has one close authority.

Qualify both protocols and both address families on loopback and the approved
private veth topology, using independent Python/C sockets and deterministic data.
Report this as isolated namespace evidence. The exact already approved topology,
duration/transfer bounds and cleanup are in the peer plan. A refused namespace
operation remains an environment blocker for that gate and grants no alternate
VM, host-root or LAN/Internet authority.

## 5. Versioning, dependencies and migration

Define `runtime-contexts/1`, a common task ABI successor and native-unit schema `/5`
for transported context lifetime/capability and executor/bridge effects. Carry
immutable admitted snapshots through semantic, Core, CFG, SSA, native and LLVM
verification. Each stage independently rejects forged origin, backing, release,
provider, effect and ABI metadata. Native interfaces expose typed values and exact
lifetime/effect contracts while producer implementation remains opaque.

Native lifetime archives identify logical declaration coordinates with
`runtime-lifetime-logical/1`; compiler-internal lifetime plans retain physical ABI
coordinates. Each lowered stage derives the conversion from its own exact record
and buffer groups. An older complete composite contract without that marker
requires rebuild. Unmarked direct-parameter contracts and incomplete contracts
retain their existing interpretation. This archive version leaves the `/5` unit
schema and common task layout unchanged.

Existing `/4` units may import only through a checked legacy compatibility path
when their full original ABI/effects/layout remain valid. A stale unit with changed
task/context layout is refused with a version/ABI diagnostic and requires rebuild;
never reinterpret old opaque frames. Keep module source/body/bitcode fallback
forbidden. Document exported symbol and installed-library changes explicitly.

Hosted dynamic contexts and composition are opt-in. Unused default/native/no-OS
profiles acquire no pthread, liburing, GLib or GObject dependency. Static policies,
legacy ownership and the selected Linux ring flags retain their contracts. Windows
and foreign source/runtime closure is inspected; affected Windows execution needs
fresh narrow permission. This decision does not authorize VM access, installation,
host networking/security changes, historical negative-fixture rewrites or RC2.

## 6. Evidence and implementation freedom

Implement the reusable mechanisms across all required ownership/storage families.
Qualify actual emitted Astra O0/O1/O2, all eight mixed SDK O0/O2 builds plus O1,
new custom allocator providers, same-type context variations, deterministic and
real race/failure matrices, measured progress/overlap/costs, sanitizers and the
complete applicable final registry. Preserve failed invocations and failed freezes.
Freeze compiler/runtime/A before choosing and writing the structurally different B.

Approval accepts these observable lifetime, scheduling, endpoint and ABI contracts.
Compatible helper naming, internal data structures, lock granularity and test
implementation are autonomous engineering choices. Breaking those contracts or
reducing a mandatory gate requires a new decision. Historical negative fixtures
remain unchanged until their exact replacements receive separate consent.
