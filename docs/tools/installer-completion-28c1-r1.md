# 28-C1-R1 installer and CI completion evidence

This campaign remains **PARTIAL**. Its corrected intake starts at
`4c96dd81e571742fa74739c561e72e793f3f5852`, tree
`2441302d08ed3f507c34c031a4ac0f4842de541e`. The original 28-C1 report remains
PARTIAL; its Linux package results and failed memory streams are historical.
The canonical report's RESULT and qualification ledger bind the final revision
and completed current observations. Task build outputs live under
`~/Workspace/codex/work/astra/build/release28c1-r1/`; observations live under
the corresponding `runtime/release28c1-r1/`.

## Authenticated intake

The corrected 107,930,991-byte submission has SHA-256
`e2a32e5aa496bde7ec5d9370f6305f88ce75b6b710610d8c83d357c315826358`.
Its bundled offline verifier passed: 76 members, 61 read-only references,
57 source witnesses, 12-component maximum archive depth, and the complete
12,942-blob / 28,166-mapping predecessor transport. The installed, unchanged
`pm-next` validator accepted this exact ZIP and prepared it in the existing
checkout. The superseded rejected ZIP was not retried.

Live HEAD/tree, all 57 source witnesses and 504 formatter exclusions matched.
The existing preservation audit authenticated 451 protected paths, 6,622 donor
files, 14 hook records, Git settings, ABI proposal and the untracked peer script.
The genuine predecessor postpublication receipt hashes to
`a19e095bd3a70715629bf6f617445818f513d5ddaaf651b1bf906a61e1926798`;
its publisher command/streams and actual 7,090,189-byte canonical report were
independently rehashed. That report's SHA-256 is
`96208db3f6a78f7adceebc05417d45527bbc21393a775c8e0a761cf9b95351cd`.
Its immutable prepublication C8 record was preserved, rather than rewritten.
The authentic 27-D report was reopened from the predecessor submission; its
live seed and local capsule still match their independent pins.

## LLVM failure isolation

The original C adapter oracle and both O0/O2 native compiler hosts reproduce the
unsuppressed optimizer failure with the original serialized `values` IR.
`llvm-direct.c` removes Astra's adapter, frontend and platform providers entirely.
It uses LLVM's declared C API, checks the loaded library's 23.1.4 version,
verifies input/output IR, enables verification after every pass, and disposes
the parser/module/context/pass options/target/message resources.

The original library still fails when LLVMRunPasses has a null target machine
and only `function(instcombine)`. Two tiny independent functions containing an
integer add and an integer and reproduce it; see `llvm-instcombine.ll`.
The original error remains in `foldUsingDistributiveLaws`, including the
stack-derived comparison previously located at function offset `0x56`.
An identity function passes, and malformed IR is refused without an output.

An independent host relink of **all unchanged official static archives** still
fails. Rebuilding only `InstructionCombining.cpp.o` from the exact unchanged
23.1.4 source, replacing that member in a private copy of
`libLLVMInstCombine.a`, and relinking clears the focused oracle with both
the pinned upstream Clang and host GCC. Other archive members remain unchanged.
The original object itself contains the failing instructions before linkage.
Its producer comment identifies Clang 23.1.4 at the official release commit.

The original function is 13,115 bytes in a hot text section; the ordinary Clang
rebuild is 1,078 bytes. An explicit high-inlining-threshold experiment generated
a 5,839-byte function and also passed. This does **not** establish the original
upstream build flags, a source-level LLVM defect, a particular PGO defect, or
a Valgrind false positive. The evidence isolates an archive-object production
dependency; the exact producer transformation remains unresolved. The previous
standalone `opt` signal-handler retention observation remains separate.

The original library's strict memory status remains **NOT_PASS**. The rebuilt
library is labeled **LLVM 23.1.4 + unmodified InstCombine translation unit
rebuild**. It is a diagnostic derivative, without a source patch or approval
to replace the release dependency. Existing bootstrap and package validators
deliberately reject its distinct receipt status. No suppression, verification
removal, changed test expectation, or replacement LLVM version was introduced.

The portable `tools/ci/llvm_instcombine.py` recipe authenticates both original
archives, every selected LLVM archive, the producer and all upstream build
headers before compilation. It snapshots its own source and refuses source
drift. Build paths and logs are explicit. For example, from the project root:

```sh
python3 -B tools/ci/llvm_instcombine.py \
  --archive ORIGINAL_LLVM_23_1_4_TAR_ZST \
  --source ORIGINAL_LLVM_23_1_4_SOURCE_TAR_XZ \
  --llvm AUTHENTICATED_UNPACKED_LLVM_ROOT \
  --build ~/Workspace/codex/work/astra/build/NEW_DIAGNOSTIC_LEAF \
  --runtime ~/Workspace/codex/work/astra/runtime/NEW_DIAGNOSTIC_LEAF
```

`tests/install/diagnostics/llvm_compare.py` recompiles the independent oracle,
records its explicit loader routing and library resolution, reproduces the
original failure, checks the rebuilt oracle with strict unsuppressed all-kinds
memory, and compares exact optimized IR for minimal/values/identity controls.
The positive and invalid-IR controls remain mandatory.

## Current qualification scope

Current compiler/adapter/provider/library source inputs are byte-identical to
the authenticated starting revision. The existing Stage2 O0/O2 images retain
their original generation identities; they were not relabeled as new builds.
The broad Book, boundary and native/ABI/ownership/physical/source-owner replay
explicitly selects the isolated Clang-rebuilt library. Its exact product and
toolchain hashes are retained in the current qualification ledger. This cannot
qualify the original failing LLVM library or establish a new package release.

