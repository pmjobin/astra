# Host-native execution v0

ARGS-1 additionally accepts native `int main(string[] args)` with an explicit [hosted argument snapshot provider](hosted-arguments-v0.md). An independent entry plan binds the exact source symbol and verified text-slice-v10 signature. Only its wrapper prepares/disposes arguments; ordinary native calls remain ordinary calls. Existing `int main()` has no capture or validation cost.

NUM-CONV-1 lowers scalar integer→floating directly with sitofp/uitofp under the
existing nearest/ties-even environment. Floating→integer uses ordered exact range
guards and a non-unwinding trap before fptosi/fptoui, preserving truncation-first
fractional edges and excluding NaN/infinity. Initial IR sanitizes invalid operands
with a validity select; optimized IR must preserve trap semantics. No runtime
helper, libm, allocation, ABI profile or fast-math change is required. See
[conversion IR](../ir/numeric-conversions.md) and qualification.

[Hosted buffer allocation v0](host-buffer-allocation-v0.md) qualifies direct
zero-initializing allocation/deallocation on x86-64 Linux. Explicit native buffer
operations request the static backend; buffer-free programs acquire no allocator
symbols or dependency. Unqualified allocator targets fail before object emission.
The language operation remains target-neutral and does not require a general
Astra runtime library. Numeric contraction/FMA rules remain unchanged.

OWN-FIELD-1 requires no new LLVM ownership mechanism. Native class fields use
the existing Resource `ptr` representation; replacement lowers to incoming
capture, old pointer load, null-guarded direct release and new pointer store.
Destruction releases current fields in reverse declaration order after normal
user deinit, including replacements performed during deinit. Object result and
parameter ABIs are unchanged. No heap, object copy, header bit, destructor
pointer, active bitmap or dynamic dispatch is introduced. See
[owned-field IR](../ir/owned-resource-fields.md).

[Native aggregate-v7](../abi/native-aggregates-v7.md) adds flattened copyable struct
parameters/results. LLVM parameters are ordinary leaf channels. A single-leaf
result returns the leaf directly; multiple leaves use a backend-only LLVM literal
struct built/extracted at call/return boundaries. This carrier is never Astra
semantic/Core/CFG/SSA aggregate authority. No default hidden struct pointer,
sret, byval, memcpy/memmove or aggregate alloca is needed. Host spills remain LLVM
choices; native transport does not introduce C aggregate interoperability.

[GEN-1](../ir/generics.md) finishes specialization before CFG, so the backend
receives only ordinary concrete functions and direct calls. Core records
`astra.gen.D.I` identities; LLVM retains existing deterministic internal
`astra.fn.N` symbols. Repeated canonical keys emit once; unused definitions emit
nothing; same-representation distinct instances remain separate before optimization.
No runtime type arguments, dictionaries, boxes or dispatcher are emitted.
Generic qualification records O0/O2/FMA, exact floating
transport, vector, recursion, property and ownership machine/runtime evidence.

PROP-1 emits [computed property accessors](../ir/properties.md) as deterministic
internal direct fastcc functions. Nullable getter access guards before entry;
nullable setter access guards before RHS execution. Live `this` has no entry
check. F64 uses double arguments/results, retaining strict operations without
fast-math, contraction, unsafe alias attributes or property runtime machinery.
Property qualification records native/O2 execution,
exact transport, physical predecessor verification and x86-64 machine evidence.

F64-1 qualifies [binary64 scalar execution](../language/f64.md) on the same
default LLVM 22 x86-64 Linux configuration: empty CPU/features and code-generation
optimization NONE. Double arithmetic, comparisons, fpext/fptrunc, calls, recursion,
control flow, storage, slices and owned object results obey upstream exact rules.
Constants use compiler-owned integer bits then LLVM constant bitcast; no decimal
parser selects their value. Native boundaries use [fp64-v6](../abi/native-fp64-v6.md).
No fast-math or contraction is granted; FMA-capable and O2 runs are qualification
audits. The inherited foreign execution contract requires nearest/ties-even,
masked exceptions and preserved subnormals. Other targets remain unqualified;
no SH-4 lowering decision is made. See F64 evidence.

[Owned object results](../ir/object-results.md) lower to internal fastcc PTR functions with first `ptr %result.storage`. The caller reserves exact candidate storage, the factory calls the existing void constructor directly there, and caller cleanup guards/destructs the returned PTR. Factories create no returned-object alloca or copy. Forwarded/null results leave candidates unused. O2 and machine evidence appear in qualification.

OBJ-OWN-1 retains lexical `alloca %astra.class.N` construction and passes its
original PTR into consuming native calls. Shared OWNBOUND commit disarms the
caller capability; a non-forwarded callee runs null-guarded exact fastcc deinit.
No storage copy, relocation, allocator/deallocator, object header, refcount or
ownership flag is emitted. `noalias`, `nonnull`, `readonly`, `byval` and `sret` are
not inferred. Tests exercise same-object borrow+own at O2, mixed cleanup order,
forwarding, conditional transfer and non-unwinding traps. See
[object ownership IR](../ir/object-ownership.md) and
qualification.

