# Generic owned runtime arrays

Borrowing an array, copying an element and transferring an allocation are separate
operations. Plain/borrowed `T[]` parameters borrow; `owned T[]` parameters and results
transfer one base/count group and its static cleanup responsibility.

[Owned buffer exchange](owned-buffer-exchange.md) also works in these bodies:
`swap(a, b);` requires two live owned `T[]` slots with the same exact lexical element
identity and the existing signature-derived element premise. `T[]` and `U[]`
reject in the definition even if a caller could supply equal concrete types.
The statement creates no new constraint or caller-slot reference parameter.

```astra
owned T[] relay_array<T>(owned T[] values) {
	return move values;
}

owned T[] make_array<T>(int count) {
	return new T[count];
}

T scratch<T>(T[] source) {
	owned T[] values = new T[len(source)];
	values[0] = source[0];
	T saved = values[0];
	return saved;
}
```

A signature must supply the exact element premise. A direct T[] parameter, whether
borrowed or owned, or an owned T[] result supplies copying, storage, zero and trivial
destruction requirements. A local declaration/new expression cannot add a missing
requirement. Definitions are checked without demand, and a favorable concrete call
cannot rescue an invalid definition. Unresolved locals still require explicit types;
concrete callers may infer owned results with `var`.

The admitted elements are the same 34 primitive/vector/mask types and eligible ordinary,
nested and concrete generic records as BUFFER/STRUCT-ELEM. This includes bool, six
integer widths/signs, f32/f64 and unmanaged void*, plus i8/u8 vectors with 2/4/8/16
lanes, i16/u16 with 2/4/8, int/u32/f32 with 2/4, and bool masks with 2/4/8/16.
Text, Resource, Class, tracked pointers, nested collections and owning elements remain
excluded. SliceType is neither a GEN1_PLAIN_COPY value nor a GEN-OWN Ownable argument.
An independent owned U constrained by Ownable retains its Resource/Class contract.

Counts require int/i32. Zero count creates canonical null/zero ownership without
allocation or free. Positive counts allocate one contiguous initialized block.
Structural zero means integer zero, false bool/mask lanes, positive floating zero,
null void*, and recursive record zeros. It does not establish application invariants,
run constructors/setters, or give padding source semantics. Target layout supplies
stride and alignment, including records with padding. Negative dynamic counts,
checked physical size/address overflow and nonzero OOM trap before publication.
Traps do not unwind. Existing static-count diagnostics remain distinct from runtime
guards; no public uninitialized allocation is added. An explicitly selected
[allocation-failure action](allocation-failure.md) may run only on allocator null,
with an enforced fatal trap if it returns. It does not change element premises,
type inference, specialization keys or allocations inside called libraries.

```astra
var values = make_array<f64>(8);
var copied = clone_array(values);
var forwarded = relay_array(move copied);
values = clone_array(values);
values = relay_array(move values);
release values;
values = new f64[0];
```

A named owner must move explicitly. Copies, repeated moves, use after move/release,
self-move replacement and converting a borrow into an owner reject. Physical null/zero
after disarming does not make the moved binding usable. Incoming owners follow the
concrete replacement/rearm policy; borrowed parameter bindings remain immutable.
Scope exit, return, break/continue and early release dispose each still-live owner
in the established cleanup order. Returning an owner transfers its allocation, never
a pointer to a local descriptor. Direct allocation, named moves and direct owned-call
forwarding work in owning initialization/replacement/return positions. A discarded
owned result or an escaping non-owning capture rejects. Consuming call arguments still
require a named move; `relay_array(new int[8])` and inline factory arguments reject.

Replacement first completes the incoming producer, then disarms its named source if
needed, disposes the old live destination and publishes the complete new group. A
completed clone borrow ends before disposal. If incoming production traps, the old
allocation has not been freed. Same-call borrow plus transfer, later argument
invalidation, and indexed destinations or receivers invalidated by RHS effects remain
unsafe. A completed element snapshot can precede a transfer of its former source.
Fully concrete owning fields can receive/replace generic results, including cloning
the old field. Field moves/releases retain their existing exclusions.

Inference observes exact E from SliceType<E>; owned formals observe a named owner
without committing its move and ordinary call checking commits once. Bare owners still
fail the missing-move rule. Borrowed/owned slice, direct T and independent owned U
observations agree canonically in written order. Whole concrete generic records remain
one candidate. int/i32 deduplicate; nominal types never merge by layout. Result context,
counts and caller metadata supply no inference. `make_array(8)` therefore rejects even
with a typed destination. Literal arguments retain independent typing; no promotion,
partial type list, null wildcard, nested pattern or constructed formal solving is added.

See [ADR 0080](../decisions/0080-generic-owned-runtime-arrays.md) for deferred work and
[array production](../library/array-production.md) for explicit source selection.
