# Native first-success cache plan, v1

`NativeLazyCache` is an internal supplemental plan, not a public binary ABI or
serialized property registry. Existing copied channels retain their minimum
profiles. Checked getters reuse native-exceptions-v14 and the nominated class
root. No new runtime dependency or object header is required for a plain class.

Each declaring class appends a state byte and naturally aligned copied payload
for each declared lazy, after its existing complete parent/header and declared
fields. Derived storage keeps the full zero-offset base prefix, including base
caches and tail padding. Declared field indices remain stable. Construction
explicitly stores state 0 even in lexical/caller-result storage; it neither reads
nor initializes payload bits. Allocation extent/alignment includes all slots.
The cache adds state, payload and target padding per instance; unused lazies still
consume storage. Moving heap ownership moves responsibility for the same address.

The original getter name is the `fastcc` gate. It computes exact declaring-class
state/value addresses from its receiver, reads state and selects Ready (2),
Empty (0) or fatal Evaluating/invalid state. Ready reads only its exact payload.
Empty stores Evaluating (1), then calls the private initializer once. The body
uses ordinary source cleanup and existing exception lowering. Normal completion
stores the copied payload before Ready. Failure stores Empty after body cleanup
and returns the exact exception pointer. Reset affects only this property.

Nonthrowing gates return the copied channel. A throwing gate receives receiver
PTR then the existing private caller success-slot PTR, and returns exception
PTR. Its cold path allocates one complete copied result slot; only a null
exception edge reads it. Success publishes the cached/result value to the caller
slot and returns null. Failure does not publish success. Warm success copies to
the same caller channel. This adds no unwinder or exception object copy.

State/payload operations are ordinary nonvolatile, nonatomic loads/stores with
conservative explicit alignment 1. The allocation and layout remain naturally
aligned. The design makes no thread-safety claim. Retained expected identities,
branch destinations and ordered instruction roles reject wrong slots/receivers,
early Ready, late Evaluating, failed-cache state corruption, wrong exception
channels, target/convention changes and additional effects. Private result-slot
extent/type/alignment are checked independently. Generic LLVM validity is also
required, and deliberately corrupted modules are never executed.

Raw pointer caching extends no pointee lifetime. Copied floating/vector/mask
channels add no arithmetic or fast-math/contraction flags; NaN arithmetic keeps
its existing source rules. Normal cleanup and fatal recursion have separate
qualification. See [ADR 0093](../decisions/0093-first-success-cached-properties.md).

## Owning cache extension, v2

An owned cache appends the same state byte and a PTR payload. Its source-free
plan also records a distinct owned factory ordinal and exact retained Class
ordinal. The public getter's PTR result is receiver-borrowed; only the factory
has an owned heap result. Checked factories and getters have separate success
slots and exception channels. LLVM calls the factory only from the Empty path;
it does not lower the canonical observation stub as another producer.

Destructor epilogues test Ready, load the payload, clear payload/state, then
null-guard exact child destruction and free. Declared caches retire in reverse
order before ordinary field/base cleanup. Physical bindings retain exact slots,
state transitions, value/exception channels, branches and destructor calls.
Generic LLVM verification alone is insufficient. See [ADR 0120](../decisions/0120-owned-lazy-factory-observation.md).
