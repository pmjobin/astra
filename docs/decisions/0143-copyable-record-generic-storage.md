# Copyable record generic storage

The same `Vector<T>` declaration now specializes recursively copyable records,
exact unique heap Classes and exact move-only Resources. The G2 move-only
element alternative is implemented by Resources. Owning record elements are not
admitted by this container profile; they keep their separate G1 local, native
value-boundary and enum contracts.

In a general Class template, `owned T` and the explicit transfer marker on T
derive the concrete transport mode. For a copyable record they become ordinary
complete value copies; the caller writes `values.append(point)`. Class and
Resource specializations retain explicit consuming arguments. This rule is
limited to the template's exact type argument. It changes neither ordinary
record move syntax nor unique owner semantics outside that profile.

Record slot operations use typed complete value groups in Checked, Core, CFG
and SSA. Indexed observation produces a value snapshot; take produces a snapshot
and removes the selected element. Append and replacement admit complete
snapshots, including native call results and indexed copies. A new bounded
container-consumption role requires one complete matching group consumer.
Every stage rederives exact nominal type, recursive copyability, leaf ordering
and index type. There is no aggregate computation value in SSA and no scalar
owner cleanup contract for a copied record.

The native element is the existing `NativeStructValuePlan` in COPY_VALUE mode.
Generic member signatures reconstruct logical record groups from their physical
channels. The slot descriptor freezes the original record leaf declarations,
including field paths and types. A changed layout is rejected even in a
constructor-only template with no record parameter/result signatures from which
to recover it. Native metadata holds no predecessor graph or runtime type table.

LLVM stores contiguous, naturally aligned flat value tuples. Element size and
alignment determine allocation extent, relocation, indexing and removal stride.
Complete tuple packing/extraction, exact helper calls and complete helper bodies
remain audited after SSA and native plans are released. Copied elements require
no scalar destructor; the container still owns and releases its backing exactly
once. Class and Resource helper signatures and cleanup retain their distinct
contracts. The hosted allocation failure policy remains fatal; negative reserve
retains the previous valid state.

`generic-record.astra` checks nested values, a 24-byte tuple, a four-byte
single-leaf tuple, zero values, independent mutation, growth, copied indexing,
take, replacement, native-result insertion and indexed-copy insertion. Distinct
same-layout records retain independent specialization identities. The Class
witness additionally holds Resource/buffer-owning elements across growth and
take, with exact destructor traces.

Ten selected suites pass (`surge-10-generic-record-closed`): 99 public generic
commands, four generic TAP proofs, historical Bag controls, all four fresh
builder-free enum controls and the 206-command G1 public aggregate regression.
Public programs execute at O0/O1/O2 and under unsuppressed Valgrind. The new
proofs corrupt and restore complete CFG/SSA groups, result consumption, native
keys/layouts and LLVM-valid element extents/field operands. Initial schema
build failures and the corrected missing typed dump branch are WIP findings,
not passing evidence.

G2 still requires broader generic member/method and composition work. G3–G9 and
A73–A84 remain required; this component is not campaign acceptance.