OBJ-BOUND-1 needs no new LLVM lowering path. NABI maps a validated borrowed
ClassType parameter to PTR, then ordinary internal fastcc entry binding supplies
one incoming SSA reference. There is no entry null guard, parameter object alloca,
memcpy, destructor registration or extra lifecycle call. Existing field/method
validation traps only at use, preserving RHS/argument order. Emission adds no
`nonnull`, `noalias`, `readonly`, `byval`, `sret`, `dereferenceable` or `nocapture`.
Caller ObjectStorage cleanup remains lexical and observes borrowed mutation.
Default/O2 execution, alias sensitivity and x86-64 machine evidence are recorded
in OBJ-BOUND-1 qualification.

OBJ-LIFE-1 emits `define internal fastcc void @astra.ctor.N(ptr %this, ...)`
and `@astra.dtor.N(ptr %this)`. The caller owns the lexical object alloca; init
initializes it with exact field GEP/store operations and returns no reference.
Deinit calls always use the original storage address, even after reference nulling
or rebinding. The unified lexical planner places mixed Resource/object calls at
normal scope exits after any return-value evaluation. Calls remain effectful under
O2. No allocator, lifecycle header/flag/stack, destructor registration, landingpad,
personality or unwinder exists. A trap stops subsequent cleanup. Execution and
x86-64 evidence are in OBJ-LIFE-1 qualification.

OBJ-1 lexical construction uses compiler-private `%astra.class.N` layouts and
one object alloca per construction site in an activation. Field initialization
stores in source-written order; reference copies use the same opaque ptr and emit
no object memcpy or extra alias alloca. Identity uses `icmp eq/ne ptr`. Empty
classes have exactly `{ i8 }` backing layout to preserve distinct live addresses;
that byte is not a source field or runtime metadata. Explicit SSA guards lower to
null comparison, trap and valid continuation before field RHS or method argument
effects. Class methods are internal direct fastcc calls to
`astra.class.method.<class-ordinal>.<method-ordinal>`, with PTR first and existing
v0-v5 explicit channels. `this` needs no guard. No noalias, vtable/vptr, RTTI,
refcount, GC header, descriptor, allocator or deallocator is added. Normal/O2
identity and alias workloads and x86-64 machine evidence are recorded in
OBJ-1 qualification.

METHOD-1 emits [native struct methods](../ir/methods.md) as deterministic
`astra.method.<struct-ordinal>.<method-ordinal>` internal fastcc definitions.
The first physical input is `ptr %this`, followed by ordinary explicit scalar,
vector, Resource or flattened slice parameters. Calls are exact/direct and pass
the existing caller storage address. Callees allocate no receiver object or
copy, and field access uses backend-private exact struct GEP/load/store. Receiver
field access omits nullable-pointer checks; general `p->field` still guards.
No receiver noalias/readonly/nonnull attribute, vtable, RTTI or runtime method
descriptor is added. A method named `main` cannot serve as executable entry.
Qualification includes O2 alias controls, receiver
alloca audits, scalar/vector/slice/recursive machine code and owned boundaries.

SLICE-1 uses a backend-private `{ ptr, i32 }` for local slice values. Construction
uses insertvalue; length uses extractvalue; branch/loop merges use aggregate phi.
Subrange guards precede element GEP, with a null-base empty edge containing no
GEP. Index guards precede base use and exact scalar/vector GEP/load/store.
Current IntegerTypes losslessly extend to i64 for mathematical validation; count
narrows only after proving its <=1024 bound. All slice GEPs are plain. Alignment
comes from backing array layout, and guard/empty splits update the established
physical final-block authority. No ABI, runtime helper or native slice boundary
is introduced. See [slice values](../ir/slice-values.md) and
qualification.

ARRAY-1 realizes [local array storage](../ir/array-places.md) as `[N x T]`
allocas, including `[N x <M x T>]` for vector elements. Captured initializers
store in ascending element order. Dynamic exact integer checks trap before
GEP/load/store and before RHS effects; only valid indices zero-extend to i64
for plain GEP. No inbounds promise, semantic pointer arithmetic, new runtime
helper or ABI channel is added. Target layout supplies alignment. Existing
LlvmBlockState.end remains the phi predecessor authority after bounds guards.

VEC-MEM-1 reuses exact fixed-vector LLVM types for addressable alloca, whole
load and whole store. Numeric vector pointers remain opaque ptr, with DPTR null
guards before access and the same final-block phi predecessor authority. LLVM
supplies alignment, audited against the configured target DataLayout for every
supported shape; no frontend 16-byte rule exists. Load/store adds no f32
arithmetic or fast-math flags. Machine legalization may split memory operations
without creating source lane operations or an atomicity promise. Execution
remains qualified for default x86-64 Linux. See vector-memory qualification.

DPTR-1 lowers supported scalar and existing struct typed pointers through
ordinary native PTR and LLVM opaque ptr. Address-taken integer/f32 locals use
entry allocas of exact i8/i16/i32/float type, initialized at the source
declaration point; direct and indirect reads/writes use that same storage.
Unaddressed locals retain Astra SSA promotion. Every scalar pointer access
reuses the existing explicit nonnull guard before its physical load/store,
including writes. The null path traps without unwinding. Physical final-block
tracking remains authoritative for branch/loop/short-circuit phi predecessors.

