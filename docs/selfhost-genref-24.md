# GENREF-24: lexical member reference correspondence

Initial HEAD/tree are `6a9d99fab42a8ff49a92801625fe0b4d799b9faf` /
`9ef70582645dd5b356bc7327c57ed4d30fbd7dd4`. The unchanged installed pm-next
accepted the exact 128,251-byte submission. CALLPLACE-23's 21,408,478-byte PASS
report has SHA-256 `ba6ff507734ff831ef7770f9e9e0ad141b3472a4524e541cee477f8b4bde88cb`.
The older MEMBERCALL-22 checkpoint remains PARTIAL.

Before changing compiler implementation, all four original source populations
reproduced `CHECKED_CONSUMER 1 7`. Their separately executed source ledgers were
byte-identical to CALLPLACE's final ledgers. The read-only observer was compiled
by unchanged C0 from that exact baseline; its independent field-by-field result
agreed with the existing reference predicate for every plan through the first
failure. Its source snapshot, exact build identity, command, timings and outputs
are preserved under the external `genref24/witness-baseline-v1` runtime.

| Cohort | First failing plan | Original / concrete method | Original / concrete reference | Original / concrete node | Token | Original / concrete scope |
| --- | ---: | --- | --- | --- | ---: | --- |
| original | 28 | 1995 / 16587 | 57028 / 116354 | 22443 / 175249 | 43990 | 7750 / 12880 |
| LLVM23-base | 28 | 2064 / 17349 | 66897 / 126439 | 24032 / 189245 | 46981 | 8698 / 13842 |
| Class15-current | 26 | 2186 / 18560 | 78319 / 137935 | 34938 / 207366 | 69024 | 9610 / 14759 |
| live-initial | 26 | 2201 / 18670 | 79467 / 139086 | 35629 / 209229 | 70371 | 9724 / 14873 |

Each pair is the `walk` token in a recursive `this.walk(...)` call in the frozen
`compiler/core/consume.astra`, bytes 1719–1723. Both references have domain 4,
state 1, reason 0 and alternative 0. Source/node/token/span/domain/scope/order and
range checks succeed. The actual concrete reference targets the original lexical
method, kind 11, owned by the original Class. The old verifier instead remaps
that method's symbol to the plan's concrete standalone function, kind 1.

The binding and callable identities have distinct existing roles.
`BindingIndex.complete_reference` completes a member call only with a kind-11
lexical method owned by the exact receiver Class. `generic_method_target` selects
that source declaration; `generic_select_call` separately stores its executable
specialization in `generic_calls`. A concrete function with a hidden borrowed
receiver is not a lexical Class method. The old reference copier could also
remap an already-completed member edge to that function, making reference
identity depend on completion order. The same rule must therefore govern early
and late completion, while ordinary lexical locals, parameters and outer Class
fields continue to use their exact instance substitutions.

The repair preserves that lexical method target in the copier. The independent
verifier reconstructs its authority from the original declaration, the actual
receiver's exact nominal Class, token, scope and accessibility. It separately
checks node/reference ranges, order, forward/reverse chain membership, reason
and alternative state. Deferred member completion must prove the exact method,
field or initializer owner; a completed bit and a nonzero target are insufficient.
Ordinary local/parameter and enclosing-instance substitutions retain their
existing correspondence. Exact generic keys, call matching, borrow/ownership,
cleanup, receiver ABI, LLVM layout lifetime, all other compiler stages and the
256-instance/8-million SSA limits are unchanged.

The Python reference oracle independently walks the original/concrete syntax
trees from declaration roots, reconstructs symbol/scope correspondence using
declaration nodes and owner/parent chains, and checks exported maps against
that reconstruction. It does not use the copier's map as its proof. Its separate
mutations include same-layout nominal confusion, forged equal keys and hidden
receiver borrow loss. The native reference predicate has 37 substantive mutation
categories per profile; three well-linked wrong deferred targets pass the retained
v1 predicate and fail the final predicate, with valid twins restored. These are
distinct from the 27 Python-oracle categories and 28 inherited downstream controls.

Final C0-built compiler v3 passes the following at both O0 and O2:

| Current observation per profile | Result |
| --- | --- |
| Inherited native source identities freshly emitted/executed | 187; all raw LLVM byte-identical to predecessor |
| New distinct executable source programs | 15; 202 total source identities |
| New independent C0/native pairs | 15, including C0 syntax/C++ ABI measurements and source-visible results |
| New unsuppressed Valgrind pairs | 15; no memory errors or lost allocations |
| Material native allocation cases | 13; exact trace addresses retired, including nested record/Class/backing order |
| Native reference-model mutations | 37; code 7 refusal and valid twins restored |
| Separate independent reference-oracle mutations | 27 |
| Independently rejected LLVM-valid physical alternatives | 7; valid twins restored |
| Original source statuses | 80: 56 admitted / 12 rejected / 12 deferred |
| Replayed inherited downstream model controls | 28, excluded from new mutation counts |
| Source refusal controls | 10; writer destination preserved |
| Generic resource probes | 512 same-key requests retain one instance; 257 distinct requests retain 256 and refuse |

