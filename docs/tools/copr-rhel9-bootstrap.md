# RHEL 9 LLVM 22 bootstrap

The RHEL 9 x86-64 source RPM uses the build-only seed pinned in
`tools/ci/seeds/RHEL9-PROVENANCE.json`. Its dynamic dependencies are
`libLLVM.so.22.1` and `libc.so.6`. The ELF imports `LLVM_22.1`, and
its highest glibc symbol version is `GLIBC_2.34`.

The seed link used the relocatable compiler object recorded by both the
independent CentOS Stream 9 build and COPR build 11347573. The compiler
and library Git subtrees match the pinned bootstrap source byte-for-byte.
The Red Hat buildroot compiled the seed's C providers and linked a new
executable. The RPM then uses that seed to compile the 239 production
Astra source inputs and nine C translation units in a separate target
buildroot. The SRPM carries the seed as a source, and the installed RPM
requires system LLVM and Python 3.11.

## Replay the seed link

Use the x86-64 UBI 9 image in the provenance pin. The original buildroot
used the following Red Hat RPMs, verified with the image's Red Hat RPM
signing keys. The SHA-256 values refer to the whole RPM files.

| RPM | SHA-256 |
| --- | --- |
| `llvm-devel-22.1.8-1.el9.x86_64.rpm` | `be665537bc0a453e391edf79d1477d47143377d608800b32a524f502b8a62932` |
| `llvm-libs-22.1.8-1.el9.x86_64.rpm` | `e36e3f7f4a8e6a365723839eebb0f7788e66ddbed19fbfd8bd4b28e3a8e6238c` |
| `python3.11-3.11.13-10.el9_8.x86_64.rpm` | `a05e16b5733bceb90f8fc47ffabd7a888d4ba4c7f38af0438a1b871afcb4ea54` |

Install the RPMs with DNF's `localpkg_gpgcheck=1` after running
`rpmkeys -Kv`. Install `gcc`, `binutils`, `time`, `rpm-build` and
`redhat-rpm-config` from the same UBI repositories. The seed link used
`gcc-11.5.0-17.el9_9`, `binutils-2.35.2-72.el9_9` and
`glibc-2.34-290.el9_9`.

The authenticated predecessor report bundles the receipt as
`runtime/binary-build-evidence/source-generation.json` in its evidence
transport. The matching `astrac-O2.o` is the output of its local Stream 9
SRPM rebuild. Mount both read-only. The replay checks the receipt, object
and all compiler, library and C provider input bytes. Run this from the
read-only checkout mounted in the UBI 9 container, using fresh mounted
build and runtime directories.

```sh
/usr/bin/python3.11 -B tools/ci/rhel9_seed.py \
  --producer /input/astrac-O2.o \
  --producer-receipt /input/source-generation.json \
  --build /build/seed \
  --runtime /logs/seed
```

The finished file is `/build/seed/astra-rhel9-llvm22-x86_64.elf`. The
recipe requires byte equality with the pinned seed. The seed's literal
native `--version` text comes from the pinned compiler source. The
runtime version is independently verified through `LLVMGetVersion`
and the installed wrapper reports that runtime version.

## Local source RPM and rebuild

Run the COPR source worker entry point from a clean, pinned Git checkout.
Give the local seed as an explicit input and keep outputs outside the
checkout.

```sh
make -f .copr/Makefile srpm \
  spec="$PWD/packaging/rpm/astrac.spec" \
  outdir="$build/srpm" \
  ASTRA_RHEL9_SEED="$seed"
```

The RHEL 9 SRPM records `llvm-devel = 22.1.8`, `llvm-libs = 22.1.8` and
`python3.11` even when the source worker runs on Fedora. When the
approved seed file is present at
`tools/ci/seeds/astra-rhel9-llvm22-x86_64.elf` in a dedicated SCM
checkout, the same Makefile selects it. The selected seed's hash and
license provenance are checked before source generation.

Mount just the resulting SRPM in a fresh UBI 9 build container with
the target RPM dependencies and disable container networking for the
rebuild. Use a fresh writable mount at `/rpmbuild`.

```sh
rpmbuild --rebuild --define '_topdir /rpmbuild' /input/astrac.src.rpm
```

The local qualification runs the RPM installation in a fresh consumer
without the checkout or seed. The direct LLVM ABI tests, physical
mutation suite, payload controls and Guide use the same compiler built
by the SRPM. Hosted EPEL 9 delivery requires its separate source build
and clean DNF evidence.
