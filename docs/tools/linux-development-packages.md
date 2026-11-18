# Linux development packages

Current Linux products are `astrac` with distribution-managed LLVM and no
bundled LLVM. Read [the current findings](system-llvm-28c.md) for exact platform
statuses, package hashes, the LLVM 22 branch adapter and Ubuntu's strict-memory
blocker. Fedora 45 uses `llvm-devel` at build time and `llvm-libs` at runtime;
Ubuntu 26.04 uses official `llvm-22-dev` and `libllvm22`. Windows is separate.

Build providers and packages with `package.py --system-llvm --development`
using an authenticated `handoff.py --system-llvm` input. `system_llvm_matrix.py`
records real header declarations and runtime exports; `system-llvm-abi.c`
exercises the branch/LP64 ABI. `clean_install.py --development --system-llvm`
requires the target-built `--oracle`, exact `--predecessor` and its SHA-256,
plus fresh external `--build` and `--work` leaves. Its consumer mounts only the
package, QA oracle, old migration package and output leaves; no LLVM headers,
private toolchain or compiler checkout. The old product is used only during
migration, after the fresh-system native, Guide and strict-memory checks.

`development.py` builds a fresh generation with isolated build-only pinned
LLVM 23, then packages against distro LLVM. Optional exact predecessor DEB/RPM
paths and SHA-256 arguments enable full clean migration acceptance. Without
them, its result is explicitly PARTIAL/build-only. The manual GitHub workflow
keeps the pinned actions and `ubuntu-26.04` runner. New binary uploads are
removed until a separate owner decision; the prior exact approval grants no
permission for these products. No new hosted run is claimed.

## Historical private-LLVM delivery (2026-11-17)

The following records retain the preceding executed milestone and its exact
old products; their private-LLVM interface is superseded for current Linux builds.


The separate `development-packages.yml` workflow builds a fresh current-source
compiler from the authenticated public 27-D Stage3 seed. Its routine build is
one O2 compiler generation; the installed compiler must compile and execute
both O0 and O2 programs. This does not qualify three-stage convergence or
replace the independent C0/27-C inputs required by strict nightly.

The DEB builder is explicitly `ubuntu-26.04`. Installation uses a separate,
digest-pinned Ubuntu 26.04 userland. Fedora 45 reuses the SHA-256-bound compiler
object; its C providers and original LLVM library are built on Fedora. This is
one compiler generation, not two independent compiler-source builds. Both
clean installation environments share the host kernel; no VM is used.

`tools/ci/development.py --build /absolute/build --runtime /absolute/runtime`
runs acquisition, generation, packaging, fresh installation and bundling on an
Ubuntu 26.04 host with Docker. Prerequisites are `g++`, `python3`, `git`,
`libxml2-dev`, `libzstd-dev`, `zlib1g-dev`, `zstd`, `time`, and `dpkg-dev`.
Every build/runtime leaf must be fresh and outside the checkout. Individual
`bootstrap.py`, `handoff.py`, `package.py --development`, and
`clean_install.py --development --llvm /authenticated/llvm` recipes also support
local Podman execution with explicit task-owned engine storage paths.

The official LLVM 23.1.4 archive is unchanged. Its C header closure includes the
generated target `.def` files and nested `Transforms/PassBuilder.h`, which a
fresh source build needs beyond seed smoke. All are pinned by bytes and SHA-256
from the authenticated upstream archive. The diagnostic InstCombine rebuild is
not adopted. Original LLVM strict unsuppressed memory remains **NOT_PASS**.

Packages use commit-specific `devunqualified` versions and carry
`/usr/share/astra/DEV-UNQUALIFIED.txt`. Debian dependencies are calculated from
the actual linked ELF libraries using `dpkg-shlibdeps`, including the distro's
current library package names. RPM uses its native dependency generator.
The compiler's intrinsic CLI version remains `0.0.3-dev28c1`; the package and
provenance identities identify the new source build separately.

Installed acceptance covers native O0/O2, C ABI/ownership, exact negative
diagnostics and output preservation, deterministic API docs, installed Guide
commands, an ordinary user, corrupt/missing dependency refusals, reinstall
repair, and removal. The strict-memory observation runs independently and
retains nonzero failures, including a standalone LLVM C API oracle with
identity and malformed-IR controls. A functional lifecycle PASS never changes
a memory NOT_PASS to a qualification PASS. The strict defaults of the existing
nightly/install recipes remain in place.

