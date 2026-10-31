# Retained CAD adoption

The workload is the selected CAD-2 implementation at
`f415381f92daecfa683838206dffa5ea78d78477`, not Astra's similarly named compiler
fixtures or later PIXEL application code. See the
qualification report for the measured outcome and
[workload guide](../../workloads/cad/README.md) for input verification and commands.

## Authority and numerical freeze

The exact source tree contains 55 files (635,121 bytes). The committed
[member inventory](../../workloads/cad/cad-members.json) records every Git blob,
mode, SHA-256 and size. `prepare.py` extracts the exact commits read-only;
`materialize.py` verifies the complete CAD snapshot before applying P's patch.
The full independent oracle is `oracle/reference.py`, with trajectory and
symmetry helpers in `tests/`. Its tolerances and all Python assertions are unchanged.

| Original source | Frozen operation or representation |
| --- | --- |
| `src/numeric.astra:27` | Conversion wrappers and signed floor/ceil correction, with the original guard before C truncation. |
| `src/numeric.astra:41` | Inverse snapshots all three outputs before stores; covariance reconstruction retains each original operation and branch. |
| `src/numeric.astra:75` | Original sRGB/normalized Lab convention, matrix coefficients, powers, division order and output rounding. |
| `src/algorithm.astra:23` | Nine-f64 Kernel; five exact integer support values stored as f64 in P; Context holds twelve anonymous Buffer handles. |
| `src/algorithm.astra:58` | Initialization, strict integer support inequalities, row-major enumeration and pair count limit. |
| `src/algorithm.astra:100` | Color inactivity bound and exact `2^-54` classifier. |
| `src/algorithm.astra:110` | Kernel maximum-log normalization, retained normalized logs, then per-pixel normalization; serial reductions preserved. |
| `src/algorithm.astra:195` | M-step computes moments about the old center, divides and recenters before lattice/covariance correction. |
| `src/algorithm.astra:229` | Counterfactual E/M uses separate scratch buffers and restores both live sigma values. |
| `src/algorithm.astra:303` | Four-cardinal-neighbor orientation; original represented angle, overlap and undefined-normal predicates. |
| `src/algorithm.astra:328` | Activity uses entering sigma and updated color means; updates retain sequential multiplication by 1.1. |
| `src/algorithm.astra:338` | One-sided locality moment about the constrained center, divided by mass, threshold 0.2 in output coordinates. |
| `src/algorithm.astra:410` | Component comparisons, convergence and state/next swap occur in their original order. |
| `native/adapter.c:196` | Integer RGB sample conversion, libpng settings, status returns and image cleanup. |

The numerical-change ledger for L and P is empty. P changes no literal,
numerical function body, reduction, initialization, loop or persistent numeric
layout. Compiler semantic dumps independently compare the exact decoded widths
and bits of the floating literals by function; source suffixes were not changed.
The historical compiler remains a reconstruction tool, never a patch source for
the current compiler.

## Compatibility source map

P imports the pinned textual snapshot and applies
[port.patch](../../workloads/cad/compat/port.patch). The complete changed set is
five existing files and two new boundary files. The build passes actual source
files separately to `astrac`; it selects the ARGS provider explicitly.

The original production entry is:

```astra
int main(int argc, void* argv) { return downscale(argc, argv); }
```

The adapted production dispatch is:

```astra
int cad_entry(int argc, void* argv) { return downscale(argc, argv); }
```

The actual shared [entry](../../workloads/cad/compat/entry.astra) is
`int main(string[] args)`. It copies each explicitly borrowed text view through
the [application adapter](../../workloads/cad/compat/arguments.c), calls
`cad_entry`, then frees the terminated copies. The accepted ARGS wrapper disposes
its own snapshot after main returns. The step and orientation test entries get
the same name-only adjustment; their numerical statements remain unchanged.

The adapter exists because the retained parser and libpng boundary take C
strings and current Astra exposes bounded UTF-8 views. It rejects embedded NUL,
invalid counts and inconsistent copy requests; empty text is explicitly
terminated without reading a null data pointer. Partial failures release all
copies already made. It retains only its independent copies, never borrowed
text pointers. CAD's supported argument/PNG failure returns remain unchanged.
New adapter allocation/text-view failures return 1 with explicit diagnostics.
The accepted ARGS provider's UTF-8 validation precedes application entry.

All existing C numerical Buffer allocation, accessors, scalar conversion/libm,
PNG storage and CSV/statistics serialization remain in P. This is intentional
for the compatibility comparison. P supplies no evidence that anonymous numeric
storage has migrated to native owned arrays.

## Corpus and parity

The thirteen original Meson entries contain two native test groups and 52 Python
methods: five analytical, three errors, eight differential, sixteen synthetic,
nine corrections, two correction-image, five symmetry and four reference
methods. Their parameterized scenarios and images are separate counts. The 37
original CAD-1 hash/iteration controls are 23 synthetic, ten differential and
four reference cases. No sum of these overlapping counts is an additional test
total.

Native comparison hashes exact retained PNG, CSV and native-statistics bytes.
CSV uses the original 17-digit binary64 serialization. A difference is a native
parity failure regardless of oracle tolerance. The comparison tool records
every selected identity and both concrete paths; it maps only the original
test harness's time-named run directory, never artifact payloads. On a CSV
difference it records the first differing row, column and decoded float bits
in the first differing sorted artifact. Diagnosis then orders that case's
initialization, E, M, lattice, correction and finish checkpoints to find the
earliest causal difference. No symmetry remapping is added for route parity.

