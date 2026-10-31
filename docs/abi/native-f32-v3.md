# Native floating scalar profile v3

A concrete [GEN-1](../ir/generics.md) f32 instance uses the existing F32 channel
and scalar-fp-v3 or a subsuming effective program profile. Its parameterized
definition has no ABI/profile. Exact f32 transport, no hidden type arguments,
and existing LLVM lowering remain unchanged; no generic-specific profile exists.

[Computed property accessors](../ir/properties.md) use the existing signature
channels: an f32 getter is PTR → F32, and its setter is PTR, F32 → void.
Scalar-fp-v3 is sufficient; properties add no ABI type or capability profile.
The explicit receiver and setter value preserve ordinary native call ordering.

F64-1 leaves scalar-fp-v3 frozen, including its F32 channels and old dumps.
By-value f64 requires [fp64-v6](native-fp64-v6.md), which subsumes existing channels.
F64 locals and pointee/element types do not broaden v3's physical contract.

`NativeScalarType.F32` denotes one binary32 native floating-point value channel.
This is physical call-channel authority, distinct from canonical semantic
`F32Type` and from LLVM's realization as `float`. It freezes neither register
assignment nor a target ABI or cross-version calling-convention promise.

The completed NABI model, verifier, and dumper remain independent of semantic,
Core, CFG, SSA, and LLVM objects. Parameters remain one direct channel each;
results remain at most one channel. Void remains absence of a result.

`NativeAbiVersion.SCALAR_FP_V3`, printed `scalar-fp-v3`, is selected for the
program and its native signatures if any native parameter/result contains scalar
f32 and no native signature contains a vector, slice or by-value f64. [Vector-v4](native-vectors-v4.md)
takes precedence when a vector occurs at a native boundary, followed by
[slice-v5](native-slices-v5.md) and [fp64-v6](native-fp64-v6.md).
It takes precedence over PTR and exact-width integer channels regardless of
source declaration order. It permits F32, I8/U8/I16/U16/I32/U32, B1, and PTR.
For example, `f32 blend(f32 a, f32 b, u8 mode)` transports F32/F32/U8 -> F32.
`f32 process(owned Resource r, f32 gain, u8 mode)` transports PTR/F32/U8 -> F32;
the ownership obligations remain in upstream call semantics and SSA.

Body-only f32 locals or fields do not select v3. Without a floating signature,
[scalar-v0](native-scalar-v0.md), [scalar-ptr-v1](native-pointer-v1.md), and
[scalar-int-v2](native-integers-v2.md) retain their established selection rules
and dump bytes. V0/v1/v2 reject F32. V3 does not alter integer sign/width,
B1, PTR, owned transfer, or cleanup behavior.

CABI has no F32 channel. Source extern(C), export(C), and normalized VAPI C
signatures reject f32. Qualifying C `float` requires a separate target calling
convention, register-class, promotion, and variadic contract. No C float test
helper participates in Astra native f32 calls.

[Language f32](../language/f32.md), [ADR 0036](../decisions/0036-binary32-semantics.md),
and F32-1 qualification contain the semantic and
backend execution obligations.
