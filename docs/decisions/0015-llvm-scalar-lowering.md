# ADR 0015: Verified LLVM scalar lowering

Status: accepted for ASTRA-LLVM-1.

## Context

SCALAR-1 supplies numeric and trap semantics, CALL-1 supplies exact callee
identity and evaluation order, SSA-1 supplies block arguments, and NABI-1
supplies physical scalar call channels. LLVM-1 crosses the protected backend
boundary to realize these authorities as target-independent, verified LLVM IR.
It does not change the language or upstream representations.

## Decision

1. Lowering consumes verified SsaProgram and verified NativeAbiProgram. It
   repeats SSA/NABI verification and reuses NativeAbiValidator to check counts,
   ordinal correspondence, signatures, and every direct call before construction.
   Correspondence is within-compilation function order, never source/debug names.
2. NABI supplies physical function-channel authority. LLVM function types come
   exclusively from NativeSignature. SSA value types go through the existing
   NativeTypeMapper before the centralized LLVM mapper.
3. LLVM is downstream physical lowering, never Astra semantic IR or an upstream
   type authority. Raw LLVM objects remain under `src/backend/llvm/`.
4. Native I32 becomes LLVM i32; Native B1 becomes LLVM i1; an absent NativeResult
   becomes LLVM void. B1 → i1 is this backend realization and does not freeze
   bool memory layout or future machine carriers.
5. Native-internal functions use LLVM internal linkage and `fastcc`. Every Astra
   direct call uses the same convention. Neither fastcc nor ordinal names
   `astra.fn.N` are permanent native ABI or public symbol promises.
6. All LLVM functions are declared and bound to exact SSA/native identities
   before any body. Parameters map by ordinal, supporting forward calls,
   self recursion, and mutual recursion without name lookup.
7. All primary blocks and their ordered block-parameter phis are created before
   instructions. Astra block arguments become LLVM phi nodes; LLVM's phi
   representation does not become Astra SSA architecture.
8. Backend helper/control blocks may refine physical control flow to preserve
   Astra semantics. Each SSA block tracks its actual LLVM end block after
   splitting. Phi incoming predecessors are the blocks that actually branch.
9. Distinct parallel SSA edges to the same target get distinct deterministic
   physical edge blocks. Their ordered arguments reach phis from distinct
   predecessors, with no change to Astra SSA.
10. Wrapping addition, subtraction, multiplication, and unary minus use ordinary
    add/sub/mul with no nsw/nuw assumptions. Unary minus is sub-zero; unary plus
    aliases its operand directly. Integer constants use AstraIntValue and safe
    int64 arithmetic to construct exact two's-complement i32 bits.
11. Bool constants are i1 false/true and negation is xor with true. Ordered
    integer comparisons use signed predicates; scalar equality uses eq/ne.
12. Signed division/remainder require explicit guards. At their stored SSA
    position, divisor zero branches to an LLVM trap intrinsic call followed by
    unreachable. The intrinsic is obtained with LLVMLookupIntrinsicID,
    LLVMGetIntrinsicDeclaration, and LLVMIntrinsicGetType, through LLVM 22's
    qualified C API. It is not an ordinary foreign function declaration.
13. After the nonzero guard, INT_MIN/-1 branches to a special path. Division
    supplies INT_MIN; remainder supplies zero. Only the remaining path may
    execute raw sdiv/srem. A backend-local continuation phi joins the results.
14. Neither zero nor the INT_MIN/-1 path may execute raw sdiv/srem. If LLVM's
    C builder has already folded a guard to true, the impossible normal block
    ends unreachable without constructing an invalid constant operation or
    dead poison value. The explicit guards remain in the module.
15. Instruction/effect/trap order follows stored SSA order. Backend lowering
    never re-walks source trees, reorders arguments, or moves guards past calls.
16. No optimization pass is run or required for correctness. LLVM's ordinary
    builder may fold constant operands; that is distinct from a pass pipeline.
17. One module/context pair is owned by LlvmModuleArtifact. After lowering it
    retains no source, types, syntax, checked/Core/CFG/SSA/NABI graphs, or debug
    provenance. Module disposal precedes context disposal. Builders and maps
    have construction-only lifetimes and are cleaned up on errors as well.
18. LLVM verifier success is mandatory before accepting or dumping a module.
    Diagnostics are copied then freed with LLVMDisposeMessage. Failures are
    deterministic internal compiler errors, never source diagnostics.
19. Deterministic construction uses a fixed `astra.scalar` module identifier,
    ordinal function/parameter/value/primary-block names, and value/edge-based
    helper names. No target triple, data layout, timestamps, pointers, random
    identifiers, absolute paths, or debug metadata enter normal IR output.
20. `--dump-llvm` exposes the verified artifact. Silent `--check` now includes
    lowering and LLVM verification. Plain source invocation continues to
    reject native object/executable emission as unimplemented.
21. `astrac` and real backend tests intentionally link the qualified system
    LLVM 22. Upstream and standalone representation tests remain LLVM-free.

## Construction order and alternatives

Array-order body traversal would fail for valid SSA whose dominating definition
has a later block ordinal. An iterative deterministic depth-first traversal
visits dominators before uses; the first successor is visited first. Stored
instruction order inside each block remains unchanged. Primary creation follows
ordinal order with the designated entry first, as required by LLVM. This needs
neither a new SSA analysis abstraction nor instruction placeholders.

Direct parallel-edge lowering would give one LLVM predecessor multiple incoming
values for a target phi. Splitting both edges only when their target is identical
preserves identity and arguments without changing the upstream graph.

A select around an already-executing raw signed division would not protect its
invalid inputs. Guarded control flow makes the permitted raw-operation domain
explicit before optimization and preserves observable trap order.

## Scope and evidence

[The backend inventory](../backend/llvm-scalar-v0.md) describes implementation
and regression coverage. LLVM graph assertions, exceptional-path exploration,
goldens, negative verifier tests, weak-reference lifetime tests, linkage checks,
and strict builds enforce this decision.

No C++ API/shim, new production dependency, target machine, optimization pass,
native object, executable, linker, JIT, C ABI, stable mangling, or debug-info
generation is introduced. ASTRA-EXEC-1 owns target-machine selection and machine
emission/execution qualification.
