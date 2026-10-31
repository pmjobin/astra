# Owning record container elements

General `Vector<T>` storage now derives COPY_VALUE or MOVE_VALUE from the exact
record field graph. The same declared source supports copied records, unique
Classes, exact Resources and concrete owning records. Template `owned T`
signatures use ordinary complete record boundaries for record T; callers supply
explicit named whole-record moves for owning values. No global ownership or
nullability default changes.

Insertion captures every original field before one complete ownership commit.
The commit identifies the exact container operation, backing field, value shape
and original source. CFG permits no intervening effect; SSA requires all scalar
disarms and complete buffer-pair disarms immediately before that operation.
A slot take produces a complete MOVE_VALUE result and immediately initializes
one fresh record owner. Missing move metadata, missing disarm or missing take
acquisition rejects. Copyable elements retain their existing snapshot behavior.
Owning elements cannot be copied by indexing or foreach; moving a fresh factory
result directly into a slot remains outside this named-owner profile.

Native slots retain the canonical complete value plan, its copy/move mode,
physical leaves and frozen original field responsibilities. Moving records use
the existing NativeStructValuePlan ownership map; no erased scalar pointer
cleanup is substituted for an aggregate. The same exact leaf cleanup routine
serves enum payloads and container slots. Resources call their original C
destructor; heap Classes call their exact native destructor and then free;
buffers retire their original backing once. Null owner pointers are skipped.

Contiguous native tuples contain every field and complete PTR/I32 buffer pair.
Reserve relocates tuples and retires only the old empty backing. Replacement
installs the incoming tuple before retiring the prior element. Drop clears and
retires elements in reverse current slot order, with reverse record declaration
cleanup. Take removes and shifts the selected complete tuple without destroying
its transferred fields. Allocation failure remains fatal under the existing
hosted slot policy; negative reserve leaves the prior valid container unchanged.

The public witness grows, replaces and extracts nested records containing two
Resource domains, an owning Class and buffers. It checks a field extraction after
take, Class identity, complete empty/null single-leaf records, checked failure
cleanup and exact destructor output. Core, CFG, SSA, native and LLVM controls
must corrupt and restore owning-copy, missing commit/acquisition/disarm, changed
responsibility and LLVM-valid wrong destructor cases. Existing copied, Class,
Resource, generic-method, sequence and enum witnesses remain regression gates.

This component supplies the owning aggregate domain required by A75; the
application itself and all remaining campaign acceptance remain outstanding.
Generic owner transport/nesting, properties/lazy effects, nonnull composition,
metadata and separate-unit work continue under G2 and G4–G9. LAZY-1 Q4 remains
HELD/INCOMPLETE.
