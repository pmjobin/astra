# Scalar numeric conversion IR

`CheckedNumericConversionExpression` and `CoreNumericConversionValue` retain
source/destination semantic identity, operand, provenance, exact conversion
kind and rounding/trap policy. `NumericConversionKind` distinguishes:

| Integer→floating | Floating→integer |
|---|---|
| SIGNED_INT_TO_F32 | F32_TO_SIGNED_INT |
| UNSIGNED_INT_TO_F32 | F32_TO_UNSIGNED_INT |
| SIGNED_INT_TO_F64 | F64_TO_SIGNED_INT |
| UNSIGNED_INT_TO_F64 | F64_TO_UNSIGNED_INT |

Policies are NEAREST_TIES_EVEN and TRUNCATE_TRAP respectively. Verifiers recompute
legality from IntegerType signedness/width and F32Type/F64Type identity, reject
mismatched source operands and invalid kinds/policies, and verify canonical type
identity. IntegerType.minimum/maximum remain the only destination range authority.
Existing FloatConversionKind and integer modulo conversion nodes are unchanged.
No semantic/Core code imports LLVM or physical opcodes.

```text
(numeric-convert (from int) (to f64)
	(kind signed-int-to-f64) (policy nearest-ties-even) ...)
(numeric-convert (from f64) (to int)
	(kind f64-to-signed-int) (policy truncate-toward-zero-trap) ...)
```

Core keeps a value operation; it does not substitute opaque helper calls.
Checked and its symbols can be destroyed before independent Core verification.
Core specialization clones the operation and exact metadata without source recovery.

For integer→floating, CFG emits one CfgNumericConversionInstruction, no guard.
For floating→integer it emits CfgNumericGuard, then conversion consuming the
guard result. The guard evaluates/captures its source once and traps unless finite
mathematical truncation fits the exact destination. Normal continuation returns
the same floating scalar with destination-specific proof. Later call arguments
are emitted after this ordered guard/conversion. Physical trap blocks are expanded
by the backend, following the existing ordered bounds-check model.

SSA uses SsaNumericGuard and SsaNumericConversionInstruction with ordinary scalar
SsaInstructionResults. Independent verification maps guard results to destination
contracts and checks standard SSA dominance before permitting conversion. Guard
absence, wrong interval, invalid policy, reordered definition and non-dominating
branch proof all reject. There is no boxed number, runtime proof, type tag, new
ABI channel, or reference to CFG/Core/Checked objects.

LLVM compares in exact f64 against open bounds MIN−1/MAX+1. Ordered predicates
reject NaNs/infinities; f32 comparison widening is exact and is physical policy.
The invalid path calls llvm.trap and is unreachable; the successful continuation
contains fptosi/fptoui. A validity select also substitutes zero on invalid inputs,
so initial IR cannot create poison even if that sanitized operand is speculated.
O2 IR and runtime audits check guard control dependence and adversarial sources.
Integer sources use signedness-specific sitofp/uitofp directly to float/double.
No helper, heap or libm dependency is introduced; no fast-math policy changes.

Literal suffixes are resolved before CheckedFloatExpression construction.
CoreFloatValue/SSA constants receive exact BinaryFloatValue bits, without suffix
metadata or decimal parsing. SourceSpan remains diagnostic provenance only.
See [ADR 0066](../decisions/0066-explicit-numeric-conversions.md) and
qualification.
