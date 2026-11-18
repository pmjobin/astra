# ASTRA-28C COPR source build and repository delivery

This is one delivery campaign, using the existing checkout and the unchanged
installed `pm-next` workflow. The original prebuilt-RPM publication and
intermediate source-build packets were never launched and are superseded.
Fedora 45 x86_64 source-build and repository delivery: **SCOPED PASS**.
Development packages remain **DEVELOPMENT_UNQUALIFIED**. Full compiler release
qualification remains PARTIAL.

## Intake and source identities

The authenticated submission is
`ASTRA-28C-COPR-SOURCE-BUILD-AND-REPOSITORY-DELIVERY-SUBMISSION.zip`,
31,326,131 bytes, SHA-256
`6c3f2ca440d08568eae1c4c8534ef393a11eb18e841c8e1a063110677be18cf1`.
The bundled offline verifier passed before the installed intake check/prepare.
The initial HEAD was `fc6b84511e0d0b2ed80980e90d0b26b9a2987c06`, tree
`8c9cefcad2488bcf522c9889937d87d10864c4af`. All 31 supplied Git source witnesses
matched that initial revision. No task base was repinned.

The preceding report was 556,905 bytes, SHA-256
`60c9b09c2f11d3415ab1ed1322c11b39599db6a33547662fc1cda8182f0b22bb`;
its real post-delivery receipt matched. The historical preceding submission
SHA-256 remains
`bd95acf2d38b0a8e509c686f7dfcaa55eccb8112f0410b78ea468e9124408f2e`.

