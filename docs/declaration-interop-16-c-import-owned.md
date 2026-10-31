# Owned C Class import results

An imported `owned u8[]` method result transfers a counted byte owner through
the same declaration schema as an exported byte result. The matching C function
returns status and writes private data/count/error places. The provider's
`<prefix>_bytes_release` consumes both data and count places.

```astra
[Foreign(error_factory="foreign_fault", error_domain="16", errors="Fault=-1600")]
owned u8[] snapshot() throws Fault;

[Foreign(error_factory="foreign_fault", error_domain="16", errors="Fault=-1600")]
[ForeignChannel(parameter="result", encoding="utf8-counted")]
owned u8[] description() throws Fault;
```

The explicit UTF-8 encoding selects a logical text channel and
`<prefix>_text_release(char **, int32_t *, astra_foreign_error *)`. The native
result remains an owned byte buffer: it can feed an ordinary native UTF-8 owner
factory, and never pretends that a temporary foreign allocation is a static or
receiver-borrowed native string. Counted text preserves embedded NUL. An explicit
`utf8-nul` result also has a count output, excludes embedded NUL, and requires a
terminator at that count in the provider's promised allocation. The owned native
buffer contains exactly the payload, excluding the terminator.

The adapter verifies status/error consistency, nonnegative counts, required
backing, and the selected text representation before publication. It allocates
and copies into the ordinary native buffer allocation domain, then retires the
foreign candidate through its exact declared release operation. It never passes
the foreign payload directly to native `free`. Even empty and provisional failed
results go through the matching provider release. The provider release must
complete successfully, clear its error record, and consume both places; violating
this total-retirement obligation traps. This is a boundary promise, not a proof
about arbitrary malicious C memory.

An allocation failure, malformed text, invalid count or contradictory status
retires the provisional foreign result and input staging before constructing the
native checked exception. Mutable borrowed outputs and scalar output places only
publish after all result conversions succeed. The caller's inout values remain
unchanged on failure and out scalar places retain their initialized empty value.

Independent and generated-header C providers use an allocation with a hidden
header before the payload, and poison that payload during release. Native callers
then inspect their independent snapshots. Unique/shared O0/O1/O2 matrices include
eight unsuppressed Valgrind executions, staged-output rollback, first/second input
allocation faults, result-copy faults, provisional failures, empty/null results,
invalid UTF-8, embedded NUL and missing terminators. Detached Core, CFG, SSA,
native ABI, C ABI and LLVM mutations check owned transfer, byte element identity,
matching retirement, snapshot extent and UTF-8 validation.

This is an intermediate implementation slice. Imported properties and callbacks,
foreign handle exports, plus declaration-derived COM/GObject personalities and
the complete SDK acceptance gates, remain active M16 work.
