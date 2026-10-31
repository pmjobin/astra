# 0021: Scalar native functions exported through C wrappers

Status: accepted for ASTRA-CEXPORT-1.

`export(C)` attaches a C ingress boundary to an Astra-native definition. The
native function remains the semantic and body identity throughout compilation;
a separate physical wrapper makes it callable from C.

The frozen decisions are:

1. `export(C)` attaches foreign boundary metadata to a native definition. It
   requires a body and cannot be combined with `extern(C)` in either order.
2. `export` is a keyword; the ABI spelling is the case-sensitive identifier `C`.
   `C` is not a global lexer keyword.
3. The function remains an ordinary native `FunctionSymbol`, `CoreFunction`,
   `CfgFunction`, `SsaFunction`, and `NativeFunction`. Export does not change its
   identity, body representation, native linkage, or source semantics.
4. Astra-to-Astra calls resolve the native function directly, including forward
   calls, self recursion, and calls between exported functions. Export metadata
   is never a `DirectCallableSymbol` or a native call target.
5. C callers enter through a generated wrapper, a separate physical function.
   The native body stays internal/fastcc; the C wrapper is external/ccc and calls
   the exact native function using fastcc.
6. The supported boundary has int parameters and int or void results only.
   Native bool/B1 does not define C `_Bool`; bool exports reject explicitly.
7. The external symbol is exactly the source function name, with no aliases,
   annotations, mangling, or user-specified physical names.
8. Imports and exports occupy one explicitly verified external C symbol domain.
   Source namespace uniqueness alone is not physical ABI protection.
9. `CheckedProgram` owns `CExportSymbol` metadata separately from native checked
   functions. Each export uses a GLib WeakRef to the exact `FunctionSymbol`.
   There is no function-to-export backreference or strong ownership cycle.
10. Export ordinals are deterministic source order among exports, independently
    of import ordinals. They aid inspection and planning, not source identity.
11. Core, CFG, and SSA each own separate export objects with weak references to
    their exact stage-owned native function. Builders create all native
    identities first and translate export targets through temporary exact maps.
    No stage re-resolves a target by name or creates an upstream wrapper body.
12. NABI remains exclusively native, unchanged in model, builder, verifier, and
    dump. Exported bodies retain `NATIVE_INTERNAL`; wrappers never enter NABI.
13. One `CAbiProgram` describes both directions: existing `CAbiFunction` entries
    are imports and distinct `CAbiExport` entries are exports. Import architecture
    and ordered effectful C calls remain unchanged.
14. `CAbiProfile.SCALAR_V0` still applies. C I32 and native I32 remain distinct
    physical type identities despite both realizing as LLVM i32.
15. CABI planning consumes verified SSA and NABI, validates their correspondence,
    and copies the exact native function ordinal into each export. That ordinal
    is a within-compilation physical key, never a public ABI or source identity.
16. Completed CABI retains symbols, signatures, direction by entry type, ordinals,
    and provenance only. It survives SSA, NABI, and semantic-type destruction;
    its standalone model/verifier/dumper have no upstream or LLVM dependency.
17. LLVM creates all native functions before export wrappers. Wrapper types come
    exclusively from CABI signatures, with NABI used for compatibility validation
    and exact ordinal binding. No call-time name resolution chooses the target.
18. Wrappers contain only argument forwarding, one native fastcc call, and return.
    Current I32 parameters/results need no conversion. Equal representation does
    not justify aliasing, changing conventions, merging bodies, or removing the
    wrapper. No wrapper optimization pass is introduced.
19. `--check` includes CABI planning, wrapper generation, and LLVM verification.
    `--dump-llvm` includes C export wrappers, independently of process launch.
    Neither mode needs linked C objects. Existing object/link transactions apply.
20. Exported `main` is valid in stage modes, but executable entry validation rejects
    its collision with the separate EXEC-1 `main` wrapper. Export metadata never
    replaces native `int main()` entry selection; wrapper sharing is deferred.
21. C headers, aliases, pointers, strings, structs, callbacks, variadics, C bool,
    ownership annotations, stable native ABI, and shared-library production are
    outside this milestone. The C companion declares exact int32_t signatures
    manually. Export support makes no broad ABI stability promise.
22. VAPI remains future declaration input for imports, not an export definition
    mechanism. The existing semantic and physical boundary authorities remain
    the integration points for future declaration sources.

A distinct `CAbiExport` preserves the accepted import representation and makes
it impossible to insert a wrapper contract into the typed imported-call map.
A direction flag on the imported function would require guards at every import
consumer; changing native identity would violate native calls and recursion.
Small stage-specific metadata records solve the concrete mapping/lifetime
problem without a common ABI-bearing function abstraction.

See [language rules](../language/c-exports.md),
[physical contract](../abi/c-scalar-export-v0.md), and
qualification.
