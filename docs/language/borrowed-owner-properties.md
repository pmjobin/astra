# Borrowed owner properties

An explicit native Class property can expose a temporary borrowed view of one
owned Class or Resource field while keeping the field private.

```astra
class Holder {
	private owned Child child;
	init(owned Child child) { this.child = move child; }
	property borrowed Child view {
		get { return this.child; }
		set(owned Child incoming) { this.child = move incoming; }
	}
}
```

The getter must contain exactly `return this.owned_field;` over the declared
exact Class or Resource type. It is synchronous, nonthrowing, direct and uncached.
The result can enter an exact borrowed parameter or compare with null. It cannot
be stored, copied, returned, captured, converted to an owner, or passed through
generic borrowing. The containing receiver stays borrowed through the complete
argument evaluation and call, preventing overlapping mutation or consumption.

An optional setter receives an explicit `owned` parameter of the same type.
`holder.view = move replacement;` commits the normal native owner transfer and
retires the previous field owner through its exact cleanup contract.
`holder.view = null;` clears the nullable owner slot. A Class replacement must
have heap provenance, as required by existing owned child fields. A borrowed or
lexical Class cannot become a persistent owned child.

Acquire a replacement as a named owner before assigning it. A checked producer
that fails before or after acquiring that temporary leaves the old property
owner intact; ordinary unwinding cleans an acquired temporary. Assignment itself
has no new throwing or allocation policy. Destructors retain their existing
nonthrowing contract. Direct producer assignment and checked accessor signatures
are outside this finite slice.

Plain computed getters continue to execute on every access. This addition
preserves the historical lazy-property qualification. A separate
[`lazy property owned`](properties.md#owning-lazy-results) form now supplies a
checked owned factory and bounded cache observation. Neither form permits
virtual borrowed getters, receiver-backed stored aliases, general borrowed
results or reflection.
