# Native aggregate leaf channels v7

[Struct collection elements](native-struct-elements-v11.md) use this existing leaf transport for copied record arguments/results. Their in-memory layout remains ordinary record storage; it is never derived by concatenating these register channels.

[buffer-v8](native-buffer-v8.md) is the next monotonic native profile for complete
owned-buffer PTR/I32 parameter/result transfer. v7 struct contracts and LLVM-only
aggregate result carriers remain unchanged; buffer ownership never becomes an
ordinary aggregate SSA Value. Containing classes retain object PTR contracts.

`NativeAbiVersion.AGGREGATE_V7`, printed `aggregate-v7`, extends the accepted
compiler-owned monotonic NABI profiles. It subsumes every scalar, pointer,
vector, slice and F64 capability through v6. Frozen profiles v0–v6 retain their
existing eligibility and mapping; they cannot contain a struct value plan.
This is not a stable external ABI and does not follow host C aggregate rules.

A program containing any source signature with a copyable concrete StructType
parameter or result selects v7 for its native signatures. Body-only struct copying
selects no newer profile. A Struct* boundary remains PTR, regardless of pointee
field types. Receivers retain their existing PTR contract, separate from explicit
struct values. CABI/VAPI do not gain aggregate support from v7. CABI-FP-1 independently
adds scalar C float/double under [scalar-fp-v2](c-fp-v2.md). A native
Lab containing f32 and f64 fields may accept/return aggregate-v7 values, call
C float/double functions, initialize fields from those results, and return a
native aggregate. Its C calls and native struct boundaries keep separate
authorities; no C struct layout or C aggregate calling convention is implied.

| Exact semantic shape | Ordered physical leaves |
| --- | --- |
| Pair { int x; f64 y; } | I32, F64 |
| Lab { f64 l; f64 a; f64 b; } | F64, F64, F64 |
| Outer { Pair inner; i16<8> samples; } | I32, F64, VECTOR(I16,8) |
| One { f64 value; } | F64 |
| Box<f64> { f64 value; } after materialization | F64 |
| Pointer { void* value; bool valid; } | PTR, B1 |

NativeStructValuePlan retains copied source declaration ordinal/name, an ordered
list of NativeStructLeafChannel(field ordinal path, existing NativeAbiType), and
SINGLE_LEAF or LEAF_AGGREGATE result carrier choice. It is not a NativeAbiType.
NativeSignature retains exact struct-parameter grouping and optional struct-result
plan. Parameter group offsets index the existing signature parameter array;
SLICE remains one group that expands to adjacent PTR/I32, and receiver/object
result storage prefixes remain independently ordered. No STRUCT scalar channel,
padding channel, runtime descriptor, size threshold, or target layout rule exists.

The builder uses the same StructLeafOrder/CoreStructLeaves order as whole copy:
nested structs recurse in declaration order, vectors stay whole, and scalar
leaves reuse B1/integer/F32/F64/PTR. Exact semantic identity and CopyabilityAuthority
are verified upstream. The standalone native model owns only physical data.
Source association validation rejects replacing A's plan with same-layout B's
plan even when their LLVM signatures coincide. Field bits transport without
arithmetic, conversion or new rounding; padding bits have no preservation promise.

## LLVM realization

For Pair identity, the frontend emits a signature equivalent to:

```llvm
define internal fastcc { i32, double } @identity(i32 %x, double %y) {
	%r0 = insertvalue { i32, double } zeroinitializer, i32 %x, 0
	%r1 = insertvalue { i32, double } %r0, double %y, 1
	ret { i32, double } %r1
}
```

A call recovers the two ordinary leaves with extractvalue. A one-leaf nominal
struct instead uses that LLVM leaf type directly for its parameter/result.
The LLVM aggregate exists solely as the backend return carrier; it is not Astra
struct storage and does not introduce an Astra semantic/Core/CFG/SSA aggregate
Value. Scalarized identity/forwarding needs no alloca, load/store, memcpy/memmove,
sret, byval, hidden input pointer or hidden result-storage pointer.

NativeStructValuePlan is target-independent. LLVM may choose registers and spill
physical values, including large results; those machine decisions do not redefine
source copy semantics. Representative x86-64 machine evidence is qualification,
not an x86 calling-convention promise for future SH-4. Class/ObjectStorage results,
Resource transfers, borrowed contracts, C aggregate interoperability and generic
Copy/Move remain separate. See [ADR 0062](../decisions/0062-native-struct-values.md),
[IR](../ir/struct-values.md), and qualification.
