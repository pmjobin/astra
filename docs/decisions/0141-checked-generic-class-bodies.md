# Checked generic Class bodies

Surge 10 first removes the fixed wrapper-body recipe from an explicit general
template profile. `class Depot<T> { ... }` specializes its ordinary checked
member bodies using the existing semantic declaration materialization. This is
not source-text substitution. `where T : ExactHeapClass` retains its previously
qualified finite recipe and source refusals.

The general profile currently has one owned `T[slots]` field and one constructor.
Its synchronous direct members accept `T`, int and bool and return owned `T`,
int, bool or void. Constructor parameters are checked normally. Bodies may use
ordinary statements, branches, loops and member calls. Definite initialization,
move liveness, checked storage operations and automatic destruction retain their
existing authorities. Methods with their own type parameters, properties,
inheritance and asynchronous/throwing template members are still excluded.

An immutable definition identity carries each member's declared type roles and
ownership roles, independently of syntax and predecessor graphs. Core, CFG and
SSA reconstruct the exact concrete signature and continue their normal body
verification. They do not demand one fixed operation or one basic block. The
native verifier checks declaration ranks, exact Class argument identity, typed
parameter/result channels and allocation provenance. Existing typed LLVM
operation and full helper-body audits remain active.

`generic-body.astra` exercises one definition with two distinct Class arguments,
constructor capacity, conditional growth, a loop calling another member,
continue, owned append, owned return and conditional replacement. Public
O0/O1/O2 and unsuppressed Valgrind executions check resulting state and cleanup.
The independent proof fixture releases each predecessor graph and corrupts and
restores specialization keys, signatures, native member targets and ownership.
Historical exact-Class source and native controls remain required regressions.

This is a G2 implementation component. General element storage for copyable
records and move-only Resources/records, broader generic methods, iteration,
cross-unit transport and integrated applications remain required before G2 or
Surge 10 acceptance. No source-level owner erasure or runtime type registry is
introduced by this component.
