# ADR 0094: Call-scoped Resource and Class generic borrowing

Status: user-approved `Q11A-RESOURCE-CLASS-BORROW`, 2026-10-14.

The user requested Class support and a lifetime proof before implementation,
then explicitly approved the reviewed Resource + Class scope. This supersedes
ADR 0060's deferred `borrowed T` decision only for the finite contract below.
Historical decisions and their qualification claims retain their original scope.

An explicit `borrowed T` under the sole Ownable capability denotes a dependent
call-bounded view of its existing owner. It never denotes copied T or ownership
acquisition. Eligible helpers and callers are synchronous; helpers are top-level,
native and nonthrowing, with one such loan, copied scalar neighbors and a copied
scalar/void result. Existing generic ownership transfer and plain-copy domains
remain unchanged.

Admit exact nominal Resource and native Class identities, including Class owners
in lexical, caller-backed and heap storage. Reuse borrowed-noescape parameter
contracts, owner-borrow/parameter-reference nodes, structured ownership flow,
monomorphization and concrete CFG/SSA/native authorities. Rebuild independent
Core checks before specialization. Owner reads at capture and invocation protect
symbolic argument ordering; concrete liveness remains at the existing CFG fixed
point. Source and Core independently reject coroutine loan contexts.

Borrow-only Class specialization needs no allocation-domain key: it acquires no
cleanup and selects no deallocation. The concrete caller retains exact storage
and cleanup provenance. Generic consuming Class transport still selects lexical
cleanup and rejects heap owners at source. Full heap `owned T` transport needs
its own provenance/instance-key/result-storage design; this milestone does not
remove that boundary.

Preserve exact nominal identity across substitution. Generic Class calls do not
upcast a Derived actual to Base. Noescape prevents storing, returning, copying,
moving/releasing or capturing the loan. Ownable supplies no new members or
comparison operations. Generic owned locals, multiple loans, aggregate T,
callbacks, async/await, generic members/classes, C/GObject adapters and persistent
lifetime policies remain deferred.

No new node, runtime reflection, destructor callback, hidden retain/release,
refcount, boxing, owner metadata, LLVM pointer attribute or ABI profile is added.
Native pointer erasure follows verified semantic ownership and type identities;
the native compatibility bridge separately checks SSA correspondence.

The [lifetime argument and source gaps](../gen-borrow-1-class-design.md) and
[portable source/native/optimized controls](../../tests/gen-borrow-1/README.md)
define the finite proof obligations. Q11 remains OPEN for generic owning locals,
heap generic consuming provenance, broader aliases and persistent loans.