The self-contained Meson regression runs the exact original numerical foundation
and its assertions, with an extracted scalar C/libm adapter. It needs no private
images, libpng development files, NumPy or Pillow. It is one original unit group,
not application acceptance or a replacement oracle.

## Costs and limits

Timing cases are frozen before comparative sampling: original
`constant-37-119-213` (16×12 to 4×3) and `narrow-line` (40×40 to 8×8,
pixel-art mode). They expose startup/I/O overhead and nontrivial numerical work.
Raw matched samples, median and spread are required before a timing claim.
Concurrent qualification durations are descriptive only. L/P/I comparisons
separate compiler generation, adaptation and data representation; no route
comparison establishes blanket C/C++ parity.

Counts of C functions, source lines, crossings or copies are structural measures.
They do not measure human review speed or establish the cause of elapsed-time
changes. Whole-process RSS, application allocation counters, static stack
estimates and transitive peak stack remain different quantities.

## Actual native-state attempt and stopping point

The original first state allocation is `src/algorithm.astra:60`:

```astra
c->state = cad_buffer(c->count * 9); c->next = cad_buffer(c->count * 9);
```

The actual [retained probe](../../workloads/cad/probes/owned-kernel-allocation.astra)
uses the same nine-f64 `Kernel` declaration and this code:

```astra
owned Kernel[] state = new Kernel[count];
var first = state[0];
var last = first;
last.sigma = 1.0d;
state[count - 1] = last;
if (first.sigma != 0.0d || state[0].sigma != 0.0d || state[count - 1].sigma != 1.0d) { return 1; }
```

The small case succeeds and releases its owner. At the original allocation-error
size it traps before the record accesses. This is a required state slice, not an
I-route implementation of the numerical path. Native value-return rewrites,
owned Context fields, support-array migration, iteration rewrites and elimination
of C Kernel accessors were not completed. No idealized after-code is presented
as an executed downscaler. P retains the original numerical pointer results,
load/store helpers, explicit twelve-buffer `dispose` and iteration body unchanged.

The prospective support mapping is exact, but was not implemented: input/output
dimensions are positive and at most 16,384; input pixels are at most 4,194,304;
`x0/y0/x1/y1` are computed as integers, and `start` is the checked cumulative pair
count capped at 67,108,864. C `int32_t` to `double` is exact over those values, and
the original checked truncation reverses that mapping. No floating algorithm
quantity needs to become an integer. This proof does not establish a migrated
implementation or its alias/ownership behavior.

## Observed gaps, in priority order

1. **Required native allocation-failure protocol — missing capability.**
   `src/algorithm.astra:60` in the pinned CAD calls `cad_buffer`, whose failure
   contract is exit 2 and `failure 3` (`native/adapter.c:42`, original test
   `tests/test_cad.py:345`). The accepted compiler instead traps on null
   ([allocation contract](../backend/host-buffer-allocation-v0.md), lines 25–32;
   [lowering](../../bootstrap/backend/llvm/llvm-buffer-allocation.vala), lines 61–64). The minimal
   [scalar reproducer](../../workloads/cad/probes/owned-scalar-allocation.astra)
   and real Kernel reproducer both demonstrate it. P's workaround retains C
   numeric ownership; that is expressly insufficient for I. A blanket signal
   adapter cannot distinguish the retained bounds control. The next bounded
   campaign should decide and qualify the native owned-array allocation-failure
   boundary needed by CAD, then resume this pinned migration. No repair or
   language-contract change is included here.
2. **Public argument/text boundary — composition cost, with a working adapter.**
   Original `src/main.astra:1`, `int main(int argc, void* argv)`, is rejected by the
   accepted compiler. The minimized declaration and diagnostic are retained in
   the campaign's initial P probe. The actual accepted workaround is
   [entry.astra](../../workloads/cad/compat/entry.astra) plus
   [arguments.c](../../workloads/cad/compat/arguments.c): 24 and 54 physical lines,
   an argument table and one terminated copy per argument in addition to the
   ARGS snapshot. This makes entry plumbing more verbose. It is an application
   adapter cost, not a request for unsafe public string conversion or a new ABI.
   The tested public-boundary restriction is UTF-8 argv: a raw `ff` argument
   returns 2 before P entry, while L reaches its usage error and returns 1.
   This non-numerical protocol difference is recorded outside the retained corpus;
   arbitrary POSIX filename bytes were not qualified as P inputs.

The retained minimal entry-boundary source is
`build/app-cad-1/probes/entry-boundary/old-entry.astra`:

```astra
int main(int argc, void* argv) { return 0; }
```

The current public compiler's `old-entry.astra -o program`, invoked in that
directory, rejects it at `old-entry.astra:1:5`: executable entry requires `int main()` or
`int main(string[] args)`. The workaround above uses that actual accepted grammar.
This resolved cost does not justify another feature campaign before the required
native-allocation boundary is addressed.

These are the observed issues, not a five-item feature wishlist. This synchronous
workload provides no decision about async, nullability, comparison chains, regex
or other broader roadmap candidates.
