# ADR 0158: derived effects and closed local object optimization

Status: implemented; final Surge 11 integrated qualification is recorded
separately from this design decision. No native or C ABI channel changes.

SSA is the first stage containing the complete, specialized call graph and
physical ownership events needed for this analysis. Checked/Core/CFG continue
to establish source types, loans, ownership and ordered effects; they carry no
new asserted purity or escape permissions. There is no `[Pure]` promise to trust.

`SsaEffectAnalysis` computes a conservative fixed point from current bodies.
It recognizes receiver projections, scalar local storage, selected numerical
instructions and proved direct calls. Unknown instructions, pointer-valued
arguments, foreign pointer calls, suspension, checked throws, volatile accesses,
owned results and local allocations fail closed. Scalar C calls may preserve
receiver noncapture when they receive no receiver-derived address; they prevent
readonly and memory-free claims. Cycles without established facts stay unknown.

The inspectable bit set is receiver noncapture (1), receiver readonly (2),
no external or trap memory effects (4), and readonly lazy initializer body (8).
The last bit describes the body, never the ordinary state-writing cache gate.
Potential checked scalar/vector arithmetic, conversion, lane and policy traps
prevent bit 4: LLVM 22 models `llvm.trap` as an inaccessible-memory write.
This deliberately withholds some facts that a later range proof could establish.

LLVM maps proved bits to `captures(none)`, receiver `readonly` and function
`memory(none)`. It adds no blanket `nounwind`, `willreturn`, `nosync`, pointer
validity or borrowed-view exclusivity. Generic methods are checked after exact
specialization; reading no field can prove a scalar method pure even when its
receiver has owned fields. Lifecycle bodies additionally require scalar fields
through the ancestry because their implicit cleanup is material.

Native-unit declaration files have immutable `SourceFile.native_interface`
provenance. The analysis refuses them before driver import binding, so a stub
body can never become a purity proof. No caller optimization facts are exported
in a native interface. Existing versioned compiler/object/signature fingerprints
remain authoritative; A96 verifies independent source-free consumers and
rejects changed FP policy fingerprints.

The allocation transformation selects one exact, synchronous local Class with
scalar fields, scalar parameters/results and one verified owner. Every reference,
validation, receiver call and cleanup must be accounted for. Calls require
receiver noncapture. Transfers, returned owners, identity comparisons, pointer
casts, unknown address uses, borrowed pointer parameters, Shared/Closure capture,
async frames and checked throwing functions are excluded. Constructor and
destructor order remains in SSA. A promoted object receives an entry alloca;
its matching deallocation alone disappears. LLVM can then replace fields with
scalars. This changes selected representations, not the general allocator policy.

Only such unescaped stack roots receive callsite receiver `noalias`. All other
arguments remain unqualified, including potentially overlapping borrowed views.
The call binding retains the exact alloca, activation, callee and operand.
Two mutable views, a C-returned pointer and a foreign-retained pointer supply
no exclusive root proof.

Readonly scalar lazy factories have a further finite case: the selected local
object has no destructor, its fields never change after its constructor, all
receiver uses remain readonly and every lazy factory is readonly, nonthrowing
and nonrecursive. Calls may then use the original initializer body directly.
Repeated evaluation has the same operands, result and effects, allowing LLVM
to remove unused hidden cache state. Side-effecting factories, field mutation,
owned cache values, retry, recursion, cancellation and observed receivers keep
the ordinary first-success gate. Historical LAZY-1 Q4 remains HELD/INCOMPLETE.

Exact virtual calls use the same closed-owner analysis without stack placement
for polymorphic Classes. The original call/accessor identity is retained beside
the derived nominal slot target. Unknown interface arguments and escaping owners
stay dynamic. Physical signatures must match before LLVM emits the direct call.

Shared elision is narrower: a fresh explicit acquisition establishes strong
count one; only responsibility bookkeeping may precede an unused clone and
its immediate balanced cleanup in the same block. There is no overflow,
observer, borrow, callback, weak operation, suspension or intervening execution
in that interval. The compiler removes that increment/decrement pair while
preserving source ownership events. Field-based clones, unknown counts and
used temporaries retain their guards and reference count effects.

Primitive permission values live in a stage-independent source protocol;
native vector-memory plans use native physical shapes, without semantic type
dependencies. Standalone native compilation tests enforce this boundary.

SSA verifiers recompute each claim against current bodies. Native plans retain
private origins, exact instruction/target ordinals and sealed admission.
Original LLVM artifacts retain attributes, complete body order, operands,
predicates, memory qualifiers and call conventions without retaining upstream
graphs. The optimized LLVM clone is independently verified; it may infer its
own legal facts. Original artifact identity checks do not pretend to prove
source correspondence for arbitrary LLVM rewrites.

`ASTRA_EXPLAIN_OPTIMIZATIONS=1 --dump-ssa` exposes the facts without changing
ordinary dumps. `ASTRA_TEST_OPTIMIZATIONS=on|off` controls only these new facts
and transformations, defaults on for O1/O2 and off for O0, and rejects other
values. It does not alter LLVM's selected optimization level or FP policy.
The raw lowering audit may force it on at O0; performance pairs use the same O2
pipeline. Source-debug spans remain attached to original operations. No new
aggregate variable-location promise is made for promoted objects.

Qualification uses A93 packets, A94 stream metadata, A95 dynamic/exact/generic
and Closure/Shared/Weak processing, seven independent mutation tests, and four
same-O2 application ablations. See the
[optimizer guide](../language/semantic-optimization.md) and
[qualification recipe](../../tools/qualification/numerical-optimization-11.md).
The metadata semantics follow the primary
[LLVM 22.1 language reference](https://releases.llvm.org/22.1.0/docs/LangRef.html#parameter-attributes).
