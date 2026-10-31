# Idiomatic native CAD source and qualification map

APP-CAD-2 resumes the exact selected CAD, with zero intended numerical algorithm
changes. See the new report,
[ADR 0083](../decisions/0083-idiomatic-cad-resumption.md) and the
[versioned recipe and commands](../../workloads/cad/idiomatic/README.md).
The old adoption report remains historical.

The owned Context has twelve array fields; output is a thirteenth local owner.
`K = wo*ho`, `N = wi*hi`, `Q = pairs`. Strides below are actual emitted allocator
strides, verified by machine call-site observation on the qualified executable.
Every historical `Buffer` also had an eight-byte C count header. Native arrays
remove those headers; owner descriptors and Context storage are separate.
The exact emitted Context type layouts imply 160 bytes for P and 256 for I under
the qualified LP64 ABI; output's handle grows from 8 to a 16-byte descriptor.
Thus the 104 removed ordinary heap-header bytes correspond to 104 additional
local owner-metadata bytes. The separate `20*K` support-payload saving remains.
`inventory/native-layout.json` retains both public LLVM declarations and the
layout arithmetic; these sizes are not a measurement of transitive peak stack.

| Original buffer / logical f64 slots | I owner and element | Elements × stride | Meaning, initialization and lifetime |
| --- | --- | --- | --- |
| state / 9K | Context.state, Kernel | K × 72 | Current center, covariance, normalized Lab and sigma. Explicit original initial values; current/entering snapshot through the iteration. |
| next / 9K | Context.next, Kernel | K × 72 | Simultaneous M result; zero allocation then original M assignments/corrections. Previous state retained after value swap. |
| supports / 5K | Context.supports, Support | K × 20 | Four integer exclusive support bounds and checked pair start; explicit original integer formulas. |
| means / 2K | Context.means, Vec2 | K × 16 | Separate constrained-center scratch, fully assigned before installing centers. |
| colors / 3N | Context.colors, Lab | N × 24 | Original normalized Lab conversion in pixel order; retained read-only thereafter. |
| pmax / N | Context.pmax, f64 | N × 8 | Per-pixel log maximum; explicit negative maximum-f64 initialization each E step. |
| psum / N | Context.psum, f64 | N × 8 | Per-pixel exponential sum; explicit positive-zero initialization each E step. |
| check / N | Context.check, f64 | N × 8 | Per-pixel normalization checks; explicit positive-zero initialization each E step. |
| ranges / 6 | Context.ranges, Range | 3 × 16 | Lab channel low/high domain pairs; first pixel initializes both bounds, original min/max order follows. |
| logw / Q | Context.logw, f64 | Q × 8 | Log weights, including original two-stage normalization; each pair written in original order. |
| weights / Q | Context.weights, f64 | Q × 8 | Normalized kernel weights, retained for observations. |
| gamma / Q | Context.gamma, f64 | Q × 8 | Per-pixel assignments; both original normalization passes retained. |
| output / 3K | local output, Rgb | K × 24 | Original rounded integer samples represented exactly as f64, retained until PNG boundary returns. |

`Kernel` names its nine genuine state components; it happens still to occupy 72
bytes, now measured rather than inferred from the earlier probe. `Rgb` is distinct
from `Lab`. `SymMat2`, `Vec2`, `ExpectationSummary`, `CorrectionEffect` and
`OrientationObservation` are ordinary value records. Scalar collections retain
f64 arrays. No algorithm state or numeric output lives in C.

Allocation order is state, next, supports, means, colors, pmax, psum, check,
ranges, then logw, weights, gamma after support enumeration, then output after
iteration. Context.init needs initialized owned fields, so its last three fields
start as canonical empty arrays, with no allocator request. Replacement installs
the three actual pair arrays. Native calloc zeroing replaces the original Buffer
calloc; all explicit nonzero and per-iteration application initialization remains.
No fill/clone helper adds an extra pass or an unannotated critical allocation.

The storage-pass ledger below counts logical source traversals, not physical
DRAM writes or timings. calloc's zero guarantee does not establish when the
operating system commits or clears each page.

