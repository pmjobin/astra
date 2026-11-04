# Bounded private Class storage profile

This opt-in CLASSSTORAGE-15 profile has source-bound O0/O2 engineering
qualification recorded in `docs/selfhost-classstorage-15-progress.md`. The
canonical report records publication status and final Git identities. Whole-source
native admission remains deferred.

The profile targets GNU/Linux x86-64 LP64 with an independently checked LLVM
target/data layout. A Class value is an eight-byte handle aligned to eight
bytes. Its separately named object payload follows source field order and
natural target alignment. Empty payloads occupy one byte. Plain records remain
values; a Class field contains a handle rather than an embedded Class payload.
Generic instance names include the nominal/argument/target/private-profile key.
LLVM type caches belong to one module/context and never outlive that owner.

The source capability check and a separate source consumer establish eligibility:
one concrete native Class declaration, one constructor, initialized scalar/plain
record or supported owned fields, no inheritance, virtual/custom destruction,
foreign exposure, shared/weak ownership or cyclic payload graph. A qualified
`ExactHeapClass` argument must satisfy those checks. The initial closed generic
Class policy supports an exact Class element in owned owner-slot fields, as used
by `Bag<T>`. It does not qualify arbitrary generic Classes such as `Vector<T>`.

Explicit default heap construction allocates `calloc(1, payload_size)`, checks
failure and calls the actual specialized constructor. Failure traps before
publication. The supported constructor is a straight-line initialization of
every declared field exactly once, without throws or partial rollback. Its
first parameter is the existing hidden borrowed receiver, followed by source
arguments in order. An owned Class parameter/return uses a pointer channel;
the source owner/null flags remain distinct. No additional owning receiver is
inserted. Calls to public C imports/exports still reject Class channels.

The source owner state determines responsibility independently of pointer bits.
Moving a handle disarms its old local; a null owned handle still has an owner
state. Borrowed calls preserve ownership. Payload addresses are reconstructed
from the current handle at use, with a null guard and source-derived field GEP.
An implicit private destructor guards null, retires owned fields in reverse
declaration order, then frees the payload once. Custom destructor effects,
exceptions/rollback and general owner-field replacement remain deferred.

Owner slots use an addressable `{ pointer, i32 count, i32 capacity }` descriptor
of 16 bytes aligned to eight, with offsets 0, 8 and 12. Elements are eight-byte
unique Class handles. Each helper validates descriptor range/backing consistency.
Reserve rejects negative extents and traps on default allocator exhaustion before
mutating the original descriptor. It transfers handles before freeing old backing. Append consumes one
non-null owner into a vacant slot. Take shifts remaining entries and clears the
vacated tail. Replace publishes the incoming owner before retiring the previous
one. Teardown clears each remaining slot before reverse-order retirement and
then releases/resets backing. The helper receives the authoritative descriptor
address; a detached aggregate copy is invalid.

Read-only consumers independently check source/type-owner identity, field and
constructor authority, Core/CFG/SSA operand/loan order, ABI channels, target
payload layouts, actual LLVM load/store/GEP/call/cleanup graphs and metadata.
The mutation consumer deliberately reseals physical mutants, so a matching byte
seal cannot certify them. A separate C++ layout-only probe derives descriptions
from C0 syntax and observes size/alignment/offsets without reading candidate
layout plans or generating application bodies.

Caller-backed `.init`, arena/custom allocation, owning-Class record projection,
mixed null/caller-backed and heap result joins, general shared/weak policies,
public C/COM/GObject Class ABI and unsupported buffer indexing remain deferred.
No universal heap policy or public language/ABI promise follows from this profile.
