# COPR source RPM delivery

`astrac` uses the ecosystem project `pmjobin/astra`. The first target is
`fedora-45-x86_64`. This is a DEVELOPMENT_UNQUALIFIED development channel;
repository delivery does not qualify a compiler release.

The installed `copr-cli 2.8` supports `buildscm --method make_srpm`. COPR calls
`.copr/Makefile` from its SCM checkout with `outdir` and `spec`. The source
generator checks the full checkout commit, reads Git blobs rather than working
files, rejects modified tracked inputs, and creates a deterministic source tarball
with an exact SHA-256 file inventory. The SRPM contains that tarball, the spec,
and the approved build-only seed. Untracked peer work is excluded.

The spec authenticates both source inputs before extraction. The build driver
checks the source manifest against the spec's full commit and tree, executes the
authenticated seed with Fedora system LLVM, and compiles all current compiler
Astra sources and the required library modules into a new O2 object in a fresh
directory. C providers are compiled against RPM-owned LLVM headers, checked with
the executable C API/enum witness, and linked to RPM-owned system LLVM. The
native and isolated documentation images use the existing package payload
builder; they contain no seed, previous object or LLVM library. Normal RPM
dependency generation remains enabled. Image hashes are installed for the
existing dispatcher's verification, so RPM stripping of those already stripped
images is explicitly disabled; no broad dependency/post-install bypass is used.

`SOURCE-BUILD.json`, `DOCS-BUILD.json` and `source-compilation/` under
`/usr/share/astra` retain source identity, generated object hash, exact compiler
command, toolchain identities and CPU/wall/RSS observations. Root/build logs and
the signed RPM remain independent distribution evidence.

## Reproduce locally

Use the real checkout and a full committed source identity. Keep all output
outside the repository, under the project's build/runtime roots:

```sh
commit=$(git rev-parse HEAD)
python3 -B tools/ci/copr_source.py --commit "$commit" --output "$build/srpm"
make -f .copr/Makefile srpm outdir="$build/scm" spec=packaging/rpm/astrac.spec
python3 -B tools/ci/copr_controls.py --commit "$commit" --build "$build/controls" --runtime "$runtime/controls"
podman --root "$build/containers" --runroot "$runtime/containers" \
  build -t localhost/astra-copr-fedora45:28c -f packaging/rpm/Containerfile packaging/rpm
```

Mount only the inspected SRPM and a fresh output directory into the builder,
disable its network, and use `rpmbuild --rebuild --define '_topdir /work/rpm'`.
Use the same explicit `--root` and `--runroot` on subsequent Podman commands.
Do not mount prior compiler objects. Inspect the SRPM with `rpm -qpl` and
`rpm2cpio`; inspect the resulting RPM requirements, payload and ELF loader.
`tests/install/copr.py` supports explicit local RPM mode for prepublication
testing and repository mode for the actual delivery gate. Run it in a fresh
Fedora 45 userland with only QA inputs, outputs and (for local mode) the RPM
mounted. Supply the independent LLVM oracle and existing strict-memory fixtures
in `/qa`. Repository mode obtains `astrac` through DNF and validates its source
commit, signing information, installed behavior, Guide, strict memory, update,
reinstall and removal. Local mode cannot earn repository delivery credit.

## Manual publication boundary

Before the first remote write, obtain one owner approval naming the public Git
repository and branch, full commit, source tar hash, exact seed, COPR project,
Fedora chroot and resulting development binary distribution. Do not infer it
from this recipe or submission. Do not change project settings, enable extra
chroots, configure webhooks or create a GitHub Release.

After approval, push the reviewed branch and verify its public object ID, then
use the approved full commit with the installed CLI:

```sh
copr-cli buildscm pmjobin/astra --clone-url https://github.com/pmjobin/astra.git \
  --commit FULL_APPROVED_COMMIT --type git --method make_srpm \
  --spec packaging/rpm/astrac.spec -r fedora-45-x86_64 --nowait
```

Retain the genuine build ID, public URL, source log, root/build logs, source RPM
hash, signed binary hash and clean repository installation receipts. Use
`dnf copr enable pmjobin/astra` and `dnf install astrac`; a local RPM install
cannot substitute for this gate. Never put COPR credentials in logs or source.

## Bootstrap licensing and limits

The only seed is `tools/ci/seeds/astra-27d-stage3-o2-linux-x86_64.elf`, 2,388,496
bytes, SHA-256 `560e7c9eaeb6cdb974efdd43ed4ac41191cdda4acdb4afd77052325addf1f1c6`.
Its Apache-2.0 WITH LLVM-exception license and provenance accompany the source
archive. The immutable public acquisition URL and original source commit/tree
are in `tools/ci/seed-linux.json`. It requires x86-64, the GNU loader,
glibc >=2.34 and the LLVM_23.1 symbol version. No C0 oracle is an input.

COPR's [SCM documentation](https://docs.copr.fedorainfracloud.org/user_documentation.html#scm)
defines the Makefile interface. Its FOSS requirements and Fedora's
[third-party repository policy](https://fedoraproject.org/wiki/Third_Party_Repository_Policy)
still apply; this bootstrapped development recipe does not claim compliance with
the stricter official Fedora compiler packaging process.

Only Fedora 45 is initially allowed by the build driver. The live metadata
survey found CentOS Stream 9 glibc 2.34 / LLVM 23.1.3 and Stream 10 glibc 2.39 /
LLVM 22.1.8. Stream 9 remains UNKNOWN pending actual seed/header/native tests;
Stream 10's observed default LLVM cannot load this seed. EPEL and RHEL chroots
need their own evidence and approval; none is enabled by this implementation.

The prior Fedora 45 scoped PASS remains historical. Ubuntu system-Z3/LLVM
strict-memory NOT_PASS, original LLVM 23.1.4 NOT_PASS, C0
ACCEPTED_WITH_DISCLOSURE, missing original C0 and 1044 records, and the unfinished
Windows port are unchanged. No convergence or full release claim follows from a
single source generation.
