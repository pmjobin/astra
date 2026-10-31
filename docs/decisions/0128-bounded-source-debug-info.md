# 0128 — Explicit source DWARF and scalar variables

Status: implemented for the bounded DWARF 4/scalar profile.

`astrac -g` adds LLVM 22 DWARF 4 debug metadata to compilation, `--check`, and
`--dump-llvm`. Debugging is off by default. The selected initial profile emits
real source files, subprograms and instruction coordinates from verified SSA
source spans. The executable launch wrapper retains the source entry's location
so an optimized program still has a line table when all private functions inline.

Integer, floating and boolean parameters and addressable scalar locals have
debug identities. O0 parameters use private debug stack storage to preserve their
values after argument registers are reused. Optimized parameters use debug value
records; optimization may remove variables. Promoted scalar locals, aggregate
values, async frame variables and debugger expressions beyond this scalar profile
remain outside the initial variable guarantee. Actual `.astra` paths are emitted
as absolute paths; there is no path remapping option yet. C11 is the debugger
expression dialect, with `Astra Stage 0` as producer, not a claim of generated C.

The artifact retains copied source identities and exact LLVM debug attachments.
Its verifier rejects changed or stripped locations and changed subprogram/file
identity before optimization. LLVM verifies the optimized copy separately. The
debug builder is disposed before its module/context; no semantic graph survives
in the LLVM artifact. Debug info introduces no target runtime provider dependency.

`tests/ecosystem-abi-8/debug-check.py` exercises public O0/O1/O2 parity, ELF
dependency/section inspection, independent `llvm-dwarfdump --verify`, decoded
line tables, and real GDB source breakpoint/parameter/local reads when installed.
`debug-proof.vala` corrupts a line, strips a location and removes a subprogram,
then requires rejection and byte-identical restored IR. Independent producer/
consumer source origins and formatted A64 modules are qualified separately.
The generated bodyless UTF-8 factory maps implementation instructions to its
real annotated source declaration. See the [debug guide](../language/source-debugging.md).
