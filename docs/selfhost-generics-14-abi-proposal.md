# GENERICS-14 bounded private Class receiver proposal

Status: approved in the native session by the owner's explicit response,
"Approve the bounded private receiver ABI". The original proposal identity and
approval are retained in the task runtime. Approval is not qualification.
NATIVEABI-13-R1 explicitly records receiver/hidden-result channels as absent.

The frozen `method-concrete` and `method-outer` programs both pass current C0
at O0 and O2. They need direct instance methods on a nominal generic native
Class, with concrete receiver selection and method-level type arguments.

Proposed initial domain: native Classes with no parent, interface, dispatch,
foreign metadata, fields or deinitializer; one empty, parameterless init;
methods selected statically by declaration and enclosing instantiation.
Method bodies must remain in the already supported scalar/value/owner domain.
Field-bearing Classes, custom destruction and virtual calls remain DEFERRED.

Represent each constructed empty Class as a distinct live allocated object
with at least one byte of storage, rather than an erased constant. A private
method receives one explicit hidden borrowed pointer before its source
parameters. That channel retains the exact nominal Class TypeId and instance
identity in the checked signature, Flow loan, Core/CFG/SSA and native ABI plan.
It grants no noalias, capture, alignment or validity attributes. Receiver
evaluation precedes source arguments. Moving or freeing the owner during the
loan is rejected. Ordinary scoped retirement frees each live owner once;
allocation failure retains the existing fatal-allocation policy.

No generic or Class pointer is exported or imported through the public C ABI.
The representation is private to the compiled source set. Symbol keys include
the method declaration, ordered enclosing/method type arguments and the
qualified ABI policy; independently verified machine layout remains separate
from target-agnostic Typecore identity. Source-unit ordering cannot select a
different instance or produce duplicate public definitions.

Approval would authorize implementing and qualifying this bounded convention,
not claiming it passes. Acceptance still requires the frozen C0 executions,
actual Astra LLVM/ELF execution at both profiles, independently checked receiver
plans, malformed-receiver/owner/ABI mutations and unsuppressed memory evidence.