The completed Book replay passes all 63 cases in the exact 252 host/target
profile combinations. The complete 12-case boundary suite also passes with
this diagnostic library. These results supersede no historical receipt: the
original 31/63 qualification and 33 failed memory streams remain unchanged.
All 23 native suites completed, including ABI/ownership controls, 46 independent
physical mutations and source-owner qualification. The source-owner component
builds took 1,693.315 seconds at O0 and 2,474.150 seconds at O2; these are actual
overlapping process observations, not a summed campaign duration or a benchmark.

Book and boundary runners now offer `--keep-going`: a failed profile is
recorded and other profiles are attempted, while the suite still fails and
all original compiler/program/IR/diagnostic/memory assertions remain in force.
The original-library `values` control attempts all four profiles, records two
failures and exits nonzero. The entire original-library boundary run likewise
finishes with eight failed profiles and a nonzero result. The 8M SSA guard
remains unchanged; no unperformed 8M exhaustion test is claimed.

`tests/install/diagnostics/userland.py` authenticates and installs the original
DEB/RPM in the existing Ubuntu 24.04/Fedora 45 builder userlands, reproduces
the original failure, and explicitly overlays each distro's separately rebuilt
diagnostic library. Its C oracle and installed compiler's values/lazy-8 O0/O2
compile/link/execute/strict-memory checks pass in both userlands. These are
focused installed-payload comparisons, using a shared host kernel. They are
not new installers, clean-machine release lifecycle tests, or cross-version
upgrade qualification. The historical unsigned installers remain unchanged.

Failed experiments remain available: the first recipe incorrectly expected
the archive's `clang` symlink to be a regular executable; the second resolved
a ccache launcher as the linker executable. The corrected recipe authenticates
`clang-23` and selects the system linker explicitly. Direct RPM installation
refused the unsigned package; the retry used the same offline DNF route as
the authenticated prior campaign. The formatter initially loaded a mismatched
system libpython after a host update; selecting the retained qualified
Python's own libpython restored its exact pinned environment. Neither formatter
pins nor installed `pm-next` were changed. Original diagnostics retain their
pre-format C source bytes; final focused checks use the guarded formatted C.

## Hosted and native Windows gates

Nightly CI previously omitted the complete boundary/source-owner gates and
could lose detailed suite logs when an early command failed. It now invokes
the existing consolidated regression driver, including all 63 Book cases,
boundaries, native ABI/ownership/source-owner/physical tests and documentation
checks, and preserves suite evidence even on failure. Failed qualification
blocks packaging. The consolidated driver requests keep-going Book/boundary
coverage without accepting failed suites. This is local engineering, not a
hosted run qualification. The PR lane remains explicitly a seed smoke lane.

The complete regression driver also requires the independently authenticated
rebuilt-C0 oracle/runtime and the frozen 27-C source closure. Those local inputs
are not installed on a fresh hosted runner, and their portable acquisition is
not implemented. Nightly now checks that closure before expensive downloads or
builds. Publishing only the 27-D seed and pushing a workflow cannot close this
additional gate; the selfhosting seed must not replace its independent oracle.

The seed distribution URL remains null. Preflight returns BLOCKED and hosted
acquisition refuses before any download. Trust refusal controls remain active.
No GitHub push, artifact upload, public seed distribution, tag, release,
code signing, secret mutation or VM startup occurred.

The actual host is Linux, with no native Windows compiler/CRT, PowerShell,
Inno Setup, Wine or MinGW compiler available. Linux-specific argument transport,
target selection, providers, LP64 assumptions and `/proc/self/exe` dispatch still
require a real native port. No Windows compiler, selfhosting chain, EXE
installer or native lifecycle is claimed. The observed historical VM was not
started. Unvalidated Windows changes would not close this gate.

Owner actions before external execution are concrete and separate:

1. Provide an authorized Windows-native runner or explicitly authorize the
   intended VM's startup and test scope. Establish its target/CRT, authenticated
   LLVM/seed, native rebuild and installer/lifecycle evidence.
2. Choose and authorize an immutable seed distribution location. The raw ELF
   is 2,388,496 bytes with SHA-256
   `560e7c9eaeb6cdb974efdd43ed4ac41191cdda4acdb4afd77052325addf1f1c6`;
   the local capsule's `761182f0...` digest identifies a different artifact.
   Commit/review the actual immutable URL and digest before acquisition.
3. Separately authorize pushing the reviewed revision and running Actions.
   A prospective command is `git push origin HEAD:refs/heads/astra-release28c1-r1`;
   it has not been executed. Record genuine run IDs/URLs, runner versions,
   source/tool/workflow hashes and downloaded artifact identities afterward.
   First engineer and review portable acquisition of the rebuilt-C0 oracle,
   compatible runtime and Git-checked 27-C source closure. Any distribution
   of those additional inputs also needs the applicable owner authorization.
4. Resolve the original LLVM producer cause or approve an explicitly disclosed,
   fully qualified dependency derivative before any public distribution.
   Produce and clean-test fresh packages from the approved final input set.

Rebuilt C0 remains ACCEPTED_WITH_DISCLOSURE and its historical memory result
NOT_PASS. The original C0 and 1,044 proofs remain missing. Formal Reference
28-A2-R1 remains PARTIAL with 222 witness gaps. The scoped Guide and 27-D
selfhosting results retain their original boundaries. Independent verifiers,
ABI E25-A-v1, ownership/lifetime rules, module-owned layout-cache lifetime and
256-generic / 8M-SSA guards are unchanged.
