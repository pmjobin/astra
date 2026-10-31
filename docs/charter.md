# Astra engineering charter

Established by **ASTRA-CHARTER-1** (the conceptual ASTRA-0 phase).

> Native first. Compatibility at the boundary. Pay only for what you use.
> Preserve semantics long enough to optimize them.

1. Astra owns its semantics and its architectural lineage.
2. Generated C is never semantic authority, including the C emitted by the Stage-0 host compiler.
3. GObject is not Astra's native object model.
4. C interoperability is permanent and first-class.
5. Foreign compatibility belongs at explicit boundaries.
6. Semantic operations survive long enough for Astra to optimize them before physical lowering.
7. Ownership comes from language semantics and is never inferred from raw pointer shape.
8. Computed values and authoritative storage/place are distinct concepts.
9. Freestanding operation is a first-class requirement.
10. The language core assumes no mandatory OS, GLib, GObject, GC, heap, threads, reflection, or heavyweight unwinder.
11. Runtime facilities are pay-for-use; no universal runtime is prescribed.
12. LLVM is a physical machine backend, never Astra's semantic IR.
13. SIMD and short-vector semantics are first-class future language requirements.
14. Embedded and Dreamcast constraints influence architecture from the beginning.
15. AEP-class DSP and numerical workloads are official optimization workloads.
16. Exact ABI and ownership semantics fail closed when unsupported; dishonest approximations are forbidden.
17. Vala and frozen LLVM-v2 may teach Astra as semantic/ABI oracles and sources of lessons, but have no architectural authority.
18. Self-hosting is a future maturity milestone, not an early design constraint.

ASTRA-CHARTER-1 establishes documentation, a reproducible host build, a trivial
`astrac` driver, and an internal LLVM C API construction/verification proof. It
implements no grammar, parser, semantic model, Core IR, ownership or place
lowering, ABI, FFI, object/property system, generics, delegates, async, SIMD
language types, runtime, GObject/GIR integration, compatibility frontend, or
self-hosting. Future direction is not a claim of implemented capability.

All implementation is independently authored. Public API declarations and
documentation may be consulted; Vala compiler and frozen LLVM-v2 implementation
source must not be copied, vendored, imported through Git history, or made a
build dependency. Any proposed nontrivial external source requires an explicit
provenance/license review first. A compatible license does not waive this rule.

The [architecture invariants](architecture/invariants.md) give reviewable
identifiers to these commitments. The implementation language and its host
libraries do not define Astra language semantics or generated-program costs.
