# ADR 0080: Generic owned runtime arrays

Status: accepted for ASTRA-GEN-BUFFER-1.

Direct `T[]` may borrow storage, while `owned T[]` parameters, results and explicit
locals carry the existing BUFFER responsibility. Both use the same canonical
SliceType. `T` remains a plain-copy element, never an Ownable array capability.

Every direct T[] parameter and every owned T[] result establishes four separately
recorded facts on that exact lexical T: copying, fixed storage, structural zero and
trivial destruction. The concrete admission authority remains BufferElementTypes
with its complete field graph. Borrowing does not construct a value; the current
closed element domain independently supplies the zero/destruction facts. A plain
T signature or a local allocation cannot invent these premises.

`new T[count]`, explicit local ownership, moves, release/rearm and result forwarding
reuse concrete buffer grammar. Borrowed-only signatures can allocate scratch space.
Named transfers spell `move`. Inline allocation/factory arguments to consuming calls
remain excluded. Plain slice returns, symbolic owned fields and direct owned-T locals
remain excluded. Result context does not infer T.

Parameterized Core reuses its bounded owner and producer nodes with a symbolic
buffer cleanup contract. BufferValueShape records logical element/base/count types,
not physical layout. A symbolic contract carries no allocator symbol, byte stride,
callback or runtime active flag. Materialization substitutes the element and creates
the existing concrete buffer shape and cleanup before concrete verification.
It also maps local identities, record parameter acquisitions, cleanup ranks and
producer contracts. Source bodies are never rechecked or reconstructed.

The shared structured ownership proof gains reads, releases and acquisitions beside
moves. It checks branch/loop possibility sets in unused definitions; concrete CFG
remains the execution authority for scope cleanup. Call argument borrows remain live
through argument evaluation; a completed value snapshot or clone call ends its borrow.
Replacement produces the incoming owner before disposing the old owner.

An independent owned-array type would duplicate canonical slice identity and invite
different inference keys for equivalent calls. Making SliceType plain-copy or Ownable
would authorize unrelated transport and lifetime operations. Both alternatives are
rejected. No universal owner value, runtime dictionary, hidden result pointer, sret,
byval, allocator redesign, new ABI profile or production dependency is introduced.
Numeric owners reuse buffer-v8; record owners reuse struct-elements-v11. The existing
hosted GNU LP64 allocator and x86-64 Linux record qualification remain the boundary.

The ordinary opt-in `buffers.astra` library supplies clone_array and filled_array,
with an explicit slices.astra source dependency. Clone performs ascending recursive
value copies into independent storage. Unmanaged pointer values remain shallow.

Resize/reserve/realloc, dynamic containers, generic classes/methods, unresolved owned
fields, RAII elements, string ownership, direct Ownable borrowing, public Copy/Move/
Element/Zeroable capabilities, default(T), constructed/nested formals, general borrowed
returns, C arrays/aggregates, custom allocators, modules, new targets and external CAD
migration remain deferred. See the [language](../language/generic-owned-arrays.md),
[IR](../ir/generic-owned-arrays.md) and [library](../library/array-production.md) rules.
