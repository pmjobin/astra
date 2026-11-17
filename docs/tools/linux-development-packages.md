# Linux development packages

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
