# 28-C1 installer and CI engineering disposition

**PARTIAL.** Actual unsigned development DEB and RPM packages install and work
on the declared Linux userlands. They are not release-qualified: broader strict
compiler memory fails with the packaged LLVM dependency. Native Windows, seed
distribution and GitHub-hosted execution are also open. No public release, push,
tag, deployment, signing key, repository permission or secret was changed.

The installed canonical report is
`~/Workspace/codex/reports/astra-report-current.zip`. Its final commit/tree,
gate ledger, raw evidence transport and artifact inventory are authoritative.
This document records durable findings; it does not preclaim the publisher's
later successful execution.

## Authenticated inputs and source scope

The exact 100,529,727-byte submission has SHA-256
`b954139abb277084db067194a73b19d7e80f05f53eba15a6be5342d477db0920`.
Initial HEAD was `1c66336d5e6ff6b0a137e83102630be0557066e6`, tree
`e2d992d8e7f807284b0de3484057dad3696a6fc2`. The offline verifier authenticated
67 indexed entries, 51 read-only references and 46 committed source witnesses.
The live installed 28-A2-R3 publication was authenticated separately from its
immutable prepublication B9-pending record. The predecessor report SHA-256 is
`ef53ff2537c894677deb46fa14c2e7face881fb315b083921d1a5b2a55eadb7e`.

The selfhosting seed is the actual 27D Stage3 O2 Linux ELF, 2,388,496 bytes,
SHA-256 `560e7c9eaeb6cdb974efdd43ed4ac41191cdda4acdb4afd77052325addf1f1c6`.
Its source commit is `0060fa319f0e72ea402ab64af87e3b3d2cab62b9`; the later
generation-recipe revision is separately bound. The original 27D report,
segmented evidence archive, seed blob and generation receipt were rechecked.
The reproducible local seed capsule is 1,387,228 bytes, SHA-256
`761182f09c5bd9c110afd5d98db4be162a6dc179fe2fd4a90ddf4cc1396ae014`.
Its distribution URL remains null. It is not available to a clean hosted runner.

Current compiler sources were frozen at
`791c763c571c994b35d30f2530bbda4f401a8d4a`, tree
`ed001ea1ca0f9b6c9731a909d6ab98a1f34efbbf`. The only compiler source change
is the `0.0.3-dev28c1` version banner. E25-A-v1, the 256-instance and 8M SSA
bounds, independent verifiers and module-owned LLVM layout-cache lifetime are
unchanged. Source paths passed to the compiler are repository-relative; the
working directory remains the real authenticated checkout.

The final packages bind packaging/Guide commit
`4dd7d3d0ab0e168a28e0582b2e55f432b9558a8e`, tree
`b2e0850ec4d3f9f6ed6798ffbae0bc16fbc045e3`, and the separately frozen compiler
source revision. Later diagnostic and report changes do not retroactively
change the package's source identity. The report records both revisions.

LLVM is exactly **23.1.4** from the official Linux archive, SHA-256
`efdd1dbd089b99bfcfcde7b8eb1236163f2e88df5a981cca4f783ec9cb5e0378`.
The full archive is 1,190,060,068 bytes. A streaming acquisition recipe validates
261 selected members (about 753 MB), including all 201 static archives, rather
than requiring its entire 12.4 GB expanded payload on a hosted runner. Separate
Ubuntu and Fedora builds link these archives into private LLVM C API libraries.
The original upstream absolute zstd build path is explicitly replaced by the
distro's declared `-lzstd` dependency. No runner-default LLVM substitution occurs.

## Actual Linux artifacts and installed behavior

All artifact paths below are relative to
`~/Workspace/codex/work/astra/build/release28c1/`.

| Platform | Artifact | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Ubuntu 24.04 amd64 | `ubuntu-package-notices/astra-development_0.0.3~dev28c1-1_amd64.deb` | 38,349,510 | `8c260da73471814caf780a604d74b3af454a4526dcb0dbe3dc635fcc1bff5386` |
| Fedora 45 x86-64 | `fedora-package-notices/astra-development-0.0.3-0.dev28c1.1.x86_64.rpm` | 38,171,513 | `2207c00cba71651ef9e1cedbcc45c3a9f919dffcddc48de909b4a894ea6d5869` |

