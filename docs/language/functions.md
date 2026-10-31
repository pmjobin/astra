# Native functions and callable contracts

DIAG-1 permits a trailing suffix of [caller-information parameters](caller-information.md)
on native free/generic functions, methods and constructors. Omitted suffix
positions become ordinary string/int constants during semantic checking; all
parameters remain in the full signature. Explicit values obey ordinary rules.

Plain native Resource, Class and Slice parameters select the existing bounded
BORROWED_NOESCAPE contract. Explicit `borrowed` is equivalent; `owned` means
transfer. Scalars/vectors remain values and copyable structs remain COPY_VALUE.
See [parameter borrowing](parameter-borrowing.md) for the complete matrix,
noescape rules and intentional compatibility changes.

[Generic functions](generic-functions.md) are supported at top level in GEN-1:
`T identity<T>(T value) { return value; }`. Generic and ordinary functions share
one callable name namespace without overloading. Each definition owns exact
lexical type parameters and is checked once, including unused definitions.
Generic main, members, C boundaries and generic ownership remain unsupported.

F64-1 supports exact f64 native parameters/results, recursion, methods and
constructor parameters. Arguments and results require matching type or explicit
f32↔f64 `as`; no implicit promotion exists. F64 fields follow ordinary native
scalar-field rules. F64 can coexist with borrowed/owned objects and Resource,
including an owned object result with hidden caller-storage PTR. Existing argument
evaluation, transfer commit and cleanup order remain unchanged. By-value f64
selects [fp64-v6](../abi/native-fp64-v6.md); C/VAPI floating signatures reject.

[Owned ClassType results](object-results.md) are supported on ordinary native functions and struct/class methods. Fresh construction, null, move of an owned parameter, and exact owned-result forwarding share the existing result contract. A hidden physical storage PTR precedes the receiver and explicit parameters, without becoming a source parameter.

Native declarations use `result-type name(parameters) { ... }`, with no
`function` keyword. A supported owned Resource or ClassType result may prefix the result type
with `owned`. Explicit parameters use ordinary exact type checking and optional
`borrowed` or `owned` contracts where the type permits them. All signatures are
collected before body checking; forward calls, recursion and mutual recursion
are supported. See [direct calls](calls.md) for resolution and evaluation rules.

Native [struct and class methods](methods.md) reuse this declaration syntax inside a
struct or class and the same parameter/result checker. Each method adds one implicit
receiver contract, separate from the source parameter list. `this` denotes exact
mutable instance storage and cannot be supplied or rebound as a source parameter.
Method names belong to their struct's field/method namespace; free-function names
are independent. `this.method(...)` and `local.method(...)` bind exact static
member targets, without a free-function fallback.

Supported explicit boundaries include exact integers, bool, f32, f64, vectors, void*
and nominal handles, supported typed-pointer parameters, plain or `borrowed T[]`
parameters, plain or `borrowed ClassType` parameters, and owned Resource/ClassType
parameters/results. Borrowed objects are nullable, mutable, aliasable and noescape;
local copies and forwarding use function-region authority without transferring
caller ObjectStorage cleanup. Unqualified/borrowed ClassType results reject. Constructors reuse these same parameter rules. See
[borrowed object parameters](borrowed-object-parameters.md). Typed-pointer and slice
results still lack return-lifetime contracts and reject. Arrays remain storage
aggregates without native by-value boundaries. Concrete copyable structs have
[native COPY_VALUE parameters/results](struct-values.md), including exact
concrete generic-origin instances. Parameter storage is independent and read-only.
Struct-returning calls have bounded initialization, assignment, argument and
return consumers. Whole leaves snapshot at each argument position and before
return cleanup. Such signatures select aggregate-v7; receiver policy is unchanged.

Calls evaluate explicit arguments left-to-right. A method first prepares its
receiver. Owned argument capture and final transfer commit, owned result
consumption, borrowed noescape rules, trap ordering and ordinary return checking
are shared. Calls remain conservatively effectful, including discarded results.

Native physical signatures use the existing NABI profiles and LLVM internal
fastcc. Methods add a PTR receiver channel after any hidden result-storage channel; explicit parameters/results
retain existing mapping and slice grouping. Methods cannot be C imports,
exports, VAPI members or program entry points. Only a free `int main()` or `int main(string[] args)` is an
executable entry. No overload, function/method value, delegate, closure, static
method, generic method or virtual dispatch is introduced. Class lifecycle uses
its [dedicated construction syntax](object-lifecycle.md).

## Explicit generic capabilities

Top-level generic functions may declare `where T : Eq, Ordered` after their
parameter list and before their body. Separate clauses constrain additional type
parameters; each parameter has at most one clause. Every call checks all exact
requirements, including phantom arguments. See [generic capabilities](generic-capabilities.md).

## Multi-source composition

All supplied [source files](source-files.md) share the existing function namespace.
Native signatures are collected globally before bodies: forward calls and mutual
recursion need no prototypes, regardless of CLI or declaration order. Duplicate
functions and multiple `main` declarations reject globally. One executable still
requires native `int main()` or `int main(string[] args)`; check/dump modes need no entry. See [process arguments](process-arguments.md) for the opt-in text-entry provider.

## Immutable text boundaries

TEXT-1 supports string parameters/results on native free functions and methods,
and string constructor parameters. Plain/explicit `borrowed string` parameters
canonicalize to BORROWED_NOESCAPE and retain immutable parameter bindings. Locals
can copy or reborrow the view. Unqualified string results require definition-level
STATIC_TEXT proof on every return path, including recursive definitions. Borrowed
inputs and mixed static/borrowed joins cannot escape; caller literals never prove
a callee result static. Owned string and foreign string boundaries reject.
See [text](text.md) and [native text-v9](../abi/native-text-v9.md).
