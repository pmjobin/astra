# 0131 — Versioned independent native units

Status: accepted for the bounded GNU x86-64 LP64 profile.

An Astra producer can emit a relocatable object and an adjacent `.asti`
interface with `-c --module NAME --emit-interface FILE --native-export NAME`.
A later compiler invocation accepts `--import-module FILE`. It reads the
interface and verifies the existing object; it does not read or recompile the
producer implementation. `--entry-object` emits a consumer object with its C
entry wrapper for an independent native linker invocation.

The `astra-native-module/1` receipt records the exact compiler executable,
target triple/data layout, normalized semantic and physical native signatures,
ownership/non-null channels, nominal type names, field visibility and
target-derived sizes/alignment/offsets. ABI identity determines exported native
symbols. A separate fingerprint covers the complete canonical interface and
object SHA-256. Missing, stale, altered, duplicate or unexpected metadata and
objects fail before consumer lowering/linking. This is a local build identity
check, not cryptographic authentication of an untrusted author.

The initial `gnu-x86_64-lp64-scalar-pod-class/1` profile supports primitive
scalars, flat scalar-field POD values, and exact nonpolymorphic Classes with
scalar fields, explicit constructors/destructors, heap-owned results and
borrowed inputs. Generic, virtual/interface, throwing, async, buffer, Resource,
owned-Class-input and transitive producer imports are outside this profile.
Those selections fail explicitly. No default source ownership or C ABI changes.

The canonical declaration model traverses the ordinary frontend and ownership
checks. Representative bodies establish typed layout/allocation provenance;
an immutable SSA import marker and exact backend module plan require external
native declarations with no imported implementation bodies. Typed/physical
signature, symbol, calling-convention and linkage checks survive lowering.
Private fields retain their original accessibility; internal declarations
cannot be exported. ABI names omit compilation-local ordinals and source paths.

`tests/ecosystem-abi-8/module-check.py` qualifies separate O0/O2 producers and
consumers, O1, scalar/POD arguments and results, factory/borrow/constructor/
destructor Class channels, source removal, source relocation/reordering,
GDB/DWARF and unsuppressed Valgrind. Its mutation controls reject stale object,
target/layout/compiler/ownership/visibility/signature/identity changes.
`module-proof.vala` corrupts and restores import/export backend plans and
requires byte-identical restored LLVM output. These are focused independent
unit guarantees, not a stable cross-compiler or universal package ABI.