Plain memory introduces no numeric conversion, fast math, GEP, readonly, or
noalias attribute. Signedness does not alter storage width; float loads/stores
preserve binary32 bits. Target-selected natural alignment is justified by
direct initialized local construction and compatible native pointer forwarding,
without a stable numeric alignment/layout or pointer-width promise. C typed
pointers and unaligned primitives remain deferred. The
DPTR qualification records exact width/null/phi audits,
default and O2 execution, machine evidence, and baseline-compared Valgrind.

BIT-1 lowers bit operations to exact scalar/vector and/or/xor and complement via
xor all-ones. Dynamic counts are checked in their own integer width/signedness
before shl/ashr/lshr; invalid edges trap and end unreachable. Only valid counts
are physically normalized and, for vectors, splatted. These are backend details,
not Astra conversions or count-vector types. No source shift has nsw/nuw/exact.
LlvmBlockState.end preserves actual guard-continuation phi predecessors.
Byte-vector legalization may scalarize. See [IR contract](../ir/bitwise-shifts.md)
and qualification.

VEC-DOT-1 qualification covers exact integer
whole-vector dot/MAC modulo its scalar accumulator width and ordered non-fused
f32 dot/MAC on default x86-64 Linux. Integer lowering widens by source
signedness and multiplies/adds without overflow flags. Physical widened LLVM
vectors may exceed source shape limits. F32 lowering uses vector fmul and an
explicit ascending scalar fadd chain, with no fast math, unordered reduction or
FMA. FMA-capable optimized machine audits retain the same results. Existing
qualification restrictions, native channels, process entry and linkage remain.

VEC-DSP-1 qualifies saturating arithmetic,
widening, packing and interleave on the existing default x86-64 Linux vector
execution path. Other vector-emission configurations remain unqualified under
VEC policy. LLVM signed/unsigned saturation intrinsics, half shuffles plus
source-signedness extension, exact clamp/truncate packing and structural
interleave are realizations of Astra semantics. Machine SIMD matching is recorded
but never required. F32 interleave introduces no arithmetic or fast-math flags.

VEC-LANE-1 qualifies splat, extract, insert, shuffle and eager vector select
under the same default x86-64 Linux policy. Splat seeds a defined zero vector,
inserts lane zero and shuffles it to every lane. LLVM extractelement,
insertelement, shufflevector and vector select copy exact values without
undefined/poison selected lanes, new fast-math flags or FMA contraction.
Instruction selection may scalarize or spill and is evidence rather than a
semantic requirement. See lane qualification.

VEC-1 qualifies fixed-vector and mask execution on default x86-64 Linux, with
empty CPU/features and the existing target-machine configuration. Other native
vector targets reject pending explicit qualification. This is a semantic
qualification, with no hardware SIMD guarantee; target legalization may split or
scalarize values. F32 lanes preserve nearest/ties-even, signed zero, subnormals,
infinities and NaNs, without fast math or multiply/add contraction. The separate
FMA-enabled audit also executes the rounding witness. Vector signatures and owned
Resource/PTR channels coexist; main remains int/i32 main(). See
vector qualification.

OWNBOUND-1 native owned Resource parameters/results retain the existing internal
fastcc pointer ABI. Parameter acquisition uses the incoming SSA pointer, caller
transfer commits define source null immediately before invocation, and return
transfers define source null before lexical cleanup. The backend consumes ordinary
pointer SSA and existing null-guarded cleanup calls; it needs no ownership-specific
calling convention, descriptor, flag or destructor argument. Executable entry
remains exactly `int main()`. C ownership exports and direct owned-call chaining
remain unsupported. Qualification records consume,
null, pass-through, release/move/borrow/rearm, cleanup order, argument order,
recursion, native-result consumption, object/linkage and memory checks.

ASTRA-EXEC-1 extends accepted LLVM scalar lowering into a native executable for
the host running astrac. [ADR 0016](../decisions/0016-host-native-execution.md)
freezes the boundary. The qualified host is Fedora x86-64 with system LLVM
22.1.8; target identity and data layout are discovered, never hard-coded.

```text
source → syntax → checked semantics → Core → CFG/flow → SSA → NABI + CABI
                                                            ↓
                                                  verified LLVM bodies
                                                            ↓
                                      host triple/layout + launch wrapper
                                                            ↓
                                                LLVM verification again
                                                            ↓
                                               target-machine object
                                                            ↓
                                           configured host C driver / CRT
                                                            ↓
                                           atomic executable publication
```

## CLI and entry policy

```sh
astrac program.astra                 # a.out in the current directory
astrac program.astra -o program
astrac -o program program.astra
astrac -o program -- -program.astra   # source spelling begins with '-'
```

SOURCES-1 accepts one or more explicit source files as one program. `-o OUTPUT`
may precede or follow sources and occur once; the output must be nonempty. The parent
directory must exist. Paths with spaces, quotes, punctuation, and shell
metacharacters are passed literally. No `--run`, `--target`, CPU/features flags,
assembly mode, public object-only mode or sysroot is added.
Successful compilation exits 0, prints nothing, and produces an executable.
Source/semantic/flow/entry/backend/emission/link/output failures exit 1;
malformed CLI usage exits 2. Help/version cannot be combined with compilation.

