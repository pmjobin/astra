# Explicit owning closure values

`Closure<Env,Result,Args...>` is a distinct linear native handle. It requires an
exact concrete nongeneric, nonpolymorphic native Class environment, a copied
numeric or bool result, and up to four copied numeric or bool arguments.
`closure_bind(move environment, named_code)` takes an independently allocated
heap environment and a nonthrowing native function whose first parameter is
`borrowed Env` and whose remaining signature exactly matches the closure.

The runtime carrier contains three pointers: native code, environment, and the
exact native environment destructor. The carrier and environment are both
owned. Invocation loads the transported code and environment and applies the
native calling convention. Final cleanup loads the carried destructor, destroys
the environment and captured owners once, then frees environment and carrier.
The semantic/Core/CFG/SSA cleanup authority retains exact Env identity; it is
never an arbitrary C cleanup symbol or a data-pointer-to-code cast.

`closure_invoke(function,args...)` borrows the carrier for one synchronous call.
Locals and native owned parameters/results use existing exact Resource move and
cleanup channels; borrowed parameters cannot escape. Scalar argument checking
cannot consume the backing carrier. Environment fields can explicitly move
unique Class owners or cloned `Shared<T>`/`Weak<T>` owners, with their original
cleanup. Ordinary `Fn` values remain copied code pointers without a carrier.

Raw or typed pointer fields in the environment and its owned Class/buffer capture tree are refused; shared payload internals retain their existing explicit lifetime policy.

The initial form excludes checked code targets, aggregate/owned return values,
implicit captures, borrowed fields, stack environments, polymorphic or generic
environments, async migration, foreign casts and retained callbacks. A checked
caller may own a nonthrowing closure: ordinary checked unwind destroys its
captures. Checked exceptions *through* indirect closure invocation are not part
of this signature profile and are refused at binding.

The separate syntax is intentional: an existing Class `invoke` method does not
become an owning closure value, and no lambda inference is introduced. Native
Class environment semantics supply capture ownership; typed carrier/code
operations supply the distinct first-class closure.
