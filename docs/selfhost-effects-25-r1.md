# EFFECTS-25 R1: source effect checking and remaining native gates

Effect domain: **PARTIAL**. This continues EFFECTS-25 under the existing
E25-A-v1 approval; it does not add a numbered milestone or supersede the
historical EFFECTS-25 PARTIAL result. The approved private checked-call
transport is still unimplemented in the self-hosted Flow/Core/CFG/SSA/LLVM
pipeline. No new Astra-emitted recoverable-error executable is qualified.

## Implemented source checking

`compiler/semantic/effect-check.astra` resolves the nominated error root and
exact nominal ancestry from source bindings. Signature checking rejects a
concrete unrelated throws bound. `CheckedIndex.validate` separately binds the
retained error type, throws flag and dispatch to declaration syntax. The
conditional call consumer reconstructs the result, bound and argument edges
without treating a known success type as an initialized owner.

The throwing-call deferral previously skipped known argument-type mismatches.
It now checks arguments against their declared types while keeping call/local
deferral 17. Arguments do not inherit a blanket effect deferral before their
ordinary type checks. Deferred/unknown arguments cannot certify the independent
conditional-call contract. This does not discharge move obligation 19.

`effect-source.astra` independently walks callable bodies with a lexical handler
stack. A declared ancestor bound is open: listing known descendant catches does
not exhaust it. Earlier ancestor catches hide later descendant catches. Handler
bodies see outer handlers, and bare rethrow requires a lexical catch. Catch
bindings carry a borrowed nominal type; throwing a borrowed catch or moving it
as an owned error rejects. Constructors and unsupported throwing dispatch/foreign/
async boundaries remain outside this bounded profile. `generate-effects.py`
reconstructs typed syntax edges from the existing syntax schema; its generated
walker contains no handler or ownership decisions.

These checks establish the listed source constraints only. They do not prove dynamic error
identity/origin, error-owner liveness, reservation rollback, initialized success
storage, or cleanup. All existing Flow and native admission guards remain active.

## Independent source and runtime evidence

The focused O0 batch compares 20 source controls with unchanged C0. The final
profile controls add an unrelated nominated root named Fault. Twelve
Typecore model mutations alter signature/result/bound/dispatch/argument facts,
require rejection at the conditional-call consumer, and restore valid controls.
These are Typecore controls, not the required 20 cross-stage effect mutants or
six LLVM-valid physical effect alternatives. Final compiler profile receipts
and gate accounting are in the published `final-audit.json` attachment.

The predecessor baseline was independently replayed before final qualification:
four exact source populations at both profiles and 202 inherited native source
identities per profile. Raw LLVM, LLVM assembly/verification, linking, actual ELF
execution and behavior checks retain their separate receipts. Distinct ELF byte
identities are 202 at O0 and 182 at O2. This predecessor replay alone supplies no
evidence about the changed compiler. Final changed-compiler regression results
are recorded separately.

Fresh complete ledgers at both final profiles compare every original source,
node, syntax kind and byte span against the frozen predecessor: 79/85/92/92
sources and 174297/188293/206465/208328 nodes. All eight populations match;
the original producer/local/move facts are also checked in those ledgers.

Both final compiler profiles pass the same inherited native behavior and retain
all 202 raw LLVM identities. The 80 statuses remain 56 admitted, 12 rejected and
12 deferred. Per profile, 28 inherited model controls, 10 source negatives,
layout-cache lifetime controls and 15 unsuppressed normal-return Valgrind runs
pass. All four source populations preserve the conditional facts; complete
original native emission is attempted and refused with the destination intact.

| Compiler invocation | O0 | O2 |
|---|---:|---:|
| Cold wall seconds | 1252.20 | 1956.70 |
| User CPU seconds | 1241.41 | 1940.24 |
| System CPU seconds | 1.62 | 1.69 |
| Peak RSS KiB | 2013752 | 2024852 |
| Exact warm identity reuse seconds | 1.15 | 1.10 |
| New qualified Astra effect executables | 0 | 0 |

The cold compiler invocations overlap. Provider/shim objects can reuse exact R1
objects from the earlier rejected checks; warm identity reuse does not compile
the program. These measurements do not establish a matched-workload speedup.

C0 error/success execution, unsuppressed Valgrind, and GCC/Clang layout probes
remain separately attributed design oracles. They do not increase the Astra
effect executable count. Neither successful C0 execution nor a successful build
constitutes E25-A-v1 implementation qualification.

## Independent original-source obstruction

The four frozen producer/local/move chains retain nominal FlowGraph types
197/198/202/202, signature flags 68, initializer/local deferral 17 and move
obligation 19. A known conditional FlowGraph type remains distinct from a live,
successfully initialized owner.

Original graph 55, symbol 2053 (`CheckedIndex.add_signature`) separately fails
`flow_owner_capture_verified`, predicate 26, at
`swap(this.signatures, grown)`. The field side has no admitted field/root slot;
the local has slot 6. `class_storage_receiver` supplies a concrete synthetic
receiver only for supported specialized members. The original nongeneric method
has a nominal lexical receiver but no such storage slot or field inventory.
The containing Class also exceeds the current whole-Class storage admission
domain. Assigning an arbitrary root would bypass the lifetime and alias proof.

`r1-owner.astra` reads the actual failing events through nonthrowing borrowed
inspection helpers returning copied values. Printing happens after those borrows
end. It changes no events, slots, verifier decisions or source methods. The
independent Class receiver/root obstruction remains DEFERRED; it is not evidence
that the approved effect transport is impossible.

## Unmet completion gates

Remaining work includes the private nullable owned error return, complete
success storage and method receiver order; independent error layout/descriptor/
getter/destruction authority; Flow success/error edges and reservation/entry
semantics; separate live catch owners; Core/CFG/SSA ownership and handler maps;
LLVM branch/signature/publication checks; exactly-once runtime cleanup; at least
12 new Astra-native programs/profile including eight error paths; error-return
Valgrind; and the required cross-stage and physical mutations. No Stage 1 or
whole-compiler native success follows from this revision.

The original 80 statuses, 1,044 historical proof hashes, 451 protected paths,
read-only donor, C0, installed workflow and public C ABI remain preservation
obligations. Historical proof hashes are not relabeled as fresh semantic proofs.
The two 8M-step SSA deferrals, wide-u64/f32 Valgrind discrepancy and complete
Utf8Message factory coverage remain separately unqualified. Build/source ceilings
are unchanged. Cold build, CPU/RSS, failed-attempt and timeout receipts retain
their individual attribution; overlapping wall intervals are not added and no
matched-workload speedup is claimed.
