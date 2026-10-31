# ADR 0126: explicit qualified with captures

The bounded spelling is `with (config) { config.port ... }`, or
`with (var config = make_config()) { ... }` for a fresh scope-owned result.
The receiver must be an existing owned native Class local, including an owned
parameter's established local slot. Initializers use ordinary owner acquisition
and checked-call rules. The named binding cannot shadow an existing binding.
An initializer's owner is destroyed on all exits from the surrounding lexical
scope. A named outer owner remains owned by its original scope.

We examined leading-dot member lookup. The existing expression-receiver grammar
deliberately admits only bounded indexed projections and text byte_length;
implicit receiver lookup would add another name-resolution context and ambiguity
in nested scopes. Explicit qualification keeps fields, properties, free calls
and independently named receivers unambiguous. The construct is not a source
alias substitution: dedicated Checked and Core scope/capture identities bind
each qualified receiver use to the original owner slot.

The scope is synchronous and concrete. The receiver cannot be consumed, released,
rearmed, or replaced while captured. Direct overlapping field/property writes,
buffer exchange and structural owner-slot mutation reject. Potentially aliasing
native methods/helpers undergo the same transitive conservative readonly effect
check as foreach inspectors. Virtual dispatch, lazy initialization, unknown
effects and throwing inspectors are excluded. Unrelated checked calls, allocation
and throws remain usable and preserve cleanup. Plain get-only properties and
direct fields are supported; there is no expanded getter purity assumption.

Core independently verifies the exact source slot, containing function, owner,
live receiver type and active capture for each use. Text views retain their
original owner's existing lifetime authority; a fresh scoped owner's text cannot
escape to an outer destination or static-text return. Existing moved-owner flow
checks apply to the entry capture even for an empty body. Core also independently
guards consumption through owned arguments, field transfers, rearm, Shared and
closure acquisition.

CFG captures and null-validates the original Class pointer once on entry.
Qualified member uses share that captured value. The existing Class guard,
evaluation, field and call operations lower through SSA and native LLVM without
a new ABI or runtime service. Normal lexical cleanup handles early return and
checked exits. Classes without methods use the same Class pointer guard; with
does not invent a method receiver at CFG/SSA boundaries.

Qualification compares authored with and explicit lexical-scope equivalents at
O0/O1/O2 with exact factory/member/destructor traces and unsuppressed Valgrind.
Independent Checked/Core origin, escape and consumption mutations, and removed
CFG/SSA capture definitions, reject and verify again after restoration. A53
loads real UTF-8 configuration files and renders nested receivers, including
early return, explicit checked failure, empty/invalid UTF-8 and missing files.