Each package was built with distro-native C providers and the actual
source-generated O2 compiler object. Fresh pinned base containers received only
the package, lifecycle QA and empty output directories. No developer compiler,
LLVM tree, source checkout, historic provider objects or C0 manifest was mounted.
The distro package manager installed the declared external prerequisites.
Containers share the host kernel; no separate-VM claim is made.

The final archives include 176 distinct verbatim notices from 298 upstream
source entries, collected from the authenticated 23.1.4 source archive
`819ecf7351f1a66f76b2d701d8942faaf5faeb324cb90c9d5b090de142434bb2`.
This includes xxHash, Unicode, regex and BLAKE3 notices alongside the LLVM,
Polly, ISL and imath main licenses. The DEB also installs the conventional
`/usr/share/doc/astra-development/copyright` file. Earlier package revisions
remain retained; the table identifies the later notice-complete bytes actually
retested through both clean-install lifecycles and the memory reproducer.

Both final packages passed:

- Literal Guide install commands, metadata, `--version` and `--help`.
- Direct private `LLVMGetVersion` returning `[23, 1, 4]`.
- Native O0/O2 compile, ELF object inspection, system C link and program execution.
- Owning C ABI behavior: five drops and sum 30; type and ownership refusals,
  absent outputs and preserved sentinels; deterministic `astrac doc` JSON.
- Strict all-kinds, unsuppressed memory for the selected installed smoke inputs.
- All 43 current installed Guide shell blocks, including input-data edge cases.
- Non-root compile/link/run; missing and tampered dependency refusals; docs
  without LLVM; corrupt-image repair by same-version reinstall; uninstall while
  preserving the external compiler/Python prerequisites.

These are passing scoped tests, not a whole-compiler memory PASS. Cross-version
upgrade, other distributions, package bit-for-bit reproducibility and Windows
are unqualified. Packages are unsigned and remain local. Each installer is
larger than the unchanged installed reporter's 25 MiB ZIP limit, so the report
contains exact identities, paths, build recipes, payload inventories and raw
test evidence; the actual installer files remain at the paths above.

## Current safety evidence and unresolved optimizer failure

The consolidated native lane completed all 23 suites across both compiler
profiles, including source-owner O0/O2 generation, native execution and strict
memory. All 46 independent
physical mutation controls passed (14 ownership, 7 range and 2 enum mutations
per profile). The completed native ABI, ownership, weak/shared, range, match,
formatting, collection, intrinsic and C-client suites passed their actual
expectations. The source-owner builds took about 1,767 seconds at O0 and
2,594 seconds at O2; individual raw resource receipts remain in the report.

Focused docs schema, isolation, native/comment-equivalence and strict extraction
memory passed. API previews passed at both profiles after selecting only the
ten Astra library inputs from the expanded bootstrap receipt; five C providers
are not documentation input files. The 476-case grammar dump preflight passed;
this is not a new typed-source grammar regeneration.

The full Book run stopped on `values` at host O0 / target O2. The remaining
previously untouched cases were run individually with the original strict
recipe and expectations unchanged. In total, all 63 cases were attempted;
31 completed the four-profile strict matrix and 32 remain unqualified. Each
failed case stopped at its first failing check, so 252 successful profiles are
not claimed. The exact generic 256/257 checks completed; the boundary suite
stopped at `lazy-8-O0-O2`, leaving its remaining cases unqualified.
The stream audit rehashed 4,327 command records and 881 distinct memory streams;
33 memory streams failed and remain recorded as failures.

Valgrind reports conditional branches using uninitialized stack data in
`llvm::InstCombinerImpl::foldUsingDistributiveLaws`. The focused `values` check
returns 99 with 18 errors from two contexts, zero suppressed errors and zero
live heap blocks. It reproduces with both bootstrap host profiles and with both
final installed O2 package payloads. Retained disassembly shows the reported
branch at function offset `0x56` following a stack-slot comparison. This
localizes the observation; it does not establish a complete upstream root cause.

