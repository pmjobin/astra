# Native struct-elements-v11

This profile follows text-slice-v10 without renumbering older profiles. It adds
independently owned recursive record-element plans for native borrowed slices and
owned buffers. It does not define a C record ABI.

The outer transport remains PTR plus I32 record count. A borrowed record slice
has a mutable, borrowed-noescape contract; an owned buffer parameter/result has
one grouped owner with transfer responsibility. A numeric slice, deep read-only
text slice and record slice with the same outer channels are not interchangeable.

Each `NativeRecordElement` names one exact nominal declaration ordinal and name,
with declared fields in order. Each field contains exactly one admitted primitive
leaf type or another exact program-owned record shape. Complete storage,
structural zero and trivial destruction obligations are explicit. The independent
verifier rejects missing, duplicated, stale, cyclic or unsupported shapes and
mispaired owner channels. SSA correspondence validation additionally checks exact
logical parameters/results, record identity, field identity/order and leaf types.

Struct-by-value parameters/results continue to use aggregate-v7 recursive scalar
and vector channels. Record storage never concatenates these register channels.
A local-only record collection does not change an unrelated scalar signature's
profile. Existing numeric buffer, numeric slice and text contracts remain intact.

Physical layout is separately target-qualified. The initial witness is x86-64
Linux with eight-byte pointers. It records natural field offsets, complete
allocation sizes, ABI alignment and record stride. Mask vectors use packed LLVM
i1 lane storage: bool<2>, bool<4> and bool<8> allocate one byte; bool<16> allocates
two. A C _Bool array is not an oracle for this representation. Padding has no
source equality or copy contract.

Allocation additionally retains BUFFER's hosted GNU LP64 allocator gate and
alignment guarantee (admitted vector fields require at most 16-byte alignment).
Counts are exact I32; multiplication and offsets are checked in i64 against
overflow and the qualified signed address range before allocation/inbounds GEP.
All-zero bytes realize the admitted zero leaves, including semantic null pointers,
on this selected target. No cross-target promise follows from that observation.

The retained mixed-layout witness has `Leaf { bool<4> mask; void* address;
f32 small; f64 large; i16<8> vector; }`: offsets 0/8/16/24/32, size/stride 48,
alignment 16. `Record { u8 start; Leaf left; Leaf right; u8 end; }` has offsets
0/16/64/112, size/stride 128, alignment 16. Nested leaf offsets add to their
containing field's offset. The numerical client's Kernel has left/right/weight/
shape offsets 0/4/8/16, size/stride 32 and alignment 8; Shape's gain/bias offsets
are 0/8. These are target witnesses, never semantic type identities. The complete
34-leaf layout table and the matching GCC/Clang subset are retained with the
execution evidence linked from the qualification report.

Fixed/borrowed helpers acquire no allocator requirement. Owned arrays use the
existing one-block allocation/free path. There are no per-type callbacks, headers,
initialization bitmaps, constructors or element destructors. CABI/VAPI continue to
exclude S, S[], S*, C aggregate transport and allocator metadata.

GEN-BUFFER-1 specializes direct `owned T[]` contracts to these existing record
owner plans. Generic copying of a record value retains aggregate-v7 transport;
returning its array owner retains the complete PTR/I32 group and static buffer
cleanup. See [generic owned-array IR](../ir/generic-owned-arrays.md). No new ABI
profile or physical-layout authority is introduced.
