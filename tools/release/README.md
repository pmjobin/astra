# Independent developer builds

`developer-build.py` creates two clean source, build and install environments
from the committed Git revision. It builds only discovered installable Meson
targets, disables compilation caches, normalizes source/build paths in C debug
and file metadata, and installs into task-owned staging directories. It never
installs into the host system prefix.

```sh
python3 tools/release/developer-build.py \
	--output /absolute/external/astra-build/distribution --jobs 4 \
	--liburing-prefix /absolute/existing/liburing-2.15
```

Omit `--liburing-prefix` for the default profile without the optional Linux
provider. Matching installed dependencies must already exist; this recipe does
not install packages or download code. Required build tools are Python 3.12+,
upstream valac, a C11 compiler, Meson/Ninja, GLib/GObject and LLVM 23. Installed
compiler dependencies remain explicit system libraries; provider selection is
optional for generated programs.

For each run the recipe moves the newly created source/build directories out of
their original paths, relocates the installed prefix, and exercises its compiler,
O0/O1/O2 executables, source debug emission, formatter, package build and real
LSP client. It records installed file identities and compares all bytes/modes
between independently built prefixes. Differences remain visible for review.
No earlier source receipt substitutes for this execution.

The recipe checks that every supported checked-in Astra/VAPI/C/header library
input is installed byte-for-byte. It writes `share/licenses/astra/THIRD-PARTY.json`
from actual shared-library hashes and installed RPM or dpkg metadata, stage-0
tool identities and selected liburing header/archive identities. System shared
libraries and the external liburing archive are not bundled. The MIT notice for
selected liburing inline headers accompanies the project license. The installed
`share/astra/docs/tools/developer-release.md` documents private installation,
compilation, package/editor/debug use, supported profiles, ABI upgrades and removal.

`manifest.json`, command logs, the exact Git source archive and a normalized
binary archive remain under a unique external run directory. The artifacts are
explicitly development builds. Reproducible bytes alone do not qualify a release.
The retired RC1/RC2 campaign promoter is recoverable from the pinned Git revision
in `docs/history/active-tree.md`; there is no active replacement promoter.

`integrity.py` retains generic registry-closure and deterministic archive checks.
Their mutation and independent-byte tests are registered as
`optimizer-hardening-18-release-policy`. Those checks do not grant release status.
