> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# Surge 13 qualification recipes

Run from the repository root. Source, tests and portable recipes belong in Git;
products and raw receipts use the project's designated external build directory.
These are ordinary Python/Ninja/Meson commands; no supervisor is involved.

```sh
build=<historical-private-path>
ninja -C "$build" astrac
python3 tests/concurrency-runtime-13/qualify.py "$build" "$build/concurrency-runtime-13/final-selection"
python3 tests/concurrency-runtime-13/image-tiles.py "$build/astrac" "$build/concurrency-runtime-13/image-tiles"
python3 tests/concurrency-runtime-13/metrics.py "$build" "$build/concurrency-runtime-13/metrics"
```

`qualify.py` verifies the source/build routing through Meson introspection,
builds the exact selected test dependencies with normal warning settings,
executes all 22 Surge 13 registrations and the explicitly listed historical
intersection, checks every Meson result, then runs the actual liburing timer
control. `regression-selection.txt` is the authoritative historical selection.
The existing compiler recipe uses LLVM 22 and Vala with warnings as errors.
The actual selected host also has pthread, Clang/GCC, Valgrind, LLVM sanitizer
passes, strace, QEMU/SeaBIOS, GLib/GObject/GIR and an existing liburing 2.15
prefix. Pass its prefix to the timer/payload scripts or set
`ASTRA_LIBURING_PREFIX`; this recipe uses `$HOME/.local/opt/liburing-2.15`.
No library installation or kernel setting change is performed.

`image-tiles.py` supplements the checked-in four-worker A109 with 2/4/8-worker,
two-seed image-checksum and weak-race runs at all public optimization levels.
`applications.py` separately requires all A109–A120 IDs and records each source,
expected output, execution level and cleanup observer. The complete corpus
includes real threaded, Actor and socket operations, never placeholder counts.

Each dedicated Python recipe accepts `COMPILER OUTPUT_DIRECTORY`. Receipts
record commands, expected/actual exits and output, timing, compiler identity and
input/product hashes. Reruns retain prior receipts in `attempts/`. Evidence
marked PASS is granted only after independent output checks. An interrupted
or failed attempt without overall PASS remains historical failure evidence.
Raw generated LLVM, objects, binaries, traces and verbose logs stay external.
The committed evidence index carries compact identities for the final receipts.

`sanitizers.py` instruments actual emitted Astra LLVM memory operations with
LLVM's ASan or TSan passes, then links matching instrumented C providers.
ASan/UBSan, TSan and unsuppressed Valgrind complement source/stage mutations
and independent observers. Finite executions do not prove universal race
freedom. GObject's historical memory checks retain their established precise
lost-allocation policy; native Surge 13 clients use all leak kinds.

The atomic/policy Vala proofs corrupt admitted identity, layout/transfer,
nullable Actor error results, native operations and LLVM instructions, require
refusal, restore each mutation and verify again. The existing Shared proof
also exercises missing reference publication, control free, duplicated payload
destruction and false weak upgrade. Cancellation and Actor retirement each
have an isolated deliberately broken runtime plus a restored control.

`pool-admission.c` and `actor-retirement.c` are explicitly private-runtime C
supplements. They qualify bounded admission/drain and retirement synchronization;
they are not counted as native applications. `callback-affinity-oracle.c`
retains and enters the actual generated C thunk; it does not replace the native
application body. Socket wrappers observe real kernel operations and exact fd
retirement. Wall-clock watchdogs bound all concurrent executions.

`metrics.py` uses already qualified product hashes and their unchanged output
oracles. It records three ordinary timed runs, process RSS/context switches,
sampled heap peak, ELF size/dependencies, a separately interposed count of real
pthread creation/explicit mutex acquisition, and separate syscall summaries.
Observer counts include test observers. Timing includes launch/teardown and
is not a calibrated microbenchmark or acceptance speed threshold.