New programs cover lexical reuse, same-layout nominal records, outer fields,
generic methods, nested direct records, borrowed aliases, parameter/member
shadowing, branch cleanup, copied record owners, array result transfer, unrelated
families, owning parameters, recursive nongeneric and generic methods, and an
unrelated qualified module. They run through Typecore, Flow, Core, CFG, SSA,
LLVM assembly/optimization verification, native ELF, independent C0 and memory
checks. Unique source tuples are counted separately from duplicate ELF bytes.

All four original frozen populations independently pass the specific reference
gate at both profiles, then actually stop at `CHECKED_CONSUMER 1 25`. The
source/node/span population hashes are unchanged. The independent syntax oracle
verifies 2,394 / 2,394 / 2,367 / 2,367 reference pairs across 66 / 66 / 64 / 64
instances. No increase in typed-use counts is used as the advancement proof.

| Cohort | Next call / argument node | Exact source span in `compiler/semantic/flow-check.astra` | Original obligation-19 call node |
| --- | --- | --- | ---: |
| original | 49913 / 49912 | 23489–23520 | 40833 |
| LLVM23-base | 52089 / 52088 | 23687–23718 | 42968 |
| Class15-current | 69393 / 69392 | 24314–24345 | 46736 |
| live-initial | 70840 / 70839 | 24893–24924 | 47584 |

The next actual failed predicate is unchanged `generic_calls_verified`, diagnostic
witness 13: its unchanged `generic_type_matches` rejects the argument to
`index.graphs.append(move graph)`. The recorded argument type is **TypeId 0**,
flags 4 (owned), obligation 19; the local `graph` symbol also has type 0. The
call result is type 14 with flags 0 and obligation 19. The local name is not
evidence of a nominal FlowGraph type. All four earlier original calls retain
type 1, flags 0 and obligation 19. Whole modules still refuse; they do not execute
as native compiler programs.

Both complete original `admit_record_value` and `class_storage_slot_flow` callers
retain byte/AST identities and their `throws Error` signatures. Their native
complete-caller status remains **DEFERRED**. C0 parsing/AST comparison is not native
execution of those callers. The separate unsupported-effect control still refuses
at effect 6; no recoverable error transport, exception ABI, public policy, fatal
trap substitution or broader throwing-body qualification is introduced.

All 451 protected paths, 6,622 read-only donor files, 1,044 historically attributed
proof hashes, original reports, hooks/config, peer work and excluded fixtures
remain intact. Historical three-specialization SSA work-limit cases, wide-u64/f32
Valgrind discrepancy, complete Utf8Message factory/exception coverage, full compiler
native admission, self-compilation and Stage 1 retain their deferrals.

Final cold C0 compiler builds measured 1,210.98 s / 1,967.89 s wall time,
1,199.85 s / 1,947.89 s user CPU, 1.86 s / 1.95 s system CPU and
1,964,404 / 1,973,584 KiB peak RSS at O0/O2. Exact-identity warm reuse measured
1.11 s / 1.12 s and performs no recompilation. Builds overlapped; parent/child
timings and RSS are not additive exclusive benchmarks. The audit records exact
ELF sizes and all successful, failed and cancelled build receipts. Refused
shadowing drafts, the oversized one-function resource probe, early observer and
selector errors, cancelled v2 builds and intermediate v1 qualifications remain
attributed to their actual revisions. All 151 recorded authored build-input
versions have been recovered by exact SHA; private session logs are not packaged.

Reproduction recipes live in `tests/selfhost-genref/`: `state.py` records initial
preservation/baselines; `observe-build.py` and `observe-run.py` produce the
pre-repair witness; `corpus.py`, `source-probe.py`, `oracle-generate.py`,
`build.py`, `data-run.py`, `cohorts.py`, `next-blocker.py`, `qualify.py`,
`inherited.py`, `mutation-build.py`, `mutations.py`, `oracle-mutations.py`,
`physical.py`, `controls.py`, `resources.py` and `lifetime.py` retain explicit
build/runtime routing and command ledgers. `audit.py` binds actual results to
the final clean Git state; `handoff.py` packages every current attempt using
lossless, hash-verified transport through the unchanged installed publisher.
Generated evidence belongs under external `work/astra/{runtime,build}/genref24/`.

The graph tables use `columns.py` for byte-exact token-column storage, with an
original-byte hash for every restored observation. `transport.py` reads the
unchanged `astra-line-chunk/1` format using one disk spool. The existing chunk
writer, observation/ledger restorers, installed workflow and report caps remain
unchanged. Earlier packaging attempts and the complete oversized archive remain
preserved with their actual status/hash; their duplicate transport bytes are
listed as external artifacts instead of being nested in the replacement archive.
