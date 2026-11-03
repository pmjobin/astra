# LLVM-12 frozen scope and independent expectations

This selection precedes emitter implementation. It is 24 unique programs: six
new numeric witnesses and eighteen unchanged SSA-11 sources. Expected ordinary
stdout/stderr is empty. All exit 0 except inherited scalar-control, which exits
255. Cleanup traces are independently derived from allocation size and reverse
scope/field cleanup, and compared to separately compiled C0, not used by lowering.

Numeric (6): wrapping (new exact unsigned/signed overflow), signed-compare,
bitwise, division, shifts, conversions. Branch (4): ssa-diamond,
ssa-nested-diamond, ssa-and-skip, ssa-or-skip. Loop (4): ssa-counter,
ssa-nested-continue, ssa-break-version, nested-loops. Call (4):
ssa-separate-functions, ssa-chain, ssa-overwrite-join, ordered-owned-arguments.
Ownership (4): ssa-argument-order, ssa-owning-return, ssa-borrow-end,
owner-loop-exits. Extra (2): ssa-field-memory, scalar-control.

Target: installed LLVM 22.1.8, GNU/Linux x86-64, host PIC object, C entry
`int main(void)`. Integer/bool/void, flag-free wrapping arithmetic, signed and
unsigned predicates, guarded division and shifts, same-module direct calls,
concrete native records and owned primitive buffers are intended. Record field
order follows checked nominal declarations, buffer carrier is {ptr,i32}.
Functions are private to this module except main: aggregate arguments/results use
LLVM first-class aggregate values; borrowed records use addresses. This private
stage ABI is not a C0 module import/export ABI or an external aggregate ABI claim.
Storage uses LLVM's module-context types and host layout. Every root/owning leaf
has an explicit runtime armed bit. Moves disarm, stores arm, and exact CFG cleanup
blocks conditionally release leaves in their retained order. Loans have no machine
operation and retain their independently verified CFG order.

Floats, strings, generic/async/exception/foreign/indirect calls, special policies,
nonprimitive buffer elements and unsupported operations defer before output.
All 80 predecessor statuses stay immutable: SSA invalid/deferred cannot emit;
SSA positive outside this matrix is named LLVM_DEFERRED, with operation/type.
The 73-source compiler closure remains deferred. No Stage 1 claim.

Public API consumes retained SSA with exact owner and checked profile; upstream
verification, emitter correspondence checking, LLVM verification and independent
IR/behavioral oracles remain distinct gates. Failures expose no public artifact.
Limits bound tables, work and output. Error stages distinguish invalid upstream,
unsupported type/operation, invalid IR, unavailable target, resource exhaustion
and output failure. Raw LLVM handles stay inside the module owner.
