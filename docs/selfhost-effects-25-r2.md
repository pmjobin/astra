# EFFECTS-25 R2: checked signature contract and remaining native boundary

Effect domain: **PARTIAL**. R2 does not complete milestone 25. The original
EFFECTS-25 and R1 PARTIAL checkpoints remain unchanged. The original native
E25-A-v1 approval and proposal were authenticated; no duplicate design approval
was requested. No Stage 1, release or whole-compiler native claim follows.

`NativeCheckedAbi` retains the exact source owner, declaration, signature,
success type and nominal error bound for the first private scalar/void slice.
Its LLVM type constructor places caller-owned success storage first for a free
nonvoid function and omits it for void. Both return the nullable error pointer.
The physical consumer independently inspects actual LLVM parameter types,
address spaces, fastcc, linkage, arity, varargs and attributes. It does not call
the physical type mapper. Methods, generic instances, owner arguments and
record/buffer/Class results remain outside this implemented signature subset.

These are declaration contracts. They neither initialize success storage nor
allocate, transfer or retire an Error. The ordinary native ABI planner and its
independent verifier now explicitly refuse checked signatures rather than
letting a declaration flag select an ordinary return channel. Existing Flow
admission guards remain active. No new error body or recoverable-error ELF is
implemented by this revision.

The focused physical probe admits six source controls, including void with no
parameters, mixed scalar arguments and a separately nominated root named Fault.
Five carrier/generic/nonthrowing controls remain deferred. Thirteen copied-plan
mutation categories and seven LLVM-valid signature alternatives per admitted
source reject with valid controls. Fixture bodies contain `unreachable`: they
are not native effect programs, cleanup proofs or the required cross-stage and
error-body mutations. Their contribution to those acceptance counts is zero.

The earliest void/scalar success/error sources are attempted through the actual
Astra emitter at both profiles. Independent unchanged C0 executions, LLVM
verification and unsuppressed Valgrind are separately attributed oracles. Astra
refuses emission and preserves the destination. In these minimal sources,
Flow reports global `TYPE_POLICY 7` for Error/RuntimeError, constructor
`MEMBER_POLICY 18` and `UNSUPPORTED_EFFECT 6`, plus unsupported throw/try syntax
and the checked declaration. The native entry reports `LLVM_INVALID_UPSTREAM:
Core 3`. No candidate error-path LLVM reaches assembly or execution.

The next implementation boundary is the bounded Error root's independent
layout/allocation/destruction authority and Flow's separate error owner and
checked-call successors. Reservations must commit at call entry, abort on a
later argument error, and initialize the caller result only on success. Core,
CFG and SSA still need effect operations, exact handler/cleanup edges, owner
versions and success-only dominance. LLVM still needs checked calls, guarded
publication, error returns and independently bound cleanup. Signature planning
cannot discharge any of these obligations.

The R2 receipts distinguish the predecessor baseline from final compiler
qualification. Each profile preserves 202 inherited source identities; the
baseline has 202 distinct O0 ELF hashes and 182 at O2. Historical statuses remain
56 admitted, 12 rejected and 12 deferred. The final audit separately records
current execution, raw LLVM identity, inherited model/layout controls and
15 unsuppressed normal-return memory checks per profile. Twelve existing C0
effect oracles and four additional minimal C0 frontier programs per profile
remain excluded from the new Astra executable count.

All four frozen cohorts retain their original source/node/span identities and
conditional FlowGraph TypeIds 197/198/202/202. Initializer/local deferral 17 and
move obligation 19 remain pending. Original native emission is attempted and
refused upstream; no unchanged original throwing function executes.
`CheckedIndex.add_signature`, graph 55/symbol 2053, independently retains
predicate 26: `this.signatures` has field/root slot 0 while `grown` has slot 6.
No receiver root, alias premise or Class ownership rule was invented to change
that result.

The report's `final-audit.json` binds every gate to final Git and product
identities, cold wall/CPU/RSS, exact warm reuse and interval overlap. Failed
routing, semantic-check and oracle-probe attempts remain in the evidence.
Builds and temporary data use isolated external `effects25-r2` directories;
portable cohort/ledger runners retain their historical defaults. The installed
publisher and workflow are unchanged.

Unmet gates include the first real error ELF, complete ownership/control and
independent stages, 12 new Astra programs/profile with eight error paths,
error-return Valgrind, 20 cross-stage mutation categories, six LLVM-valid
error-body alternatives and an original throwing function running natively.
The two historical 8M-step SSA cases, wide-u64/f32 Valgrind discrepancy, complete
Utf8Message factory and whole-compiler/Stage 1 deferrals remain separate.
The 451 protected paths, 6,622 read-only donor files, 1,044 historical proof
hashes, C0, public ABI, LLVM23 and existing resource ceilings are preserved.
