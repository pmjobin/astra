# ADR 0093: First-success copied-value class caches

**Direction:** USER_APPROVED Z1-FIRST-SUCCESS-CACHE and bounded reusable throws
clause, from the actual ASTRA-LAZY-1 starter on 2026-10-09. The stored starter in
the input archive is not itself approval. This partially answers roadmap Q16.

Use contextual `lazy property T name [throws C] { get { ... } }` on concrete,
nonvirtual get-only classes over existing copied primitive/vector/mask/raw pointer
channels. Each exact receiver/property has Empty, Evaluating and Ready states.
Construction is lazy; first normal completion, including local cleanup, caches
the copied result. Ordinary failure resets after cleanup and transfers the same
exception for retry. Evaluating reentry traps. Sibling caches and effects survive
failure. There is no setter/reset/invalidation, cached owning/text value, lock,
generic framework or new unwinder.

A separate byte state avoids value sentinels and keeps null, zero, false and exact
floating payloads. Appending state/value pairs to complete declaring-class
storage preserves ordinary field indices and inherited base identity. The gate
and private body reuse ordinary callable cleanup and class exception channels;
this costs one private copied success slot for a throwing cold read. Compared
with a source macro or library wrapper, native identity remains available to
stage and retained physical correspondence checks. Compared with general lazy
ownership or synchronized initialization, this scope uses the already admitted
copy/lifetime domain and leaves those larger decisions open.

The optional throws clause also applies to ordinary nonvirtual get-only copied
class properties. Static reads retain their declared effects on warm paths.
Error.message, diagnostic formatting and its bounded receiver-view lifetime
subset retain their existing behavior.

[Language semantics](../language/properties.md), [native cache plan](../abi/lazy-properties.md)
and finite qualification define the implementation.
Final source-bound sets, costs and native results belong to the external handback.
Owning/async/concurrent lazy properties and destruction during concurrent use
remain open. Preserve seven tracks and Q01–Q35; PERF-01 stays unscheduled.
