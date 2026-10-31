# ADR 0160: Allocation policy joins the existing owner authority

Status: implementation decision for Surge 12; qualification pending.
No default ownership, error, sharing or native pointer ABI change is selected.

The current compiler distinguishes lexical/caller Class storage from unique
heap ownership and has independent owner obligations through Checked, Core,
CFG, SSA and native plans. Physical Class, array, slot, closure and frame
allocation currently converges on hosted `calloc/free`. ByteArena and
PacketArena instead store IDs and encoded bytes; they cannot supply a Class
or collection allocation. Their existing contracts remain separate.

| Existing family | Storage/release authority | Policy integration required |
| --- | --- | --- |
| Lexical/caller Class | Exact storage identity, enclosing region and ordinary destructor | Preserve storage, address and cleanup; no mandatory allocation header |
| Unique heap Class | Exact Class cleanup with allocated-origin flag | Typed declaration policy selects admission and matching release |
| Owning record | Field-specific Class/Resource/buffer obligations and prefix cleanup | Each Class leaf retains its original policy; no byte copy of owners |
| Generic owned slots/Bag | Exact element cleanup, backing pointer/count/capacity | Container backing policy is separate from each element's policy; growth preserves both |
| Shared/Weak | Opt-in nonintrusive block and exact payload cleanup | Preserve counts and block ABI; payload release follows its exact Class policy |
| Closure | Linear carrier, exact environment, observed retirement before destruction | A policy on the exact environment governs its allocation and eligible carrier storage |
| Async frame | Native continuation/frame/cancel authority | Remains hosted unless separately proved; closure environment supplies the required selected nondefault execution family |

Use a finite checked `[Allocator(...)]` declaration policy for eligible exact
Classes, including closed generic container instances. The policy contains a
typed kind, named domain, capacity/block budget and supported alignment. A
declaration-level `[Align(...)]` adds a real allocation requirement. Resolve
all options in semantic analysis and carry an independent immutable admitted
snapshot into every later descriptor. Invalid or conflicting policies fail
before emission. Nondefault policies must not be erased by local stack
promotion: allocator admission, failure and release are observable effects.

Initial region/pool domains have explicit **static backing lifetime**. Classes
of different sizes may share a named bounded region; pool slots are finite and
reusable. This supports ordinary owner movement without inventing an escaping
pointer lifetime. A reset/destruction request must refuse while any allocation
is live. Reuse advances checked generations; a stale or wrong-origin release
must be rejected before any memory/state mutation. Lexical/caller storage
retains its existing compiler lifetime proof. A future shorter-lived dynamic
domain would need a transported backing-lifetime parameter; no such lifetime
is inferred from a raw address or from this static policy.

Custom placement uses a checked native scalar callback, with static code
lifetime, to propose an offset inside a bounded compiler-owned domain. A
separate scalar notification can observe release. The runtime independently
checks extent, overflow, alignment, overlap, liveness, generation and origin;
the callback never returns a raw pointer or grants ownership. Reentrant domain
mutation fails closed. This interface supplies a user-defined placement policy
without a new trusted foreign memory/lifetime assertion. More general foreign
allocators returning pointers would require a separately approved contract.

The physical implementation may use an explicit small freestanding allocation
runtime, with source-traced state and target layout. Its API is compiler
internal; applications receive ordinary typed owner handles. Every allocation
records complete extent/alignment, domain, type/release identity and generation.
Destruction occurs before matching reclamation, including record/slot/closure
paths. Unannotated heap owners continue to use their current strategy and
fatal OOM behavior; unused policies add no allocator/runtime dependency.

Add an explicitly fallible construction spelling for the bounded supported
constructor family. Exhaustion returns a legitimate null owner before
construction or publication; it does not invoke a destructor on uninitialized
memory or consume owned constructor inputs. Nullable admission composes with
existing checked errors and record prefix rollback. Keep ordinary `new` fatal
on exhaustion. Collection admission/growth under bounded policies returns its
documented failure without disturbing existing owners or publishing a new
backing pointer. Unsupported constructor/transport/policy combinations reject.

`Repr(C)` is separate from Class allocation: only eligible independently
verified POD values can request that layout. Native Class identity/header
layout cannot be declared C-compatible. Alignments, field offsets and complete
sizes require an independent C consumer and selected-target machine evidence.

Qualification must cover heap, region, pool, custom, caller/static; multiple
Classes, mixed nested owners, two collection specializations and a real deferred
closure lifecycle; exhaustion/rollback, live-domain destruction, stale/wrong
release, escaping loans and invalid layout/alignment. Add detached mutation
and restore controls at each authority boundary, memory/sanitizer tests on
eligible host programs, selected no-OS owner execution, exact counters and
runtime/dependency inventories. This design document closes none of F3–F9.