BASELIB-1 adds repeatable `--link-library NAME`/`--link-library=NAME` for explicit
hosted facilities. Names match `[A-Za-z0-9][A-Za-z0-9_.-]*`; paths, empty names,
option markers, control characters and raw flags reject. The generated object
precedes the unified sequence of object/library occurrences, preserving order
and repetitions, with the existing `-o` pair following. All invocation remains
shell-free. Check/dump modes reject link inputs without calling the linker.
There is no automatic `-lm`, `-L`, rpath, package lookup or VAPI autolinking.
Output preservation and temporary cleanup follow the existing transaction.
See [library consumption](../library/base.md) and [math linkage](../library/hosted-math.md).

Executable production requires a source function with exact signature:

```astra
int main() {
	return 0;
}
```

Missing main, non-int main, and main with parameters receive deterministic
program-entry diagnostics: ``executable requires `int main()` `` plus the reason.
An existing malformed entry is diagnosed at its name span. This is a driver
policy, not a language-semantic rejection or reserved lexer spelling.

`--parse`, `--dump-syntax`, `--check`, `--dump-semantics`, `--dump-core`,
`--dump-cfg`, `--dump-ssa`, `--dump-nabi`, `--dump-cabi`, and `--dump-llvm` keep their stage
boundaries and original `MODE FILE` ordering. They do not accept `-o` and need
no entry. In particular, valid library-like functions and otherwise-valid
void/bool/parameterized main functions still pass `--check`. Checking includes
LLVM lowering/verification but creates no target machine and invokes no linker.
`--dump-llvm` stays free of the launch wrapper, triple, and data layout.

## Entry identity and launch wrapper

`Driver.ProgramEntry.resolve` finds the source spelling once in SsaProgram and
returns the exact native SsaFunction, ignoring imported declarations.
LlvmLowering validates separate SSA/NABI and SSA/CABI correspondence
as before, uses the existing identity map, and retains only the selected LLVM
function and function-type handles inside the LLVM artifact. It verifies that
the supplied identity belongs to that program with a zero-parameter int result.
No upstream graph or source provenance survives in the LLVM artifact.

`configure_executable` configures the target and adds exactly one function:

```llvm
define internal fastcc i32 @astra.fn.N() {
	; ordinary Astra body, unchanged by entry selection
}

define i32 @main() {
entry:
	%result = call fastcc i32 @astra.fn.N()
	ret i32 %result
}
```

