# Bounded source debugging

Add public `-g` to executable compilation, `-c`, `--entry-object`, `--check` or
`--dump-llvm`. Debugging is off by default. Other dump/format/help combinations
reject incompatible debug options. O0/O1/O2 retain their optimization meaning.

```sh
astrac -g -O0 tests/ecosystem-abi-8/debug-probe.astra -o /tmp/debug-probe
llvm-dwarfdump --verify /tmp/debug-probe
gdb /tmp/debug-probe
```

LLVM 22 emits real DWARF 4 source files, functions and instruction coordinates.
Absolute source paths preserve symlink/`..` traversal. Independently compiled
producer and consumer sources have distinct origins. Formatter-managed source
uses its actual new filename and line map. The nominated bodyless UTF-8 factory
attributes generated implementation instructions to the real annotated source
declaration; it does not expose a fictional internal source file.

Integer/floating/bool parameters and addressable scalar locals have variable
metadata. At O0, parameter debug storage preserves values after ABI registers
are reused. To exercise a local explicitly, take its address as in the maintained
probe. Addressable records with up to 128 copied scalar/nested-record fields now
carry real member types, sizes, alignment and offsets derived from the selected
LLVM target layout. GDB reads the qualified scalar record at O0/O2 across an
independently compiled C frame; a nested record is separately qualified at O0.
No record storage is fabricated for a promoted Source local. Owning record
fields, inherited/polymorphic Class layouts, general heap-local reconstruction
and broader Astra expression evaluation remain outside this variable profile.
Logical source argument indices survive physical POD/buffer flattening; aggregate
by-value record signature types remain named unspecified types, without fabricated
scalar storage. Eligible nonpolymorphic Class parameters now have real pointer
types and copied scalar/nested-record member geometry. Compiler-private header
fields stay unnamed; Source fields use their actual physical indices and offsets.
O2 can remove variables; source line metadata remains available. C11 is GDB's
finite scalar expression dialect; the producer identifies Astra Stage 0.

Selected async Source parameters bind to their actual persistent frame fields
on every resume. The DWARF value expression tracks the frame base, adds the exact
target field offset, reads only that field's extent and declares an explicit
stack value. This remains valid when LLVM spills the frame pointer. Unnamed
SSA temporaries are not presented as invented Source locals. Complete frame
field types/packing/offsets are frozen before layout-cache consultation.

[A131](../../examples/interop-tooling-14/a131/README.md) executes real GDB O0/O2
Source line breakpoints and reads aggregate members, an owning closure's capture
fields, a resumed async parameter, a checked-call parameter and a separately
compiled native-module local across independent C frames. Successful/exceptional
paths each require three exact native destructions and unsuppressed memory
checks. An optimized closure input can legitimately be unavailable even while
the selected backed capture remains readable. The portable recipe is
`tests/interop-tooling-14/a131-debugger.py ASTRAC EXTERNAL_OUTPUT`.

Debug metadata changes no ownership, native ABI or optional target dependency.
The pre-optimization verifier snapshots exact subprogram/file/line/column and
instruction attachments, and rejects corruption or stripping. LLVM validates
optimized copies. The selected mixed C/Astra recipe uses Clang `-gdwarf-4`;
observed GCC call-site and Clang DWARF5/string-offset decoder failures are
recorded in [the GIR guide](../../tools/gir/README.md), with raw failures retained.
This does not qualify arbitrary debugger/toolchain combinations.

The selected record metadata uses LLVM's
[typed debug information API](https://llvm.org/doxygen/group__LLVMCCoreDebugInfo.html).
Its verifier checks the copied Source names and exact physical field types,
offsets, extents and alignments after releasing upstream graphs. A deliberate
same-size LLVM packing substitution must reject; rebuilding the untouched Source
must restore byte-identical healthy LLVM. The additional
portable recipe is `tests/interop-tooling-14/debug-records.py ASTRAC EXTERNAL_OUTPUT`.
The closure/async proof additionally releases its upstream Class graph, rejects
an LLVM-valid Class packing change and a same-type async-field substitution,
then verifies healthy Source rebuilding and exact in-place field restoration.
Current GDB backtraces can display internal `astra.fn.N` linkage names alongside
the real Source file/line; that is distinct from a Source variable's name/type.

See [ADR 0128](../decisions/0128-bounded-source-debug-info.md),
[debug checks](../../tests/ecosystem-abi-8/debug-check.py), and the independently
compiled, formatted [A64 analyzer](../../examples/ecosystem-abi-8/A64/README.md).