| Stage | Retained work and native-port cost |
| --- | --- |
| Allocation | Thirteen ordinary zero-initialized payloads, plus eleven per invoked correction counterfactual; three canonical empty owners have no payload. All initial zero values match the old calloc buffers. |
| Initialize | One N-pixel RGB→Lab/range traversal and one K-kernel state/support traversal. Pair owners are allocated only after the original pair enumeration. |
| Each E | One N traversal sets pmax to negative maximum-f64 and psum/check to positive zero. Three per-kernel support traversals compute logs, reduce exponentials, and normalize logw/weights/update pmax. Two more Q traversals write then normalize gamma and accumulate psum/check. A final N traversal checks normalization. |
| Each M / spatial constraint | One Q traversal across the K supports writes K next records. The first K spatial traversal writes means; the second installs those simultaneous means and constrains covariance. Original shape/correction traversals remain in their original order. |
| Correction counterfactual | Two complete E/M evaluations into separate before/after arrays, followed by Q-value and 9K-component comparison traversals. These were original diagnostic computations, not new clone passes. Sigma's two scalar snapshots are restored before return. |
| Iteration observations | The original 9K-component finite/change checks and K-sigma precision-extrema traversal remain. Enabled traces serialize the same K records or Q pairs; disabled traces return before those serialization traversals. |
| State rotation | I adds one K-record exchange traversal in place of P's pointer exchange: two array reads and two writes, 288K logical bytes, plus the local value snapshot. |
| Output | One K traversal converts/rounds Lab into the native Rgb output. The boundary then reads exactly 3K scalar samples into the PNG byte image, preserving the old byte-conversion order. There is no C numeric copy. |

Ordinary per-element value loads/results also copy records as shown in the actual
source and emitted disassembly. The ledger does not equate those source copies
with a transitive stack total or a particular hardware traffic measurement.

All thirteen requests use `new Element[count] else cad_fail(3, value)`, with value
exactly the logical historical slot count in the first column. The original
constant six maps to exactly representable `6.0`. The eleven correction-observer
scratch sites use the same action: before_state (9K), before_logw (Q),
before_weights (Q), before_gamma (Q), probe pmax/psum/check (N each), after_weights
(Q), after_gamma (Q), after_state (9K), after_logw (Q), in precisely that order.
These remain native owners. The action is lazy and applies only to allocator-null.
No outer-call policy, global handler, signal translation or library clone policy
is assumed. Zero-length owner slots are not physical allocations.

Positive admitted dimensions are at most 16,384; N is at most 4,194,304 and output
dimensions cannot exceed input dimensions. Therefore K≤N, 9K≤37,748,736,
5K≤20,971,520, 3N≤12,582,912, 2K≤8,388,608. The original per-support size and
`pairs <= 67108864-size` guard cap Q at 67,108,864. The support-bound numerator
intermediates stay within signed int32 (largest conservative magnitude
536,920,064). There is no wrapped extent before the native allocation check;
all physical requests fit signed host extent arithmetic on this qualified target.

Every old support write converted an already computed int32 through cad_number;
every old support read used cad_integer on that stored exact integer. I stores
those int32 values directly. No actual floating state is truncated. Original
floor_ratio/ceil_ratio and floor_int/ceil_int wrappers, guards and C conversion
semantics remain. The public regression checks ten metadata boundary values and
bit-sensitive negative-zero/nextafter snapshots. The original tests' artificial
support constants are converted at their explicit setup boundary.

Value rewrites preserve the original arithmetic statement order. Inverse computes
all output scalars before assigning the result. Covariance parameters are copied
into mutable locals. E's summary is a value result; scratch E summaries are
explicitly bound even when not consumed. `state` and `next` remain distinct arrays.
A per-record swap implements the old handle swap because moving an owned field
out is unavailable: one temporary plus two array assignments per Kernel per
iteration. This introduces real copying (two array reads and two writes, 288K
logical bytes per iteration), not an algorithmic in-place update. Entering sigma
always comes from state, updated color and sigma from next. Correction-effect
counterfactuals own separate arrays and restore both sigma values before returning.
Borrowed Context/array arguments never outlive their owners.

Normal destruction releases output first; Context field declaration order yields
state, next, means, supports, colors, ranges, logw, weights, gamma, pmax, psum,
check, followed by argument-adapter storage and the final ARGS snapshot. Scratch
arrays retain the original explicit release order. Return statuses 1 and 3 still
release normally owned state. cad_fail/exit, traps, assertions and signals remain
fatal, non-unwinding paths; no cleanup claim is made for those paths.

