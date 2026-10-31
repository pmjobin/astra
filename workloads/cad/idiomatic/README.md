> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# Idiomatic CAD, APP-CAD-2

This is the native-state resumption of the selected production CAD at
`f415381f92daecfa683838206dffa5ea78d78477`, using the frozen compiler at
`0e847be42a00be7f8d85c4c50f813a8d0c540cb3`. It is the same numerical algorithm.
The qualification report states the
measured outcome; [the source map](../../../docs/workloads/cad-idiomatic.md)
explains every migrated owner and adapted test boundary.

The recipe is exact original source, the unchanged `../compat/port.patch` and
compatibility entry/argument adapter, then this directory's `port.patch` and the
three textual replacements listed in `origins.json`. That manifest records both
P and I hashes and modes for every changed member. No live application checkout,
private image, generated executable or later PIXEL source belongs in this recipe.
Original source comments/notices remain intact. The compiler's license is not an
application license grant; these imported application files retain their original
provenance. New compiler-repository tooling has its own existing license notice.

Run from the compiler repository. Use fresh output directories; no command below
refreshes historical APP-CAD-1 or ALLOC-FAIL-1 evidence. Existing local NumPy,
Pillow, libpng and libm are mandatory; there is no installation or download step.

```sh
python3 -B workloads/cad/qualify_idiomatic.py --preflight \
	--cad-repository <historical-private-path> \
	--assets <historical-private-path> \
	--output build/app-cad-2/reproduction-inputs
python3 -B workloads/cad/qualify_idiomatic.py --acceptance \
	--cad-repository <historical-private-path> \
	--assets <historical-private-path> \
	--compiler build/app-cad-2/candidate-build/astrac \
	--args-provider build/app-cad-2/candidate-build/lib/astra/args-posix.o \
	--output build/app-cad-2/reproduction-I
python3 -B workloads/cad/compare_idiomatic.py \
	build/app-cad-1/L-cad/test-results \
	build/app-cad-2/reproduction-I/I-build/test-results \
	--output build/app-cad-2/reproduction-L-I-parity
```

The acceptance command executes all thirteen original Meson entries, including
private reference images and the unchanged independent Python oracle, then checks
all 37 original controls. Missing exact inputs produce `BLOCKED_INPUT` and exit 2.
It deliberately reports `I_ORIGINAL_ACCEPTANCE_PASS`, with full campaign status
still incomplete: memory, failures, exact parity, installation and final compiler
suites are separate obligations. The comparison command requires 20,560 native
artifacts and all 39 other JSON reports. Its only exceptions are the ten original
runtime/seconds fields and the original run-directory identity mapping.

For public, image-free reproduction, build the compiler normally and run:

```sh
meson test -C build --no-rebuild --print-errorlogs app-cad-idiomatic-numerical-ownership
```

That registered test compiles the actual numerical source and original adapted
assertions, plus the actual Context declaration and snapshot/borrow/replacement/
disposal controls. It needs no private PNGs or extra Python packages. It is one
regression test, not a substitute for the full workload.

`../memory_idiomatic.py`, `../install_idiomatic.py` and
`../measure_idiomatic.py` expose their actual required paths with `--help`.
The allocation observer is test-only: it identifies logical allocation sites
using exact executable return addresses matched to public compiler dumps. It
never supplies numeric values or changes the production binary. Injection is
separate from Valgrind, whose allocator interception bypasses that mechanism.
`timing-plan.json` was frozen before comparative samples.

Historical commands and pins keep their historical meaning: APP-CAD-1 I was
BLOCKED_COMPILER; ALLOC-FAIL-1 closed the allocation-failure boundary and did not
run full I. This resumption does not rewrite either result.
