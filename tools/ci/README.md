# Astra 28-C1 bootstrap and installer engineering

This campaign adds local Linux packaging and fail-closed Actions recipes. It is
not a public release. Windows is unavailable; hosted execution and distributed
seed acquisition are unqualified. The installed canonical 28-C1 report records
the actual final gate outcomes, artifact hashes and retained failed attempts.

## Trust inputs

`seed-linux.json` pins the real 27D Stage3 O2 ELF by length and SHA-256. Its
compiler source is commit `0060fa319f0e72ea402ab64af87e3b3d2cab62b9`, tree
`8569db6bf75f673fbea70a8c8fc45a1626ae3ace`. The generation recipe belongs to the
later report commit, explicitly distinguished in the capsule. `seed_bundle.py`
verifies the owner-supplied 27D report, its segmented archive, the exact seed
blob and Stage3 receipt, then constructs a reproducible local capsule containing
the binary, source archive, provenance, license and toolchain manifest.

The seed's URL is deliberately null. `preflight.py --require-distribution` and
`pipeline.py` fail before bootstrapping if a runner cannot acquire the trusted
seed. An owner must authorize a durable distribution location and review a
manifest update before hosted use. Downloaded checksum files cannot replace the
committed digest. There is no lookup of a host `astrac`, rolling release or cache.

`llvm-linux.json` pins the official LLVM **23.1.4** archive and every selected
member. The archive supplies static LLVM archives, not a usable `libLLVM`
shared C API. `llvm_dylib.py` links the pinned archives, including Polly/ISL,
inside each supported distro with that distro's C++ compiler and system
zlib/zstd/libxml2. Its receipt binds every archive input and the resulting shared
library. The package embeds that private library and the upstream license
notices under `tools/release/licenses/llvm-23.1.4`. System dependencies are
installed by the distro package manager, not copied from the developer host.

`llvm-config --system-libs` names an upstream build-machine static zstd path.
The recipe explicitly replaces that one dependency with `-lzstd`; it does not
substitute LLVM versions or arbitrary archives. The host's default LLVM 23.1.5
is not a compiler dependency in this campaign. Separately qualified source
formatting tools retain their original identities.

Bootstrap trust remains a trust assumption. Stage convergence is not diverse
double compilation or a proof against a malicious seed. Rebuilt historical C0
remains **ACCEPTED_WITH_DISCLOSURE**, strict all-kinds memory **NOT_PASS**;
the original C0 and 1,044 proof records remain lost. The formal Reference's
28-A2-R1 PARTIAL and 222 unclosed semantic witnesses remain unchanged.

## Local build routes

Run all recipes from the real Git checkout with explicit inputs. New output
directories must be outside source and unused. For this checkout use the
authorized `~/Workspace/codex/work/astra/build/release28c1/` and corresponding
`runtime/release28c1/` roots. Never replace previous products in place.

1. Authenticate the seed against the report with `seed_bundle.py`. A local
   `--seed` argument still must match the committed length and hash.
2. Acquire the pinned toolchain with `trust.py --manifest tools/ci/llvm-linux.json
   --output ABSOLUTE_FRESH_DIRECTORY`. Extraction streams the full archive but
   retains only selected members, validating their names, types and hashes.
3. Run `llvm_dylib.py --llvm SELECTED_ROOT --manifest tools/ci/llvm-linux.json
   --build FRESH_BUILD --runtime FRESH_LOGS` in the declared Linux distro.
4. Run `bootstrap.py` with `--seed`, `--llvm`, `--library`, `--library-receipt`,
   `--commit` (exact clean compiler input revision), `--build`, `--runtime`,
   `--stages 2 --jobs 2`. It compiles current Astra source and fresh C providers;
   Stage1 O2 produces Stage2 O0/O2. Source filenames are repository-relative
   and the working directory is the authenticated checkout. Object, native,
   semantic-doc and dispatcher bytes are compared across those generations.
   No arbitrary-path reproducibility is claimed.
5. After committing package and Guide inputs, `handoff.py --products RESULT
   --identity IDENTITY --output HANDOFF` binds generated objects and both source
   revisions. Compiler sources may be frozen at an earlier ancestor than the
   packaging/docs revision. `package.py` verifies both source sets before use.
6. `package.py --kind deb|rpm` relinks the authenticated object with freshly
   compiled distro C providers and that distro's private LLVM library. Supply
   `--object`, `--handoff`, `--llvm`, `--library`, `--library-receipt`, `--build`
   and `--runtime`. Use a fresh Ubuntu 24.04 builder for DEB and Fedora 45 for
   RPM, with source and LLVM inputs mounted read-only. `rpm_job.py` automates
   the Fedora container route for Actions.
7. `clean_install.py` consumes the exact builder-reported SHA-256 and a single
   package, then launches a fresh pinned base image. It mounts no source,
   compiler build directory, toolchain or historical manifest. Only the
   package, lifecycle QA and output directory enter the install container.

The Python public launcher checks the installed native image and LLVM against
the package's root-owned installation manifest. It then execs the real native
Astra compiler. This catches corruption and missing files; it is not a defense
against an administrator who can replace both manifest and binary. The doc
image retains its independent no-LLVM boundary. The C dispatcher and all native
images are built from the declared current source; Python does not compile
Astra.

## Installed behavior and evidence

