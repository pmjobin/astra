# Native vector channels v4

[GEN-1](../ir/generics.md) admits every supported numeric vector and bool mask as
an exact generic argument. Specialization precedes CFG and native planning, so
instances use ordinary vector-v4 or a subsuming effective profile. Signed/unsigned
vectors remain separate instances independent of identical physical lane widths.
Generic definitions have no vector ABI or maximum profile.

SLICE-BOUND-1 adds [slice-v5](native-slices-v5.md) for programs with native
borrowed slice parameters. That profile also carries the existing vector
channels. Programs without slice parameters retain the profile rules below.

VEC-MEM-1 adds no ABI version. A TypedPointerType whose pointee is VectorType
maps to existing NativeScalarType.PTR. `void clear(i16<8>* p)` therefore remains
pointer-profile-compatible. `void store(f32<4>* out,f32<4> value)` uses PTR plus
VECTOR(F32,4), selecting vector-v4 through the actual by-value channel. The
pointee alone never selects vector-v4. C vector-pointer and vector ABI/VAPI
support remain deferred. See [vector memory](../language/vector-memory.md).

VEC-DOT-1 uses vector-v4 unchanged: `i32 f(i16<8> a,i16<8> b)` and
`f32 g(f32<4> a,f32<4> b)` have existing vector parameters and scalar result
channels. `dot_wrap`, `mac_wrap`, `dot` and `mac` introduce no ABI type/profile.
Vectors constructed only inside a scalar-signature function do not select v4.
C vector ABI and VAPI vector declarations remain unsupported. See
[dot/MAC IR](../ir/vector-dot.md).

VEC-DSP-1 also uses this profile unchanged. Saturation, widen, pack and
interleave produce existing VectorTypes and add no channel or profile. Vector
body operations retain the signature's scalar profile; vector signatures use
vector-v4, including Resource/vector/integer workloads. CABI/VAPI vectors remain
unsupported. See [DSP IR](../ir/vector-dsp.md).

VEC-LANE-1 uses this profile unchanged. Splat, extract, insert, shuffle and
mask select are body value operations; no new physical type/channel/profile
exists. Scalar signatures with primitive bodies retain their old profile if
there is no vector boundary. CABI and VAPI remain unchanged. See
[primitive IR](../ir/vector-primitives.md) and qualification.

VEC-1 generalizes the compiler-owned native channel model:

```text
NativeAbiType
	NativeScalarAbiType { scalar_type: NativeScalarType }
	NativeVectorType { element: NativeScalarType, lanes: int }
```

A vector is not a NativeScalarType. Parameters and results own `abi_type`.
Existing scalar constructors and guarded `scalar_type` accessors preserve scalar
clients; generalized code uses `abi_type`. Structural equality preserves both
vector element signedness and lane count. The model has no semantic or LLVM
objects and remains independently constructible, verifiable, and dumpable.

Elements are I8/U8/I16/U16/I32/U32/F32/B1. PTR vectors reject. The semantic
VEC-1 shape capability is also checked independently at the physical boundary:
counts 2/4/8/16, numeric payload at most 128 bits, and all four B1 counts.
B1 lanes make no packed storage-width promise. Each parameter and each non-void
result uses exactly one direct channel; no hidden lanes, descriptors, alignment
channels, or pointers are introduced. This does not promise one hardware register.

```text
(native-abi vector-v4
	...
	(parameter #0 VECTOR(I16,8))
	(parameter #1 VECTOR(I16,8))
	(result VECTOR(I16,8)))
```

## Profile selection and compatibility

`NativeAbiVersion.VECTOR_V4` prints `vector-v4`. Under the existing program-wide
profile architecture, any native parameter/result with a VectorType selects v4
for that program and its native signatures, regardless of declaration order.
It permits all prior scalar/PTR channels alongside vectors. If no native
signature has a vector, the previous v0/v1/v2/v3 selection policy and dump bytes
remain unchanged. Body-only vector operations do not require a new callable
profile. Earlier profiles reject vector channels.

`f32<4> process(owned Resource r, f32<4> gain, u8 mode)` uses
PTR / VECTOR(F32,4) / U8 → VECTOR(F32,4). Ownership argument capture/commit,
parameter acquisition, and lexical cleanup remain upstream contracts. Masks are
normal native values, including VECTOR(B1,N) parameters and results.

`VECTOR(I8,16)` and `VECTOR(U8,16)` remain distinct even though LLVM realizes
both as `<16 x i8>`. Compatibility checks reject a physical signedness mismatch
before LLVM. No C ABI channel or profile changes: extern(C), export(C), and
VAPI vectors remain unsupported. These internal profiles are not a stable
cross-version binary ABI promise.

## LLVM realization and target qualification

| Native element/channel | Fixed LLVM realization |
| --- | --- |
| VECTOR(I8/U8,N) | `<N x i8>` |
| VECTOR(I16/U16,N) | `<N x i16>` |
| VECTOR(I32/U32,N) | `<N x i32>` |
| VECTOR(F32,N) | `<N x float>` |
| VECTOR(B1,N) | `<N x i1>` |

Constants use LLVMConstVector with exact scalar constants, including F32-1
integer-bit bitcasts. Dynamic construction inserts into a fully defined zero
vector. Integer add/sub/mul/negation use wrapping operations without nsw/nuw;
comparisons select signed or unsigned predicates from the retained element type.
F32 dispatch reuses fadd/fsub/fmul/fdiv/fneg and OEQ/UNE/OLT/OLE/OGT/OGE with
no fast-math flags or contraction. Mask NOT is xor with all-ones; all/any use
backend extraction followed by scalar AND/OR. Vector block parameters use vector
phis with the existing exact physical predecessor authority.

Default x86-64 Linux execution is qualified with empty CPU/features and the
existing target-machine configuration. Other native vector targets reject pending
qualification. Backend legalization may use SIMD, multiple operations, or scalar
lanes. The FMA-capable audit records and executes separate multiply/add lowering;
no SIMD choice is a language requirement. No vector memory ABI is established.

[ADR 0037](../decisions/0037-short-vectors.md), [language](../language/vectors.md),
[IR](../ir/vector-values.md), and qualification provide
the upstream contract and validation evidence.
