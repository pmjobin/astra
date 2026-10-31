# Consuming native Class inputs

An actual `owned Item` parameter in a selected declaration maps to
`item_prefix_handle **`. Its optional annotation is
`[ForeignChannel(parameter="input", transfer="full")]`. The referenced Class
declares its own profile, prefix and lifetime. Native ownership, nominal identity,
nonnull facts and independent heap origin remain verified through each stage.

The owner slot itself is mandatory. A nullable channel permits a null handle in
that slot. Owner slots and result storage must be distinct; repeated owner-slot
addresses refuse before output initialization. Two distinct slots may hold the
same shared handle only when the caller owns two corresponding native strong
references. A unique owner cannot satisfy two consuming parameters. Valid output
storage is initialized before subsequent argument validation.

Before transfer the bridge checks all contexts, ownership duties, active unique
borrows, pointer/count relationships and scratch conversions. A failed check or
scratch allocation leaves input slots and their duties intact. Construction first
allocates its new native root. Once transfer begins, slots become null and native
parameter cleanup owns retirement on every native outcome. A later wrapper
allocation failure retires the fully constructed root and its transferred fields.

Private wrapper metadata records which native ownership duties belong to C
callers. It neither acquires a root nor decides when a root dies. A unique root
still has no reference count; its availability is either zero or one. Shared
acquire/release and successful weak upgrades update this bookkeeping alongside the
existing authoritative native strong operations. Reentrant calls may borrow a
transferred object but cannot consume or release a C duty that has already moved
into native code. Native last-owner cleanup invalidates admission before running
destruction and retires any cached wrapper once.

Returning a moved input preserves root and wrapper identity and republishes that
same ownership duty. Returning a shared native clone adds its existing native duty
to C bookkeeping without an extra native acquisition. Unique consumption refuses
when any active receiver or borrowed argument aliases that object. Shared borrows
remain pinned until output conversion and cleanup finish.

The integration recipe exercises independent and generated-header C clients at
O0/O1/O2 for unique/shared objects, allocation failures before and after transfer,
multiple-owner aliases, nullable slots, identity through move/return, reentry,
foreign construction contexts, weak promotion and native field cleanup. The
mutation suite removes heap authority, owner-slot clearing and duty retirement;
ordinary LLVM validation still accepts the physical mutations, while the stronger
artifact proof refuses them. Checked native error mappings and the remaining M16
imports, personalities and qualification gates are subsequent work.
