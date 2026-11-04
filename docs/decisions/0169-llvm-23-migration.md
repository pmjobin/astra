# ADR 0169: LLVM 23 host backend

Status: accepted for the current GNU/Linux x86-64 development profile.
The owner explicitly authorized this migration after the CLASSSTORAGE-15
checkpoint found that the installed LLVM 22 runtime had been replaced.

## Decision

Use system LLVM major **23** through the existing narrow C API boundary.
The measured host version is **23.1.4**. Meson rejects other majors and
compiles/links the required C API against the selected `llvm-config`.
The standalone Astra emitter also requires the qualified patch version and
uses that tool's shared-library path and link name. No library is renamed,
no LLVM implementation is vendored, and no host package or global setting
is changed by the migration.

LLVM 23 replaces `LLVMBr` with `LLVMUncondBr` (70) and `LLVMCondBr` (71).
Conditional-branch block operands now follow successor order. Both the Vala
backend's mechanical bindings and the independent Astra physical checker
distinguish the two instructions. Existing successors are checked through
`LLVMGetSuccessor`; the condition remains a separate channel. The new
`llvm-branch-api` regression tests the actual public C API, including swapped
and restored successors, operand order, both opcodes and LLVM verification.
See [LLVM 23 release notes](https://releases.llvm.org/23.1.0/docs/ReleaseNotes.html#changes-to-the-c-api).

All emitter integer-constant construction supplies bits limited to the physical
integer width before `LLVMConstInt`, including negative literals and all-ones
operands. The installed LLVM 23 release retained high input bits when the old
emitter supplied a sign-extended 64-bit value for a 32-bit type. The existing
independent literal checker detected this mismatch; it remains strict. The
producer now supplies canonical bits under the existing wrapping semantics.
The numeric consumer independently reconstructs destination-width expected bits
without calling the producer helper or masking an observed LLVM value.

This changes the implementation's dependency, not Astra source semantics,
owner policy, public C ABI or the approved private generic receiver ABI.
Existing lifetime, numeric, metadata and allocation checks retain their
independent reconstruction and mutation controls. LLVM layout caches retain
their existing module/context ownership; the O0/O2 layout regression and its
deliberately retained-cache negative remain required.

## Tool and oracle identities

Rebuild products in a fresh external build directory. An old binary with
unchanged bytes and missing LLVM 22 dependencies cannot qualify as a current
oracle. Relevant regression recipes now accept an explicit
`--compiler-sha256` for the independently rebuilt production compiler;
the historical default identities remain unchanged. A caller must choose
and record the oracle identity rather than implicitly trusting any supplied
executable. The Class-storage environment audit defaults to LLVM 23.1.4
and still checks the emitter's complete dependency sidecar before reuse.

The current host also changed Python, Meson, Node and clang-format binaries.
`format/toolchain.json` records their newly exercised identities and the
rebuilt compiler. The representative lane pilots, adversarial formatter
guards and 405 public formatter checks over 74 source files precede adoption
of these pins. The qualified Uncrustify 0.78.1 release binary is reused.
A narrow lexical enum-indentation adapter retains the established tab/alignment
columns under clang-format 23. Its token, column and idempotence tests supplement
the ordinary guards; the twelve existing enum sources remain byte-exact.
Only touched eligible source is passed to guarded apply; the complete
read-only check and all 451 protected byte/mode identities remain required.

## Historical evidence and scope

ADR 0004's original LLVM 22 qualification and all earlier numbered milestone
results remain historical. The published CLASSSTORAGE-15 ENVIRONMENT_BLOCKED
report remains byte-exact and continues to describe its original tree and
missing-library observations. This separate migration neither repins that
submission nor clears its published intake marker.

No new Class-storage implementation, whole-compiler admission, Stage 1,
release, full registry campaign or numerical-policy change is implied.
The historical wide-u64-to-f32 Valgrind numerical exit 1 remains DEFERRED,
with the original raw receipt preserved even if a new toolchain behaves
differently. Current measured tests and build costs are recorded in
`docs/llvm-23-migration.md` and the external `runtime/llvm23-migration/`
receipts beneath the project's existing work directory.
