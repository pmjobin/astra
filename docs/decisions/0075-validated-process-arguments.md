# ADR 0075: Validated process arguments

Status: accepted for ASTRA-ARGS-1.

The hosted entry may be `int main()` or `int main(string[] args)` (equivalently,
`borrowed string[]`). The latter receives the entire ordered invocation vector,
including index zero when supplied. Index zero is invocation text, not verified
executable identity. No splitting, option processing, environment access,
normalization, locale conversion or lossy repair occurs.

Two capabilities compose. The ordinary native `SliceType<StringType>` domain
supports borrowed parameters, local copies and rebinding, `len`, checked reads
and forwarding in functions, methods and constructors. Descriptor slots are read
only. Both the table and every payload have a deep borrow lasting through use;
extraction yields an ordinary borrowed string, never a static string. Per-write
origins preserve saved copies across rebinding. Static-only string results cannot
return these borrows. Writable numeric slices retain their existing contract.

The separate hosted bridge snapshots the table and payload bytes in one checked
allocation. It validates the copied bytes as strict shortest-form scalar UTF-8
before publishing any native view. A zero count needs no allocation or argv
dereference. Empty elements are null/zero. Preparation returns 0 on success, 2
for invalid shape, encoding or size, and 3 for allocation failure, leaving the
output null on failure. The wrapper calls the exact selected native entry only
after success, then disposes once after native normal return and lexical cleanup.
Traps, signals and foreign nonreturn do not acquire unwinding semantics.

The startup allocation and byte copy are deliberate costs of the opt-in text
entry. Borrowing original argv would not establish snapshot stability. A global
argument registry or a special args-only indexing operation would prevent normal
native composition and is excluded. Existing `int main()` performs no capture or
argument validation.

Native `text-slice-v10` plans retain an ordered outer table-pointer/I32-count
group and an inner pointer/I32-byte-length descriptor, read access and deep
borrow obligations. Target layout determines padding and stride. Initial object
and hosted bridge qualification is x86-64 Linux. The independently linked
`args-posix` provider is private compiler startup machinery, not public CABI
string input, export or collection support. No provider is implicitly linked.

This does not admit owned strings or string slices, local/fixed string arrays,
string fields, slice results, generic collection arguments, raw pointer
conversions, wider source integers or mutable descriptor slots. Raw OS-byte/path
arguments need a different explicit entry policy. Diagnostics, raw recovery,
environment APIs, option parsing, concatenation, modules and async remain later
work.