The default convention is ccc (LLVM's printer omits it). The external wrapper
contains one call and one return; no argument adaptation or language semantics
are added. Astra main remains `NativeLinkage.NATIVE_INTERNAL`, LLVM internal,
fastcc, with NABI channels. A recursive source `main()` call still targets the
internal function. Structural tests use main at a nonzero ordinal and identical
NABI debug names, then inspect LLVM function/call identity directly. A dead
recursive branch allows the same fixture to run normally; bounded live main
recursion needs state unavailable with the present zero-argument language subset.

The shim is private platform launch infrastructure. CABI-1 allows explicit
scalar C imports; CEXPORT-1 adds separate user-requested C export wrappers.
Ordinary Astra calls stay native, and native symbols stay internal. There is no
argc/argv exposure.
No stable native object or executable ABI, local symbol spelling, section
structure, fastcc realization, or separate-compilation compatibility is promised.

## Target and object resources

| Component | Responsibility |
| --- | --- |
| `src/backend/llvm/capi/llvm-target.vapi` | Minimal mechanical LLVM 22 Target/TargetMachine C declarations |
| `llvm-target-machine.vala` | Native initialization, triple lookup, target machine/data ownership, module configuration, object emission |
| `llvm-module.vala` | LLVM module/context ownership, borrowed entry handles, wrapper insertion, verification |
| `llvm-lowering.vala` | Bind the selected entry using existing SSA/NABI/LLVM correspondence |
| `src/driver/program-entry.vala` | Source entry policy and diagnostics |
| `host-linker.vala` | Platform driver argv invocation and link failure diagnostics |
| `executable-output.vala` | Private temporary paths, publication, cleanup |
| `native-compilation.vala` | Configure, emit object, link, publish |
| `src/driver/meson.build`, `linker-config.vala.in` | Build-time host driver discovery and generated argv |
| `src/main.vala` | Public stage/compilation CLI orchestration |

LLVMInitializeNativeTarget and LLVMInitializeNativeAsmPrinter run once via
GLib's initialization primitive. No all-target, assembly-parser, disassembler,
or JIT initialization occurs. LLVMGetDefaultTargetTriple supplies the triple;
LLVMGetTargetFromTriple resolves it, reporting LLVM's error without fallback.

LLVMCreateTargetMachine receives the selected target, default host triple,
empty CPU (LLVM target default), empty features, LLVMCodeGenLevelNone,
LLVMRelocPIC, and LLVMCodeModelDefault. These request broad host compatibility
without machine tuning. LLVMCreateTargetDataLayout returns separately owned
target data. LLVMSetTarget and LLVMSetModuleDataLayout configure the module;
the latter copies the layout, so the module does not borrow target data.
LLVMCopyStringRepOfTargetData supplies reporting text. All owned LLVM message,
triple, layout, lookup-error, and emission-error strings use LLVMDisposeMessage.

LlvmTargetMachineArtifact disposes target data and then its target machine.
Its lifetime is independent of LlvmModuleArtifact, which still disposes module
before context. Target handles never enter source, semantic, Core, CFG, SSA,
or NABI representations. Layout never defines semantic scalar types.

`target.configure(artifact)` also supports an internal object without a wrapper.
`target.emit_object(artifact, path)` requires matching triple/layout, verifies
again, and uses LLVMTargetMachineEmitToFile with LLVMObjectFile. It copies and
disposes LLVM error text, removes a failed object output, and throws a backend
emission error. Its caller owns the temporary output path. No textual assembly
intermediate or explicit Astra optimizer/pass pipeline is used. LLVM's machine
code generator performs the transforms necessary to emit machine instructions.
The LLVM 22 system headers qualify the bindings; the public
[target C API reference](https://llvm.org/doxygen/group__LLVMCTarget.html)
documents this family of operations.

## Link and output transaction

Meson takes its native C compiler command array, removes an explicit automatic
ccache/sccache prefix, resolves the driver executable with native program
discovery, preserves any configured compiler arguments, and generates a Vala
argv array. A compiler path that is itself a toolchain wrapper remains that
configured path. Nothing assumes `/usr/bin/cc`. The build summary records the
selected driver. Meson cross builds are rejected.

The effective command is the array:

```text
[configured-driver, configured-arguments..., absolute-temporary-object,
 absolute-user-object-0, absolute-user-object-1, ...,
 "-o", absolute-temporary-executable]
```

GLib.Process.spawn_sync passes this array directly. There is no shell command
string, quoting/reparsing, direct `ld`, optimization flag, or Astra runtime
library. PIC works with the qualified host driver's normal PIE defaults and CRT.
Failure reports the driver, normal exit status or abnormal wait status, stderr,
and nonempty stdout. Successful linker output is captured without normal noise.

ExecutableOutput creates `.astra-exec-XXXXXX` with private permissions in the
destination's parent directory, holding `program.o` and `program`. Source
checking, entry resolution, lowering, and target/wrapper verification complete
before temporary creation. After successful linking, g_rename publishes the
executable over the final path on the same filesystem. A pre-existing file
survives every failure before publication. A publication failure is its own
driver/output diagnostic. Destruction unlinks temporary files and removes the
private directory on all ordinary success/error paths. No `/tmp/astra-*` files
are created by astrac, and TMPDIR cannot force a cross-filesystem publication.
The host driver may use its own temporary service. Forced termination and
power-loss durability are outside ordinary cleanup guarantees.

## Runtime contract and qualification

ASTRA-LOOP-1 uses this executable path unchanged. Cyclic block arguments lower
to LLVM phis and branch backedges before the existing target/object/link stages.
No loop runtime, NABI channel, new flag, or optimizer is needed. Native tests
qualify zero/one/10,000 iterations, accumulation, per-iteration body locals, bool
even/odd state, condition/body calls, nested loops, and conditional returns.
Trap-split bodies use correct physical backedges; a divisor reaching zero
on a later header visit traps then. A 144-result bounded recurrence matrix
compares machine wrapping with AstraIntValue. A nested-loop artifact survives
upstream destruction and object emission, then executes after the LLVM module
and target machine die. See [loop qualification](../toolchain.md#astra-loop-1-qualification).

SCALAR-1 remains the oracle: wrapping add/subtract/multiply/negation, signed
comparisons, division truncating toward zero, dividend-signed remainder,
INT_MIN/-1 yielding INT_MIN, and INT_MIN%-1 yielding zero. Parameterized helpers
exercise these operations in actual machine code. The bounded differential
matrix compares 14 representative operand pairs through 166 checks in one
executable, using AstraIntValue for every expected scalar result.

Zero division/remainder is non-returning: no normal result and no continuation
past the operation. Runtime tests reach the trap through parameterized calls
and require abnormal termination on the qualified POSIX host, without asserting
a signal number. LLVM may use a native trap instruction or abort-like fallback;
uniform signals are not a language promise and need no Astra trap runtime.
CABI-1 observes ordinary foreign-call order through C-side state. Ordering before
a non-returning trap remains a structural LLVM check, because the same process
cannot query that state after trapping.

Tests compile through public astrac and run independent child executables after
the compiler exits. They cover exit 0/42, scalars, bool channels/joins, branches,
SSA phis (also after division), direct/forward calls, self/mutual recursion, and
choose-call. Structural tests verify the wrapper before emission. Weak references
prove all upstream graphs die before object generation, LLVM module/context and
target-machine artifacts die before linking, and the object/transaction die
before execution. Optional readelf checks relocatable host format, local native
functions, external wrapper, and final executable format. Tests force real LLVM
file errors, real missing-wrapper link failure, partial linker output and status
capture, spawn failure, publication failure, and pre-existing-output preservation.
Controlled temporary directories prove cleanup with spaces and punctuation.

Upstream and standalone test executables remain LLVM-free. astrac, LLVM backend
tests, and EXEC tests deliberately use the same qualified LLVM 22 library.
See [toolchain evidence](../toolchain.md) for the exact target, layout, driver,
test counts, linkage audit, and Valgrind results.

No cross compilation, runtime library, stable native symbols, optimizer
pipeline, multi-file model, strings, owned function boundaries,
objects, or other new language constructs are introduced.

## Loop-control execution in LOOPCTRL-1

Native qualification exercises simple break (result 7), bounded odd sums,
multiple continue/break sites, zero iterations, old/new edge values, inner-only
break/continue, body-local availability, and calls before transfers. Break-state
checks distinguish pre-loop 5 from entered-loop 10; continue-state checks
distinguish a carried 10 from fallthrough 20. Condition calls are reevaluated.
Division/remainder transfer paths execute their guards before branching; zero
divisors still trap. Source-preserved post-transfer calls/stores never execute.

A second 144-case recurrence uses two continue sites and alternate wrapping
updates, comparing native results to AstraIntValue over six seeds, six bounded
iteration counts, and four multipliers. It uses no C signed-overflow oracle.
Existing object/link/launch behavior and NABI signatures are unchanged. Nested
native artifact lifetime tests release upstream graphs before execution.
See [qualification](../toolchain.md#astra-loopctrl-1-qualification).

## Short-circuit runtime qualification

SHORTCIRCUIT-1 executes all four AND and all four OR truth-table combinations.
False AND and true OR suppress direct and call-based zero-divisor traps; true
AND and false OR require abnormal trap termination. A trapping LHS always runs.
Nested/chained expressions, initialized/reassigned bool locals, call arguments,
bounded loop conditions, break, and continue are covered. Continue tests reach
both a final skipped zero divisor and a newly required zero divisor, proving full
condition reevaluation. Artifact lifetime tests release CFG/SSA/NABI/compiler
resources before executing the result. See qualification.

## CABI-1 link objects

`astrac [--link-object OBJECT]... FILE [-o OUTPUT]` accepts repeatable relocatable
object paths before or after the source. Driver layers carry the ordered list
through NativeCompilation and ExecutableOutput to HostLinker. Final argv is:

```text
configured-host-C-driver <Astra-temporary-object> <user-object-0> <user-object-1> ... -o <temporary-executable>
```

Invocation is shell-free. Paths become absolute without collapsing symlink/..
pairs; spaces and metacharacters stay literal. Object basenames starting with
`-` can use `./`. There is no archive, library search, arbitrary flag forwarding,
`-l`, `-L`, or pkg-config policy. Check/dump modes reject link options and never
attempt external resolution; an absent external symbol is legal through LLVM
verification and fails only at executable linkage.

Unresolved symbols and missing object files produce link-phase failures, preserve
existing output, and clean all temporary paths. Imported `main` does not satisfy
native entry requirements. Companion C objects use int32_t and bounded static
state to qualify effects/order; repeated objects, paths with spaces, short-circuit,
loops, recursion, and destruction before linking are covered by runtime tests.
See [C interop](../language/c-interop.md).

## CEXPORT-1 ingress and executable boundaries

Export wrappers already exist in stage LLVM, so --dump-llvm shows them and
--check generates/verifies them without linking. NativeCompilation adds the
separate process-entry wrapper, emits all global export wrappers and local native
implementations, and uses the existing transactional link flow unchanged.

An exported main is valid in stage modes but executable ProgramEntry validation
reports
``C export symbol `main` conflicts with the executable entry wrapper``. This occurs before LLVM
launch-wrapper/output creation. Direct backend collision checks defend the same
boundary. Imported main still cannot satisfy the native entry requirement.

Manually declared C companion callers qualify int/void ingress, wrapping,
while/break/continue, &&/|| effect suppression, bounded recursion, native calls to
the same exported function, C → Astra → C round trips, C-observed left-to-right
order, and abnormal divide-by-zero termination. Object audits require local
astra.fn.N and global export symbols, with C undefined references naming only
the external wrappers. Lifetime tests release SSA/NABI/CABI before object emission
and LLVM before linking/calling the exported function. Failed links and main
collisions preserve prior output and clean temporaries. No shared-library mode,
header generator, alias mechanism, or production dependency is added.
See qualification.

## PTR-1 execution

Opaque pointers use the existing target/data-layout and object/link pipeline.
No semantic pointer width or linker option is added. `--vapi` and `--link-object`
remain independent; pointer headers supply neither layout nor libraries.
`--check` and LLVM dumps succeed without symbol implementations; symbol absence
is still a link-time error with transactional output preservation.

Test-only C objects return addresses of two static objects or NULL and compare
identities without allocation/free or Astra dereference. Runtime fixtures cover
native copy/recursion, null both ways, equality, branch/null/loop SSA joins,
C export echo and both roundtrip directions, aliases/nonexistent headers, and a
short-circuit null guard whose C counter proves skipped evaluation. Native
functions remain internal/fastcc and external C wrappers remain explicit.
See PTR-1 qualification.

## Native local structs

Non-address-taken STRUCT-1 field Places disappear through generic scalar SSA promotion before the
backend boundary. LLVM receives only existing i32/i1/ptr values and ordinary
field merge/loop phis. No LLVM struct type, extractvalue, insertvalue, aggregate
alloca, size/alignment, or field-offset calculation is required. NABI/CABI remain
scalar/pointer-only because struct parameters and results reject semantically.
The original scalarized STRUCT-1 path is unchanged.

Execution tests cover basic fields, mutation, recorder order 21, single/multiple
field joins, zero/one/many loop iterations, bool fields, pointer identity, null
short circuit, and break/continue. Structural tests verify scalar phi predecessors,
trap ordering, identical LLVM for representative scalar equivalents, independent
stage lifetime, and object/linkage authority. See STRUCT-1 qualification.

## TPTR-1 addressable native structs

Typed native pointer parameters use existing PTR/LLVM ptr without new channels.
Only addressable locals or indirect field access require a backend-private
struct type. One entry alloca per addressable local supplies exact direct field
GEPs; indirect fields use the pointee's exact struct type and field ordinal.
Loads/stores remain scalar, with no whole aggregate copy or stable layout.

Indirect accesses branch through explicit null guards to llvm.trap/unreachable
or a non-null GEP/access continuation. Store guards follow RHS effects. Physical
end-block tracking preserves phi predecessors after null splits, including loops
and short-circuit joins. No pointer conversion or parameter alias/null/access
attribute is inferred. See [native struct storage v0](native-struct-storage-v0.md).

Qualification executes caller mutation, before/after loads, same-object aliases,
distinct locals, nullable pointer locals, recursion, loops with break/continue,
and both skipped and required short-circuit dereferences. Read/write null cases
terminate abnormally. Stage tests release SSA before emission and LLVM before
linking/running an addressable executable. The toolchain remains LLVM 22.1.8,
with no new dependency or target runtime. See TPTR-1 qualification.

## OWN-1 execution qualification

Owned foreign locals use existing object emission/linkage with no new dependency
or ownership runtime. A bounded static C resource pool records acquisitions,
live resources, destruction count/order, effects, and invalid/double destruction.
Runtime fixtures cover null skipping, 321 LIFO, nested scopes, return-expression
order, early return, branches, ordinary loop backedges, continue, break, and nested
returns. An alternate destroyer proves distinct contracts remain distinct.
Trap fixtures arm a destroyer that would exit 91 if invoked; abnormal signal
termination verifies the non-unwinding policy. See OWN-1 qualification.

## MOVE-1 execution qualification

Explicit local transfer adds no native/C ABI channel or LLVM runtime primitive.
Validated CFG moves normalize into pointer SSA definitions: destination receives
the old source and source receives null. Conditional source cleanup consumes a
pointer phi, with incoming blocks taken from actual cleanup continuations.
No runtime ownership flag, refcount, retain/release or target ownership stack exists.

The existing test-only static resource pool qualifies linear and chained transfer,
actual-null moves, both conditional paths, both-arm moves, return evaluation,
break/continue, fresh loop-body owners, distinct contracts and LIFO order. It records
create/destroy/live/error counts and destruction timing. The mixed fixture retains
addressable Pair storage and stored Pair* borrows. A trap fixture verifies that
moving does not introduce unwinding. See MOVE-1 qualification.

## RELEASE-1 execution qualification

Explicit releases reuse SSA cleanup, exact CAbiCleanupFunction declarations and
null-guarded ccc calls. The owner receives a null SSA definition after cleanup,
so lexical cleanup cannot physically destroy twice. No backend production change,
runtime ownership flag, reference count, ABI channel or dependency is needed.
Physical continuation tests cover release before branching, short-circuit CFG
entry and loop backedges, including subsequent lexical null cleanup.

The existing resource recorder checks basic/null release, move destinations,
completed borrows, conditional true/false and both arms, early return, fresh loop
owners, break/continue, exact statement ordering, changed destruction order and
two distinct cleanup contracts. Three-way pointer joins and unreachable release
preserve the existing control-flow policy. Traps remain non-unwinding. See
RELEASE-1 qualification and
object/linkage audit.

## REARM-1 execution qualification

Rearming compiles to an ordinary producer C call and pointer value flow. The
LLVM backend, NABI, CABI and VAPI production code are unchanged. No ownership
helper, runtime flag, cleanup-rank tag, contract pointer or extra alloca is added.

Native fixtures exercise release/rearm, move/rearm, null results, repeated cycles,
mixed MOVED/RELEASED joins, both-arm producers sharing one cleanup contract,
conditional resource/null phis, terminating predecessors, release/move loops,
continue, break, borrowed use and argument-effect/trap ordering. Every non-null
resource is checked for exactly one destruction, no live remainder and no recorder
errors. Stable slot tests freeze overall destruction **123** for a=1, b=2,
release a, rearm a=3, including the conditional case. Existing cleanup ordering
fixtures keep their expected output. See qualification
and object/linkage evidence.

## INTS-1 native qualification

The exact [integer family](../language/integers.md) executes through native
fastcc calls at i8/i16/i32 width. `i32 main()` satisfies the established canonical
int entry rule; u32/i16 main results reject. Independent Python runtime oracles
cover all arithmetic, comparisons, boundary/sign cases, and signed MIN/-1;
zero division/remainder require abnormal non-returning termination without a
specific signal. Fixtures additionally execute wrapping loops, both branch
paths, promoted and addressable struct fields, forward/recursive native calls,
and owned Resource transfer with u8/u16 parameters and borrowed calls.

See INTS-1 validation and `tests/ints/execute.py` for
reproducible counts. No Astra runtime dependency or new C ABI width is added.

## F32 host execution

[F32-1](../language/f32.md) executes native float parameters/results, arithmetic,
comparisons, loops, branches, struct fields, addressable fields, and mixed
Resource/F32/U8 boundaries. Main remains int/i32. Tests generate float work inside
Astra; the existing C companion handles only integer/resource contracts.

The qualified f32 emission path is the default LLVM 22 x86-64 Linux target:
empty CPU/features, PIC, default code model, and code-generation level NONE.
SSE/SSE2 operations preserve subnormals and round to binary32 per operation.
Other f32 target configurations reject until qualified. No target runtime,
FTZ/DAZ setup, excess precision, or contraction permission is added.
Foreign code must restore nearest/ties-even, masked floating exceptions, and
preserved subnormals before returning to Astra. Exception flags and dynamic
rounding changes are not language-visible state. See the
qualification report.

## Explicit generic capabilities

GEN-CAP-1 instances use ordinary existing NABI v0-v6 signatures and LLVM
operations. Eq<void*> carries pointer values; Numeric<f64> uses fp64-v6 when
f64 occurs at the boundary. Definitions have no ABI. No witnesses, dictionaries,
boxing, type descriptors, capability helpers or C/VAPI capability exports exist.
Integer and floating division retain their distinct trap/IEEE semantics.
See capability qualification.

## Recursive struct fields

STRUCT-AGG-1 lowers concrete nested structs and vectors as ordinary LLVM aggregate
elements, preserving exact double and whole-vector loads/stores. The same recursive
Place address routine handles local, dereference and field roots. Non-addressed
nested locals retain scalarization; addressed roots use ordinary GEPs. DataLayout
owns offsets/alignment. No memcpy, heap, descriptor, aggregate ABI or NABI profile
is added. See qualification.

## Generic native structs

GEN-STRUCT-1 introduces no backend generic definition, type arguments, layout rule, runtime metadata or NABI profile. Its materialized CoreStructs reach LLVM through ordinary concrete CFG/SSA fields. Generic-origin Struct* remains PTR even with f64/vector fields. Non-addressed leaves promote normally; addressed roots use existing GEP/load/store. Qualification compares ordinary control layouts, exact f32/f64 transport, all 24 vector/mask Box shapes and preserved callable O2/FMA machine output. See [generic aggregate IR](../ir/generic-structs.md) and qualification.

## GEN-OWN-1 execution

[Generic ownership](../language/generic-ownership.md) specializes before CFG and
native ABI planning. The backend contains no Ownable operation. Resource owners
use direct concrete release calls; Class owners use exact native destructor or
lifetime-only behavior and existing caller-provided result storage. Transfer and
recursive forwarding preserve exact pointers, with no memcpy, relocation,
destructor function pointer, dictionary, owner header, type switch or heap.
Qualification covers O0/O2 identity, null cleanup,
conditional/recursive ownership, left-to-right capture, non-unwinding traps,
F64/vector companions and representative x86-64 code.

## Whole native struct copies

[Struct copy](../ir/struct-copy.md) reaches LLVM as ordinary scalar/vector
operations. Memory copies load every source leaf before any destination store.
Explicit Place validation reuses existing recursive address and null lowering;
copy-only promoted locals require no aggregate alloca. There is no frontend
memcpy/memmove, copy runtime helper, heap or descriptor. LLVM may combine legal
operations while preserving snapshot/alias semantics. NABI/CABI/VAPI are unchanged:
Struct* uses PTR and by-value aggregate parameters/results still reject.

## Multi-source composition

SOURCES-1 extends source operands to `astrac FILE... [-o OUTPUT]` and all existing
parse/check/dump modes. One invocation performs one LLVM lowering, emits one object
and links one final executable. No object/link stage exists between Astra sources.
Existing external `--link-object` and `--vapi` contracts remain separate and unchanged.
The existing global entry rule applies across the source set. Target requirements
aggregate across all functions: one buffer-using source selects the existing hosted
allocator gate; file composition alone introduces no requirement or runtime symbol.
Canonical program ordering makes LLVM output independent of CLI source order. Debug
information is not expanded. See [source files](../language/source-files.md).

TEXT-IO-1 adds an explicitly selected hosted output source and qualified
`text-posix.o`, installed with target identity under Meson's configured libdir.
The ordinary CLI composes the source with `--link-object`; there is no prelude,
autolinking or provider-name recognition. The provider's write/errno dependency
is separate from failure providers, buffers and libm. The compiler rejects
unqualified C text targets before object emission. See the exact build/install
and relocation recipe in [text output](../library/text-output.md).
