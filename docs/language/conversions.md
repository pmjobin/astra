# Conversion families

GEN-1's [plain-copy type parameters](generic-functions.md) permit no cast to or
from T. A generic definition rejects such conversions before instantiation;
concrete int/f64 instantiations cannot legalize them. Explicit conversions between
ordinary concrete types retain their existing semantics inside generic bodies.

F64-1 adds explicit floating `as` conversions: `f32 as f64` is exact widening;
`f64 as f32` rounds nearest/ties-even. Zero and infinity signs are preserved;
narrowing overflow produces signed infinity, while underflow produces subnormal
or signed zero. NaN payload/sign retain F32's unspecified source policy.
The operand keeps its own source context: an otherwise uncontextualized decimal
remains f32 even before `as f64`. A precision suffix fixes the operand format
before rounding. NUM-CONV-1 adds [scalar integer↔float casts](numeric-conversions.md);
implicit, vector floating and identity floating casts remain unsupported. See [f64](f64.md) and
[floating conversion IR](../ir/floating-values.md).

[Explicit integer `as` conversions](integer-conversions.md) use ICONV-1 wrapping
modulo semantics for exact integer scalars and equal-lane integer vectors.
Destination syntax never contextualizes the source expression.

[Vector DSP widening and packing](vector-dsp.md) are separate shape-changing
special forms. Widening selects a half-vector then uses ICONV conversion, with
source signedness controlling extension. `pack_wrap` converts modulo the narrower
destination width, placing first-source lanes before second-source lanes.

`pack_sat` uses the compiler-owned `saturating_convert_to` authority: interpret
the source mathematical integer, clamp to the destination interval, then encode
exactly. Saturating conversion is distinct from `as`; no general scalar
saturating-cast syntax exists yet. Bool, f32 and pointer conversions remain
outside these integer conversion families.