The pinned standalone `opt` investigation is a separate NOT_PASS observation:
it retained 73,728 bytes through `llvm::InitLLVM` signal-handler setup under
strict all-kinds checking. That run did not reproduce the same uninitialized
branch and is not evidence that the two failures have the same cause.

No suppression, compiler verification bypass, source-fixture change, LLVM
version substitution or historical-memory waiver was used. Resolve the exact
23.1.4 dependency failure through an authenticated corrected build and repeat
the affected source generations and strict qualification before release use.

## Open gate ledger and next actions

| Gate | Actual disposition | Required next action |
| --- | --- | --- |
| C0 intake | Authenticated exact ZIP, Git base, protected/peer state and genuine predecessor publication | Retain the installed publisher's final identity |
| C1 bootstrap | Authenticated local seed; Linux generation receipts retained; distribution and Windows trust open | Authorize an immutable seed location; establish native Windows root of trust |
| C2 Linux artifacts | Real source-generated DEB/RPM; both tested on their declared userlands | Keep qualification scope separate from C7 |
| C3 Windows | No native compiler or setup EXE | Port startup/providers, target/CRT/ABI/doc dispatch; authenticate seed; native rebuild and clean install tests |
| C4 installed programs | Linux smoke and lifecycle pass; Windows absent | Execute the same native Windows contract after C3 |
| C5 hosted automation | Three committed workflows; local lint/refusal controls; zero remote workflow executions | Owner authorization to push the workflow revision and distribute seed, then retain genuine run URLs and artifacts |
| C6 Guide | Current Linux install/setup/tooling replay passes; Windows explicitly unavailable | Add Windows commands only after native acceptance |
| C7 regression | PARTIAL: broader compiler strict memory NOT_PASS | Repair and requalify the exact LLVM dependency; finish the affected matrices |
| C8 delivery | Exact source/artifact/evidence records prepared | Run unchanged installed canonical publisher and independently reopen its actual result |

Read-only GitHub access succeeded for `pmjobin/astra`; the workflow inventory
returned zero. Access denial is not the blocker. The new workflows exist only
in the local checkout, and this milestone explicitly excludes push authority.
PR/native tokens are read-only; actions use reviewed full SHAs, transferred
artifacts are bound to producing-job hashes, and no cache bypass exists.
Seed acquisition and Windows probes fail closed. Owner preparation rejects
PARTIAL; its optional isolated attestation concerns candidate metadata. Full
release-package staging/signing remains unimplemented and unqualified.

A shut-off local `win11` VM was observed and left untouched. Linux-hosted probes
found no Windows CRT for the selected Clang target; the current startup source
also explicitly rejects non-Linux LP64 hosts. Current target selection, POSIX
providers and `/proc/self/exe` dispatch need an actual port. Neither a Windows
LLVM MSI nor a cross-target probe supplies a native Astra compiler or installer.

## Failed attempts and historical boundaries

Raw evidence retains the interrupted absolute-source-path build, initial seed
capsule recipe-revision mismatch, toolchain extraction/dependency experiments,
Ubuntu fortified-write build warning, developer-home-path package refusal,
missing tutorial data, incorrect absolute-path doc test, API input-selection
failure, and all strict-memory failures. Corrections changed authored recipes
or test invocations; no earlier receipt was overwritten or promoted to PASS.

The Guide changes are limited to first-run/setup/tooling and hosted-provider
instructions. The original contributor recipes remain explicitly historical.
All 63 existing Book cases and their source fixtures remain byte-exact. Four
source-witness hash pairs in `docs/books/rules.json` track the banner-only file
change without modifying the witnessed semantic text.

Formal Reference 28-A2-R1 remains **PARTIAL**, with 222 unclosed semantic
witnesses. Rebuilt historical C0 remains **ACCEPTED_WITH_DISCLOSURE**; its strict
all-kinds memory remains **NOT_PASS**. The original C0 and 1,044 proof records
remain lost. Current observations do not restore or supersede those states.
