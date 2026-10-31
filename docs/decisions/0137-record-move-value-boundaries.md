# ADR 0137: derived record MOVE_VALUE boundaries

Status: implemented scalar-owner component of unfinished Surge 10.

A concrete record containing owned fields derives `MOVE_VALUE` for native
parameters and results. Its declaration and function signatures need no extra
move-only annotation. Recursively copyable records retain `COPY_VALUE`.
`MOVE_VALUE` remains a value boundary with complete field responsibility; it
does not become an identity pointer or borrow a Resource destructor as its root
cleanup authority.

An argument transfers an explicit whole move of a named owning record. All
argument values are captured before committing that move. A checked failure in
a later argument leaves the source live. Once the call starts, the callee owns
every transferred field, including on checked failure. An owned record factory
initializes a fresh local or forwards a complete result directly from a return.
Inline factory arguments use a named local followed by its explicit move,
matching the established named-owner argument rule.

Successful parameter/result acquisition creates a complete new value lifetime
in recursive declaration order. Its destruction follows the reverse of that
order. Local construction rollback still follows actual written acquisition
order, and whole-local moves still preserve that local order. This distinction
avoids transmitting mutable cleanup ranks as runtime value data. Different
parameters retire in reverse formal declaration order, including when a record
is adjacent to a separate Class owner. Ordinary incoming scalar-field updates
retain the established requirement for a fresh mutable local.

Checked and Core producers retain the exact derived mode. Core independently
verifies complete root responsibility and delayed argument disposition. CFG
acquires each complete parameter/result group atomically and binds every move
to its exact call or return. SSA snapshots the original owner paths/ranks and
binds complete acquisition/disarm events to those groups. A transfer cannot
precede another argument effect. Disarmed pointer joins are proved from every
incoming edge; a null-only join is not an uninitialized or live owner.

Native signatures carry copied field cleanup authority alongside their physical
scalar channels. Canonical native record declarations bind both local cleanup
obligations and value-boundary obligations to the same exact ordinal paths,
nominal types and Resource/Class cleanup kinds. The independent native verifier
can therefore reject a substituted destructor after Checked/Core/CFG/SSA have
been freed. LLVM retains its existing physical cleanup operand audits.

The executable witness covers triple-nested Resource/Class records, factories,
method transport, direct result forwarding, Class extraction from a parameter,
checked factory/callee/argument failure, scalar inspection before transfer and
mixed parameter destruction order. O0/O1/O2 runs use exact independent observer
traces and unsuppressed Valgrind. Corruptions remove acquisitions/commits, move a
commit before another argument effect, reorder parameter cleanup, substitute a
native destructor, omit obligations and alter LLVM cleanup operands after
earlier graphs are freed.

This first boundary profile supports scalar Resource/Class owners and copied
scalar/vector companions in synchronous nongeneric contexts. Complete buffer
pair transport, owning tagged alternatives and generic/async composition remain
required work. Separately compiled exports still require G7's versioned module
contract. No C/GObject ABI or nullability default changes here.

The buffer boundary extension is documented in [ADR 0138](0138-record-buffer-value-channels.md).
