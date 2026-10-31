# Copied POD C Class imports

Bodyless `declarations-v1` imports accept public, flat scalar records as copied
parameters and results. The fields determine the shared nominal schema; a tuple
with the same machine widths cannot replace the declared record. Closed generic
records use their exact substituted type and field identity.

```astra
struct Sample { int count; f64 scale; bool enabled; }

[Foreign(error_factory="foreign_fault", error_domain="16", errors="Fault=-1600")]
Sample adjust(Sample input, f64 delta) throws Fault;
```

The public C entry point takes a record by value and returns it through a typed
output pointer. Native Astra passes its independently verified record leaves.
`--emit-class-source` supplies a reverse mechanical forwarder: its private entry
point receives a pointer to canonical C record storage, dereferences it, and calls
the public provider entry point. Compile that source with the target C compiler
and link it with the Astra object and provider. The target compiler implements
the platform's by-value calling convention. The forwarder contains no provider
or application algorithm.

The LLVM adapter packs each input into private, naturally aligned C storage and
reconstructs the native result from individual fields only after checked success.
Even a one-field record has separate C storage and native carrier plans. Common
layout witnesses check every scalar size, alignment, field offset and total
extent. Headers carry matching C11/C++ layout assertions.

Checked/Core retain the ordinary copied-parameter acquisition prologue. CFG
requires the exact ordered leaf initializations before its typed foreign-return
operation; SSA retains the exact nominal leaf groups. Each verifier reconstructs
the schema from its own fields and bindings. Native ABI verification rejects
substituted nominal input/result plans, and C ABI verification requires canonical
record-pointer channels. Generic materialization preserves imported root metadata
and the typed foreign-return operation.

PODs compose with copied scalars, scalar reference channels, counted parameters
and owned byte/text results. Mutable outputs stay private until result conversion
finishes. A provider error or invalid produced count retires a provisional owned
buffer before the native exception is constructed.

The portable matrix uses independent and generated-header C providers with a
mixed 40-byte record, an adjacent-scalar record with signed/unsigned wide fields,
a closed `Duo<f64>` and a one-field record. Astra callers inspect actual results.
Native O0/O2 and C forwarder O0/O2 combinations plus O1 smoke cover unique/shared
providers; whole-executable Valgrind checks use no suppressions. Source negatives
retain private/nested/pointer-field, borrowed-record and conflicting-result
refusals. Independent stage mutants replace nominal types/groups, remove a
parameter acquisition, alter a physical channel and permute equal-typed LLVM
field addresses without executing corrupted code.

This remains an intermediate M16 slice. Imported properties and callbacks,
foreign handle exports, actual declaration-derived COM/GObject personalities, opaque SDK
composition and the final acceptance matrix remain active work.
