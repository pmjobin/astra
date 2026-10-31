# Explicit generic method specialization

General-body Class templates can declare one method type parameter in addition
to the Class parameter. `U echo<U>(U value)` and `owned T forward<U>(owned T value,
U tag)` specialize ordinary method bodies. The caller supplies one explicit,
closed, recursively copyable U argument. Class T keeps its existing copied-record,
exact unique heap-Class or exact Resource transport. U does not erase owners.
The historical `where T : ExactHeapClass` recipe profile retains its restrictions.

Semantic checking maintains a canonical work queue keyed by Class application,
original generic member ordinal and exact U argument. Signatures close in the
caller's lexical type context; each original method body is checked in its own
T/U context. Calls discovered inside specialized methods join the same queue.
Closed methods have ordinary typed receivers, parameters, results and ownership
flows. This uses neither source rewriting nor a runtime box or dynamic registry.
The current bound is 1,024 closed method applications per compilation.

An immutable declaration schema distinguishes Class T from method U. Core, CFG
and SSA copy the key, rederive recursive U copyability from their own field/enum
graphs and verify the concrete signature and ordinary body. CFG/SSA reconstruct
logical copied-record parameters from complete physical groups. The copied U
cannot acquire a cleanup contract or weaken the owned T result/parameter proof.

Native metadata retains a pure argument descriptor, original generic member and
Class/target ordinals. Copied records retain their full canonical value plan and
frozen leaf declarations, including when U is absent from the physical signature.
Each function binds its original argument once. Erased keys, wrong declarations,
swapped instances, forged unused arguments and changed layouts reject without
access to predecessor compiler graphs. Enum arguments retain nominal copied
snapshot/result roles. The existing ABI channel verifier checks the scalar and
vector domain; raw void pointers confer no ownership.

The public witness uses one Store declaration over Class, copied record and
Resource domains. Method arguments include integers, booleans, a multi-leaf
record and a copied enum; a method with unused U tests metadata-only identity.
Forwarding Class/Resource owners preserves exactly one cleanup responsibility.
All dump stages, O0/O1/O2 native execution, exact cleanup output and unsuppressed
Valgrind are required by the generic public harness. Independent tests mutate
and restore stage keys, owned results and native layout/argument metadata.

This is a bounded G2 component. Symbolic method applications from unconcretized
free generic functions, method constraints, multiple U parameters, generic
properties, throwing/async template methods and nested container construction
remain outside this component. The campaign must continue through the remaining
G2 composition and G3–G9/A73–A84 gates. LAZY-1 Q4 remains HELD/INCOMPLETE.