The source-change ledger is bounded to the following recipe members; the exact
P/I hashes and modes are in `workloads/cad/idiomatic/origins.json`.

| Member | Reason and unchanged authority |
| --- | --- |
| src/algorithm.astra | Native records/owners, borrowed helpers, value results, scalar trace/output boundary. Original formulas, serial loops, comparisons, thresholds, convergence and hard ceiling retained. |
| src/numeric.astra | Value parameters/results; distinct Rgb. Original arithmetic, precision, coefficients and provider wrappers retained. |
| native/adapter.c | Remove Buffer/free/get/set and pointer-backed numeric trace/output. Stream computed scalars to the original CSV/PNG conversion, retaining libm/parser/errors. |
| tests/numeric.astra | Invoke value-result functions and Rgb fields; original assertions/expected constants unchanged. |
| tests/algorithm.astra | Construct the real Context and typed arrays, call real I functions, consume owners. Original fixtures, assertions, inactivity and correction checks retained. |
| tests/step.astra | Read each original CSV scalar into real I records, invoke real E/M/corrections, serialize the same checkpoints. No P dispatch or input-size selection. |
| tests/orientation.astra | Native Context/support/gamma setup and OrientationObservation result. Same test parameters and observed scalars. |
| tests/state_io.c | Read-only scalar CSV transport replaces Buffer writer. It computes no expectation and retains no numeric array. |
| meson.build | Remove the now-unneeded fake main symbol rename in the numerical group; all original thirteen entries and timeouts remain. |

Every original Python/oracle file is byte-identical. The full oracle retains
its differing arithmetic/eigensolver, same-state every-iteration replay, free
trajectories, identity-only perturbations, correction-effect and saturation tests.
Native route parity uses no floating tolerance. The 17-digit snapshots cover the
original logical observation points; they are not raw bits of every temporary.
The 234-literal/51-function audit controls original decoded f64 bits and ordered
floating operators, with explicit value-initializer/constructor moves. It is not
by itself a proof of complete numerical equivalence.

The C boundary owns decoded/encoded byte images and terminated argument copies.
The native Rgb output stays authoritative: three scalar calls per output pixel
validate the same rounded values and write bytes in original sample order, then
the original libpng settings encode them. There is one byte conversion pass and
no persistent C f64 output copy. Trace-only calls stream nine samples per Kernel
checkpoint and three per input Lab pixel, with the original `%.17g` formatting.
Remaining math, options, PNG, argument, diagnostic and trace calls are counted
separately in the evidence. Fewer Buffer crossings do not prove a speedup.

The public entry still accepts UTF-8 text. It preserves APP-CAD-1's documented
invalid-UTF8/startup-OOM differences from historical raw argv; it does not claim
arbitrary POSIX-byte path support. Argument copying rejects embedded NUL, checks
status, and cleans partial construction. The frozen ARGS provider is unchanged.

The following complete function pairs are extracted from the actual qualified
P and I sources, not prospective syntax.

P `load_kernel`:

```astra
void load_kernel(void* data, int index, Kernel* k) {
	int i = index * 9;
	k->mx = cad_get(data, i); k->my = cad_get(data, i + 1);
	k->xx = cad_get(data, i + 2); k->xy = cad_get(data, i + 3); k->yy = cad_get(data, i + 4);
	k->l = cad_get(data, i + 5); k->a = cad_get(data, i + 6); k->b = cad_get(data, i + 7); k->sigma = cad_get(data, i + 8);
}
```

I `load_kernel`:

```astra
Kernel load_kernel(Kernel[] data, int index) { return data[index]; }
```

P `inverse`:

```astra
void inverse(SymMat2* out, SymMat2* a) {
	f64 det = determinant(a);
	require(finite(det) && det > 0.0, 10, det);
	f64 xx = a->yy / det;
	f64 xy = -a->xy / det;
	f64 yy = a->xx / det;
	out->xx = xx; out->xy = xy; out->yy = yy;
}
```

I `inverse`:

```astra
SymMat2 inverse(SymMat2 a) { SymMat2 out = {xx=0.0,xy=0.0,yy=0.0};
	f64 det = determinant(a);
	require(finite(det) && det > 0.0, 10, det);
	f64 xx = a.yy / det;
	f64 xy = -a.xy / det;
	f64 yy = a.xx / det;
	out.xx = xx; out.xy = xy; out.yy = yy;
	return out;
}
```

