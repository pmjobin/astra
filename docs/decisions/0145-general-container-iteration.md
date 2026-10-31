# Iteration over general value containers

The existing checked container iteration contract now distinguishes complete
copied record snapshots from scoped Class/Resource inspection loans. The same
Vector source serves these domains. A copied binding is initialized once before
each loop body from the exact backing field and hidden index. Changing or
returning the snapshot does not change or retain the element storage.

Class/Resource bindings remain nonowning call-scoped views. Their native helper
must satisfy the transitive readonly inspection check. An explicit borrowed
foreign handle parameter does not establish readonly foreign effects; the
Resource witness uses an ordinary native nullness inspector. No foreign ABI or
unique ownership policy changes.

Checked-to-Core construction checks the copy/loan distinction and the complete
record snapshot association directly. Core independently reconstructs it and the
existing exact condition/step/collection contract. A mutated body cannot silently
omit the snapshot or read a different index. CFG and SSA use the shared complete
record result groups and consumption proof; no alias into record slot storage
survives that operation. Class/Resource loans end at their argument call boundary.
Structural mutation, relocation, source destruction and possibly aliasing helper
calls are conservatively refused within the source loop.

The public container witness combines a source-defined stateful iterator and
owned cursor buffer with Vector growth, fixed-array/slice nesting, record copies,
independent copied return after container cleanup, empty/break/continue/return,
and Class/Resource cleanup on checked failure. It checks exact output at
O0/O1/O2 with unsuppressed Valgrind. Negative controls cover reserve, take,
replace, release, effectful aliasing helpers, mutable inspectors and owner loans
stored as aliases. Independent proof controls erase Checked binding authority,
omit or change Core snapshots, truncate CFG groups and remove SSA consumption,
then restore each original before verification.

The first forged Checked test exposed a missing builder-boundary check: Core
would reject the malformed snapshot but the builder initially accepted it. The
builder now checks it explicitly. This failed attempt is retained in runtime
logs and does not count as passing evidence.

Iteration remains synchronous and concrete. Owning-record slot elements, async
iteration, arbitrary escaping generators and polymorphic iterator protocols are
outside this component. This is not final G3/G9 or A76 campaign acceptance.
