# Explicit nonnull composition and effect-sensitive property guards

Explicit nonnull contracts now admit closed general-body Class applications,
borrowed native interfaces and exact native Fn code values. Fact reconstruction
still happens independently in Source, Core, CFG and SSA. Native code addresses
establish a code-value fact; a native Fn result may promise nonnull through its
existing unmanaged code channel. No cast from an integer or data pointer creates
such authority. Existing reference and Fn null-admission rules do not change.
Shared/Weak/Closure strengthening, unknown C contracts, open generic references
and virtual signature strengthening remain excluded.

An owned general container may initialize an explicitly nonnull child field.
Its pure borrowed property then observes the field's checked invariant. Nullable
borrowed properties also gain flow refinement: a null comparison identifies one
exact pure getter and one exact receiver. A later read of that same property may
satisfy a nonnull parameter within the proven path. Another receiver's matching
property does not share that fact. Cached/computed/virtual properties do not gain
this projection authority.

Each proof run creates canonical keys from its own receiver and property nodes.
The common fact store knows no predecessor graph. Ordinary native/C/code-value
calls, writes, owner dispositions, cleanup scopes and cooperative delays discard
projection facts and their captured Boolean implications. A fresh null check is
required afterward. This conservative profile keeps stable local/parameter facts
and separately declared nonnull-field invariants; it does not turn a nullable
field into a permanent promise or infer arbitrary helper purity.

Finite cooperative delay statements now participate in the normal nonnull proof
walk. A unique owning receiver, with a nonnull generic child, can remain live in
its existing frame across delays and moves. The ownership/frame verifiers still
prove retention, disarm and retirement. Nullable getter refinements are discarded
at suspension and must be checked again. Nonnull does not authorize a stored loan
or borrowed generic async parameter; general task/result and virtual nonnull
profiles remain separately bounded.

The public witnesses combine general container factories/fields, native interface
invocation, exact Fn code, short-circuit null guards, receiver projection and real
cooperative suspension. They execute at O0/O1/O2 with unsuppressed Valgrind. Public
controls reject null/unproved inputs, wrong code values, wrong receiver guards,
stale property facts after mutation/suspension and moved owners. The moved-owner
control rejects at the existing CFG liveness boundary; a raw Core dump precedes
that analysis and is not a final acceptance check.

Independent controls substitute null call arguments and move an ordinary call
between a guard and its protected use in Core, CFG and SSA, restoring every
change. Native/LLVM checks run after predecessor graphs are released. Existing
nonnull source/Core/CFG/SSA/field and foreign-boundary controls are rebuilt and
retained. Older interface and delay exclusions are explicitly promoted to
positive controls; unproved interface inputs and virtual strengthening still
reject.

The ABI comparison compiles one temporary source identity with equal byte spans,
then replaces only contract tokens with spaces. NABI/CABI signatures and raw LLVM
remain equal; async NABI source instruction positions differ because erased proof
obligations occupy SSA positions and are normalized only for that comparison.
The initial parity test incorrectly removed a keyword from error text and used
a different source identity; its failed receipt remains, and the corrected test
records each generated input hash. This component does not accept the full
G1–G9 campaign or A73–A84; LAZY-1 Q4 stays HELD/INCOMPLETE.
