# Retained SSA to native LLVM, bounded version 1

`llvm_lower(program, origin, profile)` accepts an independently revalidated
`SsaProgram` and the exact original owner instance. It retains that owner's
shared identity. Output requests require the original retained program again;
identical source bytes from another owner do not qualify. Context, builder,
module, target machine, target data, handle vectors, type maps and integrity seal
belong to one internal `LlvmModule`. The returned `LlvmArtifact` owns that implementation in a private field and exposes no raw references. C0 supports private fields but not private methods or throwing ordinary constructors; invalid direct implementation construction is inert, and build rechecks proof/owner/state before opening LLVM resources. `close` is idempotent and makes output impossible.
Target data dies before context types. No raw handles are returned by this API.

The current qualified profile is LLVM 23.1.4, GNU/Linux x86-64, host data layout, PIC,
O0 or O2. All same-module application functions originate in Astra lowering;
only libc calloc/free and LLVM's trap intrinsic are external. No C source or C0
application object is generated or called. C0 builds the component itself and
independent executable oracles. The C adapter performs mechanical C ABI/text,
resource and pointer-vector operations; all source/type/SSA/effect choices are
Astra algorithms. Current C0 cannot address dynamic pointer-buffer elements or
import unsigned 32-bit C arguments. Bounded nonnegative counts use bit-compatible
C int registers, and the 1024-entry C pointer vector only copies Astra-selected
handles. It contains no semantic or program lowering.

Accepted machine values are exact integer widths, bool and void; native nominal
record storage and primitive owned buffer carriers `{ptr,i32}` are supported.
Record field order comes from checked nominal declarations. Private functions use
first-class LLVM aggregate arguments/results; borrowed record arguments use their
exact authoritative place address. This is a private stage ABI, not an exported
C0 module or general foreign ABI. `main` is C `int(void)`. `noinline` deliberately
keeps function bodies and calls available for qualification while O2 runs the
standard LLVM O2 pipeline; it grants no semantic optimization premise.

One reachable LLVM block corresponds to each retained SSA block, and each exact
incoming edge receives an extra edge block. PHIs use those distinct edge blocks,
including parallel/back edges. Dead predecessors are omitted, with no undef or
poison substitute. Definitions are scheduled by available typed operands; all
PHIs exist before ordinary instruction emission. Final branch/return terms and
incoming arguments are installed only after definition mapping completes.

Integer arithmetic wraps without nsw/nuw. Core opcode 2 retains both signed and complemented integer literals; the exact +, - or ~ token governs its bits and other prefixes defer. Signedness governs predicates,
extensions and division. Casts preserve mathematical low bits, signed widening
fills ones and unsigned widening fills zeros. Division by zero traps; signed
MIN/-1 yields MIN and remainder zero. A selected safe divisor prevents constant
folding from manufacturing poison. Shift counts are guarded against negative or
>= width before normalization. Floating point, strings, pointer-valued source
operations, special policies, foreign/indirect calls, generic/async/exception
scope and nonprimitive buffer elements defer. Owning replacement is explicitly
deferred rather than leaking an old owner. Other upstream deferrals persist.

Storage roots and nominal field pointers stay explicit. Owning initialization and parameter stores are volatile implementation storage: the required allocation/cleanup observations must survive the standard LLVM O2 pipeline. This restricts optimization, grants no alias/overflow premise and introduces no source-level atomic or volatile API. The separate checker verifies the owning-store marker. Each owned buffer leaf
has a separate armed bit initialized at function entry. Transfers disarm source
leaves; initialization arms destination leaves. Exact CFG cleanup blocks branch
on that bit, free only on the taken path and disarm. Scope exit and loan markers
retain upstream order and proofs. These are ownership states, not copyable PHIs
or a noalias assertion. Struct GEPs explicitly clear LLVM's entire default no-wrap flag set (inbounds, nusw and nuw), and the independent Astra checker verifies zero GEP flags.

The separate read-only `check.astra` compares source literals, types, entry/block
and exact-edge terms, PHI values, promoted copies, loads/stores, basic arithmetic
and predicates, and direct call operands against retained SSA. Guarded arithmetic
sequences additionally have independent raw IR and executable/fatal oracles;
that checker does not claim to prove their whole arithmetic recipe. A byte-exact
module seal protects the checked pre-optimization module against subsequent
mutation. It is an integrity check, not an independent semantic certificate.
LLVMVerifyModule runs before sealing and every public write. Writes optimize a
private clone, verify it again and obtain real IR/object bytes through LLVM.
The independent llvm-as/opt executables parse/verify captured IR during tests.

Failure stages are LLVM_INVALID_UPSTREAM, LLVM_DEFERRED, LLVM_INVALID_IR,
LLVM_TARGET_UNAVAILABLE, LLVM_RESOURCE_EXHAUSTED and LLVM_OUTPUT_FAILURE.
Arenas inherit SSA's 65536 rows/1024 blocks; type recursion is 64, record fields
256, work 8 million and public output 16 MiB. Output uses a same-directory private
temporary and atomic rename only after successful verification and size checks.
Pre-existing destination content survives failure. No failed request publishes
an object or executable. Linking/execution failures are separately classified by
the focused consumer, which records exact commands and OS outcomes.

Test modes: `--llvm-raw O0|O2 OUTPUT SOURCE...` writes checked pre-optimization IR;
`--llvm-ir` writes optimized verified IR; `--emit-obj` emits actual objects.
The separate test consumer also exercises `--mutate-llvm`, `--llvm-limits` and
`--llvm-lifecycle`. Existing admission/Core/CFG/SSA modes delegate to the frozen
predecessor consumer with only its entry function renamed. They are compared
byte-for-byte for all 80 inherited sources. Test mutation methods expose no raw
handle and never turn a fault into authorized output.

No Stage 1, full compiler, broad language/backend or other target qualification.
The former 73-source compiler closure and its zero whole-program proofs remain
historical and deferred. See the focused test plan and source-bound results.

LLVM 23 uses separate conditional/unconditional branch opcodes and successor-ordered
conditional block operands. The independent checker validates each opcode and the
original exact-edge polarity. Historical LLVM 22 receipts remain historical; see
[ADR 0169](../../../docs/decisions/0169-llvm-23-migration.md).
