# 0110: opt-in native strong and weak handles

`Shared<T>` and `Weak<T>` are separate linear handle capabilities for an exact
concrete native Class. Ordinary Class construction, layout and destruction keep
their unique-owner path. These handles add no field or control block to a Class.

`shared_acquire(move owner)` transfers an independently allocated unique owner
into a separate native block. `shared_clone`, `shared_downgrade`, `weak_clone`
and `weak_upgrade` produce explicit new handle owners. Upgrade returns null on
expiration, without acquiring a strong count. Handles move, return, enter owned
parameters and reside in owned Class fields through the existing linear cleanup
pipeline. `release` and lexical/checked cleanup discharge each owner once.

The single-threaded block is `{u64 strong, u64 weak, payload*}`. Weak includes
one sentinel while strong ownership exists. Last strong release first publishes
strong=0 and payload=null, then runs the exact native payload destructor and
frees its allocation. Only after destruction returns does it drop the sentinel.
This preserves block lifetime when destruction releases weak observers. Final
weak release frees the block. Overflow and underflow trap. Block allocation
failure traps before publication; it is fatal, without checked rollback.

`shared_borrow(handle)` is admitted only as an inline exact borrowed Class
argument. It cannot be stored or returned. The owning strong handle remains
live throughout argument evaluation and the call. Null projections trap;
programs should guard nullable upgrade results before projection. Weak lifetime
alone never authorizes payload access. Shared/Weak cannot cross the C ABI.
Projection from an owned field first requires an explicit strong clone into a
named local. This gives the payload loan an independently tracked backing owner.

The compiler carries typed actions and exact cleanup/payload identities through
Checked, Core, CFG and SSA; LLVM emits native control-block operations and
registers field, arithmetic, call and branch correspondence for verification.
The initial profile excludes threads, atomics, cycle collection, implicit
sharing, subtype coercion between handle types and arbitrary foreign retention.
Strong cycles are not collected: use weak edges for observers.
`tests/shared-1b/weak-backedge.astra` exercises this policy without deliberately
leaking a strong cycle: a second node owns a weak observer of the first; terminal
strong release destroys the first, its observation expires, and final second-node
cleanup releases the remaining block authority. `stress.astra` exercises 10,000
legal clone/downgrade/upgrade/release interleavings with stable payload identity.
