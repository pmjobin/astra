# ADR 0065 — Owned runtime arrays and concrete owner replacement

Status: accepted for ASTRA-BUFFER-1.

Baseline: ASTRA-OWN-FIELD-1, `3dcfbd9c483fb0ebdebe9ce96bcdec0aa5f47654`.

Runtime-sized persistent typed storage should read like ordinary imperative
code. Applications should not need opaque buffers, floating metadata slots,
manual byte offsets, allocator arguments, or explicit free calls.

## Decision

```astra
owned f64[] samples = new f64[count];
process(samples);                 // process accepts f64[]
samples = new f64[len(samples) + 1];
consume(move samples);           // consume accepts owned f64[]
```

1. `T[]` remains the canonical borrowed `SliceType<T>`. `owned T[]` adds a
   binding, field, parameter, result, or producer/consumer ownership contract.
   There is no OwnedSliceType or OwnedArrayType.
2. `new T[count]` is a native, target-neutral owning producer with one unique
   static deallocation responsibility. It zero-initializes every element.
3. Counts and `len` use existing `int`/`i32`. Negative counts, checked byte-size
   overflow and nonempty allocation failure trap without unwinding.
4. Empty allocation is exactly null base plus zero length, without calling the
   allocator. There is no nullable-array state, capacity, header, runtime active
   bit, destructor/allocator pointer, refcount, or element construction state.
5. Eligibility independently requires fixed storage, trivial destruction, a
   defined zero, and ordinary copyability. It is not an alias of GEN1_PLAIN_COPY.
   The canonical concrete domain is documented in [the language specification](../language/owned-runtime-arrays.md).
6. Checked indexing and writable element Places reuse Slice semantics. Bounds
   validation precedes element address calculation and memory access.
7. An unambiguous nonowning slice parameter implicitly borrows the owner without
   allocation, element copying, or cleanup responsibility. Existing escape rules
   continue to reject persistent owner-derived views. Observably overlapping
   moves, replacement and destruction reject. Owned fields retain OWN-FIELD's
   conservative containing-class alias policy, including indexed assignment RHS.
8. Named owners are move-only. The existing OWNED/MOVED/RELEASED lattice and one
   owner identity govern both PTR and I32 components. Physical disarm clears the
   complete pair to null/zero; MOVED remains unusable even though its bits are empty.
9. Native owned parameters and results transfer the complete pair. Named input
   requires `move`; direct factory/allocation results may initialize locals,
   fields, replace slots or forward as results. Discard and ownership erasure reject.
10. Native owned fields definitely initialize in explicit constructors. Allocation,
    moved local/parameter and direct exact factory results are supported.
    Field move-out and explicit field release remain unsupported.
11. Fields stay live during user deinit. Deinit, its methods and scalar setters
    may replace them. Normal return cleans current Resource/buffer contents in
    one reverse declaration-order sequence. Traps do not run this epilogue;
    partial construction does not unwind.
12. OBJ-RET constructs fields directly in final ObjectStorage. Object forwarding
    and GEN-OWN relay/dispose retain the same object address, base, length and
    cleanup responsibility. No object relocation or element storage copy occurs.
13. `buffer-v8` is the monotonic native owner-boundary profile. Its PTR/I32
    channels carry ownership transfer and static cleanup metadata. Borrowed
    `slice-v5` and profiles v0–v7 retain their physical contracts and goldens.
    Physical channel equivalence does not erase semantic ownership differences.
14. Core retains allocation and ownership operations. CFG keeps a checked native
    allocation instruction; SSA uses ordinary scalar leaves with bounded pair
    metadata and complete memory actions. No universal aggregate SSA Value is
    introduced. LLVM alone uses `{ptr,i32}` return carriers.
15. Hosted x86-64 Linux GNU LP64 realizes allocation with direct `calloc` and `free` calls.
    This is physical policy, not the language definition. The allocator gate
    rejects unqualified targets before object emission. Buffer-free code adds no
    allocator symbols or runtime requirements. No compiler dependency is added.
16. `new` is contextual at an allocation expression. Existing functions named
    `new` remain valid. No `var`, inference or numeric conversion work is included.

## Concrete owner assignment correction

This milestone intentionally supersedes the Resource live-reassignment
rejection in REARM/OWNBOUND. Mutable concrete Resource and buffer locals and
parameters have independently replaceable payloads and exact static cleanup:

```astra
owned R resource = make_resource();
resource = make_other_resource();
resource = move replacement;
```

Incoming production finishes and its payload is captured before source transfer
commit, old destination cleanup and final storage. OWNED → OWNED performs one old
cleanup. MOVED/RELEASED → OWNED is rearm with no old cleanup. An RHS trap leaves
the old destination untouched. `release resource` remains intentional early
destruction. Self-move rejects. Locals and parameters follow the same rule.

This uses the existing flow lattice, stable cleanup ranks and OWNBOUND
left-to-right capture/commit policy. ClassType/ObjectStorage reassignment and
generic ownership ambiguity remain separate and unsupported. Legacy
producer-specific `owned void*` rearm retains its disarm-first restriction;
the correction applies to concrete Resource and buffer slots.

## Representation choices and consequences

`BufferValueShape` shares canonical element/view and PTR/I32 authority without
being a semantic type. `SsaBufferPair` is bounded metadata, not an SSA Value.
Grouping operations prevent half-disarm, mixed base/length origins and ordinary
owner copies. Independent verifiers check cleanup consumption, source disarm,
slot state, borrow invalidation and mixed-field epilogues after upstream stages die.

Allocation checks stay inside one target-lowerable checked instruction in CFG
and SSA, like existing checked slice operations. LLVM expands negative/zero,
size-overflow and OOM branches. Source length remains I32; size_t is backend I64.

LLVM builtin allocation elimination could remove observable OOM behavior even
with a null check. The hosted realization marks allocator declarations and call
sites `nobuiltin`; calls remain direct and no production test hook is added.
The [host backend contract](../backend/host-buffer-allocation-v0.md) records this
requirement and alignment guarantees.

Future allocators and arenas can realize the same semantic operation through a
new static strategy. Resizing needs explicit growth policy; structs need recursive
layout/zero/copy decisions; RAII elements need per-element construction and
destruction rules. Aggregate Move, generic buffer elements, owned properties,
escaping views, C arrays/floating pointers, shared buffers and `var` remain deferred.

See [IR](../ir/owned-runtime-arrays.md), [buffer-v8](../abi/native-buffer-v8.md),
and qualification and supersessions.
