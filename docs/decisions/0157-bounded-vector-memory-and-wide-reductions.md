# ADR 0157: bounded vector memory and binary64 reductions

Status: implemented and qualified within the Surge 11 profile.

`load_vector(view, offset, lanes, alignment)` reads one supported numeric vector
from a bounded scalar view. `store_vector(view, offset, value, alignment)` stores
one complete vector. Offsets have exact int/i32 type; lane count and alignment
are decimal literals. Alignment is a power of two from 1 through 16. A mask,
raw pointer, mismatched element type or unsupported vector shape refuses.
Ordinary public helpers in `numerics/vectors.astra` compose these primitives.

Operands evaluate once in source order. The complete range must fit before
forming the access pointer or writing any lane. Requested alignment is checked
at runtime after the range check and before access; failure takes the existing
non-unwinding trap. There is no LLVM assumption or strengthened parameter ABI.
Alignment 1 permits unaligned access. Aligned and unaligned operations have the
same lane bytes and alias semantics. A load snapshots its entire value before a
following store, including overlapping views. Neither operation captures a view.

The typed contract and ordered memory operation exist independently in Checked,
Core, CFG and SSA. CFG/SSA retain required effect positions. Native body plans
copy shape, operation kind and alignment and verify their original list, without
changing call channels. LLVM retains bounds, trap, address, alignment and access
proofs after upstream models are released. Its original artifact verifier rejects
changed predicates, bounds, pointers, alignment, operation or effect removal.
Ordinary LLVM optimization works on a verified clone; dead nonvolatile access
elimination remains legal when the program's observable behavior is preserved.

The sanctioned test setting `ASTRA_TEST_VECTOR_MEMORY=native|scalar` chooses
whole-vector or scalar lane memory lowering under the same checks and public
optimization level. Both execute the same declared semantics. An unknown setting
refuses when vector memory is selected. The scalar route is an independent
lowering control; LLVM may subsequently combine legal scalar accesses. It is not
a promise to prohibit every SIMD instruction in an optimized product. Tests
record the environment override, raw/optimized IR, disassembly and program bytes.

`dot` and `mac` now admit exact f64 vectors with f64 accumulators/results, using
distinct semantic modes. Strict order starts with +0 (or the explicit MAC
accumulator), rounds each lane product, then adds in ascending lane order.
Scoped FP permissions reach each arithmetic operation; default f32 output and
integer modular dot/MAC retain their existing contracts. No ABI profile changes.

Library narrowing/widening and checked f32-to-i32 lane conversions reuse the
existing exact scalar conversion authorities. Min/max propagate the first NaN
in lane order and retain the earlier lane for equal values, including ±0.
Strict sums keep serial association. No implicit reassociation, FMA, wider vector
shape, writable lane, C vector ABI or mandatory runtime dependency is introduced.
