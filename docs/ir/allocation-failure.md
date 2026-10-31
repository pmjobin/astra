# Allocation failure regions

`OwnedBufferAllocate` carries an optional typed ordinary call through Checked and
Core. Core admits a native/generic call statement or qualified C call statement
with exact void result; its ordinary call verifier still checks target identity,
types, arguments, metadata, borrows and source ownership. Core contains no calloc
name, target stride or application policy.

Generic structured ownership checking enters a choice from the post-count state
and terminates the action path. Its ownership effects never reach allocation
success. Concrete materialization clones the optional statement with the existing
parameter/local/type/cleanup/source mapping. Counts and failure arguments are not
instance keys. Symbolic constructs are gone before CFG lowering.

Annotated CFG uses `CfgBufferAllocationBranch`: a once-evaluated count plus two
distinct successors. The success block begins with `CfgBufferAllocate`, the
existing complete owner acquisition/publication instruction. The other successor
contains lazy receiver/argument evaluation and one exact ordinary call, followed
by `CfgAllocationFailureTrap`. Short-circuit argument evaluation may add blocks;
the bounded region remains a DAG with only the allocator-null entry and terminal
trap. The action token holds stage-local weak callee identities, its ordinary call
instruction and any captured destination receiver. It retains no Checked/Core
graph, closure or runtime handler object.

SSA mirrors the request with typed edges and one success-only complete PTR/I32
pair. Argument instructions may produce ordinary values and joins inside the
failure region; there is no failure-to-success join or fabricated undef/poison
owner. Constructor and ownership traversals recognize the new successors.
Independent verifiers require exact request/publication/action/trap correspondence,
unique region ownership, exclusive success predecessors, failure cause correspondence,
ordinary callee/result validity, captured-receiver validity and no synthesized
caller cleanup or acquisition in the terminal region. Dominance and existing
buffer group/ownership proofs remain in force.

The backend realizes a request using the existing target allocation plan. Signed
count, zero, checked multiply and record address-extent guards retain their old
paths. Only the positive allocation's null comparison targets the failure edge.
Physical pointer/count results remain backend-internal until the exclusive
success publication. The empty/nonempty physical phi uses actual final blocks
after guards. Edge arguments and success phis likewise use final continuations,
including splits caused by numeric guards, text comparisons and lazy arguments.

The action lowers through ordinary independently owned NABI/CABI plans. A return
executes `llvm.trap` followed by unreachable. No noreturn or purity promise is
attached to the arbitrary action. Existing intrinsic attributes remain confined
to their intrinsics. Default allocations take the previous lowering path, with
unchanged stages and dependencies. calloc/free retain nobuiltin at declaration
and call sites, preventing elimination of observable allocator failure merely
because payload values are unused.

Replacement cleanup stays after successful incoming production. Explicit action
callee behavior may release consumed owners, but the compiler adds no caller
unwinding. A field's previously captured containing receiver remains protected
under existing conservative overlap rules. Failure-only ownership effects are
checked separately from success and never committed speculatively.

Standalone Core/CFG/SSA tests build malformed models independently of parsing;
pipeline tests destroy syntax, Checked arguments, generic definitions/type
universes and each executable predecessor before retained-stage verification.
Only legitimate immutable spans/type leaves survive as required by existing
authorities. LLVM artifacts retain no semantic source graph. The physical overflow
witness uses the inherited internal layout seam, without admitting a new source
element or allocating a huge payload.
