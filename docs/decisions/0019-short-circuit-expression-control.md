# 0019: Short-circuit expressions produce control flow

Accepted for ASTRA-SHORTCIRCUIT-1, following accepted LOOPCTRL-1 commit
`4ada4088aa35e98fa09c38c01c6fa6b1fe5bfbce`.

`&&` and `||` are control-flow-producing expressions. They have explicit syntax,
checked, and Core identities separate from eager binary operators. Both operands
require the canonical semantic bool type; the result is bool. There is no
integer truthiness or conversion.

The left operand always executes first. For AND, false supplies false without
executing the right operand; true requires evaluation of the right operand and
uses its result. For OR, true supplies true without executing the right operand;
false requires evaluation of the right operand and uses its result. Call and
trap suppression, including always executing the left operand, are observable
language semantics. They do not depend on optimization or backend folding.

Runtime short-circuiting never suppresses static checking. The analyzer visits
both operands, including an unknown callee or out-of-range integer on a
statically skipped RHS. Division by zero remains a runtime trap and is valid
source in such a RHS. Neither constant-valued left operands nor either edge of
their branch are folded by this milestone's Astra stages.

Core owns a structured `CoreShortCircuitValue(operator, left, right, type, span)`.
Its children describe conditional evaluation, not an eager operand list. Core
verification checks AND/OR identity and exact bool operand/result types, without
constant evaluation or CFG reasoning. Syntax and checked nodes may die after
construction; Core still verifies, dumps, and retains source provenance.

CFG normalizes this expression using ordinary blocks, Branch, and
ConditionalBranch. Each operator first reserves a dedicated evaluation-entry
block and branches into it. Lowering the left operand may further split that
region. Only afterward does the operator allocate and initialize a bool
`CfgTemporaryPlace`, false for AND or true for OR. It reserves RHS and join
blocks. AND branches true to RHS and false to join; OR branches true to join and
false to RHS. The complete RHS region stores its result into the temporary and
branches to join. The enclosing expression continues there with Load(temporary).

The function owns these Places in a separate `temporaries` array. They have a
semantic type, provenance, and deterministic per-function construction ordinal,
but no source name, LocalSymbol, source-local ordinal, or back reference. Nested
left operands allocate their own temporaries before their enclosing operator.
Source-local ordinals remain unchanged. CFG verifies unique ownership/ordinals,
bool type, exactly one initialization, and ordinary load/write type agreement.

Temporary storage bridges pre-SSA expression values only. Generic scalar Place
promotion handles locals and temporaries through one definitions/frontiers/
renaming algorithm with exact CfgPlace object identity. No CFG phi, manual
short-circuit merge, SsaLogicalAnd, or SsaLogicalOr exists. Temporary Places and
Initialize/Store/Load disappear; ordinary SSA block parameters carry the result.
Parameter order is ascending source-local ordinal followed by ascending temporary
ordinal. Synthetic debug origins say `temporary #N`; debug metadata never
substitutes for promotion identity and retains no CFG object.

The dedicated evaluation entry is necessary for loop availability. A while
header and every continue target remain outside the temporary's initialization
block. Generic initialization-dominance filtering therefore excludes the header
from that Place's merge domain. The condition is freshly evaluated each time;
the temporary never becomes fictitious incoming loop state. Break continues to
target the exact loop exit. No undef, poison, arbitrary initial value, liveness
analysis, or pruned SSA may be introduced to repair an unavailable temporary.

Expression lowering uses one builder current-block authority. Every enclosing
initializer, assignment, return, conditional, loop, or call consumes the value
at its new continuation. Earlier trap-capable operands are materialized before
later calls or short-circuit regions. Earlier call/evaluation results may cross
blocks only when their definition precedes every incoming path. This concrete
CALL-1 extension is needed for `consume(left(), a && right())` and
`consume(x / y > 0, a || b)`. Keeping results block-local would require unrelated
storage bridges, including int temporaries; moving dominance construction into
CFG would change the standalone boundary. Instead, CFG verification checks
paths from the function entry and disconnected source roots, rejecting bypasses,
foreign definitions, use before definition, and rootless availability. The
existing SSA dominance/frontier implementation remains unchanged.

LLVM consumes ordinary SSA branches and bool block parameters, producing `br i1`
and `phi i1`. Source logical operations never become eager LLVM `and`/`or`.
Existing integer division overflow guards may still contain an internal `and`.
RHS traps/calls stay on their physical RHS paths; a trap-split RHS supplies the
phi from its actual final physical continuation, preserving LLVM-1's physical
end-block authority. NABI signatures and implementation need no change.

Function arrays remain the sole owners of blocks; successor targets use
GLib.WeakRef. Neither temporaries nor definition-result references introduce
strong graph cycles. Standalone Core, CFG, and SSA plus stage and cyclic lifetime
tests qualify these boundaries. Frontend through NABI remain LLVM-free.

Bitwise operators, compound logical assignment, `?:`, assignment expressions,
constant/branch folding, SCCP, general liveness/pruned SSA, other loop forms,
C ABI, ownership, objects, generics, SIMD, and async remain out of scope. No
external dependency or imported Vala/LLVM-v2 implementation is needed.

See [language semantics](../language/short-circuit.md),
[the lowering inventory](../ir/expression-control-flow.md), and
qualification.
