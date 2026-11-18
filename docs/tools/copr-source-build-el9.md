# `astrac` on Enterprise Linux 9

On 18 November 2026 the public CentOS Stream 9 x86_64 package passed
source-build and DNF consumer qualification. RHEL 9 and EPEL 9 currently
provide LLVM 22.1.8 and cannot load the approved seed. Overall EL9 delivery
is `PARTIAL`.

The EL9 source RPM uses `/usr/bin/python3.11` for `%build`, `%check`, the
installed CLI and its Python helpers. The RPM requires the distro `python3.11`
package. DNF keeps its own system interpreter. The normal source worker can
generate the SRPM on Fedora with its default Python. On an EL9 source worker,
invoke `/usr/bin/python3.11 -B tools/ci/copr_source.py` with `--commit` set to
the full checkout revision and `--output` set to an empty external directory.
The binary build runs the authenticated seed in the target userland. The
native compiler, the nine C provider objects and the documentation dispatcher
are built there. Development artifacts carry `DEVELOPMENT_UNQUALIFIED`.

## Target repositories on 18 November 2026

| Observation | CentOS Stream 9 x86_64 | COPR `epel-9-x86_64` |
| --- | --- | --- |
| System repositories | CentOS Stream BaseOS and AppStream | RHEL 9 BaseOS, AppStream, CodeReady Builder and Fedora EPEL 9 |
| glibc | `2.34-290.el9` | `2.34-290.el9_9` in the hosted root log |
| `python3.11` | `3.11.13-10.el9` | `3.11.13-10.el9_8` |
| `llvm-devel` and `llvm-libs` | `23.1.3-1.el9` | `22.1.8-1.el9` in the EPEL 9 build tag |
| Astra's 230 checked function names | All 230 declared and exported at `LLVM_23.1` | All 230 present in the matching signed Red Hat headers and exported at `LLVM_22.1`. Zero exported at `LLVM_23.1`. |
| Authenticated x86_64 seed | Native O0/O2 compile, link and execution passed. The standalone C ABI and LP64 witness passed. | Red Hat UBI 9.9 with the matching `llvm-libs` RPM exits 127 looking for `libLLVM.so.23.1`. |

