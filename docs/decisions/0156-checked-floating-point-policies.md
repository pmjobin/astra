# ADR 0156: checked, independent floating-point permissions

Status: implemented and qualified within the Surge 11 profile.

An unannotated declaration remains strict. The existing bracketed declaration
metadata grammar admits `FloatingPoint` on synchronous native free functions.
Each key takes `"on"` or `"off"`: `contract`, `reassociate`, `reciprocal`,
`finite`, `no_nan`, `no_signed_zero`, and `strict`. Unknown/duplicate options,
conflicting finite/NaN permissions, and strict plus an enabled relaxation refuse.
Foreign, async, throwing and unsupported placements refuse. This adds no global
math mode and changes no physical call ABI. Separately compiled functions keep
their own policy; callers do not grant permissions to callees.

Permissions are independent typed bits carried by Checked, Core, CFG, SSA and
native declarations. Each stage retains its own immutable admitted snapshot;
changing the current policy without its admission fails verification. Dumps
expose nonstrict policies. Generic materialization copies the exact policy.

`contract`, `reassociate`, `reciprocal` and `no_signed_zero` grant only the
corresponding instruction permissions. They do not imply finite values or other
FMF. Approximate reciprocal is a permission, not a promised hardware estimate.
No finite precision bound is claimed for arbitrary reassociated algorithms;
each relaxed application must state and measure its input/error domain.

Finite/NaN permissions are checked, not trusted assertions. Before flagged
binary arithmetic or comparisons, ordered lane checks restrict operands to
[-2^60,2^60] for f32 or [-2^500,2^500] for f64. Division also requires an absolute
denominator of at least 2^-60 or 2^-500, respectively. Thus all selected arithmetic
results remain finite, including after contraction. Invalid inputs take the
existing non-unwinding trap. These deliberately conservative domains reject
some otherwise valid finite computations. They must never be generalized to
raw foreign promises or unchecked result assumptions. Guards themselves are
strict. Signed zero is preserved unless its permission is explicitly selected.

Rounding mode remains nearest/ties-even and subnormals remain gradual on the
qualified x86-64 profile. NaN classification, rather than payload propagation,
is the baseline promise. Ambient rounding changes, observable IEEE trap flags,
FTZ/DAZ changes, arbitrary declaration inheritance and lexical policy blocks
are not added. Strict helper functions provide explicit nested boundaries.

LLVM records original instruction identities and exact admitted flags before
optimization. Optimized products must retain the module's permitted flag set;
strict-only modules still reject every FMF. Qualification must separately check
mixed-policy inlining and actual outputs. This post-pass subset check alone is
not proof of source correspondence.

The feature audit executes an explicit `+avx,+fma` backend product and observes
fused numerical differences in selected operations while strict callee
cancellation remains separately rounded. Default public CPU/features remain
unchanged. LLVM may legally reuse strict results for relaxed expressions; the
positive audit uses independent external inputs to avoid that reuse.
