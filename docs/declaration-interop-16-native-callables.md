# Native void callables for foreign callback adapters

Native `Fn`, `Closure` and `CheckedClosure` signatures now permit an unmanaged
`void` result. This supplies a prerequisite for typed foreign callbacks and
signals. It does not by itself expose a native code pointer as a C callback.

```astra
void apply(Fn<void,int> code) { code(7); }
void apply_closure(borrowed Closure<State,void,int> code) {
	closure_invoke(code,7);
}
void apply_checked(borrowed CheckedClosure<State,Fault,void,int> code)
    throws Fault { closure_invoke(code,7); }
```

A void invocation is a statement. It cannot initialize a local, supply an
argument or manufacture a return value. Native ownership and borrowing channels
remain exact: a void callable can still consume an owned Class argument, retire
that owner on failure and preserve its borrowed environment during invocation.
Checked void closures retain their checked exception bound and native catch
behavior.

Core permits a void call only in its exact effect statement. CFG retains the
execution marker and rejects using it as a value. SSA calls and guarded checked
success operations have no result definition. The native function pointer plan
records an explicit `void_result` fact, distinct from both a scalar result and a
record result; detached validation rejects contradictory or omitted result
channels. Its identity and native-unit shape include that fact.

LLVM emits an actual void native call. A checked void closure returns only the
exception pointer and takes its environment and actual arguments. It has no
success-value pointer, allocation, publication or load. Existing scalar, record
and owned callable results preserve their existing representations. Native code
and closure environment pointers retain their typed native calling convention.

The integration recipe executes copied scalar/POD calls, generic invocation,
ordinary and checked closures, owned Class input cleanup and checked failure at
O0/O1/O2. Its opaque leaf → middle → consumer graph covers all eight O0/O2
combinations and O1, with producer implementations removed before downstream
compilation. Source rejection cases and detached Core/CFG/SSA/native/LLVM
mutations check that a void effect cannot become a scalar result. Actual memory
checks and source-bound results are recorded in the
slice ledger.

Typed foreign callbacks still need a distinct call-scoped carrier for code and
userdata, C/native calling-convention thunks and matching stage/layout checks.
This native prerequisite does not complete M16's callback or platform gates.
