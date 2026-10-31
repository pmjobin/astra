# ADR 0078: ordinary copyable values in semantic generics

Status: accepted for ASTRA-GEN-COPY-1.

The default generic transport contract copies a value. Requiring another source
capability just to transport an ordinary record would split that contract between
primitive and record representations. Extend `GEN1_PLAIN_COPY` to eligible native
records instead. Its historical name remains internal; it no longer denotes a
permanently closed 34-type set. There is no public `Copy` or `Move` capability.

Admission uses the shared recursive Copyability rule and exact field identities.
A concrete record must be legally formed, nonempty, complete and acyclic, with
ordinary value storage. A scoped definition proof can use its exact plain-copy
type parameters and known generic-struct fields. The premise does not make a type
parameter concrete storage or zeroable. All concrete results are verified again
before CFG. Function and struct type arguments use this same default.

Known `Box<T>.value` operations and exact whole `Box<T>` direct-T candidates are
legal. Inferring a callee T as an entire application is not matching a `Box<T>`
formal or solving for the outer parameter. Nominal definitions, ordered arguments,
phantom arguments and exact outer symbols remain significant. The existing
application/materialized mapping canonicalizes final instance keys.

Definitions are checked once, including unused bodies. Parameterized Core may
retain bounded plain-T transport at existing copy consumers. Materialization
selects the existing scalar/vector operations or native struct producers, copies,
initializers and COPY_VALUE boundaries. A record argument is captured at its
argument position; record parameters get independent read-only storage. Locals
remain mutable. Concrete Core erases symbolic operations before CFG/SSA/LLVM.
No universal aggregate value, aggregate SSA phi, runtime dictionary, input pointer
convention, new ABI profile or source-body recheck is introduced.

Ordinary named struct-valued initializer entries may also use bounded producers,
including snapshots and native/generic call results. This rule applies equally to
ordinary and generic enclosing records. Complete nested braces remain supported.
Each entry captures its producer fully before writing its leaves, then finishes
before the next entry's effects. Fixed-array entries retain their existing
complete-entry publication. The enclosing declaration remains invisible in its
initializer; names, exact types and completeness still come from that storage.

Copying adds no ownership responsibility and implies no operators, zero,
construction, addressing or unknown member access. Ownable and named moves retain
their exclusive Resource/Class domain. Collections, text/views and tracked pointers
remain excluded as ordinary T; copying an eligible element does not copy its owner.
Raw `void*` retains its unmanaged scalar semantics.

Completion remains deterministic and compilation-local. Plain-copy proofs bound expanding type-application paths at 256; materialization allows at most 1,024 combined function
and struct instances and 256 active struct dependencies. Layout cycles and growing
request graphs fail before executable output. These are resource bounds, not a
compile-time termination solver. Concrete field graphs retain ordinary Copyability without a new depth or leaf
count cutoff. Constructed type-argument graphs also reject cycles and depth above
256 before recursive inspection.

Deferred: public Copy/Move capabilities, generic borrowing, text/view admission as
T, symbolic arrays/buffers/pointers, constructed-formal signature expansion,
generic methods/classes, aggregate constants/CTFE, record operators, arbitrary
rvalue member projection, owning aggregates, resizing/foreach, C aggregates,
modules, new targets and external CAD migration.

See [language rules](../language/generic-copyable-values.md),
[IR rules](../ir/generic-copyable-values.md) and
qualification.
