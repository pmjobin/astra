# ADR 0134: record roots and native Class field cleanup authority

Status: implemented component of unfinished Surge 10.

The root of an owning record is a distinct ownership responsibility. It is not
the cleanup function of its first leaf. Core and CFG give that responsibility
the exact program-owned record identity; each acquired leaf retains its own
cleanup channel and written acquisition rank. SSA expands the root and drops
the descriptor, retaining independently verified leaf owners and events.

This permits records containing only native Class owners, and nested records
mixing Classes and Resources, without a mandatory Resource field. Class fields
require an exact nonpolymorphic heap Class. Initialization accepts a named heap
owner move or a direct owned heap factory result. Caller-backed lexical storage
cannot become a heap field owner merely because its pointer type matches.
Field extraction and stored aliases remain outside this component.

The independent native record plan carries a Class cleanup ordinal separately
from a foreign Resource cleanup symbol. It verifies the copied Class identity,
type name, full field path and acquisition rank against its own declarations.
The Class descriptor and exact destructor/deallocation channels remain native;
no external C/GObject ABI or default nullability changes.

Validation: `language-generalization-10-aggregate` checks Class-only and mixed
Class/Resource records at O0/O1/O2, including checked rollback and unsuppressed
Valgrind. Negative controls retain copying, field aliasing and lexical-storage
transfer refusals. `language-generalization-10-aggregate-contracts` additionally
forges the native cleanup kind and verifies mixed artifacts after upstream
graphs are freed. Buffer leaves, aggregate ABI transport, extraction/replacement,
owning enums, generic containers and async composition remain outstanding.
