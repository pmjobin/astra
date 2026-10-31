# Finite generic heap Class consumers

The user approved Q11B after reviewing the [lifetime and instance design](../../docs/gen-own-2a-heap-design.md).
One named exact heap Class owner can enter one owned Ownable T consumer, with
concrete copied scalar neighbors and scalar/void result. The helper and caller
are synchronous; the helper is top-level, native and nonthrowing. It retains the
incoming owner until normal cleanup, including early return. Borrow-only T
helpers remain allowed. Generic heap results, forwarding/recursion and owner
locals remain excluded; Resource and lexical Class behavior is retained.

```sh
sh tests/gen-own-2a/verify.sh focused
sh tests/gen-own-2a/verify.sh regressions
```

The recipe checks the existing external Meson source route, compiles serially
with ccache disabled and runs only named registrations. Regression mode includes
Q11A's focused and finite regression recipe plus OBJ-FIELD child ownership.
The buffer rejection replay keeps its existing fresh-output guard. Generated
products stay under the supported external build; no full registry or historical
CAD/LAZY Q4/Linux async campaign is run.

Ten native programs exercise same-T lexical/heap calls in both orders,
explicit/inferred consumption, concrete local moves and heap-result/parameter
transport, no-deinit/empty Classes, exact derived teardown, early returns,
completed loans, bool/integer/f32/f64 scalar channels and existing owned-child teardown. Exact C observations
check constructors, borrow/consumer operations, destructor order and actual
deallocation. Every program also runs through independent opt/llc O2 and a
separately compiled C client, whose test-only constructor/consumer/borrow entry
checks see the original pointers. The bridge changes no production ownership or
native ABI. Same-type consumer instance keys and cleanup bodies must differ by
domain, while borrow-only bodies share their instance and acquire no cleanup.

The allocation observer interposes calloc/free and invokes the actual host
allocator. Valgrind bypasses these interposed entry points, so each of the ten
programs has native, O2 and C-client/O2 companions built with OWN_MEMORY, using
normal host allocator calls. These 30 unsuppressed memory executions check zero
errors/live bytes/blocks/suppressions and exact destructor/operation traces.
Their observer reports zero intercepted frees; Valgrind measures real cleanup.
Allocation/free event counts belong to the separate interposing runs.

An omitted executed heap free is detected by the allocation observer and by the
normal-allocator Valgrind companion. A duplicated free is detected by the observer
after the first lawful deallocation and before a second unsafe free. The unsafe
double-free memory-tool path is not run. Two native/O2 trap executions check the
existing non-unwinding policy: no destructor/free occurs after the fatal trap.

Nine TAP mutation controls independently reject wrong symbolic/actual/instance
domains, heap forwarding, wrong CFG acquisition, double acquisition, wrong SSA
cleanup origin, duplicate cleanup and mismatched native object-origin plans.
Each restores the model and verifies again. A linkage check keeps this authority
binary LLVM-free. The source rejection matrix requires deterministic diagnostics,
exit 1, no internal error/stdout, and no executable; concrete moved-owner checks
start at the existing CFG authority. Grammar exclusions are identified separately
in fixture names and diagnosed by their existing early guard.

Actual commands, exits, traces, memory reports, compiler hash and full generated
instance/SSA/native/LLVM plans remain in external checks.json, identity.json and
abi.json plus per-program dumps. The validation note
records finite qualification and retries. Q11 remains OPEN.
