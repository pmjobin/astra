# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# Generated substitutions are made only by tools/ci/copr_source.py.
%global commit @COMMIT@
%global source_tree @TREE@
%global astra_rhel9 @RHEL9@
%global debug_package %{nil}
# INSTALL.json authenticates the images: rpm must not rewrite them after install.
%global __strip /bin/true
%global __brp_strip /bin/true
%global __brp_strip_comment_note /bin/true
%global __brp_strip_static_archive /bin/true
%global _build_id_links none
%if 0%{?rhel} == 9
%global astra_python /usr/bin/python3.11
%global astra_python_req python3.11
%else
%global astra_python /usr/bin/python3
%global astra_python_req python3 >= 3.11
%endif

Name:           astrac
Version:        0.0.3
Release:        0.devunqualified.@DATE@.git@SHORT@.1%{?dist}
Summary:        Astra native development compiler with system LLVM
License:        Apache-2.0 WITH LLVM-exception
URL:            https://github.com/pmjobin/astra
Source0:        astra-%{commit}.tar.gz
Source1:        @SEED_NAME@
ExclusiveArch:  x86_64
BuildRequires:  gcc, binutils, %{astra_python_req}, time
BuildRequires:  /usr/bin/dnf, /usr/bin/rpm, /usr/bin/ldd
%if %{astra_rhel9}
BuildRequires:  llvm-devel = 22.1.8, llvm-libs = 22.1.8
Requires:       llvm-libs = 22.1.8
%else
BuildRequires:  llvm-devel >= 23, llvm-devel < 24, llvm-libs >= 23
Requires:       llvm-libs >= 23
%endif
Requires:       %{astra_python_req}, gcc, glibc-devel, binutils
Provides:       astra-development = %{version}-%{release}
Obsoletes:      astra-development < 0.0.4

%description
DEVELOPMENT_UNQUALIFIED Astra compiler, library sources, Guide and API books.
Built from pinned Git source using one licensed, hash-pinned build-only seed.
Uses distribution LLVM; no LLVM libraries or bootstrap compiler are installed.
Historical LLVM23.1.4 and Ubuntu Z3 strict-memory failures, missing original C0
and 1044 proofs, and the unfinished Windows port remain unresolved.

%prep
echo '@SOURCE_SHA@  %{SOURCE0}' | sha256sum -c -
echo '@SEED_SHA@  %{SOURCE1}' | sha256sum -c -
%setup -q -n astra-%{commit}

%build
%{astra_python} -B tools/ci/copr_build.py --commit %{commit} --tree %{source_tree} --seed %{SOURCE1} --rpm-version %{version}-%{release} --build %{_builddir}/astrac-output --runtime %{_builddir}/astrac-evidence

%install
mkdir -p %{buildroot}
cp -a %{_builddir}/astrac-output/payload/. %{buildroot}/

%check
%{astra_python} -B tools/ci/copr_build.py --audit %{buildroot}

%files
%{_bindir}/astrac
/usr/lib/astra
%{_datadir}/astra
%license /usr/share/licenses/astrac
