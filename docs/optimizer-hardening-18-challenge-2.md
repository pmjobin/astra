# M18 B2 — spatial/color masks and connected image components

Selected after freeze commit `f21053101e1eb0a791e192216a30d9b6fa0a18a7`
on 2026-10-30 at 06:46:33 UTC. Freeze 2 SHA-256:
`6f16fbc214d95521004c7d6705ac91de13b29ea4dbcdb38e740cf8266e01cea2`.
Fresh task-generated seed: **1879950433**. Requirements, independent reference
and cost hypotheses precede every B2 compiler invocation or measurement.
The original freeze record keeps its unselected state. B1's failed optimization
witness, requirements/seed/program and frozen production artifacts remain intact.

## Useful computation and independence

Classify a bounded RGB image using two spatial regions and a row-dependent color
policy. Then label every four-connected foreground component and report its area,
bounding box and brightness sum, together with every pixel label and per-row audit.
Classification is split over four interleaved row lanes. Component discovery must
merge connections across worker-row boundaries after all classification jobs join.

All header decoding, spatial/color decisions, union/find, grouping and statistics
belong in Astra. Astra uses a disjoint-set scan and a generic owned Map of component
summaries; the independent Python oracle uses a breadth-first flood fill. C supplies
bounded input bytes, scalar intermediate/output storage, coverage/lifetime/timing
observations and public runtime edges. It must not classify, join components or
compute areas, bounds or sums. No precomputed result or hidden C algorithm.

This is spatial image topology and cross-lane merging, rather than A's PCM/FIR/
biquad windows or B1's checked transaction journal/undo graph. Reusing public runtime
edges/build plumbing does not substitute those applications for the new algorithm.

## Exact input, classification and output

The input is a 16-byte little-endian `<IIII>` header followed by RGB bytes in
row-major order. Fields are magic `0x494d4732`, width, height and threshold.
The empty image has width=height=0. Otherwise width is 1–257, height is 1–129;
threshold is 0–255. Exact byte size is `16 + width*height*3`. Wrong magic, inconsistent
zero dimensions, out-of-bound fields, truncation and trailing bytes refuse without
publishing an output file. Same-path/same-inode input/output refuse before mutation.

Integer division below truncates toward zero. For pixel `(x,y)`:

- Region A is `width/7 <= x < width-width/5` and
  `height/6 <= y < height-height/7`.
- Region B is `width/3 <= x < width-width/9` and
  `height/3 <= y < height-height/5`.
- Lane is `y % 4`. Even lanes use score `red/4 + green/2 + blue/4`;
  odd lanes use `red/2 + green/4 + blue/4`. These are exact binary64 operations on
  byte inputs, with the specified additions; no relaxed policy is requested.
- Foreground means exactly one region contains the pixel, and score >= threshold.
  Store `score4 = score*4` as an integer; its mathematical value is respectively
  `red+2*green+blue` or `2*red+green+blue`, in 0–1020.

Four-connected components use horizontal/vertical neighbors only. The canonical
component label is `1 + minimum row-major pixel index` in that component; background
is zero. Component rows are sorted by label. Bounding boxes use inclusive maxima.
Per-row audits count foreground pixels and sum their score4 values.

Output begins `<IIII>`: magic `0x434d5032`, width, height, component count. It then
contains every pixel label as u32, sorted component rows `<IIIIIIq>` containing
label/area/min_x/min_y/max_x/max_y/score4_sum, and height rows `<IIq>` containing
row/foreground_count/score4_sum. Compare the complete bytes, not only a digest or
exit status. File/argument errors use 64/65, malformed admitted bytes use 3.

Fixed sizes are 0×0, 7×5, 31×17, 127×65 and 257×129, with seeds derived from the
selected seed. The generator mixes random colors, dark areas and bright vertical
strips. It is independent of the flood-fill oracle. Hand-worked empty, white and
red-only controls establish component and color-policy behavior before compilation.

## Language/runtime and prospective mechanisms

Use two independent ordinary scalar-field row-span owners, a typed interface for
the genuinely differing color policies, and a per-row history Vector. A row audit
escapes the classification activation into that history, beside span candidates;
the incoming container/policy references must not globally disable per-value proofs.
Keep observable span/history destruction. Use a nonadjacent unused Shared copy
around real color arithmetic/branches and a proved scalar helper; preserve separate
weak-observed controls. Core graph state uses a copied-scalar Vector for disjoint
sets and an owning generic Map for component summaries.
The scalar parent index is carried in the admitted nominal one-field copied
`ImageParent18` record, so the public owned-slots Vector operates on its supported
value-record family rather than inventing a primitive owned-slots specialization.

Provide a real opaque leaf→middle→consumer route and local control. Leaf owns the
row-span declaration/property contract; middle supplies span selection and color
combination. Remove producer source copies before compiling the consumer and trace
accesses. No implementation-body fallback, LTO requirement or foreign annotations
as proof. Keep exact checked native objects and producer-level mixes.

Execute sequential, four-lane threaded and actual io_uring+worker variants. Threaded
runs use workers 1/2/4. Jobs own their context-backed input and use distinct 2 MiB/
64-slot input-job and 256 KiB/32-slot frame contexts. All jobs join before global
component merging and output. Serial io_uring worker submissions are allowed and
earn no overlap/scaling claim. Verify live/reserved payload zero, allocation/release
conservation, exact retirement and distinct contexts. Report fixed backing capacity,
metadata and whole-process resident peaks separately.

The row-classification API consumes an ordinary RGB numeric view. Each job owns a
separate ordinary row working buffer and copies each selected-input row into it.
The working buffer and generic graph/history storage use their declared ordinary
heap policy; selected input/job/frame allocations keep their distinct policy and
exhaustion behavior. Include these explicit copies/allocations in cost accounting.

Hypotheses: safe span placement and unused Shared counting should show attributable
structural reductions at matched O2, while escaping history, policy differences,
weak observation, generic map/vector work and every destruction remain. No required
percentage speedup or exact total code-size decrease. Preserve neutral/slower raw
samples. Include original/renamed/field-order/helper variants, O0/O1/O2, matched facts
on/off, local/native routes, full-product unsuppressed memory checks and emitted
ASan/UBSan/TSan with explicit opaque/static exclusions.

During B2 change only its source/oracle/test/registration files. Recheck the actual
frozen production, artifacts and host inputs before/after challenge runs. A required
production repair ends this freeze: preserve all results, repair generally,
requalify A, commit another freeze and select another genuinely different challenge.
Never rewrite an old seed or tune B1/B2 into a fresh independent surprise.
