# GENERICS-14 engineering checkpoint

This is an engineering checkpoint, not milestone acceptance or Stage 1.
The installed pm-next intake accepted the exact 31,299-byte submission with
SHA-256 `5e6ae0758b69df5e05028b03ffdd87433d8e2fbbe06ed5b0d6b93810210acbf0`.
Its base is commit `5cd200f8210482835f1ff80182a59fb1532801ba`, tree
`acddbd3da33c771b956082e27d68a1bc98a53cfe`. The predecessor report is preserved
under its SHA-256 `f1215775b351bdec9ba0267c90f023ba8044b75abfa75631ea653a7edf4bb8b1`.
The live start was clean. All 451 protected inputs matched their recorded
hashes; all 6,622 read-only donor files matched the predecessor byte/mode map.

## Implemented architecture

The original syntax, tokens, spans, binder symbols and references remain the
source authority. Target-agnostic `GenericInstance` rows name a declaration,
ordered concrete TypeIds, an optional enclosing Class instance and separate
syntax/symbol/scope maps. Maps live in a bounded typed arena. A requested
instance creates concrete declaration/body syntax and binder identities; it
does not rewrite source text, call C0 to instantiate, or use a fixture table.
Explicit arguments and inference use canonical type edges. Closed nominal
records obtain distinct concrete nominal declarations, including nested
records with identical physical shapes. Copy and owner facts come from the
concrete fields and the existing checked/Flow contracts.

The separately implemented consumer reconstructs substitutions, source syntax,
binding references, signatures, constraints and method receiver selection. It
runs before Flow admission and again at admission verification. Existing
Core/CFG/SSA verifiers remain independent. Backend keys encode declaration
source identity and canonical types, including enclosing/method arguments;
the qualified native ABI plan binds those bodies to actual machine layout.
General C ABI exports are not introduced.

The owner approved the bounded private receiver proposal in
`selfhost-generics-14-abi-proposal.md` through the native session. Empty native
Classes have real allocations and scoped once-only retirement. A specialized
direct method has a hidden borrowed Class pointer before source parameters.
The original call remains intact; a checked normalized argument view retains
receiver-first evaluation and the existing loan/consumption checks. The ABI
plan records the receiver channel explicitly and grants no alias attributes.
Field-bearing Classes, inheritance, virtual/indirect dispatch and custom
Class destruction remain outside this bounded implementation.

## Current evidence and outstanding work

The fresh baseline runs pass all original 39 native programs at each O0/O2,
plus the selected original status and negative closure. The frozen v3 matrix
contains 13 distinct C0-compatible programs, each compiled and executed with
the qualified current C0 at both profiles. It includes unchanged repository
explicit/inferred fixtures, three record families, two method cases, two owner
cases and an unchanged multisource provider/consumer program.

The first standalone Astra consumer freshly admits typed specialization and
Flow for eleven programs. The two method programs are explicitly deferred in
that older development product. The receiver-enabled v2 native tools built at
both O0 and O2. Nine new programs passed actual O0 LLVM/ELF/C0/memory checks in
retained development runs. The method cases exposed a missing construction
commit identity in Flow; the early owner case exposed a missing floating buffer
element layout in the ABI plan. Both are corrected in source, with a new
independent buffer stride check. Fresh tool builds and final qualification
remain in progress.
Nineteen independent typed/binder/owner/receiver/Flow model forgeries and six
additional physical ABI/receiver/allocation/cleanup faults have authored test
consumers; they require actual successful controls and rejection receipts.

Early trials remain in `runtime/generics14/`: the older independent C0 rejects
approved unbraced syntax, so new witnesses use the qualified current C0;
C0 rejects owned fields in generic records, a by-value parameter mutation and
an inferred unresolved generic local. Revised witnesses were separately frozen
before implementation. C0 also exposed a record-projection temporary without
a reaching definition in a loop condition in the verifier implementation;
materializing that descriptor before the loop retains the same checks and
passes C0. No C0 verifier or ownership restriction was relaxed.

The guarded formatter applies only to task-owned eligible paths. There was no
repeat of the historical formatting campaign. A full read-only check passed
4,659 sources with zero changes; later touched paths have separate guards.
The whole-source consumer emitted 174,297 original nodes against the initial
source set. Its first decoder failed on 23 synthetic Utf8MessageFactory nodes;
the consumer now exposes their actual source backing for complete provenance.
Final style/protection verification, original 1,044-proof replay,
final O0/O2 execution/memory/mutation closure, exact costs and publication remain
mandatory. The runtime receipts, rather than this checkpoint, govern outcomes.

## Deferrals retained

C0-rejected owning generic-record fields and owning-record reassignment remain
unsupported. General generic Class containers, virtual dispatch, advanced
constraints/ownership, broad foreign pointers and C aggregate ABI, callbacks,
async/exception policy and whole-compiler admission remain unqualified.
The prior wide-u64-to-f32 Valgrind numerical discrepancy remains **DEFERRED**
with its original failed exit and raw identity; native numeric expectations
are unchanged. No release, Stage 1, donor write, global tooling change,
history rewrite or public push is part of this task.
