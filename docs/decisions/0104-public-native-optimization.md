# Public host optimization and object emission

The driver accepts `-O0` (default), `-O1` and `-O2`. O1/O2 run the linked LLVM 22
PassBuilder `default<O1>`/`default<O2>` pipeline and select matching machine
optimization levels. The pipeline uses the same configured target, baseline CPU,
PIC relocation and data layout as object emission. It adds no fast-math flags,
FP contraction, allocator policy or runtime dependencies. No subprocess optimizer
or generated-C route is involved.

Source foreign calls retain their declared observable effects. Before running
passes, the clone marks imported declarations and their exact calls `nobuiltin`:
a C symbol spelling alone supplies no libc/libm purity or allocation semantics.
Compiler-owned calloc/free retain their existing declaration/call protection.
Public object tests use actual linker interposition to observe a discarded `abs`
call and an otherwise unused allocation, including fatal NULL allocation.

All source, Core, CFG, SSA, native ABI, C ABI and LLVM identity/lifetime checks
run before optimization. After entry-wrapper creation and target qualification,
the backend clones the verified module. LLVM verifies each pass and the resulting
module. Existing proof handles remain valid in the original artifact; they are
never presented as unchanged instruction identities in optimized IR. LLVM's
optimization semantics are the trusted transformation boundary. Independent
executable oracles and lifetime traces qualify the supported paths.

`-c` emits one host relocatable object from the explicit whole-program source set.
It does not select a native main or create a C process-entry wrapper. Use
`export(C)` for externally callable functions, and invoke the host linker with
the resulting object. Internal native functions retain their private ABI; this
mode does not promise an incremental module interface or separate compilation.
The default object output is `a.o`. Executables continue to default to `a.out`.
Link inputs are rejected with `-c`. Unsupported optimization levels and target
options fail explicitly.

Both routes emit into a private directory beside the requested output and rename
only a successful product into place. Failed lowering, verification, optimization,
emission or linking preserves the previous product. `--dump-llvm -O1/-O2` prints
the optimized target-configured module without adding a process wrapper; unused
internal functions can consequently disappear. Ordinary O0 dumps retain their
existing format.

The qualified systems target is GNU Linux x86-64 LP64. Fixed wide/size scalars and
counted foreign buffers require its actual eight-byte pointer layout. Accepting
other triples, freestanding startup and cross-target execution remain deferred.
Self-hosting remains outside this campaign.
