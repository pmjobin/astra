# 0132: copied sequences and stateful native iterators

Implemented within the unfinished Language Generalization Surge 10 campaign.
This decision extends ADR 0125 without changing its readonly Bag element loans.

`foreach (var value in source)` admits a named fixed array, slice, owned array,
or exact native iterator Class. Array/slice iteration copies each element before
executing the body. Records derive copyability recursively using the existing
value authority. The binding is an ordinary independent value: it may be
modified or returned without borrowing the source. Source element writes affect
later reads; they do not alter an already copied binding. Moving, releasing,
replacing or exchanging the active source storage is rejected. No element loan
is held across the body, and no new stored view or owner alias is introduced.

A stateful iterator defines `bool advance()` and a copyable `current()` result.
Both are ordinary synchronous direct methods of an exact nongeneric native
Class. Each condition invokes advance once; only a successful true result calls
current, once, before the body. Either method may declare checked exceptions.
The iterator remains the unique owner of its own state, including existing
Class-owned buffers. Break and return retain the cursor position and perform
normal lexical cleanup; continue performs the next condition. No implicit reset,
clone, owner transfer, coroutine frame or new allocation is generated.

Checked and Core retain an explicit sequence contract, binding, loop target,
source identity and either hidden index or exact method identities. Core
independently reconstructs the index/length/step/copy shape or advance/current
calls. Specialization preserves the contract. Existing CFG/SSA storage,
bounds, ownership, checked-result and cleanup authorities verify the lowered
operations. Corruption tests reject absent contracts, altered indices, missing
copies, swapped iterator methods, source retirement, missing initialization
and missing bounds checks, then restore and reverify the originals.

When a loop body has no edge into its step, CFG lowering terminates the unused
reserved step as a disconnected function end. It does not manufacture a backedge
from a new disconnected root into live code. This preserves initialization
dominance after an early-return loop without weakening the verifier.

The source is named and synchronous. Polymorphic/generic iterator dispatch,
owning or borrowed current results, suspension, yield syntax and iterator views
over generalized owning elements require further work. Existing nullable
defaults and null receiver behavior remain. This is component evidence for G3,
not acceptance of all G1–G9 or the A73–A84 corpus.

See [source guide](../language/iteration.md) and
[normal Meson tests](../../tests/language-generalization-10/meson.build).
