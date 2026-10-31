# ADR 0163: hosted concurrency lifetime and scopes

Accepted by the user on 2026-10-19 UTC during the native Surge 13 session.

Strong acquisition is explicit `clone()`. Assignment transports an owning
reference by move; it never silently retains. Existing explicit `Shared<T>`
and `Weak<T>` source forms and their three-word control-block ABI remain
compatible. Their lifetime operations become atomic.

`[Shared]` makes the normal Class owner intrinsically shared. Its native root
contains atomic strong/weak state. Last strong release destroys the payload
exactly once; allocation metadata remains until the final weak release.
`shared T` independently boxes an otherwise nonshared value. Applying it to
an intrinsically shared Class is an error. Shared inheritance retains one
root identity and destructor authority. Unsupported allocator or transfer
combinations are rejected.

Monitors use a nonrecursive lock. Direct internal `this` calls reuse the
existing guard. Cross-object nesting requires an explicit ordered-lock
operation. Protected borrows cannot escape, and suspension under lock is
forbidden. The process singleton is lazy, retries checked initialization
failure, refuses recursive initialization, owns one strong anchor, and has
explicit quiescent shutdown.

The initial process singleton profile uses `[Shared, Monitor, Singleton]` on
one exact hosted Class with copied numeric fields and constructor inputs.
`new Configuration(args)` performs lazy acquisition: only the elected caller
runs `init`; ready acquisitions return another strong owner of the published
root. Arguments are evaluated at each call, and the first successful
initializer supplies the state. An escaping `init ... throws Error` is
qualified only in this profile. Failure frees the unpublished scalar root
without calling the successful payload destructor and permits another attempt.
Recursive initialization and acquisition after final shutdown abort before
waiting. There is no implicit process-exit destruction.

`var retired = singleton_shutdown(root)` returns null while extra strong
owners remain. At quiescence it closes future process acquisition, detaches
the registry anchor and returns one ordinary owning reference. Both `root`
and `retired` must then be released; remaining weak references expire after
the final strong release. Weak upgrades obey the normal atomic contract.
Singleton roots currently stay in one checked compilation unit. Allocation
failure remains the ordinary hosted allocation trap; it is distinct from a
checked initializer failure.

Thread-bound values record their constructing thread and cannot cross
worker, task, or retained-callback boundaries. Transfer and shared-access
capabilities are derived conservatively from fields and ownership. There is
no blanket unsafe capability opt-in. Reference-count safety alone does not
permit unsynchronized payload mutation.

The separate Actor decision is recorded in ADR 0164. These decisions do not authorize COM/GObject export,
foreign pointer agility, self-hosting, or SH-4 work.
