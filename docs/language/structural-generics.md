# Structural generic declarations and ownership

The current generic contract follows [ADR 0165](../decisions/0165-structural-generics-and-typed-native-units.md).
Closed instances derive their fields, members, effects and ownership from their
declarations. Collections use this same authority; a library type's name does
not grant special storage or transport permissions. Earlier exact-Class bag and
free-function profiles remain historical component descriptions.

```astra
class Cell<Value, Tag> {
	Value value;
	Tag tag;
	init(Value value, Tag tag) {
		this.value = value;
		this.tag = tag;
	}
	Value read() { return this.value; }
	property Value item {
		get { return this.value; }
		set(Value value) { this.value = value; }
	}
}
Value observe<Value, Tag>(borrowed Cell<Value, Tag> cell) {
	return cell.read();
}
int main() {
	var cell = new Cell<int, bool>(41, true);
	cell.item = 42;
	return observe(cell) - 42;
}
```

Plain value positions require recursively proved copyability. The example also
admits a copied record as Value; copying that result does not alias the original
record storage. Multiple type parameters and independent bookkeeping fields are
ordinary declarations. An open helper must prove its operations from its declared
parameter/storage premises, even if current callers happen to choose one type.

`owned T` is structural at a type-parameter-bearing occurrence. Substitution of a
scalar or copyable record gives ordinary copied inline storage; substitution of
an owning record gives its complete move-only inline graph; substitution of a
Class, Resource or supported Shared/Weak handle preserves that owner's existing
transfer and cleanup contract. This does not make concrete `owned int` legal or
add scalars/records to the separate `Ownable` capability. A Class field needs an
independently owned admissible child, not a borrowed or lexical pointer dressed
as one. Generic records can themselves contain explicit owned leaves and buffers.

Members may use ordinary checked bodies, branches, loops, independent generic
method arguments and copied or explicitly owning/borrowed property channels.
Selected synchronous owning lazy caches retain first-success publication and
checked rollback. Complete record moves, replacements and result projections
retain every initialized leaf and its original allocator; a physical pointer or
matching layout supplies no ownership authority. Partial field extraction and
mutation require their own complete place/alias proof.

Borrowed parameters and receiver-bounded getters keep their actual backing roots
live. Supported record/buffer observations do not consume those roots. Loans
cannot escape, overlap invalidation or survive an unsafe suspension. Explicit
owned async environments/results can contain eligible closed generic and owning
record graphs; worker transport additionally requires transitive Send. Ordinary
method borrowing does not become an escaping receiver capture.

Fn, Closure and CheckedClosure retain exact result/argument signatures. Admitted
copied-record, owning and borrowed channels preserve the qualifiers in their
physical call plan. Closure binding transfers one explicit environment, which
may be a closed generic Class. CheckedClosure has its exact named Error bound;
catching a failure leaves its borrowed environment reusable. General implicit
stack capture and arbitrary borrowed foreign retention remain outside this profile.

Native units export selected closed nominal types and method applications.
Dependencies carry complete checked declarations, exact object/interface digests,
ownership/callable/error/task contracts and provider identities. Consumers cannot
specialize an unexported producer body or recover its implementation from metadata.
The current GNU schema is `/6`; [native units](native-units.md) describes current
fingerprints, dependency resolution, object-derived optimizer facts and rebuild
requirements. No stable cross-version ABI is promised.

Specialization is bounded to 16,384 closed declaration requests, type-expression
depth 128, 256 native units and dependency depth 64. Infinitely sized records and
expanding specialization receive separate refusals. These budgets are resource
limits, not limits on a collection's spelling or required field/body pattern.

The current source witnesses are the individual cases in
`tests/structural-generics-15/execute.py`, its generality/native-unit/callable suites
and the M17 context/frame/record/opaque-unit suites. Historical M15/M17 evidence
keeps its original revisions. The feature ledger
records the scope and source-bound witnesses for M18 registry and installed replay.
