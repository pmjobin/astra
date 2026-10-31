# ADR 0139: exact Resource and Class owners in enum payloads

Status: implemented component of unfinished Surge 10.

An enum field marked `owned` now distinguishes an owned array, an exact foreign
Resource and a concrete heap Class. One owned field derives move-only behavior
for the entire enum, including empty cases and containing enums. Plain copied
payloads keep their existing value semantics. Shared/Weak handles, interfaces,
polymorphic Classes and borrowed scalar payloads retain their separate domains.

The scalar profile accepts an explicit move of a named owner. Payload evaluation
reserves that original owner and captures its pointer, type and cleanup. Later
payload arguments may read it. The successful constructor edge commits all
captured owners; a checked later-argument failure aborts those reservations and
leaves the original owners available. Construction publishes the tag only after
all active fields have been stored. Assignment first captures the replacement,
then destroys the previous active case before publishing its new owner.

A consuming match transfers a selected scalar field into a fresh owner with
the original destructor contract. Ignored active fields are destroyed in reverse
field order. Nested enums preserve this responsibility recursively. A Class
binding retains its heap origin when returned from an owning function. Scalar
inspection currently permits `_`; a named borrowed scalar binding needs a
separate loan contract and is diagnosed at source and Core boundaries.

Core carries a distinct named scalar capture. CFG retains capture, abort and
consuming extraction nodes. SSA binds each capture to its original owner READ,
one constructor field, one commit MOVE and fresh extraction ACQUIRE. Independent
reservation checks follow checked edges and reject invalidation before commit,
orphan captures, duplicate disposition and pending exits. Existing owner flow
continues to establish liveness and pointer provenance.

Native plans retain only a copied nominal type name, foreign destructor symbol
or exact Class ordinal, and the PTR channel. Their original scalar field
contracts and complete variant/field counts survive upstream graph disposal.
Structural verification cannot substitute a destructor, erase ownership or
replace a Class with an arbitrary pointer. Source correspondence still checks
the exact declarations. The native record ownership path constructor now takes
copied integer ordinals; the completed native model has no semantic type API.

LLVM uses the original native cleanup authority for selected fields, guards
nullable Resource/Class pointers, and separately destroys and frees heap
Classes. Physical sum projections, selected reads, source disarms and cleanup
operations remain covered by the existing operand and operation-order audits.
No external C/GObject ABI or default nullability changes.

The witness combines two foreign Resource kinds, a Class with owned fields,
nested enums, replacement, consuming and ignored bindings, checked rollback,
return forwarding and Class extraction. A second witness transfers an owned
`Utf8Message` and its original bytes together, verifies Unicode snapshot
identity after extraction, rejects malformed UTF-8 recoverably and replaces an
ignored text case. Owning record payloads, named scalar
inspection loans, generalized enum collections and the other campaign gates
remain required work.
