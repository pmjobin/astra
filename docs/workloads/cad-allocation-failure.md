# CAD allocation boundary supplement: ALLOC-FAIL-1

This supplement leaves APP-CAD-1 unchanged as
BLOCKED_COMPILER. Its L/P qualification and minimized blocker are the historical
evidence. No full I route, arithmetic/data-layout migration or I timing is claimed.

Run the focused public-CLI boundary against a candidate compiler:

```sh
python3 workloads/cad/allocation_failure_boundary.py --compiler build/alloc-fail-1/candidate-build/astrac --args-provider build/alloc-fail-1/candidate-build/lib/astra/args-posix.o --cad-repository /path/to/aster-scale --original-program build/app-cad-1/L-cad/astra-cad --original-input build/app-cad-1/L-cad/test-results/Errors/allocation-input.png --output build/alloc-fail-1/new-boundary
```

Each output directory must be fresh. The command verifies the original pinned
Kernel and `cad_fail` declaration/body from Git, compiles the ordinary native new
through public astrac, and compares status/stdout/stderr to the original L process
under the original 64 MiB address-space limit. Both concrete and generic Kernel
and scalar requests must exit 2 with these exact stderr bytes:

```text
astra-cad: failure 3 (value 37748736)
```

The final newline is required. Kernel count is 4,194,304 records; scalar count and
historical diagnostic value are 37,748,736 f64 slots. Both payloads occupy
301,989,888 bytes. Application code multiplies logical Kernel count by nine under
the validated CAD bound, without consulting target sizeof. The C adapter is the
original reporting/exit protocol; it does not allocate buffers, intercept signals
or replace the allocator. Small zero/snapshot controls, bounds and negative-count
traps and a distinct code/count action qualify the boundary separately.

The retained `allocation_probe.py` and original probes remain unchanged. Their
unannotated Kernel/scalar OOM and bounds controls still trap silently, and their
historical BLOCKED result is not rewritten as PASS.

Requalify complete P while reusing verified original L receipts/artifacts:

```sh
python3 workloads/cad/allocation_failure_qualification.py --compiler build/alloc-fail-1/candidate-build/astrac --args-provider build/alloc-fail-1/candidate-build/lib/astra/args-posix.o --cad-repository /path/to/aster-scale --retained-root build/app-cad-1 --output build/alloc-fail-1/new-P-qualification
```

This requires all original local-only assets and authorities. It reconstructs
the exact pinned CAD source and frozen compatibility patch under the new output
root, runs all 13 original P entries, compares all 37 controls and every retained
native artifact, and runs the exact boundary above. It never downloads assets,
refreshes historical logs or announces full I completion. Missing assets or
receipts prevent a full regression claim. Independent compiler emission and the
language/ownership/model/installation matrices are recorded in
ALLOC-FAIL-1 validation.

The complete compiler qualification passed:
`ALLOCATION_FAILURE_BOUNDARY=CLOSED`. The retained P rerun passed all 13 entries
and 37 controls, with 20,560 native artifacts matching verified L references.
Both final compilers matched that tested emission and independently reran the
smoke, original error and exact boundary controls.

`APP_CAD_FULL_I=NOT_RUN/INCOMPLETE` remains separate. The missing fatal-allocation
boundary is now available for its resumption campaign; no I migration or I
performance comparison was performed here.
