# Native Shared and Weak handles

Current GNU Linux threaded lifetime and `[Shared]`/Monitor policies are described
in [concurrency](concurrency.md). They use qualified atomic count operations and
transitive thread capabilities; lifetime thread safety does not make mutable
payload state thread safe. The single-threaded boxing profile below is its
historical predecessor. [Semantic optimizations](semantic-optimization.md) require
separate proofs before removing any balanced count operations.

`Shared<T>` and `Weak<T>` opt into single-threaded shared lifetime for an exact
concrete native Class. The first profile excludes interfaces as payload types,
generic Class applications, Resources, raw pointers, async transport and C ABI
transport. Ordinary unique Class objects keep their existing allocation, layout
and cleanup path.

```astra
class Counter {
	int value;
	init(int value) { this.value=value; }
}
int read(borrowed Counter counter) { return counter.value; }
int main() {
	var unique=new Counter(7);
	var strong=shared_acquire(move unique);
	var copy=shared_clone(strong);
	var observer=shared_downgrade(strong);
	release strong;
	var acquired=weak_upgrade(observer);
	if(acquired==null) { return 81; }
	if(read(shared_borrow(acquired))!=7) { return 82; }
	release copy;
	release acquired;
	var expired=weak_upgrade(observer);
	if(expired!=null) { return 83; }
	return 0;
}
```

| Operation | Contract |
| --- | --- |
| `shared_acquire(move unique)` | Surrenders one exact independently allocated Class owner and creates its first strong handle. Borrowed and lexical Class storage are refused. |
| `shared_clone(strong)` | Creates another explicit strong owner of the same payload. |
| `shared_downgrade(strong)` | Creates a weak observer that keeps only the control block alive. |
| `weak_clone(observer)` | Creates another weak observer. |
| `weak_upgrade(observer)` | Acquires a new strong owner while the payload is live; returns null after expiration. |
| `shared_borrow(strong)` | Projects the payload only as an inline argument to an exact borrowed Class parameter. The backing strong owner stays live through the call. |
| `release handle` | Discharges one handle. Lexical exit and checked unwind supply automatic cleanup. |

Handles move through owned locals, parameters, results and owned Class fields;
copying an owner requires an explicit clone operation. Borrowed Shared/Weak
parameters can inspect or clone their handle without consuming the caller's
owner. Handle specializations have exact identity: there is no implicit
`Shared<Derived>` to `Shared<Base>` conversion.

Payload projections cannot be stored or returned. To inspect an owned handle
field, first clone it into a named strong local, then borrow that local. Dropping
or consuming the backing handle during argument evaluation is rejected. Guard
nullable upgrade results before projection; projecting null traps. Clone and
downgrade operations preserve null, and upgrade of null also returns null.

The separate control block stores strong and weak counts plus the payload
address. Last strong release clears the payload address, runs its exact native
destructor chain once, and frees payload storage once. A weak sentinel protects
the block until that destruction returns. Final weak release frees the block.
Counter overflow/underflow and allocation failure trap; allocation failure does
not promise checked rollback. Counts use ordinary single-threaded memory, with
no cross-thread, executor or foreign retention guarantee. Strong cycles are not
collected; use weak backedges for observers.

The implementation decision and count invariants are recorded in
[ADR 0110](../decisions/0110-native-shared-weak-lifetime.md).
