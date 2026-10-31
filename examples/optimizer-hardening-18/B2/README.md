# B2 image topology application

This Astra program classifies spatial/color masks, then merges four-connected
components across worker row boundaries. The exact protocol, independent BFS
reference and pre-measurement hypotheses are in
`docs/optimizer-hardening-18-challenge-2.md` and
`tests/optimizer-hardening-18/b2/reference.py`. Astra uses disjoint sets and generic
owned component summaries. C supplies bytes, storage, serialization and observations.

The ordinary row-view API has two local span owners beside a genuinely retained
row audit in the incoming history Vector. Local linkage proves both span candidates.
The measured opaque route conservatively retains those allocations; its proved
scalar color helper still permits nonadjacent Shared elimination. The differing
color-policy implementations and weak controls retain their actual behavior.
All destruction, pixel/row coverage, selected-context conservation and complete
outputs are checked. No universal speedup follows from these mechanisms.

`build-image.py` takes explicit compiler, public library, build and runtime paths:

```sh
python3 examples/optimizer-hardening-18/B2/build-image.py \
  --compiler PREFIX/bin/astrac --library-root PREFIX/share/astra \
  --build ABS_BUILD --runtime ABS_RUNTIME --facts on --profile sequential
```

Replace the path placeholders with actual locations. For an uninstalled source
build, use its actual `astrac` and `lib/astra` as the library root. Outputs stay
outside the source tree. The recipe prints its receipt and executable paths;
`BUILT_NOT_QUALIFIED` means exactly that. Run the executable with input/output
paths. `qualify.py` generates all fixed inputs and compares every byte with BFS.

Use `--facts off|on` with the same `--optimization 2` for matched ablation;
`--optimization 0|1|2`, `--linkage local|native`,
`--variant base|renamed|fields|helpers` and producer-level controls are explicit.
Native leaf/middle producer settings stay identical between the facts pair.
Producer input copies are removed before consumer compilation and actual accesses
are traced. Opaque metadata may remain unknown; it grants no guessed authority.

`--profile threaded` uses workers 1/2/4 selected by `ASTRA_IMAGE_WORKERS`.
`--profile uring --uring-prefix URING_PREFIX` uses the matching existing liburing
>=2.15 headers/static archive and public file-payload/worker composition. Jobs
own selected input copies and frames. The io_uring variant submits jobs serially;
the threaded variant joins all lanes before component merging. Context backing,
slot metadata, explicit ordinary row/graph storage, static intermediate storage
and resident peaks are distinct costs. No selected-context heap fallback is used.

The separate cost and emitted-instrumentation recipes consume a successful
qualification receipt. They preserve all raw observations and explicitly exclude
exact opaque native objects/static liburing from compiler instrumentation; full
native products also undergo unsuppressed Memcheck. Original B1 remains available
in the neighboring `B/` directory with its failed optimization-witness outcome.
