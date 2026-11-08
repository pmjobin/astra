# Effects 25 R5 completion attempt

R5 starts at commit `c271e0822d0fc12a878a5adc1388aa1a8e147067`, tree
`cb487de4a6f3a8faa73675feb0b9a090047d3fef`. Submission SHA-256 is
`e7837fba03f7a19c6552776488d5848849cc65b50f3b46eb3d505c4ce4b51541`.
The exact R4 PARTIAL predecessor is 22,249,687 bytes, SHA-256
`c188a95de8b070ad5fd396afb2ad6d4132649278f05ba0e5dc49a1f3d9e8e00c`.
Its timestamped name is an offline reference label; the authenticated bytes
were present at the canonical report path. All 102 members/101 indexed
payloads, 105 submission members/104 payloads, 94 references, source blobs,
Git pins and original E25-A-v1 approval were checked before implementation.
Packet source snapshots were witnesses and never replaced live source.

The original milestone-25 contract remains the acceptance scope. R4 remains
historically PARTIAL. No milestone26, Stage1, release or push is authorized.

## Source changes and their limits

The private effects lowering now accepts source-bound boolean `!`, integer
unary `+`, signed integer unary `-`, and integer `~` when the operand has its
independently recorded exact type. The existing source/Flow consumer checks
the original prefix node, token, operand, function, handler and exact type.
Core/CFG/SSA retain their separate correspondence and dominance checks.
LLVM emission uses ordinary flag-free subtraction or xor; the physical
consumer independently checks widths, operands, masks, opcodes and the absence
of `nsw`/`nuw`. Constant results are evaluated separately. Existing float unary
operations retain their own consumer. No source filename or Class owner is
used to excuse a missing proof.

Signed integer literals have a separate unqualified frontier. Typecore's
special literal path records the prefix result but leaves the magnitude
operand without a type fact. The new lowering requires that fact and does
not invent one. Dedicated C0-valid literal probes retain the native refusal;
dynamic typed operand proofs do not qualify every signed literal form.

The checked allocator/noinline policy, zero-buffer allocation behavior,
external declarations/call memory effects, module-owned layout caches,
independent verifier boundaries, C0, public ABI, approved private E25-A-v1
and 256-generic/8,000,000-SSA ceilings are preserved. The R4 layout oracle
accepts an explicit provider directory and authenticates its objects, allowing
its original check to run after historical loose build files were cleaned.

## Original target and dependencies

Original `flow_number` remains byte-exact at
`compiler/semantic/flow-query.astra` [1870,2001), SHA-256
`8641d4ff6a1f19cc8bfc0ccbec492a8f7d4248eebcb05373c15479e7114a3e68`.
Both original source populations and disclosed reduced views are attempted
separately. Reduced-view bytes and C0 syntax subtrees are checked exactly.
Neither C0 execution nor a source-view observation counts as Astra execution.

The full original first stop is RecoverFlow declaration admission at
`SourceSpan`, node1004, `compiler/source/source.astra` [6349,7688), SHA-256
`379db79194d55c7f116b08c8dba7157bdfdebbee5dc5c2b95f1478de483c8305`.
Its owned shared field needs an actual shared owner/receiver/storage model,
retain/release, borrowed liveness and cleanup proof. Existing finite-field
admission does not supply that model; `class_storage_value` rejects the
unsupported field domain. Removing that refusal would not prove its owner.

The minimal view stops at the actual `Utf8MessageFactory` declaration,
node282, `lib/astra/text/utf8-message.astra` [383,445), SHA-256
`7f3d16f810dd512103d3f836b3acd2cb55ecfaea3ec4186e9f67bcbb738a6767`.
The source parser retains a generated `<Utf8MessageFactory>` source and
distinct validation/conversion AST nodes. Existing effects declaration
admission excludes that intrinsic, and the required checked UTF8/count
operations are not implemented by the new unary operation. No exclusion was
removed, unchecked success substituted, or C0 body installed into Astra.

Real indexed owned buffers, fixed arrays, slices, integer casts/division/
remainder and their source lifetimes remain unfinished in effects lowering.
The complete original builder, SourceBuffer and scalar formatter, remaining
C0-valid result/field/rvalue receiver and field-bearing/computed-base Error
forms remain separate obligations. The entire original execution gate stays
PARTIAL while any of those required dependencies is unproved.

Sixteen independent original C0 programs per profile execute and pass
unsuppressed returning Valgrind: empty/ASCII/multibyte/NUL counted UTF8,
eight actual InvalidUtf8 paths, original builder growth and snapshot
independence, formatter extremes including INT_MIN, original flow_number and
shared SourceSpan cover/location/path/bytes. All use unchanged complete
original dependencies. Their Astra-native credit is zero.

## Retained evidence and reproducible routing

The fresh predecessor replay retains 340 Astra source identities/profile:
202 inherited programs and 138 effects/Class programs, including 74 actual
error paths. All 101 semantic/52 LLVM-valid physical categories are retained.
Four frozen source/node populations and their synthetic builtin bytes match
exactly: 79/85/92/92 logical files, or 78/84/91/91 explicit command inputs.
Conditional 17/19 facts remain intact. CheckedIndex.add_signature remains
independently DEFERRED at graph55/symbol2053/predicate26, root0 versus slot6.
Historical 56 admitted/12 rejected/12 deferred statuses and 1,044 proof
hashes are preserved; they are not silently renewed or promoted.