P explicitly called `dispose(&c)` after `cad_free(output)`; I's complete
`downscale` returns with both `owned Context c` and `output` in scope, allowing
normal scope cleanup. The exact complete functions and initialization are in the
source recipe; the allocation/cleanup map above documents all requests, including
fatal actions. P's iteration handle swap was:

```astra
	void* previous = c->state; c->state = c->next; c->next = previous;
```

I's actual corresponding loop is:

```astra
	while (k < c.count) { var previous = c.state[k]; c.state[k] = c.next[k]; c.next[k] = previous; k = k + 1; }
```

The source build still passes four actual application sources and explicitly links
`libcad-io.so` and the target-qualified `args-posix.o`. C owns only byte images,
argument transport and platform/observation functions. This is more build plumbing
than a source-only numerical demo, and the native output boundary adds explicit
scalar forwarding code.

Observed remaining friction, ranked by current impact (none blocks this port):

1. Owned fields cannot be moved out for a constant-time state swap. The minimized
   `build/app-cad-2/friction.astra` is rejected at line 7: “moving ownership out of
   an owned field is unsupported; 'move' requires a named owner”. The actual
   complete port uses the measured record-copy loop above. A bounded future
   campaign could assess owner-field exchange semantics and its safety proof;
   this campaign neither changes the rule nor attributes all timing to it.
2. The supported text entry needs the existing terminated argument adapter.
   `compat/entry.astra` and `compat/arguments.c` remain 24 and 54 lines, respectively,
   with one table plus one copy per argument, in addition to ARGS's own snapshot.
   The original raw-argv declaration witness and UTF-8 limitation remain in
   APP-CAD-1; fresh L/P/I invalid-byte results are retained here. A later application
   boundary study can assess actual path requirements without assuming raw-pointer
   text access or arbitrary byte filenames.
3. Returning records need an explicit value consumer, even for diagnostic E
   summaries that the caller ignores. `correction_effect` binds
   `discarded_summary`; intermediate freeze 04 retains the exact diagnostic
   “struct call result requires a bounded initialization, assignment, argument,
   or return consumer”. Value parameters are also read-only, so covariance and
   summary mutation use explicit local snapshots. These are small visible source
   costs, not miscompiles or missing numerical capabilities. A future diagnostics
   review could improve guidance without changing ownership or numerical rules.

This synchronous workload supplies no conclusion about async or the wider
founding vision. Its convergence and performance results apply to the selected
original corpus, not a proof of universal convergence or C/C++ parity.

These complete entry functions show the real iteration work, numeric output
allocation and returning lifetime path together.

P `downscale`:

```astra
int downscale(int argc, void* argv) {
	if (cad_begin(argc, argv) != 0) { return 1; }
	int wi = cad_option(0); int hi = cad_option(1); int wo = cad_option(2); int ho = cad_option(3);
	Context c = {wi=wi,hi=hi,wo=wo,ho=ho,count=wo * ho,pairs=0,rx=cad_number(wi) / cad_number(wo),ry=cad_number(hi) / cad_number(ho),state=null,next=null,means=null,supports=null,colors=null,ranges=null,logw=null,weights=null,gamma=null,pmax=null,psum=null,check=null,underflow=0,locality=0,orientation=0,inactive=0,normalization=0.0};
	initialize(&c); cad_dump(c.state, c.count, 9, 0);
	int iteration = 0; bool converged = false;
	while (iteration < cad_option(6) && !converged) {
		expectation(&c); maximization(&c); cad_mstep_state(c.next, c.count, iteration + 1); constrain_spatial(&c); constrain_shape(&c, cad_option(5) != 0);
		iteration = iteration + 1; converged = finish_iteration(&c, iteration, cad_epsilon());
	}
	void* output = cad_buffer(c.count * 3);
	int k = 0;
	while (k < c.count) {
		Lab color = {l=cad_get(c.state,k * 9 + 5),a=cad_get(c.state,k * 9 + 6),b=cad_get(c.state,k * 9 + 7)};
		Lab rgb = {l=0.0,a=0.0,b=0.0}; lab_to_rgb(&color, &rgb);
		cad_set(output, 3 * k, cad_number(floor_int(rgb.l + 0.5))); cad_set(output, 3 * k + 1, cad_number(floor_int(rgb.a + 0.5))); cad_set(output, 3 * k + 2, cad_number(floor_int(rgb.b + 0.5)));
		k = k + 1;
	}
	int flag = 0; if (converged) { flag = 1; }
	cad_dump_final(c.state, c.count, 9, iteration);
	int result = cad_finish(output, iteration, flag);
	cad_free(output); dispose(&c); return result;
}
```

