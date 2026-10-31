# Allocation-failure actions

```astra
void report_allocation(int code, int count) {
	// Ordinary native code; returning is legal.
}

owned T[] make_array<T>(int count, int diagnostic_code) {
	return new T[count] else report_allocation(diagnostic_code, count);
}
```

An optional `else` call belongs only to its runtime-array allocation expression.
The direct named or supported member call must return exact void. Parentheses
around it, and the call's already legal explicit/inferred generic arguments, are
allowed. Blocks, non-call expressions, non-void results, owner fallbacks, missing
or repeated clauses, delegates, callbacks, named arguments and new temporary
receiver forms are not allowed. Ordinary if/else and semicolon rules are unchanged.

Evaluate count once at the allocation's original position. Existing static count
diagnostics and dynamic validation remain. Zero produces empty null/zero ownership
without allocation/free. A positive representable request calls the existing
allocator and publishes initialized ownership only on success. Only a null
allocator result evaluates the action receiver and arguments, once and in written
order, using the bindings and state then in effect. After normal action return,
the compiler executes a fatal trap. The next statement cannot run.

The action is not recovery. It cannot supply another array, retry, return from the
enclosing function, intercept a bounds trap, or handle faults after an allocator
has reported success. Negative counts, physical-size overflow and count-expression
traps skip it. Both count and call are nevertheless statically checked even for
literal zero. A declaration is unavailable in its own initializer.

Use a saved count when its producer has effects:

```astra
int count = next_count();
var values = new int[count] else report_allocation(17, count);
```

Writing `next_count()` again inside the action requests a second evaluation on
failure. Compiler-created literal caller data may be static; runtime receiver and
argument expressions are never precomputed for this branch. CallerFilePath,
CallerLineNumber and CallerArgumentExpression identify the written failure call
and arguments, including calls in generic definitions. Relative invocation labels,
opt-in source privacy and borrowed text lifetime rules remain unchanged.

The form is available in already legal owning local and parameter replacement,
concrete owned-field initialization/replacement, direct owned returns and forwarded
results. It does not legalize an inline consuming argument, constant or fixed-array
declaration. Existing concrete elements and signature-derived generic
COPY/STORAGE/ZERO/DESTRUCTION premises are unchanged. `make_array<int>(count, 17)`
needs explicit int because ordinary arguments do not infer T. Diagnostic arguments,
caller metadata and destination type provide no new contextual inference.

Replacement first produces the new owner. On failure the old allocation is live
at action entry, so an otherwise legal old view or `len(values)` may be reported.
Explicit moves/borrows in this separate terminal path follow ordinary ownership,
overlap and captured-receiver restrictions. Moving an independent owner only in
the action leaves it live on allocation success. No implicit transfer, owner copy,
partial owner, early compiler cleanup or runtime ownership flag is added.

The compiler does not unwind caller owners. An action may report and return,
terminate or itself trap; a returning callee can normally clean its own locals
and consumed parameters before the caller's fallback trap. It can allocate or
release resources explicitly. Keep OOM reporting small and avoid allocations
where practical: there is no emergency allocator or recursive-failure recovery.

A clause does not dynamically propagate to allocations inside called functions.
The unchanged clone_array/filled_array library retains its own default new.
Ordinary unannotated new and bounds traps need no failure provider. Native actions
need foreign ABI only when their bodies select foreign calls. C actions use
existing explicit source/VAPI/object linking and scalar/text contracts. Initial
target coverage remains hosted GNU LP64 x86-64 Linux.

Application units are independent of physical size. The CAD example requests
4,194,304 nine-f64 Kernel records (301,989,888 bytes); its historical error value
37,748,736 counts f64 slots. Application code converts these units under its
validated bounds. The compiler knows neither CAD nor the factor nine.

See the [installed example](../../examples/allocation-failure/README.md) and
[ADR 0082](../decisions/0082-allocation-failure-actions.md). General recoverable
allocation is deferred without deciding its eventual spelling.
