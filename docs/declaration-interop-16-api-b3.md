# Third frozen query-service challenge

The third freeze was committed at
`b6e24a98` before any API B3 source existed. Its production/API A inventory has
417 files and SHA-256 `e531d810e1b625988d979e8323b290b953f4ccae81d3068eb32bcc0d96e37743`.
Both selected compiler binaries are
`2ff155e4774ee3c019060253cb67d09295aa8a8aa4667110a693a3407f92a3ce`.
The contract timestamp, seed, new IIDs, physical layouts and independent expected
results were recorded before compiling the new application.

OrbitCore16/Orbit16 and the OrbitTable16 5.3 SDK implement record selection with
independent owned Row results, nullable lookup, checked errors, ordinary metadata
and two signal signatures. Probe adds a float boost to a reordered, 40-byte mixed
record. Selection changes the separately compiled closed generic from f64 to f32.
The completed signal and retained native Closure also change their last parameter
to f32; Row's score property remains f64 through an explicit native conversion.
The other signal transports a real Row carrier and UTF-8 bytes.

The rows `(23,3.75,1)`, `(47,6.25,2)`, `(83,0.5,4)` are filtered by minimum ID,
mask and ceiling; cap limits qualifying candidates. The ordinary native leaf
computes `f32(weight+bias+boost)` and selects lowest/highest with stable ID ties.
Default selection returns ID 83, score 0.5, matches 3, visited 3. Cap 1 with boost 0.5
returns ID 23, score 4.25. Changing only the first provider row weight to 8.25 changes
the independently expected score to 8.75 while preserving public declarations and
native ABI identity; object hashes change. Algorithms are never generated in C.

COM changes query ordering to scan then entry_for, reorders metadata accessors
and adds population(u32)->u64 under three new IIDs. Independent Windows definitions
use FLOAT in Selection, BOOL in the COM record and the exact new slots. An
independent provider returns population(7)=49 and query score 7.5 for the declared
input, while the native implementation returns population(UINT32_MAX)=3. Astra
imports that provider through both interfaces and retains its independent result
owner. Canonical IUnknown, reference duties, nullable success, errors, constructing
thread refusal and exact retirement remain executable assertions.

The explicitly enforced Linux challenge passes228 commands: nine mixed native
leaf/component/adapter optimization combinations, a provider-only rebuild,
independent C and generated-SDK clients, native execution, GObject C, scanned GI,
GIR-to-Astra and typed retained float Closure, native-only and propertyless cases.
Seventeen whole-client Valgrind processes report zero errors and no definite,
indirect or possible loss with suppressions disabled. ASan on actual emitted
native IR and ASan/UBSan on C/GObject glue pass 12 commands; system libraries remain
uninstrumented. The explicitly enforced Windows challenge builds and executes 27
exact binaries with independent C/COM and generated-SDK oracles.

No production/API A frozen path changed. New-client corrections were limited to
an explicit u64 comparison and the SDK alias lookup for the renamed scan method;
the earlier failed attempts remain retained. Earlier freezes and their failed
integration/GIR records are unchanged. This is frozen-challenge qualification,
not a substitute for the still-required final complete hosted registry.

```sh
python3 tests/declaration-interop-16/api-b3.py /absolute/astrac /external/output \
	/absolute/astra/docs/declaration-interop-16-api-a-freeze-3.json
```

Without the third argument the recipe is a current-compiler regression and
records that frozen challenge credit is disabled. The Windows recipe uses the
explicit `--freeze` option for the same purpose.
