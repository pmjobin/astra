# Native binary64 channels v6

Concrete [GEN-1](../ir/generics.md) f64 instances use F64 and fp64-v6 with the
existing binary64 semantics. Generic definitions have no ABI or profile; only
requested concrete signatures participate in profile selection. A combined
f64/vector instance program uses accepted fp64-v6 subsumption. No profile beyond
v6, runtime type channel or representation-based instance identity is introduced.

[Computed property](../ir/properties.md) getters/setters with f64 values use
PTR → F64 and PTR, F64 → void. NativeFunction copies exact property and declaring
owner ordinals and getter/setter kind; the signature uses ordinary existing value
channels. No NativeProperty type or newer profile exists. A program containing
F64 and vector accessors uses fp64-v6 under the existing subsumption rule.

`NativeScalarType.F64` is one binary64 by-value native channel, realized as LLVM
double on the qualified backend. It is independent of semantic F64Type, LLVM
objects and target register allocation. It never maps through a fictitious I64
channel. No cross-version or C calling-convention compatibility is promised.

`NativeAbiVersion.FP64_V6`, printed `fp64-v6`, is the next monotonic capability
profile after slice-v5. It permits all scalar, vector and slice channels supported
through v5 and adds F64. Frozen v0–v5 reject F64 without changing any other channel.
V6 still rejects VECTOR(F64,N); it does not add f64 vector support.

Selection retains existing program-wide maximum-capability policy. Any by-value
f64 native parameter or result selects v6 for the program and its signatures,
including methods and constructors. A body-only local/field/computation does not
select v6. Source pointee/element types do not cause physical F64 channels:

| Semantic boundary | Physical channel(s) | Minimum profile |
| --- | --- | --- |
| f64 parameter/result | F64 | fp64-v6 |
| f64* parameter | PTR | scalar-ptr-v1 |
| borrowed f64[] parameter | SLICE(PTR,I32) | slice-v5 |
| f64 and existing numeric/mask vector | F64, VECTOR(...) | fp64-v6 |
| f64 and borrowed slice | F64, SLICE(PTR,I32) | fp64-v6 |
| borrowed/owned object or Resource and f64 | PTR, F64 | fp64-v6 |
| owned object result from f64 input | hidden result-storage PTR, F64 -> PTR | fp64-v6 |

Implicit receiver and hidden result-storage pointer ordering remain unchanged.
Owned transfer/borrowing contracts remain semantic; physical channels do not
invent ownership, lifetime or pointer attributes. Slices retain one logical group
and expand only into adjacent base PTR and length I32. F64 stays one scalar value
through SSA and one physical channel through NABI.

The completed native model, verifier and dump own no semantic/Core/CFG/SSA/LLVM
backlinks. Standalone tests construct F64 channels without any semantic universe.
LLVM uses fpext/fptrunc for the already-specified explicit source conversions.
CABI-FP-1 separately qualifies C F32/float and F64/double under
[scalar-fp-v2](c-fp-v2.md). Native fp64-v6 never defines the C calling
convention, and C scalar-fp-v2 never defines native f64 transport. No native
profile changes are required.

See [language f64](../language/f64.md), [floating IR](../ir/floating-values.md)
and [ADR 0054](../decisions/0054-exact-binary64.md).
