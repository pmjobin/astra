# CLASSSTORAGE-15 environment checkpoint

Status: **ENVIRONMENT_BLOCKED** before candidate compiler implementation.
This checkpoint preserves the exact authorized submission and prepares the
witnesses and verification recipes needed to resume. No Class storage ABI,
semantic admission or new native execution is qualified by this checkpoint.

The installed unchanged pm-next intake validated the 22,880-byte
`ASTRA-SELFHOST-CLASSSTORAGE-15-SUBMISSION.zip`, SHA-256
`0a668794983c3222c0df3e3bdd195296f089489407f97ef34964c6b9ec8b656f`.
The initial repository was clean at commit
`7b8fea49cdd3b3b8bb284d4299a12d31b01ba682`, tree
`529159ff7c48808cf19d278c4015ad1a63adcaf4`. All packet instructions,
contract, acceptance, provenance and reference files were read. Safe unique
regular ZIP members and complete indexed byte/hash coverage were checked.
The canonical predecessor report matches
`0c0df4ce1eaae92526b3a8427be0875f6687f2ef9d567a715bab414bf7b3fbf0`.
It is preserved under `runtime/report-history/<sha256>.zip`. Its published
intake, including extra timing receipts, was preserved intact under
`runtime/intake-history/generics14-published-7b8fea49cdd3/` before preparing
this package. These runtime paths are relative to
`~/Workspace/codex/work/astra/`; no installed workflow was modified.

## Actual blocking condition

The package requires LLVM **22.1.8**. The live `llvm-config --version`
returns **23.1.4**, and `libLLVM.so.22.1` and the recorded LLVM 22 development
paths are absent. The exact current C0 oracle
`908f8db9e524cf94b7651f36e9bf0ff32c98ef64cb7eacd737c3b5f680064b45`
and both exact GENERICS-14 native emitters fail to start with exit **127**:

```text
error while loading shared libraries: libLLVM.so.22.1:
cannot open shared object file: No such file or directory
```

The emitters retain SHA-256 identities
`131065fd1f5fda9e7590f0a3cde2317e3ec06ce9b88b330748edb7c1e4032247`
(O0) and
`d70104dcd86d510dc6d3dc10e54de55bd507ce4b918dd80e9128006d66a3fcbd`
(O2). Each emitter also has 57 missing or changed dependency identities
against its exact source/tool sidecar. The binary bytes alone cannot justify
reuse. The initial witness attempt retains raw parse/check loader failures;
these are **not C0 semantic rejections**. No native build was attempted, so
cold/warm O0/O2 cost and peak build RSS are unavailable. GNU-time receipts
for the failed invocations remain in `runtime/classstorage15/frozen-v1/`.

A read-only search examined 4,831,673 existing file names under Workspace,
user caches, `/opt`, `/usr/local` and `/var/cache`, without finding the missing
LLVM 22 library or a matching cached package name. Its receipt records
permission-denied directories and ignored-path limits; it does not prove
that no recovery artifact exists anywhere. No host package installation,
LLVM substitution, library-name alias or toolchain migration was performed.
The packet explicitly excludes a broad toolchain upgrade. The guarded
formatter also requires qualified tools whose identities have drifted.
Formatting attempts and their exact refusal are in the report evidence.
No formatting pins were changed to obtain a passing result.

## Preserved work and evidence

`tests/selfhost-classstorage/environment.py` audits exact binary, source,
tool and runtime availability before oracle use. `freeze.py` now retains
proposals and returns an explicit environment failure before assigning
source dispositions when those premises are unavailable. `corpus.py`
provides twelve proposed mechanisms plus an extracted `FlowGraph`/`Bag`
reproducer and an unchanged repository owner-relay witness. All fourteen
are explicitly **PROPOSED_NOT_C0_QUALIFIED**. The reduced `FlowGraph`
retains the complete actual field list and constructor, with source-slice
hashes and spans; unrelated methods are omitted explicitly. The actual
`Bag<T>` source remains unchanged. No candidate implementation was begun
before C0 qualification.

`continuity.py` checks retained source/product identities for all 52 old
programs at both profiles, the 80 original statuses, all 1,044 raw proof
outputs and their frozen inputs. It also checks unchanged original-node
identities across the historical 174,297-node source population and retains
the 188,240-node ledger and first checked constraint error. This is fresh
**preservation evidence**, not a fresh compiler replay. All existing raw
ABI, LLVM, object, ELF and negative receipts remain tied to their original
products. The exact complete predecessor raw transport is retained with
SHA-256 `61423b9bdb16de3d27057b7fe309a3bf5b607828fd87d269874de95ed0ce1941`.

The historical wide-u64-to-f32 Valgrind numerical exit **1** remains
**DEFERRED**, including native/C0 and GCC/Clang raw receipts. Zero reported
memory errors do not establish numerical equality. No prior milestone was
reclassified. Compiler, bootstrap and library sources are unchanged;
451 protected files, 6,622 read-only donor identities, original history,
remote/configuration and hooks are preserved.

## Resume boundary and remaining gates

Restore the qualified LLVM 22 runtime/development environment and resolve
all exact dependency drift before reusing a product; rebuilding after a
changed host needs measured, source-bound qualification. A separately
approved LLVM/toolchain migration must define its own validation scope.
Do not symlink LLVM 23 under an LLVM 22 name or weaken identity checks.
Then run the environment audit and freeze recipe with new, unused external
runtime/build leaves. Retain both failed attempts. Individually establish
C0 acceptance and O0/O2 runtime observations before implementing the ABI.

The actual compiler-source frontier remains the historical checked
`ExactHeapClass` obligation on `Bag<FlowGraph>` in
`compiler/semantic/flow-model.astra`. No new source ledger or progress beyond
that stop could be measured. G1 qualification and G2–G8 remain incomplete:
private payload layout, initialization, owner/borrow transport, slots,
cleanup, independent consumer, new mutations, >=12 new native programs per
profile, fresh regressions and build costs all require actual engineering
and execution. All GENERICS-14 deferrals remain in force. No Stage 1,
whole-source, release or public ABI claim follows.

While intake is active, use installed `intake.py --resume` to recheck it.
The required report publisher marks an intake published even for
ENVIRONMENT_BLOCKED; its resume command then refuses. Preserve that marker
and checkpoint. Continuing after publication requires an explicit workflow
continuation/new matching submission or authorized amendment as applicable;
do not clear `published`, force preparation, repin the original ZIP, or
rewrite history to make a resume appear valid. The final publisher receipt
records the exact checkpoint HEAD/tree, patch, source identities and report.