COPR's `epel-9-x86_64` configuration includes `rhel-9-x86_64` and the EPEL
template. Its RHEL repositories require a client entitlement. All three Red
Hat CDN metadata requests returned HTTP 403 on this host using the distribution
CA. The packaged LLVM and Python identities above were independently checked
against Fedora's EPEL 9 build-tag index (96,910 packages), the EPEL 9 release
supplement (26,710 packages) and Red Hat's public UBI AppStream index. The
UBI LLVM and Python RPM SHA-256 values match the RHEL AppStream entries in the
build tag. Red Hat RPM signatures were verified. The two Fedora indexes had
zero x86_64 or noarch providers of the required SONAME. The executable refusal
was observed in UBI. DNF 4 independently resolved the seven package versions
in a fresh installroot using the checksummed EPEL build-tag metadata. Its
versioned provider query returned empty and its solver refused both
`llvm-devel >= 23` and `llvm-libs >= 23`. With both signed LLVM 22 packages
installed in UBI, the system-LLVM guard rejected the major version and native
`rpmbuild --rebuild` refused the actual EL9 SRPM before `%build` on exactly
those two dependencies. The hosted configuration and root log came from an
existing COPR EPEL 9 job. [Hosted EPEL configuration](https://download.copr.fedorainfracloud.org/results/@copr/copr/epel-9-x86_64/11314876-copr-cli/configs.tar.gz) · [Hosted EPEL root log](https://download.copr.fedorainfracloud.org/results/@copr/copr/epel-9-x86_64/11314876-copr-cli/root.log.gz)

The hosted CentOS Stream 9 x86_64 configuration from COPR build 11340275
enables CentOS BaseOS, AppStream, CRB and Extras Common. It uses
`quay.io/centos/centos:stream9` for bootstrap. The Astra project's
Stream chroot had the same base profile and no additional repositories,
modules or packages. The owner also enabled `rhel-9-x86_64`. COPR lists
`epel-9-x86_64` separately. [Hosted Stream configuration](https://download.copr.fedorainfracloud.org/results/rhcontainerbot/podman-next/centos-stream-9-x86_64/11340275-conmon-rs/configs.tar.gz) · [Astra COPR project](https://copr.fedorainfracloud.org/coprs/pmjobin/astra/)

The pinned CentOS Stream 9 base manifest digest is
`sha256:280add9b43d478ff06de6ccc6285afa7f1d81d8a0ea0d63e292a2f87f1d5aedf`.
The Red Hat UBI 9.9 manifest digest is
`sha256:1e9f0ed9fceafb40878bc1705ff124aa150e3fed873f18c42cdc2dded319e0a8`.
Both ran as x86_64 containers on the host kernel. The Stream toolchain used GCC
`11.5.0-16.el9`, binutils `2.35.2-72.el9` and RPM `4.16.1.3-42.el9`. Its
default Python was `3.9.25`. The distro-owned Stream LLVM library SHA-256 was
`855fac79489adb5140a903486b54b2897123f857e5a009d02d2b47f9ecaa7643`.

## Source and intake identities

The source candidate is `c08ad3000b92055b256a9f3bfe39981b248102d1`, tree
`091fa23c5ed93d280acc6b068fc3115415ee2a46`. The SCM recipe on the local
Fedora host produced two byte-identical source RPMs, 3,723,943 bytes each, SHA-256
`c848e461eb7d338fdbb8b28aff0d46d91d45d02ebb7fbd392f1a63ca3c0fa169`.
They contain the generated spec, the 1,134-file source snapshot and the
build-only public seed. The source tar SHA-256 is
`d65fb284257e3cdff75fdc5baa7a313fd28a5b8b16de8dd7d7bc8f97883a3055`.
The 2,388,496-byte seed matched its public Git origin at SHA-256
`560e7c9eaeb6cdb974efdd43ed4ac41191cdda4acdb4afd77052325addf1f1c6`.
Both source and seed licenses were authenticated. [Public seed](https://raw.githubusercontent.com/pmjobin/astra/f5cb38e4026124a64c93914a0e86b6ad182bbbf7/tools/ci/seeds/astra-27d-stage3-o2-linux-x86_64.elf)

Two additional SRPMs generated with Stream 9 Python 3.11 and RPM 4.16 were
also byte-identical, 3,719,310 bytes each, SHA-256
`41c183853c2c99fa1da451f0cdb5e37b77288c229bc04e17957e56b394901548`.
Stream zlib 1.2.11 and the local Fedora host's zlib-ng produced different gzip
streams. All four contained the same 11,878,400-byte uncompressed tar, SHA-256
`1749e4a2da349aaf5a992f61436806b2efe142b9df758a6b00ce3a2c11d69414`.
The source manifest SHA-256 was
`fe281695cdcde59f3ca3fefac7d506cacc0b17f9682e34f5dcc3d1cba9b7acac`.
Both producer environments passed the source and seed refusal controls.

## Local CentOS Stream 9 build

An offline `rpmbuild --rebuild` ran inside Stream 9 with an empty output
directory and the source-worker SRPM as its only input mount. The seed compiled
239 Astra source files at O2. GCC compiled the nine C providers and the native
documentation dispatcher. The compiler step took 1:04:48 elapsed, 3,844.91
seconds of user CPU and 12.14 seconds of system CPU. Peak RSS was 950,364 KiB.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Compiler object | 3,353,112 | `a1e4fb5aa36aeb3726aa1bd47a74d8cce8464120410ba11a84a08c475f5c2988` |
| Installed native compiler | 2,431,712 | `ed300ffc8ad022096c1939ca70232ec930492e693e47fe0088f116982314cbb5` |
| Local unsigned x86_64 RPM | 1,384,762 | `43ed6389d392078b9ac4386c291905ff169070cf66979e4d5562a6c1ad5d1083` |

The package version is `astrac-0.0.3-0.devunqualified.20261118071127.gitc08ad3000b92.1.el9.x86_64`.
An independent extraction matched the recorded compiler image and all nine
object hashes against the builder's files. The native image imports 216 LLVM
functions, all versioned `LLVM_23.1`. Its two immediate dependencies are
`libLLVM.so.23.1` and `libc.so.6`. RPM records a maximum glibc symbol requirement
of `GLIBC_2.34`, the ELF's versioned LLVM requirement, `python3.11` and
`/usr/bin/python3.11`. Only the SRPM carries the bootstrap seed.

### Installed compiler and refusal checks

DNF installed the local RPM into a fresh Stream 9 image that initially lacked
Astra, Python 3.11 and LLVM headers. The transaction pulled in the packaged
interpreter. The original `/usr/bin/python3` still resolved to
`/usr/bin/python3.9`, with the same executable hash. RPM verified its owner
package. A second fresh consumer ran the following checks against the installed
compiler. Neither consumer mounted the checkout or seed.

| Check | Stream 9 result |
| --- | --- |
| Installed use | O0 and O2 compile, link and execution passed, including foreign C calls, deterministic ownership drops, expected diagnostics and ordinary-user execution. |
| Documentation | Native JSON output passed and remained available with LLVM removed from the loader path. All 43 installed Guide shell blocks passed, including HTML rendering. |
| Strict memory | All 17 Valgrind cases had zero errors, zero suppressions and zero bytes in use at exit, including InstCombine, O0/O2 compilers and targets, negative input and documentation. |
| System LLVM | 230 header declarations and versioned exports, 216 actual native imports and 25 enum types recorded. The LP64 executable ABI witness passed. The loader used the RPM-owned system library. |
| Physical checks | The extracted compiler refused all 39 mutations and accepted all 22 positive controls under the independent debugger harness. All 12 ELF/payload corruption controls passed. |
| Package lifecycle | RPM refused removal of Python 3.11 and LLVM while Astra was installed. A tampered native binary was rejected. DNF reinstalled and repaired it, then uninstalled and freshly installed it again. |

Against those headers, Stream 9 GCC checked the calling convention of all
156 direct Astra LLVM bindings, including all 339 argument slots and every
return slot. The check compared arity, ABI class, width and alignment on
x86_64 LP64. Opaque handles crossed the boundary as pointers. The remaining
74 names are additional system functions used by the compiled product.
A runtime probe resolved all 230 names with `dlvsym` at `LLVM_23.1` and
rejected a request for the old symbol version. GCC also rejected a deliberately
incorrect return class for `LLVMContextCreate`.

The local DNF input was the unsigned RPM in the table above. Software from
these two local containers shares the host kernel. There is no qualified
older EL9 Astra package from which to test a cross-version migration.

## Hosted CentOS Stream 9 build

The owner authorized pushing the tested commit to
`ci/copr-el9-source-build-28c` and submitting it to the existing
`centos-stream-9-x86_64` chroot. The public branch resolved to the same full
SHA. COPR build 11347573 lists that single target, with networking disabled
for compilation. The branch's normal Linux smoke CI passed.
[GitHub source](https://github.com/pmjobin/astra/commit/c08ad3000b92055b256a9f3bfe39981b248102d1) · [GitHub smoke run](https://github.com/pmjobin/astra/actions/runs/44266408312) · [COPR build](https://copr.fedorainfracloud.org/coprs/pmjobin/astra/build/11347573/)

The Fedora 44 aarch64 source worker ran `make_srpm` using distro Python
3.14.10 and RPM 6.0.2. The public source-worker SRPM SHA-256 is
`4d7a4fd65ca028d8ac534e5b62fb2a86a7be1da463a22cfd46acc527f41c54fc`.
Its source tar, full pinned tree, individual file hashes and build-only seed
matched the local candidate. The hosted x86_64 Stream build log records
`/usr/bin/python3.11` invoking the target compiler build with the same
commit, tree and seed. [COPR source-worker SRPM](https://download.copr.fedorainfracloud.org/results/pmjobin/astra/srpm-builds/11347573/astrac-0.0.3-0.devunqualified.20261118071127.gitc08ad3000b92.1.src.rpm)

The hosted target succeeded. The compiler step took 1:09:08 elapsed, 4,111.76
seconds of user CPU and 7.91 seconds of system CPU. Peak RSS was 952,092 KiB.
Its compiler object, all nine provider objects and the extracted native
compiler matched the independent local build byte-for-byte. The archived
commands show both the seed invocation and each target-native GCC compilation.
[Hosted builder log](https://download.copr.fedorainfracloud.org/results/pmjobin/astra/centos-stream-9-x86_64/11347573-astrac/builder-live.log.gz)

| Public Stream 9 artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| [Target SRPM](https://download.copr.fedorainfracloud.org/results/pmjobin/astra/centos-stream-9-x86_64/11347573-astrac/astrac-0.0.3-0.devunqualified.20261118071127.gitc08ad3000b92.1.el9.src.rpm) | 3,724,602 | `3d49ec7935a48465eef17d1fec3e87e451ad3404e37a20cd25dff3690bf17ca7` |
| [Binary RPM](https://download.copr.fedorainfracloud.org/results/pmjobin/astra/centos-stream-9-x86_64/11347573-astrac/astrac-0.0.3-0.devunqualified.20261118071127.gitc08ad3000b92.1.el9.x86_64.rpm) | 1,384,932 | `0e49aa243f739dfe4874bfb2d11cdf22e5bde350caf8f4cbe0ffba148fc17457` |

The target SRPM's spec, source tar and licensed seed matched all three
members of the SCM worker's SRPM. COPR's `results.json` supplies the two
target package names. Their public COPR URLs redirect downloads to its
content storage. [Published package list](https://download.copr.fedorainfracloud.org/results/pmjobin/astra/centos-stream-9-x86_64/11347573-astrac/results.json)

### Public DNF consumer

CentOS Stream 9 x86_64 earns `SCOPED_PASS` for this development package.
Two fresh Stream 9 consumers enabled the Astra COPR. One began without
Python 3.11. DNF installed it and the compiler while keeping the default
Python 3.9 executable byte-identical. Both consumers installed by package
name, with the checkout, seed and local RPM absent.

```sh
sudo dnf install dnf-plugins-core
sudo dnf copr enable pmjobin/astra centos-stream-9-x86_64
sudo dnf install astrac
astrac --version
```

An independent DNF download matched the binary RPM hash above. RPM verified
its header and payload RSA/SHA-256 signatures against fingerprint
`15ABAA1BAE47EF69FF4191C469A25484A17044F7`. The repository configured
`gpgcheck=1` and `repo_gpgcheck=0`. Its `repomd.xml` had no detached
signature and had SHA-256
`53b636fe47f71eeccc846b9a05e19937289c6e1b39176e2558b376b015791f07`.
[DNF repository configuration](https://copr.fedorainfracloud.org/coprs/pmjobin/astra/repo/centos-stream-9/pmjobin-astra-centos-stream-9.repo) · [Repository metadata](https://download.copr.fedorainfracloud.org/results/pmjobin/astra/centos-stream-9-x86_64/repodata/repomd.xml)

The public installation passed all 17 unsuppressed memory cases, all 43 Guide
blocks, normal-user O0/O2 compile/link/run, C ABI and ownership checks, expected
diagnostics, and native JSON/HTML documentation. The signed payload passed all
39 physical refusals, 22 positive controls, 12 ELF/payload controls and the
230-declaration header/export matrix. Dependency removal was refused. DNF
repaired corruption, confirmed the installed version was current, removed the
payload, and installed it again from the repository. In a third fresh
consumer, DNF listed a single installable binary version. A real
`dnf downgrade astrac` transaction reported that the lowest version was
already installed. The package identity and native executable hash were
identical before and after that transaction.

## Intake and preservation

The initial Git revision was `2663b2f0cd01eb3650171f5b3e2c3b05d01fc917`,
tree `5c221f48e7132bc394c39857b88a967d25059cfe`. The bundled
`VERIFY-OFFLINE.py` passed on the 31,959,324-byte ZIP. The installed
`pm-next` intake then passed `--check` and `--prepare` on SHA-256
`4980eae9139a76e39d681525f311a6dd4ad42f03b3758fb13f2f8467af2a9255`.
The prior Fedora report's canonical SHA-256 was
`4d7400bb95b1620765a63c3744f48c8d766a201b4acf7b91f6922e2c3a623e52`.
It was published at 06:17:07 UTC. Its separate after-publication verifier ran
at 06:17:45.763769 UTC and recorded receipt SHA-256
`e92d57ccaf8c122526cb06703d7b8b7e60078c5f5eea96bacb72c2a08e521b4b`.
The authenticated predecessor submission was
`6c3f2ca440d08568eae1c4c8534ef393a11eb18e841c8e1a063110677be18cf1`.
The checks covered 11 Git witnesses, 1,526 evidence blobs, 3,301 logical
mappings, the installed workflow, the 504 protected paths and the untracked
peer source.

Fedora 45 x86_64 retains its earlier `SCOPED_PASS`. The existing signed RPM
from build 11346948 was fetched and matched SHA-256
`9d64b4ae3f6ceb6649f09da20c1475233143a77c5be0701e5f8e2d6f4c7c3bad`.
Its header and payload signatures verified in an empty RPM key database.
Its package signing fingerprint is
`15ABAA1BAE47EF69FF4191C469A25484A17044F7`. Its repository metadata is
unsigned. [Fedora 45 build](https://copr.fedorainfracloud.org/coprs/pmjobin/astra/build/11346948/)

RHEL 9 and EPEL 9 remain `PARTIAL` for distribution. To resume on either
target, first verify that its official buildroot supplies both LLVM 23 RPMs
and the `libLLVM.so.23.1(LLVM_23.1)(64bit)` capability. Repeat the public seed
and 230-declaration ABI checks in that target before scheduling its source
build. EL8 remains unsupported by the seed. EL10, Rocky and Alma have no
qualification from this work.

Full public release remains `PARTIAL`. Original LLVM 23.1.4 and Ubuntu 26.04
Z3 strict memory remain `NOT_PASS`. Rebuilt C0 remains
`ACCEPTED_WITH_DISCLOSURE`. The original C0 and 1,044 proof files are missing.
The Windows port is unfinished and the formal Language Reference is unresolved.
