# ADR 0138: complete buffer fields in record value transport

Status: implemented component of unfinished Surge 10.

Owning record parameters/results now support the same complete runtime-array
fields as local records, including arrays of copyable records. No field becomes
an untyped scalar owner. Semantic/Core retain the exact buffer cleanup and CFG
retains one logical buffer field. SSA expands that field to adjacent PTR/I32
channels with an immutable link to its logical path and original buffer shape.
Its independent shape check reconstructs the complete pair from the declaration.
CFG marks record buffer captures explicitly. An ordinary borrowed slice read
continues to produce a borrowed descriptor; its type alone never grants
ownership transfer. Native element layouts are built only for fields that need
them, and the extra CFG record-order analysis runs only for record owners.

Every boundary acquisition or move binds all scalar owners and buffer slots to
one root. Scalar owner events and complete buffer writes/disarms immediately
follow that marker. A pair retains one original producer, one disposition and
its static element layout. Argument capture may dominate a later checked
argument; the complete source disarm occurs only on the successful call edge.
Failure leaves the caller's original record available for its normal cleanup.

Native field channels retain separate logical paths and physical component
roles. The independent verifier requires the exact adjacent pointer/length pair
and the original declaration's buffer cleanup. Omission, scalar substitution,
split pairs, altered length types and Resource-destructor substitution fail
after earlier stage graphs have been freed. LLVM's physical free-operand audit
continues to check actual generated disposal calls.

A corruption test exposed a sequencing gap between scalar parameter owners and
buffer fields. The order check now consumes snapshots from the existing scalar
and buffer lifetime authorities, without another ownership state machine.
Automatic cleanup preserves reverse formal parameter order and reverse written
field order across both storage kinds. A final buffer deallocation retires its
storage even when that storage was already moved from; explicit release/rearm
and record-field replacement retain their separate disposition sequences.

The executable witness combines nested Resource/Class/buffer records, empty
arrays, buffer-only records, record-array elements, methods, direct factory
forwarding, checked argument/callee failure and field take/refill. It runs at
public O0/O1/O2 under unsuppressed Valgrind. These boundaries remain concrete,
synchronous and nongeneric. Owning enum composition, generalized containers,
async records and versioned separate-unit exports remain required campaign
work. External C/GObject ABI and default nullability are unchanged.