The delivery ZIP contains both actual packages, raw `SHA256SUMS`, package and
generation receipts, source/toolchain/image identities, logs, installation
instructions, and licenses. `development_bundle.py --verify /path/delivery.zip`
rechecks every indexed member and both package digests. A SHA-256 of the outer
GitHub artifact is a separate identity from each raw package SHA-256.

Public distribution requires a separate owner decision after the local package
hashes, sizes and test results have been reviewed. The workflow does not upload
binaries by default. Only an explicitly authorized
`.github/development-build-request.json` can enable upload on the reviewed CI
branch, and only when the actor is the repository owner. The record must name
the reviewed commit and local package identities and acknowledge
`hosted_rebuild_with_original_LLVM_memory_NOT_PASS`. Source changes after that
review are refused; only the request record may differ. The request file's
push trigger permits branch-only execution without merging a workflow to main.
Creating that record requires the owner's actual authorization; this document
does not grant it.

After authorized execution, use GitHub Actions > Astra Linux development
packages > the specific run > Artifacts. The workflow downloads the uploaded
bundle again and validates its complete contents. Hosted and local products
retain separate hashes and receipts. No release, tag, signature, main merge,
secret change, private oracle upload or native Windows qualification is part
of this path.

Historical Ubuntu 24.04 results and all accepted, rejected and expired
milestones remain historical. Full release still requires its unchanged
independent compiler, memory, convergence and platform qualifications.

## Delivery engineering observations, 2026-11-17

The first current-source generation completed in an actual Ubuntu 26.04.1
userland: 3,976.4 seconds wall, 3,933.48 seconds user CPU, 10.46 seconds system
CPU and 960,108 KiB maximum RSS. Its compiler source revision is `6c257304`;
compiler and library source files remain unchanged from the task intake.
The authenticated O2 object is
`a1e4fb5aa36aeb3726aa1bd47a74d8cce8464120410ba11a84a08c475f5c2988`.
Fedora consumes this exact object and rebuilds its C providers and LLVM link.

The initial packages at package revision `df580d569a72` passed complete fresh
Ubuntu 26.04 and Fedora 45 functional install, 43 installed Guide blocks,
ordinary-user execution, corruption refusals, reinstall repair and removal.
Their corrected test harness copies the documentation fixture into its build
directory and supplies a relative source name, as required by the docs CLI.
The earlier absolute-path invocation failed and its command streams are
retained. Compiler generation and package payloads did not cause that failure.
Final candidate identities, subsequent packaging revisions and run receipts
belong in the canonical report; these initial results are iteration evidence.

Both installations independently reproduced three unsuppressed memory failures:
the standalone LLVM InstCombine oracle, the owning-case O2 compilation and
the values-case O2 compilation. All three report uninitialized-value use in
`llvm::InstCombinerImpl::foldUsingDistributiveLaws`. Identity/malformed-IR
controls, O0 compilations, generated native programs, negative compilation and
isolated documentation completed their focused strict checks. The overall
strict-memory result remains **NOT_PASS**, with no suppressions.

The official archive SHA-256 remains
`efdd1dbd089b99bfcfcde7b8eb1236163f2e88df5a981cca4f783ec9cb5e0378`.
Its fresh Ubuntu library link is
`4fe64dbacd385867ca5c1b81a83646771f762cdbe00e372ed89b268d8741f80d`;
the Fedora link is
`4b7e50c4ff5019fd21e817744eaad6a4c2ce8850e12dc4e6ab76672c7141cd36`.
The historical diagnostic derivative
`f171a729134b8ee13d104b0643c528f404465f1b9d9ba5429a19d3fa287b8127`
was rehashed and the development packaging gate rejected its authentic
diagnostic receipt. It was neither executed nor substituted in this delivery.

Ubuntu's actual dependency metadata requires `libxml2-16`; the old `libxml2`
package name is insufficient. The distro-native links resolve the installed
runtime libraries, and package metadata is generated from those ELF inputs.
The first cold-build attempts also exposed omitted generated and nested LLVM
C headers. The repaired lock adds only bytes authenticated against the same
official archive; all failed attempts remain available in task evidence.
