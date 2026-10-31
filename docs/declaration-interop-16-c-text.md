# Declaration-derived C text channels

This is an intermediate implementation of ADR 0166; full M16 remains pending.
Selected native `string` parameters default to a counted `const char *` plus
signed `int32_t` length. An explicit named length can reuse another actual native
parameter. The adapter snapshots the bytes, checks canonical UTF-8 using the
compiler's existing validator, then exposes a call-scoped native string. Invalid
sequences return adapter domain zero, code/status `0x80070459`, before the native
method runs. Counted input preserves embedded NUL.

`[ForeignChannel(parameter="input", encoding="utf8-nul")]` selects a NUL-terminated
input pointer without a separate C count. The adapter searches within the maximum
signed native storage extent and validates the bytes preceding the sentinel.
The caller supplies accessible terminated storage. The input's payload plus
sentinel must fit that extent. An explicitly nullable pointer maps null to an
empty native string. Other null pointers refuse.

Native string results become independent owned snapshots, even when the native
source is a static literal or a receiver-backed property. The public C result is
`char **result, int32_t *result_length`; both pointers are mandatory. Counted
results preserve embedded NUL and do not promise an extra sentinel. An explicit
result `encoding="utf8-nul"` rejects embedded NUL with `0x80070057`, checks the
sentinel extent before addition, and produces a terminated allocation. Result
length excludes that sentinel. Empty successful results have a nonnull allocation.
The generated `<prefix>_text_release` consumes and clears the data/count slots.
Its error record is caller-owned and allocates nothing.

The receiver remains held through snapshot conversion and cleanup. Allocation
failure clears outputs and retires provisional storage. Native algorithm
allocation retains the native language's existing behavior; the fault controls
here qualify adapter scratch and snapshot allocation, not a new native allocator
contract. Snapshots outlive root destruction and are released independently.

The integration matrix runs unique/shared O0/O1/O2 with independent C declarations
and generated SDK headers. It covers embedded NUL, multi-byte text, overlong and
truncated sequences, surrogates, out-of-range scalars, nullable empty input,
negative counts, first/second scratch failure, snapshot failure, NUL conversion
and root-independent cleanup. Eight unsuppressed Valgrind runs cover complete
executables. Contradictory ownership, mutable native string input, NUL plus a
count annotation and ambiguous `result` selectors refuse before LLVM emission.
Mutation tests separately remove owned cleanup and alter NUL admission/retirement
in LLVM; ordinary LLVM validity alone does not pass the foreign contract proof.