I `downscale`:

```astra
int downscale(int argc, void* argv) {
	if (cad_begin(argc, argv) != 0) { return 1; }
	int wi = cad_option(0); int hi = cad_option(1); int wo = cad_option(2); int ho = cad_option(3);
	owned Context c = Context.init(wi, hi, wo, ho);
	initialize(c); cad_dump(c.state, c.count, 9, 0);
	int iteration = 0; bool converged = false;
	while (iteration < cad_option(6) && !converged) {
		expectation(c); maximization(c); cad_mstep_state(c.next, c.count, iteration + 1); constrain_spatial(c); constrain_shape(c, cad_option(5) != 0);
		iteration = iteration + 1; converged = finish_iteration(c, iteration, cad_epsilon());
	}
	var output = new Rgb[c.count] else cad_fail(3, cad_number(c.count * 3));
	int k = 0;
	while (k < c.count) {
		Lab color = {l=c.state[k].l,a=c.state[k].a,b=c.state[k].b};
		Rgb rgb = {r=0.0,g=0.0,b=0.0}; rgb = lab_to_rgb(color);
		output[k].r = cad_number(floor_int(rgb.r + 0.5)); output[k].g = cad_number(floor_int(rgb.g + 0.5)); output[k].b = cad_number(floor_int(rgb.b + 0.5));
		k = k + 1;
	}
	int flag = 0; if (converged) { flag = 1; }
	cad_dump_final(c.state, c.count, 9, iteration);
	int result = cad_finish(output, iteration, flag);
	return result;
}
```

The original C allocation failure function is:

```c
void* cad_buffer(int32_t count) {
	if (count <= 0 || count > 67108864) { cad_fail(2, count); }
	Buffer* b = calloc(1, sizeof(*b) + (size_t)count * sizeof(double));
	if (b == NULL) { cad_fail(3, count); }
	b->count = count;
	return b;
}
```

I makes that policy explicit at each native request. The actual constructor is:

```astra
	init(int wi, int hi, int wo, int ho) {
		this.wi = wi; this.hi = hi; this.wo = wo; this.ho = ho;
		int count = wo * ho; int pixels = wi * hi;
		this.count = count; this.pairs = 0;
		this.rx = cad_number(wi) / cad_number(wo); this.ry = cad_number(hi) / cad_number(ho);
		this.state = new Kernel[count] else cad_fail(3, cad_number(count * 9));
		this.next = new Kernel[count] else cad_fail(3, cad_number(count * 9));
		this.supports = new Support[count] else cad_fail(3, cad_number(count * 5));
		this.means = new Vec2[count] else cad_fail(3, cad_number(count * 2));
		this.colors = new Lab[pixels] else cad_fail(3, cad_number(pixels * 3));
		this.pmax = new f64[pixels] else cad_fail(3, cad_number(pixels));
		this.psum = new f64[pixels] else cad_fail(3, cad_number(pixels));
		this.check = new f64[pixels] else cad_fail(3, cad_number(pixels));
		this.ranges = new Range[3] else cad_fail(3, 6.0);
		// Canonical empty owner slots perform no allocator request.
		this.logw = new f64[0]; this.weights = new f64[0]; this.gamma = new f64[0];
		this.underflow = 0; this.locality = 0; this.orientation = 0; this.inactive = 0; this.normalization = 0.0;
	}
```

The original explicit disposal function, now replaced by the native owner
and the observed normal cleanup order above, was:

```astra
void dispose(Context* c) {
	cad_free(c->state); cad_free(c->next); cad_free(c->means); cad_free(c->supports); cad_free(c->colors); cad_free(c->ranges);
	cad_free(c->logw); cad_free(c->weights); cad_free(c->gamma); cad_free(c->pmax); cad_free(c->psum); cad_free(c->check);
}
```
