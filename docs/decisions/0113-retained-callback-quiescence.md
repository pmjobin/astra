# 0113 — Retained C callbacks with observed quiescence

Status: implemented; qualification is recorded separately in Surge-5 receipts.

The finite hosted GNU x86-64 LP64 registrar is single-threaded and invokes only
in explicit dispatch steps. It is an independently compiled C support object,
`lib/astra/interop/retained.c`; the public driver links it explicitly using
`--link-object`. Ordinary Closure users have no new support-object dependency.
There is no arbitrary foreign-library retention or thread-entry policy.

`retained_register(handler, mode)` borrows a live exact ordinary
`Closure<Env,int,int>` owner and attaches one registration. Mode zero is ordinary
admission; other modes fail before publication. The result is zero on success,
minus one on admission/allocation/capacity failure and minus two when the owner
already has an attachment. A failed admission leaves the closure usable and
unregistered. Capacity is 64 live registrations; identities never wrap or reuse.

The compiler generates a real C-convention `i32(opaque-context,i32)` thunk. C
stores that function/context pair after registration returns; a later
`retained_dispatch(handler, value)` invokes it and returns its scalar result.
The thunk privately loads exact native code/environment and calls fastcc. C
never sees the native carrier, Shared/Weak or Class layout. Neither a C function
pointer nor an arbitrary data pointer can become a native closure in source.

The linear closure remains the explicit native registration owner. Its private
carrier holds code, environment, environment destructor, opaque registration
identity and native retirement adapter. Moving the owner transfers the same
attachment once. Every cleanup path first invokes the retirement adapter and
requires an exact successful provider acknowledgement before destroying any
capture. Ordinary unregistered closures carry null attachment authority.
Native retained operations and exact owner loans are independently checked in
Checked/Core/CFG/SSA, native ABI, CABI and structural LLVM witnesses.

The provider state is registered -> stopped -> observed -> retired.
`retained_revoke(handler)` stops future dispatch and is idempotent (one denotes
a valid stop). `retained_observe(handler)` returns zero before stop or while a
callback is active, and one after actual quiescence; repeated observation stays
one. Revoked dispatch returns minus two. Null, forged, stale and retired opaque
tokens return minus three without dereferencing the supplied token. A token is
an opaque monotonically assigned integer within the qualified GNU LP64 C
boundary; it is never a callback-context or heap allocation address.

Nested dispatch is refused. Callback-initiated revoke may mark stopped, but
observation and retirement remain unavailable until the outer callback returns.
Retirement revokes, observes, removes the published registration, clears its
stored callback/context, then frees its private C record. It returns failure
while active. An invalid/missing acknowledgement traps the native cleanup before
environment destruction. A deliberately nonconforming stale-ACK provider is an
expected-trap negative control, never a normal leak-success path. A dishonest
arbitrary C implementation is outside this selected registrar contract.

`retained_dispatch` exposes copied i32 results and imposes no checked unwinding
on C. Direct CheckedClosure registration is refused. A nonthrowing native
adapter can own a checked closure, catch its precise checked failure, retain an
owned diagnostic and return scalar status to C. Native code observes the report
after dispatch returns. A35 proves failure, post-C observation and retry.

A33 proves later multiple dispatch, admission failure, duplicate revoke/observe,
stop-before-cleanup, zero dispatch and early-return retirement. A34 captures an
explicit Weak document observer; last-strong destruction occurs while the
registration remains valid, subsequent delivery sees expiry, and weak/control
storage dies with registration retirement. Unique Class allocation and ownership
remain unchanged: no implicit reference count or registration cost is added to
unique Classes.

Source/IR corruption, independent GCC/Clang C clients/providers, public O0/O1/O2
applications, stale tokens, reentry, late ACKs, ASan/UBSan and unsuppressed
Valgrind controls live in `tests/interop-async-5/retained-*`.
