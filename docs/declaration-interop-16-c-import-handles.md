# Typed imported object channels

An imported Class can borrow another declared imported Class and return an owned
instance of that Class. Every channel retains its exact nominal root, declared
public release protocol and private native Resource cleanup. Equal pointer widths
grant no conversion between roots. Forward declarations work because admission
collects all imported root identities before member signatures.

```astra
[Foreign(error_factory="foreign_fault", error_domain="16", errors="Fault=-1600")]
int inspect(borrowed Item input) throws Fault;

[Foreign(error_factory="foreign_fault", error_domain="16", errors="Fault=-1600")]
owned Item make() throws Fault;

[Foreign(error_factory="foreign_fault", error_domain="16", errors="Fault=-1600",
         null_status="1")]
[ForeignChannel(parameter="result", nullable="true")]
owned Item lookup(int key) throws Fault;
```

Borrowed object inputs are call-scoped. A mandatory null input or self receiver
fails with domain-zero `0x80004003` before the provider runs or outputs change.
An explicitly nullable input can carry an empty Resource. A mandatory owned result
must contain an owner; an explicitly nullable result may be empty. The optional
positive `null_status` succeeds only with an empty result and a cleared error
record. Other positive statuses, contradictory records and missing mandatory
owners remain checked infrastructure failures.

The result's root selects retirement. An owned `Item` returned by `Provider`
retires through Item's provider protocol. The adapter retires dirty provisional
owners on status errors and invalid produced counts before constructing the
native exception. Mutable counted outputs and scalar outputs publish after all
validations. There is no added native proxy or reference count.

A shared imported root can expose an ordinary owned-returning duplication method.
Its independent provider acquires one reference; the native caller gets a second
linear Resource duty, and each duty releases exactly once. A unique provider's
duplication method instead creates a distinct owner. The compiler derives the
same transport from either declaration and implements no duplication algorithm.

The witness combines a unique Child root declared after Provider, nullable queries,
mandatory and nullable borrows, provider-defined duplication, failed partial
object creation and staged byte/count outputs. Unique/shared Provider variants
run at O0/O1/O2 with independent and generated-header clients and unsuppressed
Valgrind. Detached stages reject substituted nominal roots and omitted root
authority; an ordinary-valid LLVM mutant selects the wrong same-signature cleanup
without executing it.

The [consuming slice](declaration-interop-16-c-import-consuming.md) adds owned
parameters and explicit input duties. Imported properties, weak operations and
callbacks remain subsequent M16 work. The
[foreign-handle export slice](declaration-interop-16-foreign-handles.md) adds typed
Resource export channels alongside native Class wrapper/heap rules. Declaration-derived COM/GObject,
opaque SDK composition and full acceptance qualification remain incomplete.
