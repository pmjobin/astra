# Declaration-derived native object channels

This intermediate slice adds borrowed native Class inputs and owned native Class
results to the C `declarations-v1` profile. Referenced Classes declare their own
explicit profile, prefix and unique/shared lifetime. A result uses that Class's
opaque handle and release domain, even when its declaration follows the exporting
service. Native Class fields remain private.

Use explicit `borrowed` parameters for call-only views, including shared Classes.
`[ForeignChannel(parameter="input", nullable="true")]` permits an empty native
reference when the source parameter is nullable. An actual source `nonnull`
requirement cannot be weakened. The semantic descriptor, Core/CFG/SSA signatures
and independent native parameter facts retain that qualification. A same-width
pointer to another declared Class does not satisfy the channel.

Each active borrowed unique object increments a temporary activity depth and
rejects C destruction until the call unwinds. Shared borrows hold a native strong
reference. The receiver and all borrowed inputs remain held through native
execution, output conversion and cleanup. Reentrant C calls can update native
state; subsequent native reads observe the committed change. A shared caller may
retire its last reference inside a callback while the active borrow keeps the
native object alive.

Selected owned Class results are heap boundaries for the existing native origin
solver. The bridge publishes the native ownership duty through an opaque handle;
it reuses an existing wrapper when available. A shared clone returning an existing
native root preserves wrapper identity and does not invent an extra acquisition.
A newly exposed root receives a wrapper. Wrapper allocation failure retires the
provisional native result, clears the output, and leaves the service usable.
Native algorithm allocation retains its existing behavior; the fault test here
targets the subsequent wrapper allocation. Nullable owned results publish null on
ordinary success when explicitly selected.

New-profile native roots retain their construction context before an external
wrapper exists. A wrapper copies that context rather than assigning the thread
which first exposes it. Data calls, unique destruction and supplementary shared
strong/weak operations enforce their context before changing native state. Weak
wrappers retain independent context metadata so they remain checkable after native
root retirement. Pointer/count lifetime APIs report refusal using their empty/zero
result, and a refused operation leaves the caller's ownership duty intact. Legacy
bounded profiles retain their existing protocol.

The independent C matrix covers unique/shared results, nullable values, nonnull
source qualifiers, wrapper reuse, allocation rollback, native state changes during
reentry, release during a borrow, wrong-thread argument/data/strong/weak calls and
an owned child surviving its factory. Eight whole-executable Valgrind runs cover
the matrix. Detached mutations substitute pointer-compatible nominal roots, remove
heap authority, alter nonnull facts and replace the recorded construction context;
they refuse before execution.

Consuming owner-slot inputs, checked native error mappings and foreign
COM/GObject object channels remain required subsequent M16 work. This slice is
not full G1/G2/G7 or final acceptance.
