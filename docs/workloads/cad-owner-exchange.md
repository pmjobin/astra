# CAD owner exchange experiment I1

APP-CAD-2's accepted idiomatic implementation remains I0. Its committed recipe,
source, guide, numerical expectations and historical receipts are unchanged.
I1 is a separate experiment proposed because I0's rotation copies `288*K`
logical bytes for `K` 72-byte Kernels each iteration.

`workloads/cad/qualify_owner_exchange.py` obtains the actual original CAD source
at `f415381f92daecfa683838206dffa5ea78d78477`, applies the unchanged accepted I0
recipe, verifies every recipe member, then replaces exactly one source line:

```astra
while (k < c.count) { var previous = c.state[k]; c.state[k] = c.next[k]; c.next[k] = previous; k = k + 1; }
```

with:

```astra
swap(c.state, c.next);
```

The preceding `k = 0` remains. The later use of `k` resets it before reading it.
No arithmetic, reduction, conversion wrapper, allocation, CLI, I/O, loop outside
this rotation, or optimization setting changes. The recipe checks that only
`src/algorithm.astra` differs; I0's hash is
`c3a92710d107a6da9ec6d618dd40b54bf23c9f73e48e2b39124e9c17868b25b3`.

The rotation occurs in `finish_iteration`. Its preceding state/next reads produce
scalar differences and complete record snapshots. There is no persistent array
view across the statement. Earlier calls complete before rotation. Later dump
and pair-observation calls obtain their views from the current fields. Record
snapshots have independent values and keep no permission tied to an allocation.

Logical state/next contents must match I0 exactly. Physical allocations permute:
after an odd number of rotations state owns the original next allocation; after
an even number it owns the original state allocation. Field cleanup order stays
at its declared reverse order. Thus which allocation is freed at a particular
field cleanup changes with parity. Each allocation must still be freed once.

Final I1 qualification passed all 13 original entries, 37 controls and 20,560
exact native comparisons against each verified L/P/I0 reference. Physical lifecycle
permutation, installed use, memory/OOM checks and matched seven-repetition timing
passed; see the validation report for separate
correctness and timing results. Missing private inputs remain `BLOCKED_INPUT`.

Run from the compiler repository with explicit local paths:

```sh
python3 workloads/cad/qualify_owner_exchange.py \
	--cad-repository /path/to/read-only/aster-scale \
	--assets /path/to/read-only/aster-scale/test-data/reference \
	--compiler "$PWD/build/own-swap-1/candidate-build/astrac" \
	--args-provider "$PWD/build/own-swap-1/candidate-build/lib/astra/args-posix.o" \
	--output build/own-swap-1/cad-final --acceptance
```

This runs the original 13 acceptance entries and 37 controls without changing
their oracle or tolerances. Exact comparisons of all 20,560 retained native
observations are separate and use `compare_idiomatic.py` unchanged. Its existing
timing-field and run-directory policy is the only allowed normalization.

Matched I0/I1 timing uses the same candidate compiler, selected providers, public
CLI flags, constant and narrow-line cases and seven balanced repetitions. The
removed logical copy traffic is not measured DRAM traffic or a predicted speedup.
APP-CAD-2's P/I0 timings and compiler-latency findings remain separate results.
