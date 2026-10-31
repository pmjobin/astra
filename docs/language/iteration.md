# Iteration

`foreach` supports these observation channels in synchronous concrete code:

| Source | Binding | State and invalidation |
| --- | --- | --- |
| Exact `Bag<T>` or general `Vector<T>` with Class/Resource T | Call-scoped readonly element loan | Structural mutation, relocation, replacement, owner consumption and loan escape reject during iteration |
| General `Vector<T>` with copied record T | Complete independent record snapshot per iteration | Structural mutation and source consumption reject during the loop; a copied binding may be changed or returned |
| Named fixed array, slice or owned array | Copied scalar/vector or recursively copyable record | Source extent/storage cannot be rebound, moved, released or swapped during the loop; element updates are allowed |
| Exact native Class with `advance()` and `current()` | Copied current value | Cursor state stays in its original Class; the source cannot be consumed during iteration |

```astra
int[3] values = {2, 4, 6};
int total = 0;
foreach (var value in values) {
	if (value == 4) { continue; }
	total = total + value;
}
```

Each indexed binding is a snapshot taken before the body, including a recursive
record copy. Changing the binding does not change the source element. Changing
source elements affects subsequent reads. A slice retains its existing checked
backing-storage lifetime; iteration does not extend that lifetime. A copied
value may leave the loop, while the binding's name is scoped to its body.

An ordinary Class can implement a stateful sequence:

```astra
class OddNumbers {
	int index;
	int count;
	init(int count) { this.index = -1; this.count = count; }
	bool advance() { this.index = this.index + 1; return this.index < this.count; }
	int current() { return this.index * 2 + 1; }
}
```

Pass a named instance to `foreach`. It calls advance for each condition and
current exactly once when that condition succeeds. Both methods may throw
declared checked exceptions, with the usual caller throws/catch requirements.
The iterator may own state such as a buffer; generated code never copies that
owner. Empty iteration, break, continue, return and checked failure use ordinary
scope cleanup. A break leaves a live iterator positioned at the last value;
another loop continues by calling advance again. Releasing the original owner
after iteration retires its state normally.

The iterator methods must currently be parameterless, direct, synchronous
members of an exact nongeneric Class without a hierarchy. Advance returns bool;
current returns an ordinary copyable value. Owned results and escaping loans
are refused. This protocol provides explicit source-defined cursor state;
coroutine generators, async iteration and polymorphic iterator interfaces remain
outside this component's implemented scope.

The [fixtures](../../tests/language-generalization-10/sequence.astra) and
[stateful witness](../../tests/language-generalization-10/iterator.astra) exercise
checked failures, early exits, nested iteration, Bag growth and destruction.
The [record iterator](../../tests/language-generalization-10/iterator-record.astra)
also exercises a checked copied-record current result.

The [container witness](../../tests/language-generalization-10/container-iteration.astra)
uses the same `Vector<T>` over records, Resource/buffer-owning Classes and exact
Resources. It grows the container from a source-defined stateful iterator, nests
borrowed slice iteration, checks independent record mutation/return, and proves
empty, continue, break, early return and checked failure cleanup. A Resource loan
can enter a readonly native inspector (for example a nullness test). Foreign
handle calls are still excluded from readonly inspection unless independently
qualified; borrowed pointer syntax alone does not establish a foreign effect.

Checked and Core container contracts retain the exact backing field, hidden
index and copied binding. Core reconstructs the required record snapshot before
each body. CFG/SSA lower that snapshot through complete copied record groups and
explicit consumption. No record snapshot holds an alias into relocatable storage;
Class/Resource inspection loans end at their checked call boundary. Structural
mutation within the source loop remains conservatively refused.