The public source branch is
[`ci/copr-source-build-28c`](https://github.com/pmjobin/astra/tree/ci/copr-source-build-28c).
The current COPR input is full commit
`b3e8675e981cbdb83b928a31048ddf0a8a512f1e`, tree
`f40adc2cc51dcc1d93fe657a4891c74b7653bc19`. Compiler and library trees, including
C providers, are unchanged from the locally source-built revision
`a4d0ab30c612a600f2117b25955b910294822ea9`; intervening changes concern packaging,
source assembly, acceptance and disclosures.

## Build method and bootstrap

The installed `copr-cli 2.8` and authenticated API confirmed actual FAS owner
`pmjobin`, project `astra`, build permission and the existing sole target
`fedora-45-x86_64`. The owner approved the exact initial reviewed push and source
inputs, existing smoke CI artifacts, manual COPR SCM builds/distribution,
packaging-only fixes preserving compiler/library/seed inputs, and task findings.
No project setting, webhook or additional chroot was enabled. No GitHub Release
was created. Existing branch smoke CI succeeded for the published build input.

`.copr/Makefile` and `tools/ci/copr_source.py` generate an inspected source RPM
from Git blobs. The tar has a complete 1,133-file source manifest, source/seed
licenses and provenance. It excludes untracked peer work, prior compiler
objects, private C0 and LLVM binaries. `%build` executes only the approved seed
to compile current compiler sources and required library modules into a fresh
O2 object, then rebuilds native C providers against Fedora LLVM headers.
Normal RPM dependency generation records the real shared LLVM dependency.

The only build-only seed is the already public 2,388,496-byte ELF, SHA-256
`560e7c9eaeb6cdb974efdd43ed4ac41191cdda4acdb4afd77052325addf1f1c6`.
Its [immutable acquisition URL](https://raw.githubusercontent.com/pmjobin/astra/f5cb38e4026124a64c93914a0e86b6ad182bbbf7/tools/ci/seeds/astra-27d-stage3-o2-linux-x86_64.elf)
is also recorded in `tools/ci/seed-linux.json`;
its original public source commit is
`0060fa319f0e72ea402ab64af87e3b3d2cab62b9`, tree
`8569db6bf75f673fbea70a8c8fc45a1626ae3ace`. Public seed bytes and original source
license were independently fetched and verified. The historical generation
recipe is present at report commit `97ef9c97007045c48b02f96b823b60108b0b25f6`,
rather than the earlier source-input revision. This is historical provenance,
not a new C0 qualification. No C0 oracle is needed or distributed.

## Genuine COPR attempts

| Build | Outcome and evidence |
| --- | --- |
| [11346940](https://copr.fedorainfracloud.org/coprs/build/11346940) | Source preparation failed: COPR passes an absolute spec path; the initial local guard accepted a relative path. Raw failure logs are retained. |
| [11346943](https://copr.fedorainfracloud.org/coprs/build/11346943) | Source RPM succeeded; target canceled early to canonicalize gzip output. Python 3.14/3.15 selected different default compression levels. The uncompressed tar was byte-identical; explicit level 9 reproduced the remote compressed bytes exactly. No binary delivery credit. |
| [11346948](https://copr.fedorainfracloud.org/coprs/build/11346948) | SUCCEEDED: SCM source preparation, cold Fedora 45 x86_64 compiler generation, signed RPM publication and actual clean DNF repository acceptance passed. |

COPR's SRPM worker uses Fedora 44 ARM. Source assembly now accepts the correct
absolute or relative spec and passes `--target x86_64` to `rpmbuild -bs`; it does
not execute the seed. Actual compiler generation occurs only in the requested
Fedora 45 x86_64 target. This does not qualify an ARM compiler target.

Canonical public source RPM:

- File: `astrac-0.0.3-0.devunqualified.20261118045328.gitb3e8675e981c.1.src.rpm`
- Bytes: 3,716,950; SHA-256 `841d73c8b5703c811d92908a6343e25a3c6dc5fd9bc111bf2051a2c347c52942`.
- Source tar SHA-256: `6dfbef81fc857661073e30c01b77586e01c886205dbf3b31d7f3b52455d6fa6b`, byte-identical to local generation across producer runtimes.
- Actual SRPM members: generated spec, source tar and the exact approved seed.
- Source URL: [COPR source RPM](https://download.copr.fedorainfracloud.org/results/pmjobin/astra/srpm-builds/11346948/astrac-0.0.3-0.devunqualified.20261118045328.gitb3e8675e981c.1.src.rpm).

Repeated local SRPMs are byte-identical under the recorded RPM environment.
SRPM headers may differ across RPM/distribution environments; the exact public
SRPM hash is recorded independently. Binary RPM byte reproducibility is not
claimed: package evidence includes measured resource observations.

## Current local source-build acceptance

The cold source generation ran in a network-isolated Fedora 45 container with
only the inspected SRPM and fresh output mounted. It had no source checkout,
prior object or private toolchain mounted. Toolchain: Fedora LLVM
23.1.5-2.fc45, GCC 16.2.1-3.fc45, glibc 2.44-2.fc45, Python 3.15.2-1.fc45,
binutils 2.47-1.fc45 and RPM 6.1.0-1.fc45.

Measured source generation: wall 1:05:22, user CPU 3,878.79 seconds, system CPU
11.40 seconds, maximum RSS 972,144 KiB. Fresh compiler object: 3,352,816 bytes,
SHA-256 `810c9dad63f83f7113234d56aea2459d2325f0d1597970925281e09bdccfbb93`.
It differs from the historical reused object
`a1e4fb5aa36aeb3726aa1bd47a74d8cce8464120410ba11a84a08c475f5c2988`.
Local native compiler: 2,430,960 bytes, SHA-256
`7cbc4dd6cba9f049763c654123d798de6d5439d931a456627137e6b682058a29`.

Actual source-built local acceptance passed:

- Clean Fedora installation, O0/O2 compile/link/run, C ABI and owning drops,
  expected diagnostics with preserved output sentinels, deterministic docs and
  installed Guide commands.
- Ordinary-user execution, system-library ownership and loader resolution,
  dependency-removal refusal, no LLVM payload or RPATH/RUNPATH, documentation
  without LLVM, corruption refusal and reinstall repair.
- Upgrade from the exact historical Fedora 45 comparison RPM, removal and fresh
  installation. That historical RPM was only a migration input, never uploaded.
- 17 strict unsuppressed memory observations: PASS; 39 actual physical mutations
  refused with 22 positive controls; 230 C API declarations checked against
  actual headers and runtime exports.
- Seed mutation, wrong commit, stale/missing source, missing license, prebuilt
  object, bundled LLVM, wrong package, wrong LLVM major, missing headers and
  foreign-architecture ELF refusal controls passed.

Historical-object helper-control RPMs were explicitly local controls used to
test packaging machinery while the cold generation ran. They earn no current
source-build or repository-delivery credit. Obsolete local attempts and genuine
remote failures remain retained, with their original revisions and outcomes.

## Actual COPR repository acceptance

The successful SCM build used `make_srpm`, not `uploadrpm`. Its cold generation
took wall 1:08:24, user CPU 4,068.61 seconds, system CPU 6.83 seconds and maximum
RSS 974,484 KiB. The fresh object is byte-identical to the independent local
generation above. Nine C provider objects were compiled against system LLVM
23.1.5; their commands and hashes accompany `SOURCE-BUILD.json` and the raw
logs. Installed native compiler: 2,430,960 bytes, SHA-256
`2e6a1dd1003e9cee5e317277a6300793595f2de0da13a2c15ac3896ba0f50fb7`.

The signed binary is
`astrac-0.0.3-0.devunqualified.20261118045328.gitb3e8675e981c.1.fc45.x86_64.rpm`,
1,383,626 bytes, SHA-256
`9d64b4ae3f6ceb6649f09da20c1475233143a77c5be0701e5f8e2d6f4c7c3bad`.
Epoch is absent (effective 0). The target-repacked `.fc45.src.rpm` is 3,717,231
bytes, SHA-256
`b1ff74fdd63691e325c4d6e503da143c7a52bdaaf09a3efd0830984c1355272e`;
its source archive and seed match the original source-worker SRPM exactly.

The actual [Fedora 45 repository](https://download.copr.fedorainfracloud.org/results/pmjobin/astra/fedora-45-x86_64/)
was enabled in a fresh official Fedora 45 container userland, with no compiler,
seed, current RPM or source checkout mounted. `dnf install astrac` and a
separate `dnf download astrac` selected the published product; the downloaded
binary matches the public artifact hash above. Container acceptance shares the
host kernel; this is not a separate machine or kernel qualification.

COPR key fingerprint: `15ABAA1BAE47EF69FF4191C469A25484A17044F7`.
The public key SHA-256 is
`cde0f86c76bfcf7e2dfb7bc4f5aabac2b74a4f672ea2ef549bfb180e42b7c6b6`.
DNF uses `gpgcheck=1`; `rpmkeys --checksig --verbose` reports both header and
payload signatures OK. Repository metadata is **unsigned** (`repo_gpgcheck=0`,
detached signature absent), as directly observed. No signing setting was changed.

The installed repository product passed O0/O2 compile/link/run, C ABI, owning
drops, diagnostics with preserved sentinels, deterministic documentation and
installed Guide commands. It also passed ordinary-user execution, RPM file
integrity, system-library ownership/loader checks, LLVM removal refusal,
documentation with LLVM hidden, corrupt-image refusal and reinstall repair.
DNF same-version update, upgrade from the exact historical comparison RPM,
uninstall with no payload left, and fresh repository reinstall passed. The old
RPM was a migration control only and was never uploaded.

All 17 strict unsuppressed memory observations passed on this actual native
compiler and Fedora LLVM. Independent tests repeated on the actual COPR product
passed all 39 physical mutations and 22 positive controls, the 230-function C
header/export matrix and 12 real ELF/payload refusal controls. No private LLVM,
static LLVM, object files, seed or RPATH/RUNPATH is installed. RPM requires the
distribution `libLLVM.so.23.1()(64bit)` and
`libLLVM.so.23.1(LLVM_23.1)(64bit)`, plus `llvm-libs >= 23`, glibc, Python >=3.11,
GCC, binutils and glibc-devel; the full automatic requirement list is retained.

The first repository run reached these product checks but stopped when its
download harness expected one RPM: COPR publishes both source and binary RPMs.
The harness now selects the sole x86_64 binary. A second complete fresh-userland
run passed signature verification and the entire lifecycle. Both raw runs are
retained. This acceptance-only fix and the final findings do not change the
published compiler/library/seed inputs or require another compiler build.

## Target survey

| Target | Status for this delivery | Actual evidence |
| --- | --- | --- |
| Fedora 45 x86_64 | SUPPORTED for this scoped development delivery; SCOPED PASS | System LLVM 23.1.5; local and COPR cold source builds, signed repository install and all scoped acceptance above. Only enabled target. |
| Fedora 43 x86_64 | NOT_SUPPORTED by this recipe; NOT_QUALIFIED | Official metadata: glibc 2.42-17, default LLVM 21.1.8-6. No target build or alternate LLVM qualification. |
| Fedora 44 x86_64 | NOT_SUPPORTED by this recipe; NOT_QUALIFIED | Official metadata: glibc 2.43-9, default LLVM 22.1.8-4. Source-worker use is not binary target qualification. |
| EL8 family / EPEL8 / RHEL8 | NOT_SUPPORTED by the current seed contract | AlmaLinux 8 metadata probe: glibc 2.28-251, LLVM 22.1.8. Seed requires glibc >=2.34 and LLVM_23.1. Actual COPR target not executed or enabled. |
| CentOS Stream 9 x86_64 | UNKNOWN for full source/package support | Actual clean probe: glibc 2.34-290, LLVM 23.1.3-1, GCC 11.5.0-16; seed binding/execution, O0/O2 compile/link/run and current C API ABI witness pass. Default Python 3.9.25 is below recipe minimum 3.11; no full compiler/package build. |
| EPEL9 / RHEL9 x86_64 | UNKNOWN / NOT_QUALIFIED | Chroots exist in COPR; Stream 9 probe does not qualify these distinct buildroots. Not enabled. |
| EL10 / EPEL10 / RHEL10 x86_64 | UNKNOWN / NOT_QUALIFIED | Stream 10 official metadata: glibc 2.39-148, default LLVM 22.1.8-1. Observed default LLVM cannot satisfy this seed; no actual target execution or enabling. |
| Other architectures/chroots | UNKNOWN / NOT_QUALIFIED | The approved seed and binary recipe are x86_64 only. No support claim or extra chroot enabled. |

## Preservation and final status

All 504 hash-protected exclusions, including the five Windows command scripts,
and the original untracked `tests/selfhost-compiler-complete/run.py` remain
preserved. Installed workflow sources, hooks/config and old build artifacts were
not rewritten. Initial preflights used the standard image cache; exact task
images were moved to the required build store and only those default-cache
copies retired. Subsequent runs use explicit project build/runtime engine paths.

The prior Fedora 45 scoped PASS remains historical. Ubuntu system-Z3/LLVM strict
memory NOT_PASS, original LLVM 23.1.4 NOT_PASS, rebuilt C0
ACCEPTED_WITH_DISCLOSURE, missing original C0 and 1,044 records, formal Reference
PARTIAL, and the unfinished Windows port are not repaired by this delivery.

All mandatory Fedora 45 source-build and remote repository gates passed in this
single delivery. The installed publisher records the exact final Git HEAD/tree
and original intake in the canonical report. The final findings commit descends
from the published build input; its acceptance/doc changes are recorded
separately from the immutable COPR source commit. Raw source, root, build and
consumer logs include failed, canceled, superseded and passing attempts. The
report retains their lossless text transport and public artifact identities;
large generated packages/builds remain under the project build directory.

Broader compiler release qualification remains PARTIAL with every historical
limitation above. No EPEL/RHEL support, Windows completion, LLVM 23.1.4 repair,
convergence, official Fedora-package compliance or full release is claimed.
