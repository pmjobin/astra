# ADR 0016: Host-native execution

Status: accepted for ASTRA-EXEC-1.

## Context

ASTRA-LLVM-1 produces verified, target-independent LLVM bodies from verified
SSA and the NABI signature sidecar. Executable production needs a host target,
native object, process-entry boundary, and platform linker service. None of
these should redefine Astra functions, scalar meaning, or upstream type authority.

## Decision

1. EXEC-1 emits code only for the machine running astrac. LLVM's default host
   triple selects the native target. There is no target/CPU/features CLI,
   sysroot, SDK selection, or cross linker; Meson cross builds are rejected.
2. All Astra-native functions retain NABI native-internal semantics. The LLVM
   realization stays internal `astra.fn.N`, fastcc, with NABI-derived channels.
3. Source `main` is an ordinary Astra function. Executable production requires
   exactly `int main()`: zero parameters and semantic result type int.
4. The driver selects the source spelling `main` once in verified SSA. It
   retains that exact SsaFunction identity. Existing deterministic ordinal
   correspondence binds its NativeFunction and already-created LLVM function.
   Wrapper creation, object emission, and linking perform no name resolution.
5. Only executable production synthesizes a backend-private platform-entry
   function named `main`, with external linkage and the default C convention.
   It calls the exact internal entry using fastcc and returns its i32 result.
6. This wrapper is a platform launch shim, not user-visible C interoperability.
   It establishes no imports, exports, C callable Astra symbols, stable names,
   headers, C/VAPI signatures, or external bool representation.
7. Program-entry policy does not change ordinary calls. Source calls to
   `main()`, including recursion, still target the internal Astra function.
   argc/argv are not exposed. The host CRT accepts the zero-argument wrapper.
8. `--check` and all parse/dump modes require no program entry. `--check` still
   includes LLVM verification; `--dump-llvm` retains target-independent bodies
   without wrapper, triple, or data layout.
9. Host configuration is downstream of verified LLVM lowering. Module triple
   and data layout come from the selected target machine. Target data layout
   never becomes semantic type authority or modifies SSA/NABI.
10. Initialize only LLVM's native target and native assembly printer through
    the LLVM 22 C API. Do not initialize every backend or the assembly parser.
11. Use the target's default CPU (empty string), no explicit extra features,
    PIC relocation, default code model, and codegen optimization level None.
    LLVM target-machine code generation runs its required machine transforms;
    Astra adds no explicit optimizer/pass pipeline.
12. An Astra-owned artifact disposes its LLVMTargetMachineRef and separately
    created LLVMTargetDataRef. LLVM message, triple, and layout strings are
    copied and disposed. No target resource reaches upstream representations.
13. Reverify after target configuration and wrapper insertion. Object emission
    is distinct from executable linking and uses LLVMTargetMachineEmitToFile
    with LLVMObjectFile. There is no textual assembly intermediate or JIT.
14. Linking uses Meson's configured host C compiler driver as a platform launch
    service supplying ordinary CRT/startup objects. No Astra runtime library
    or direct `ld` invocation is introduced.
15. Linker invocation uses an argv/process API, never shell interpolation.
    Capture exit status, stderr, and useful stdout in driver/link diagnostics,
    separately from source, entry, LLVM verifier, and emission diagnostics.
16. Create temporary object and executable inside a private directory beside
    the destination. Publish only after successful linking by same-filesystem
    rename. Every ordinary success/error path cleans temporary files; source,
    emission, link, and publication failure preserve existing final output.
17. Astra scalar traps are semantically non-returning: no normal result and
    no continuation past the trapping operation. Their process manifestation
    is target dependent. LLVM may use a trap instruction or abort-like fallback;
    no particular Unix signal is a language guarantee and no trap runtime is
    added to standardize signals.
18. No stable native object-file or executable ABI is promised. Local names,
    fastcc realization, sections, and object compatibility are implementation
    details, with no separate-compilation or cross-version guarantee.

## Alternatives and consequences

Changing source main to ccc would violate the existing native-call contract and
redirect recursive calls across the launch boundary. A separate wrapper keeps
the native declaration/body/call path intact. Keeping target configuration out
of ordinary LLVM dumps also preserves existing deterministic IR goldens.

Direct `ld` would require Astra to reproduce platform CRT and startup policy.
The configured compiler driver already owns that service. A private sibling
directory keeps object and executable names argv-safe and publication on the
destination filesystem, including when TMPDIR refers to another filesystem.
The destination's parent must already exist and permit temporary creation.
Ordinary cleanup is guaranteed; crash recovery and durability across power
loss are outside this milestone.

Qualification uses public compilation followed by child execution, structural
wrapper/call inspection, the SCALAR-1 numeric oracle, resource lifetime tests,
link/output failures, and optional ELF/Valgrind tools. It adds no target runtime,
optimization pipeline, language feature, multi-file compilation, or C FFI.
See [native execution v0](../backend/native-execution-v0.md).
