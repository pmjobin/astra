# Bounded SysV C POD values

`[CCode(record_abi="value-lp64")]` explicitly selects a foreign by-value contract
on an `extern(C)` declaration or an `export(C)` function. A source parameter or
result names the concrete struct itself. The earlier `natural-lp64` borrowed
`Struct*` contract keeps its original meaning and diagnostics. An unannotated
C struct boundary still rejects.

The supported target is GNU x86-64 Linux SysV LP64. A value record has one to
three fields, each `i64`, `u64`, `isize`, `usize` or `f64`, or a singleton `f32`,
or the naturally padded pair `{ f32, f64 }`. Natural field order, size,
alignment and offsets are recomputed independently in CABI, then checked against
LLVM target layout. CABI copies nominal names and scalar identities and retains
no native type/IR graph. Bool, small integer records, coalesced f32 fields,
pointers, nesting, generic/owning records, empty records, unions, bitfields,
packed/over-aligned layouts, flexible arrays, variadics and other targets reject.

Records of at most sixteen bytes use their one or two SysV eightbytes. Each
admitted field has its own INTEGER or SSE channel. The f32/f64 pair transports
`float` and `double`; its padding is never compared or interpreted. Twenty-four
byte records use SysV MEMORY classification: LLVM `byval` with the exact natural
record type for parameters, and an exact `sret` pointer for results. These are
the platform's real C by-value struct ABI, also emitted by the independent C
compilers; they are not an ordinary pointer parameter disguised as a record.

A signature admits at most two logical parameters and no text/buffer/callback
transport group. This conservative register budget prevents the aggregate
register-exhaustion rollback case from being approximated by independent scalar
spills. Extending that budget requires explicit complete SysV argument-register
classification. Scalar-only signatures retain their earlier capabilities.
The metadata must actually govern a record parameter or result.

Checked/Core/CFG/SSA keep exact source record identity and copied field groups.
Foreign record results have complete bounded consumers, and every emitted field
is an ordinary typed leaf definition. Native value transport stays under NABI;
the C wrapper or call boundary adapts those leaves to the separately verified C
contract. C ABI frames carry no native exception channel or resource ownership.
LLVM artifact checks retain exact imported symbols, C convention, arguments,
byval/sret type and alignment; exported wrappers retain their exact native target
and ordered field adaptation.

`examples/interop-async-5/record-diagnostics.astra` is A36. Its independent C
provider/client, all-C reference, layout assertions, public O0/O1/O2 products,
negative sources and deliberate verifier mutations are under
`tests/interop-async-5/record-*`. Qualification receipts determine the delivered
status; build success alone does not establish ABI acceptance.
