# Native sum-values-v12

This internal native profile transports concrete copyable enums. It has no C,
serialized-layout or cross-version ABI promise. Functions without enum boundaries
retain their existing native signature profile even in a program containing enums.
Each logical enum parameter is one PTR channel with exact nominal identity and
read-only snapshot role. An enum result is void physically, with one hidden PTR
caller-storage channel preceding the existing receiver/explicit parameter channels.
Other scalar/vector/record/text/owned groups keep their existing contracts.

The supported native target's data-layout authority determines each alternative's
natural field layout, including whole vectors, records and nested carriers. A
32-bit declaration-order tag precedes payload storage sized for the largest
alternative and aligned for the strictest alternative. Payload capacity is the
maximum alternative size, not the sum of all alternatives. Final size rounds to
the carrier alignment. Zero-field alternatives are valid. Invalid internal tags
have a generated trap edge and cannot select a successful source arm.

Construction zeroes the complete carrier, including padding, then stores only the
selected alternative. Complete byte copies are therefore permitted without typed
loads of inactive fields. Matching reads only the selected typed fields after an
exhaustive dispatch. Equality for payload-free enums compares tags, never padding.
No raw pointer is given source addressability into enum storage.

Each parameter is copied into independent read-only storage; each written argument
captures its value at its evaluation position. Hidden result storage belongs to the
caller. A return copies a complete snapshot, rather than returning a callee-local
address. LLVM publication records retain required producer stores and exact copy
source/destination/length; full projection paths, read operands, tag dispatch and
callee/physical channel order remain checked after upstream graphs die.

On the qualified x86_64 target, `Pair { Data(int left,int right), Empty }` requires
12 bytes, alignment 4, payload offset 4. A vector payload can require alignment 16
and a larger carrier. These are measured implementation costs, not a universal
zero-overhead claim. Qualification reports selected
layouts, copies, stack scratch, calls, branches, code size and dependencies.

The owning extension is `owned-sums-v13`. Copyable sum boundaries retain v12
snapshot and caller-result roles. Owning input channels use OWNED_TRANSFER;
owning results use OWNED_RESULT_STORAGE. Each remains one exact nominal PTR
carrier, with caller result storage independently identified.

An owned array field retains the existing concrete buffer plan: PTR/I32 plus
its exact primitive/vector/mask or record element shape and deallocation
responsibility. Nested owning carriers retain their nominal child plan.
Construction initializes fields before publishing the tag. Caller sources are
disarmed before invocation; the callee independently acquires responsibility.
Returning or extracting ownership transfers its payload beyond the carrier's
stack lifetime. Active cleanup visits owned fields recursively in reverse order,
using the existing allocator/free dependencies. Invalid live tags trap.
There is no C ABI or cross-version promise, runtime dictionary, hidden enum
allocation or reference count. Qualification of the new extension is partial;
the ledger states the observed limits.
