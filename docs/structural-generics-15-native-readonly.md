# Native readonly declaration facts

Native function metadata now includes a canonical boolean `readonly` fact. The
producer derives it from verified SSA using the existing scoped inspection
effect rules, with callback target inference disabled. Imported functions retain
the original declaration fact; empty imported bodies never prove readonly
behavior. Native ABI snapshots bind the fact once, validate correspondence with
SSA, and reject alterations after the predecessor is destroyed. The fact also
participates in the native signature and exported symbol identity.

Source, Core, CFG and SSA consumers require this original fact when a protected
inspection calls an imported function or getter. Existing direct, synchronous,
nonthrowing, nonconsuming and nonlazy checks remain. The shared checks also reject
owning record argument/result channels and owned buffer captures. Ordinary calls
outside protected inspection may still mutate their receivers.

The new `unit-readonly-*` graph contains a generic owned payload, an integer
property and copied generic record getter in the leaf library, readonly and
mutating functions in the middle library, and an owner-slot store in the client.
Only opaque artifact pairs remain during later compilation. Nine mixed O0/O2
and O1 combinations verify repeated observations, independent instances,
ordinary mutation outside the protected loan and exact cleanup, with nine
unsuppressed memory checks. Mutating protected inspection and missing,
noncanonical and changed metadata effects remain negative.

Four new stage proofs exercise imported readonly/mutating callback substitutions
in Core, CFG and SSA after predecessor destruction, and alteration of the
detached native effect fact. These remain independent malformed-model controls.

Conditional callback requirements build on this proof through the separate
[native callback contracts](structural-generics-15-native-callbacks.md). The
code-origin frontier retains nominated formal parameters independently of observed
callers and rejects opaque storage, unrelated formals and ungrounded cycles.
