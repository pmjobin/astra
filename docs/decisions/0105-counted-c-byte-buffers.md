# 0105 — Synchronous counted C byte buffers

The explicit import annotation `[CCode(buffer_abi="u8-i32")]` admits only
`borrowed u8[]` parameters. The semantic value remains the canonical byte slice;
it is neither a raw pointer conversion nor a new owner. Unannotated C slices,
other element types, owned C array parameters, all slice results and all C
slice exports remain rejected. VAPI buffer declarations are outside this scope.
Buffer-annotated imports may return only supported copied scalars or void;
raw-pointer and nominal-handle results are rejected, including owned handles.
This closes a direct returned-alias channel without relying on C provenance.

Each logical buffer becomes adjacent `unsigned char *data, int32_t byte_length`
channels in source parameter order. The independent `buffer-view-v4` CABI plan
records octet size/alignment one, mutable access and borrowed-noescape behavior.
An empty view may have a null base; a nonempty view has valid contiguous live
storage. Multiple views may alias. No `nonnull`, `readonly` or `noalias`
optimization assumptions follow from this annotation. Text uses its separate
`utf8-i32` contract and retains its existing semantics.

The caller's native slice/owner proof establishes backing validity. Existing
Core/CFG/SSA borrow checks and SSA owner-interval verification continue through
the foreign call; later argument evaluation cannot consume, replace or destroy
an already captured backing owner. The external implementation is trusted to
access only the counted extent, synchronously, without retaining either the
pointer or an alias, invoking a retaining callback or starting asynchronous work.
It must not free or resize the backing storage or consume its Astra owner.
The compiler cannot prove a C implementation obeys that obligation.

LLVM extracts both physical components from the same captured SSA value. The
artifact retains argument and component associations and rejects altered
pointer/count operands before emission. Target qualification requires hosted
GNU Linux x86-64 LP64 with eight-bit bytes, eight-byte addresses and `size_t`,
and exact I32 counts. This does not migrate Astra array lengths or indices.

The POSIX provider adds one bounded read/write operation per call, capped at
64 KiB, with EINTR retries. It returns actual progress, EOF zero or negative
errno; zero progress on a nonempty write means `-EIO`. Offset/count are checked
against the full view before pointer arithmetic. Astra owns allocation, growth,
looping, partial progress, checked errors, flush and closure. Existing scalar
byte entry points remain available with their exact original status encoding.
There is no C-side full-file algorithm or C allocation owning file contents.

Fixed signed/unsigned 64-bit C scalar channels use the separate `wide-int-v5`
superset profile. Existing I32/PTR/F32/F64 and text-only programs retain their
old profile and source boundary policy. Host-qualified size scalars map to the
corresponding physical 64-bit channel only after the target's LP64 witness.

Qualification lives in `tests/cabi-buffer-1`: independent malformed pair plans,
foreign/source correspondence, graph lifetime, physical operand corruption,
C-side arbitrary-byte mutation/alias/canary witnesses, live owner forwarding
and later-consumption rejection. Hosted fault/syscall evidence is collected by
the compiler-systems campaign. Passing these tests does not qualify retained
pointers, arbitrary element pointers, async I/O or a stable external native ABI.