The only declared Linux platforms are Ubuntu 24.04 amd64 and Fedora 45 x86-64.
No RHEL, other Fedora, ARM, macOS or Windows support is inferred. Container
tests exercise clean userlands on the host kernel, not separate VMs.

Packages install `/usr/bin/astrac`, private files in `/usr/lib/astra`, examples
and source providers in `/usr/share/astra/tutorial`, smoke examples in
`/usr/share/astra/install`, and the matching rendered books in
`/usr/share/astra/books`. The API pages preserve the existing selected preview
scope; they are not comprehensive API coverage. The full 63 Book fixture
sources are preserved. No historical developer objects, compiler seed, GDB or
Valgrind are bundled. The package manager supplies `cc`, linker, Python and
runtime dependencies. LLVM is private to Astra and does not alter system LLVM.

`tests/install/lifecycle.py` checks install metadata, CLI, native O0/O2 objects,
link/run outcomes, an owning C ABI example, negative diagnostics with absent
and sentinel outputs, deterministic API JSON, missing/tampered dependency
refusals, doc-without-LLVM, same-version reinstall and removal. Its strict-memory
lane disables default suppressions and treats every leak kind as an error.
`tests/books/tutorial.py` replays the current installed Guide shell blocks
verbatim. The old contributor commands remain explicitly historical console
blocks; their original receipts are not rewritten. Cross-version upgrade is
not yet qualified.

Full current qualification also needs the existing independent LLVM physical
mutation suites, native ABI/ownership corpus, source-owner memory, both
compiler profiles, all 63 Book cases and API isolation/schema/render controls.
Installation smoke alone cannot confer these gates. Every receipt distinguishes
build completion from native acceptance. Failed attempts are retained.

## Actions security, scope and budgets

The workflow labels are `ubuntu-24.04` and `windows-2025`. Actual execution must
record ImageOS/ImageVersion, architecture, tool hashes, wall time, CPU and peak
RSS. Local timings do not establish hosted performance. GitHub documents a
six-hour hosted job ceiling and, for standard public Linux/Windows runners,
4 CPUs, 16 GB RAM and 14 GB SSD; private repository capacity differs. See
[GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
and [Actions limits](https://docs.github.com/en/actions/reference/limits).

The selected LLVM files occupy about 753 MB; the authenticated compressed
archive is about 1.19 GB. Streaming extraction avoids the upstream full
12.4 GB payload. Recipes refuse less than 4 GiB free before acquisition; this
is a minimum preflight, not a guarantee of all hosted peak usage. Retain actual
disk/RSS observations before treating the 330-minute nightly budget as proven.

| Lane | Bound | Evidence retained |
| --- | --- | --- |
| PR Linux | 25 minutes | source checks, refusal controls, seed native smoke; 7 days |
| Windows probe | 10 minutes | actual feasibility refusal; 7/14 days |
| Nightly Linux | 330 minutes | two generations, independent mutations, Book/native checks, DEB |
| Fedora packaging | 45 minutes | pinned container, relink and RPM receipts |
| Each clean install | 30 minutes | install, native/Guide/memory and removal receipts |
| Owner preparation / attestation | 10 minutes each | exact candidate metadata; 14 days |

Artifacts use source SHA and run ID names; checks bind transferred objects and
packages to independent producing-job outputs. No cache is used. CI tokens are
read-only; checkout never persists credentials. There is no
`pull_request_target`, release secret, public release, tag push or deployment.
Nightly concurrency preserves the current run rather than cancelling it.

The reviewed action revisions are recorded in the workflow files:
`actions/checkout` v4, `actions/upload-artifact` v4,
`actions/download-artifact` v4 and the supported `actions/attest` v3, each pinned
to its actual full commit SHA. Their official metadata and action definitions
are retained with campaign evidence. Review updates deliberately; do not follow
floating tags at execution time.

Release preparation requires the owner on main, an exact candidate SHA and a
completed successful trusted nightly run for that SHA. It refuses PARTIAL,
stale, foreign or missing native installer qualification. The optional isolated
attestation job has `id-token: write` and `attestations: write`, uses the
`release-preparation` environment, and requires an explicit dispatch input.
No environment or secrets were created in this campaign. At present preparation
cannot pass: Windows and hosted/distribution gates remain open. Candidate
metadata attestation is not a package signature or a public release.

## Windows blockers and next engineering work

The retained seed is ELF64 and only authenticated for Linux. Current
`compiler/driver/arguments.c` requires Linux x86-64 LP64 and captures arguments
through ELF startup. `compiler/backend/llvm/capi.c` rejects non-Linux target
triples. Runtime providers use POSIX APIs; the doc dispatcher uses
`/proc/self/exe`. An official Windows LLVM MSI does not supply an Astra seed,
Windows CRT implementation or a native compiler port.

A Windows follow-up must authenticate a native root of trust, port startup,
filesystem/providers, target selection and calling convention without changing
E25-A-v1, and prove a native Windows rebuild. Only then should a pinned audited
installer generator produce an EXE and undergo independent Windows Server 2025
install/PATH/O0/O2/C ABI/doc/uninstall tests. No fake setup EXE, Wine equivalence,
cross-target-only success or code-signing claim is supplied here.

After explicit authorization to make the workflow revision available remotely
and distribute the seed, trigger the nightly for its exact commit. Preserve
real run URLs and artifact digests, investigate hosted limits, and complete
native Windows qualification before enabling any release-preparation PASS.
