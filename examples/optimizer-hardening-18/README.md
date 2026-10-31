# M18 application A: windowed telemetry processing

Requirements chosen before application measurements, after compiler checkpoint
`ac20e25f`. This is application A; no production freeze or application B is selected.
The first qualification and its limits are recorded in
`docs/optimizer-hardening-18-checkpoint-11.md` in the source distribution.

Process deterministic runtime PCM-derived samples in independent telemetry windows.
Default input has 48,013 samples with window sizes 16/31/64 and final scalar tails;
fixed seeds 17/43/91 vary samples and metadata. Each window performs a vector affine
front end, a five-tap FIR, a stable direct-form-II-transposed biquad and an ordered
energy reduction. The algorithm executes in Astra using the public numerical library.
Independent C/Python references and platform input/output edges are allowed; they
must not replace an application computation.

Combine actual native leaf→middle→application linkage with scalar metadata readers
whose capture/read facts are checked against the supplied objects. Remove producer
implementation copies before consumption and retain source-access tracing evidence.
Use ordinary generic report state, multiple local metadata/audit owners, a concrete
typed interface stage, typed properties, one genuinely escaping neighboring owner,
and checked validation failures with deterministic cleanup. Separately exercise
balanced Shared work with a pure helper and retain weak-observed controls.

Qualify the sequential route first, then bounded M17 context/worker and io_uring
streaming routes. Workers own distinct window/filter state and output ranges. Use
worker counts 1/2/4, multiple task granularities and context contention/idle-wake
observations. Context capacity, live payload, metadata and measured RSS are separate
quantities. Only generated task files may be opened or written by the file-I/O route.

The strict oracle uses the specified scalar operation and reduction order and checks
output bits, report counts/energy and failure identities. An explicit contraction
variant may differ only at the approved contraction sites; its prospective absolute
error budget is `2^-36 * (1 + window_length)` per bounded output/energy value. Inputs
are bounded by one, FIR coefficients sum to one and the selected stable biquad has
bounded gain below four; the budget conservatively exceeds accumulated binary64
rounding across this finite pipeline. It is not chosen from measured differences.
No reassociation, reciprocal, NaN, signed-zero or alias permission is added.

Keep equivalent variants for renaming, extra independent state, legal field ordering,
helper extraction, leaf/library/application splitting, a third nominal stage type,
branch placement, tail lengths and an escaping neighbor. Compare O0/O1/O2 and matched
O2 facts on/off with source/tool/product hashes, exact outputs, allocation/destructor/
retain observations, IR/disassembly, sizes and repeated raw costs. Report neutral and
slower samples. Successful compilation alone does not qualify any route.

Only after the production dependencies and all A obligations pass may the campaign
commit/hash a freeze and choose a materially different B. A production repair during
B invalidates that freeze and requires requalification and a different challenge.

## Explicit build and installed SDK use

The source recipe takes separate compiler, generated-product and scratch paths:

```sh
python3 build-telemetry.py --compiler /absolute/prefix/bin/astrac \
	--library-root /absolute/prefix/share/astra \
	--build /absolute/task/build --runtime /absolute/task/runtime \
	--profile sequential --optimization 2 --facts on
```

The installed example is under `share/astra/examples/optimizer-hardening-18`.
For a checkout build, omit `--library-root` to use its checked-in `lib/astra`.
Select `--profile threaded` for the public worker/context route, or `--profile
uring --uring-prefix /absolute/existing/liburing-2.15` for actual file/worker
composition. No dependency is downloaded or installed. The JSON result names the
executable and full source/tool/command receipt. Facts off is the same LLVM
optimization level with the selected Astra optimization families disabled.

Run the executable with `ASTRA_TELEMETRY_SAMPLES`, `ASTRA_TELEMETRY_WINDOW` and
`ASTRA_TELEMETRY_SEED` to vary bounded inputs. `ASTRA_TELEMETRY_OUTPUT` names a
task-owned binary64 output file. The io_uring executable additionally takes one
task-owned path for generated PCM input. Worker count (1–4), granularity (1–256)
and idle ticks (0–1000 ms) use the corresponding `ASTRA_TELEMETRY_*` variables
documented in `telemetry-host.c`; the optional barrier is an observation control.
