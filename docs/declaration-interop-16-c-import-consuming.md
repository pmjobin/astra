# Consuming imported object parameters

An imported method can declare an `owned Item` parameter. The channel's full
transfer follows that source ownership contract, and the public C entry point
receives `item_handle **`. The native call consumes the caller's Resource duty
on entry, including when validation or the provider operation fails.

```astra
[Foreign(error_factory="foreign_fault", error_domain="16", errors="Fault=-1600")]
int take(owned Item input) throws Fault;

[Foreign(error_factory="foreign_fault", error_domain="16", errors="Fault=-1600")]
owned Item relay(owned Item input) throws Fault;
```

Checked/Core use the ordinary owned-parameter acquisition prologue. The typed
foreign-return operation names every consumed owner in declaration order. CFG
requires the exact acquired local duties and ends those responsibilities at the
boundary. SSA requires the exact incoming owned parameters. Each stage rejects
missing or substituted duties; the native ABI independently requires matching
nominal Resource cleanup and owned-transfer channels. The dumps expose the
consumed-duty count.

LLVM initializes private owner slots before receiver, place, count or allocation
checks. C can consume an input by clearing its slot, retain that owner in provider
state, or relay it to an owned result. On every return path, the bridge retires any
remaining private owner through its exact provider root. It clears the private
slot before invoking retirement, and processes remaining duties in reverse order.
Early validation failures and staging allocation failures therefore retire inputs
before constructing native exceptions. A C refusal does not restore an owner to
the already-consumed native caller.

Result validation and mutable-output publication follow input retirement. An owner
relayed to a result has left the input slot, so the bridge publishes the returned
duty without disposing it. Two shared Resource duties may contain the same provider
pointer; the provider owns the corresponding reference counts. Unique duplication
requires distinct owners. No extra native reference count or proxy is introduced.

The witness covers all four unique/shared Provider and Child combinations at
O0/O1/O2, independent and generated-header C consumers, and unsuppressed Valgrind.
It exercises C consumption, untouched input slots on success/error, consumption
before error, invalid produced counts, first/second staging allocation failures,
missing receivers and mandatory places, empty owned inputs, deferred provider
storage, owner relay and paired shared duties. Detached Core/CFG/SSA mutations omit
consumed duties; a native mutation removes owned transfer; ordinary-valid LLVM
mutants pass a raw owner instead of its slot and retain a slot before cleanup.
Corrupted ABI code is never executed.

The [foreign-handle export slice](declaration-interop-16-foreign-handles.md) carries
typed imported Resources through native Class boundaries. Imported properties/weak operations, callbacks,
declaration-derived COM/GObject, opaque SDK composition and the complete M16
acceptance matrix remain active work. This slice does not complete M16.