Pre-task cleanup preserved an archive but removed loose GENREF receipts and
provider objects. Initial retained recipes therefore recorded four failures
per profile. R5 authenticates selected R4 evidence into its own runtime,
relocates source witnesses explicitly, and rebuilds foreign C companions from
the unchanged native-ABI corpus. Historical paths and evidence are not
rehydrated or overwritten. Generic identities encode physical source paths:
the relocated R4 replay has 58/202 strict original raw LLVM matches, with
58 O0/70 O2 ELF matches. These are actual identity differences. R5 records
the original and relocated predecessor comparisons separately. R4's
historical 0/120 raw effects matches against R3 remain 0/120; a normalized
text diagnostic is never called raw identity.

The final strict R5 comparisons match 23/138 retained raw LLVM outputs
against R4 at each profile, with 23 O0/64 O2 identical ELF products. The
202 inherited outputs match all 202 raw outputs of the explicitly relocated
R4 replay at each profile, and 58/202 raw outputs of the original R4
checkpoint. Execution and independent validation are recorded separately
from these exact byte comparisons.

The new domain has thirteen source witnesses, eight requiring an actual handled
Error, twelve illegal source controls, and three C0-valid signed-literal
deferrals. The independent C0/LLVM helper preflight has 39 positive cases,
nine LLVM-valid changed physical forms and three separate domain rebindings.
It supplies no Astra-native or integrated full-module mutation credit.
Twelve new semantic stage mutation categories remain unestablished; counts
do not replace the original source requirement.

The superseded final2 O0 compiler built in 2329.03 seconds, then its first
new native witness reached valid SSA and failed the independent physical
consumer. GDB localized the exact noncanonical i1 mask: LLVMConstInt was
given a 64-bit all-ones value, and LLVMConstIntGetZExtValue exposed the
unmasked bits despite an LLVM-valid printed `true`. The corrected producer
constructs the exact width mask; the independent consumer still computes its
own expectation. A focused regression uses the real producer and independently
rejects the original noncanonical C-API input. The superseded O2 compiler and
unneeded ABI diagnostic were explicitly terminated with signal15, preserving
GNU-time receipts and process identities. None of these failed/stopped
candidates has new unary-native qualification.

The corrected independently built compiler hashes are
`0421ffd0dabd26f0dfbbfed04530c19dc83da2f68a266e4545a2d36676638572`
(O0) and `b54cbd47f5f679bf1d1fd47cded524fa9dc6936997bd413886a7905102397ac3`
(O2). Actual cold build wall/user/system/RSS measurements are respectively
2297.95/2282.24/1.64 seconds/2,396,280 KiB and
3290.12/3267.47/1.71 seconds/2,395,376 KiB. These measurements are
not a compiler speedup claim.

Final matched native qualification passes all 41 consolidation recipes per
profile: 340 retained identities plus 13 new witnesses, totaling 353 Astra
programs and 82 actual handled error paths per profile. Their emitted LLVM
is verified, ELF execution returns 42 and returning Valgrind is unsuppressed,
with zero errors and no live allocations; independent C0 runs agree. All
101 retained semantic and 52 independently LLVM-valid physical mutation
categories pass at both profiles. These counts do not include the C0-only
original oracles, and genuine original flow_number Astra executions remain
zero. The unchanged milestone contract remains PARTIAL.
All real failed checks, returning/fatal memory controls, cold build and exact
reuse receipts remain in the lossless evidence. The first persisted C-only
physical producer exposed a diagnostic-message double free; its failed run
is retained, the provider lifetime is corrected, and the final complete
physical consumer proof passes at C0 O0/O2. No Astra execution is credited
for that C fixture.

Run the explicit R5 route from this checkout with `PM_CODEX_BUILD_DIR` and
`PM_CODEX_RUNTIME_DIR` set to the project's external build/runtime roots:

```sh
python3 -B tests/selfhost-effects/r5.py recover-full-build --mode O0 --version canonical
python3 -B tests/selfhost-effects/r5.py recover-full-build --mode O2 --version canonical
python3 -B tests/selfhost-effects/r5.py recover-r5-consolidated --mode O0 --version final --component "$PM_CODEX_BUILD_DIR/effects25-r5/full-canonical-O0/astra-llvm-O0"
python3 -B tests/selfhost-effects/r5.py recover-r5-consolidated --mode O2 --version final --component "$PM_CODEX_BUILD_DIR/effects25-r5/full-canonical-O2/astra-llvm-O2"
```

Versioned execution leaves refuse overwrite. Repeating the build with exact
source/tool/product identities can reuse its compiler; that measurement is
not recompilation or speedup. Per-command GNU time records retain actual
wall/user/system/RSS, including overlap and nested parent recipes; their CPU
or wall times must not be indiscriminately summed.

Only the unchanged installed pm-next publisher writes the canonical report.
The separate after-publication verification checks delivered ZIP/member
coverage, Git/source bindings, transport and every indexed evidence byte.
G12 can pass delivery integrity while the compiler milestone remains PARTIAL.

The next bounded source work is a verified shared receiver/field owner model
at the actual SourceSpan frontier and genuine checked UTF8/count conversion
for the actual factory, followed by original buffer/slice/formatter lowering.
Keep the two original populations separate and require Astra-emitted original
flow_number execution at both profiles before closing its gate.
