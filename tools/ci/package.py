#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Relink authenticated Astra objects on each distro; build real DEB/RPM packages."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys

from bootstrap import PROVIDERS
from system_llvm import discover, audit_payload, audit_elf
from common import ROOT, clean_environment, external, identify, require, run, sha, verify, write


def build_payload(a, handoff, build, runtime, env, llvm):
	"""Construct the same installed product from an independently authenticated object."""
	stage = build/'payload'
	private = stage/'usr/lib/astra'
	private.mkdir(parents=True)
	config = Path(llvm['config'])
	cc = Path(shutil.which('cc')).resolve()
	material = dict(format='astra-package-build/1', compiler_mode=a.mode, compiler_object_sha256=sha(a.object), compiler_source_commit=handoff['source_commit'], provider_rebuilds=handoff.get('provider_rebuilds', {}), package_source_commit=handoff['package_commit'], package_source_tree=handoff['package_tree'], source_inputs=handoff['sources'], package_inputs=handoff['package_sources'], handoff_sha256=sha(a.handoff), LLVM=llvm['version'], system_llvm=llvm, cc=identify(cc), recipe_sha256=sha(__file__), package_kind=a.kind, unsigned=True)
	if a.development:
		suffix = 'devunqualified.'+handoff['package_commit'][:12]
		default_version = '0.0.3~'+suffix+'-1' if a.kind == 'deb' else '0.0.3-0.'+suffix+'.1'
		material.update(qualification='DEVELOPMENT_UNQUALIFIED', original_LLVM_strict_memory='NOT_PASS', diagnostic_derivative_used=False, package_version=getattr(a, 'package_version', None) or default_version)
	fingerprint = hashlib.sha256(json.dumps(material, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
	write(runtime/'docs-build-identity.json', dict(fingerprint=fingerprint, material=material))
	objects = []
	for name in PROVIDERS+['compiler/docs/host.c', 'compiler/driver/doc-guard.c']:
		obj = build/(Path(name).stem+'.o')
		extra = shlex.split(subprocess.check_output([config, '--cflags'], text=True, env=env)) if name.endswith('/capi.c') else []
		if name.endswith('/host.c'):
			extra.append('-DASTRA_DOC_BUILD_SHA256="'+fingerprint+'"')
		if name.endswith('/doc-guard.c'):
			# This fatal guard deliberately ignores a best-effort stderr write.
			# Ubuntu fortifies write(); retain its warning and unconditional _Exit.
			extra.append('-Wno-error=unused-result')
		run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *extra, '-c', ROOT/name, '-o', obj], runtime/('provider-'+Path(name).stem), env)
		if not name.endswith('/doc-guard.c'):
			objects.append(obj)
	compat = ['-Wl,--wrap=LLVMGetInstructionOpcode'] if llvm['major'] == 22 else []
	run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-I'+llvm['include'], ROOT/'tests/install/diagnostics/system-llvm-abi.c', build/'capi.o', llvm['library']['path'], *compat, '-o', build/'system-llvm-abi'], runtime/'abi-build', env)
	run([build/'system-llvm-abi'], runtime/'abi-run', env)
	common = [cc, '-no-pie', a.object, *objects, *compat]
	native, doc = private/'astrac.native', private/'astrac.doc'
	run([*common, llvm['library']['path'], '-o', native], runtime/'native-link', env)
	run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-I'+llvm['include'], '-DASTRA_SYSTEM_LLVM_MAJOR='+str(llvm['major']), ROOT/'tests/install/diagnostics/llvm-direct.c', llvm['library']['path'], '-o', build/'llvm-oracle'], runtime/'oracle-build', env)
	undefined, _ = run(['nm', '-u', native], runtime/'imports', env)
	names = sorted(set(re.findall(rb'\b(LLVM[A-Za-z0-9_]+)(?:@[^\s]+)?\s*$', undefined, re.M)))
	require(b'LLVMContextCreate' in names, 'missing LLVM boundary')
	run([*common, build/'doc-guard.o', *(['-Wl,--defsym=__real_LLVMGetInstructionOpcode=astrac_doc_backend_unavailable'] if compat else []), *['-Wl,--defsym='+n.decode()+'=astrac_doc_backend_unavailable' for n in names], '-o', doc], runtime/'doc-link', env)
	run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', ROOT/'compiler/driver/doc-launch.c', '-o', private/'astrac'], runtime/'dispatcher', env)
	for path in [native, doc, private/'astrac']:
		run(['strip', '--strip-debug', path], runtime/('strip-'+path.name), env)
	material['needed'] = audit_elf(native, llvm, runtime, env)
	doc_deps, _ = run(['ldd', doc], runtime/'doc-dependencies', env)
	require(b'LLVM' not in doc_deps, 'doc isolation broken')
	bin_dir = stage/'usr/bin'
	bin_dir.mkdir()
	shutil.copyfile(ROOT/'tools/ci/launch.py', bin_dir/'astrac')
	(bin_dir/'astrac').chmod(0o755)
	share = stage/'usr/share/astra'
	share.mkdir(parents=True)
	(share/'install').mkdir()
	for path in (ROOT/'tests/install').iterdir():
		if path.suffix in ('.astra', '.c') or path.name == 'smoke.py':
			shutil.copyfile(path, share/'install'/path.name)
			# Public tutorial sources remove dependence on historic developer objects.
	kit = share/'tutorial'
	shutil.copytree(ROOT/'lib/astra', kit/'lib/astra', ignore=shutil.ignore_patterns('__pycache__', 'meson.build'))
	shutil.copytree(ROOT/'lib/runtime/platform', kit/'lib/runtime/platform', ignore=shutil.ignore_patterns('meson.build'))
	fixtures = json.loads((ROOT/'tests/books/examples.json').read_text())
	kit_sources = {row['path'] for row in fixtures['files']}
	for case in fixtures['cases']:
		kit_sources.update(case.get('data', []))
		kit_sources.update(row['data'] for row in case.get('extra_runs', []))
	kit_sources.update(['tests/books/examples.json', 'tests/books/tutorial.py', 'tests/books/tutorial.json', 'tools/docs/render.py', 'tools/docs/api.css', 'docs/chapters.json'])
	for name in sorted(kit_sources):
		require(not Path(name).is_absolute() and '..' not in Path(name).parts and name in handoff['package_sources'], 'tutorial input outside authenticated source closure')
		target = kit/name
		target.parent.mkdir(parents=True, exist_ok=True)
		shutil.copyfile(ROOT/name, target)
	shutil.copytree(ROOT/'docs/guide', kit/'docs/guide')
	api = {}
	for name, sources in {'library':['lib/astra/base/order.astra'], 'compiler-source':['compiler/source/source.astra', *sorted(n for n in handoff['sources'] if n.startswith('lib/astra/') and n.endswith('.astra'))]}.items():
		api[name] = build/(name+'.json')
		run([doc, 'doc', '--output', api[name], *sources], runtime/('api-'+name), env, cwd=ROOT, timeout=600)
		require(json.loads(api[name].read_text())['format'] == 'astra-api-docs/1', 'unrecognized API format')
	sys.path.insert(0, str(ROOT/'tools/docs'))
	import books
	pages, book_receipt = books.build(api['library'], api['compiler-source'])
	require(pages == books.build(api['library'], api['compiler-source'])[0], 'non-deterministic books')
	for name, data in pages.items():
		target = share/'books'/name
		target.parent.mkdir(parents=True, exist_ok=True)
		target.write_bytes(data)
	write(runtime/'books.json', book_receipt)
	licenses = stage/'usr/share/licenses/astrac'
	licenses.mkdir(parents=True)
	shutil.copyfile(ROOT/'LICENSE.txt', licenses/'LICENSE.txt')
	(licenses/'SYSTEM-LLVM.txt').write_text('Dynamically linked distribution LLVM '+llvm['version']+'.\nLLVM is not bundled. See the installed '+llvm['runtime_package']+' package for its licenses and sources.\nhttps://llvm.org/LICENSE.txt\n')
	if a.kind == 'deb':
		copyright_path = stage/'usr/share/doc/astrac/copyright'
		copyright_path.parent.mkdir(parents=True)
		copyright_path.write_bytes((licenses/'LICENSE.txt').read_bytes()+(licenses/'SYSTEM-LLVM.txt').read_bytes())
	write(private/'INSTALL.json', dict(format='astra-installation/1', version='0.0.3-dev28c1', LLVM=llvm['version'], system_llvm=llvm, files={str(path.relative_to(private)):dict(bytes=path.stat().st_size, sha256=sha(path)) for path in private.rglob('*') if path.is_file()}, source_commit=handoff['source_commit'], handoff_sha256=sha(a.handoff), qualification='DEVELOPMENT_ARTIFACT_REQUIRES_INSTALL_AND_REGRESSION_RECEIPTS'))
	write(share/'PROVENANCE.json', material)
	if a.development:
		(share/'DEV-UNQUALIFIED.txt').write_text('DEVELOPMENT_UNQUALIFIED / UNSAFE_OR_UNQUALIFIED_DEVELOPMENT\nOriginal official LLVM 23.1.4: strict unsuppressed memory NOT_PASS.\nNo diagnostic InstCombine replacement is included or approved.\nSingle compiler generation; full convergence and independent C0 qualification remain required for release.\nUnsigned development package. No public release, Windows qualification or release approval.\nPackage source: '+handoff['package_commit']+'\nCompiler source: '+handoff['source_commit']+'\n')
	for path in stage.rglob('*'):
		if path.is_dir():
			path.chmod(0o755)
		elif path.is_file() and path not in (bin_dir/'astrac', private/'astrac', native, doc):
			path.chmod(0o644)
	for path in stage.rglob('*'):
		if path.is_file():
			require(b'/home/pmjobin' not in path.read_bytes(), 'developer home path in payload: '+str(path.relative_to(stage)))
	audit_payload(stage)
	return stage


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('object', 'handoff', 'build', 'runtime'):
		p.add_argument('--'+key.replace('_', '-'), type=Path, required=True)
	p.add_argument('--system-llvm', action='store_true', required=True, help='Linux products require distribution-managed LLVM')
	p.add_argument('--mode', choices=('O0', 'O2'), default='O2')
	p.add_argument('--kind', choices=('deb', 'rpm'), required=True)
	p.add_argument('--development', action='store_true', help='Explicit unqualified preview with commit-specific package metadata')
	a = p.parse_args()
	handoff = json.loads(a.handoff.read_text())
	current = subprocess.check_output(['git', '-c', 'safe.directory='+str(ROOT), 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
	require(handoff['package_commit'] == current, 'wrong package source commit')
	require(a.development, 'Linux products retain devunqualified until separately qualified')
	suffix = 'devunqualified.'+handoff['package_commit'][:12] if a.development else 'dev28c1'
	deb_version = '0.0.3~'+suffix+'-1'
	rpm_release = '0.'+suffix+'.1'
	if a.development:
		os_release = dict(line.split('=', 1) for line in Path('/etc/os-release').read_text().splitlines() if '=' in line)
		require(os_release['ID'].strip('"') == ('ubuntu' if a.kind == 'deb' else 'fedora') and os_release['VERSION_ID'].strip('"') == ('26.04' if a.kind == 'deb' else '45'), 'wrong development package userland')
	require(handoff['format'] == 'astra-native-handoff/1' and handoff['status'] == 'AUTHENTICATED_GENERATION_INPUT', 'untrusted generation handoff')
	require(sha(a.object) == handoff['products'][a.mode]['object_sha256'], 'native object mismatch')
	for name, digest in handoff['sources'].items():
		require(sha(ROOT/name) == digest, 'packaging source differs from generation: '+name)
	for name, digest in handoff['package_sources'].items():
		require(sha(ROOT/name) == digest, 'packaging input differs from frozen handoff: '+name)
	build, runtime = external(a.build), external(a.runtime)
	env = clean_environment()
	env['SOURCE_DATE_EPOCH'] = '1794873600'
	llvm = discover(a.kind, runtime, env)
	stage = build_payload(a, handoff, build, runtime, env, llvm)
	private = stage/'usr/lib/astra'
	native, doc = private/'astrac.native', private/'astrac.doc'
	if a.kind == 'deb':
		payload_files = sorted(path for path in stage.rglob('*') if path.is_file())
		installed_size = sum((path.stat().st_size+1023)//1024 for path in payload_files)
		control = stage/'DEBIAN'
		control.mkdir()
		dependencies = 'libc6 (>= 2.39), libstdc++6, libgcc-s1, libxml2, libzstd1, zlib1g'
		if a.system_llvm:
			probe = build/'shlibdeps'
			(probe/'debian').mkdir(parents=True)
			(probe/'debian/control').write_text('Source: astrac\n\nPackage: astrac\nArchitecture: amd64\nDescription: dependency audit\n')
			out, _ = run(['dpkg-shlibdeps', '-O', '-e'+str(native), '-e'+str(doc), '-e'+str(private/'astrac')], runtime/'shlibdeps', env, cwd=probe)
			require(out.startswith(b'shlibs:Depends=') and len(out.splitlines()) == 1, 'ambiguous native dependency metadata')
			dependencies = out.decode().strip().split('=', 1)[1]
		require('libllvm22' in dependencies, 'missing system LLVM runtime dependency')
		(control/'control').write_text('Package: astrac\nVersion: '+deb_version+'\nArchitecture: amd64\nBreaks: astra-development\nReplaces: astra-development\nProvides: astra-development\nMaintainer: Astra contributors <noreply@localhost>\nSection: devel\nPriority: optional\nDepends: '+dependencies+', python3 (>= 3.11), gcc, libc6-dev, binutils\nDescription: Astra native development compiler with distribution-managed LLVM\n '+('DEVELOPMENT_UNQUALIFIED. Original LLVM strict memory NOT_PASS.\n ' if a.development else '')+'Unsigned engineering artifact. No public release qualification.\n')
		with (control/'control').open('a') as stream:
			stream.write('Installed-Size: '+str(installed_size)+'\n')
		(control/'md5sums').write_text(''.join(hashlib.md5(path.read_bytes(), usedforsecurity=False).hexdigest()+'  '+str(path.relative_to(stage))+'\n' for path in payload_files))
		artifact = build/('astrac_'+deb_version+'_amd64.deb')
		run(['dpkg-deb', '--root-owner-group', '--build', stage, artifact], runtime/'package', env, timeout=600)
		run(['dpkg-deb', '--info', artifact], runtime/'metadata', env)
		run(['dpkg-deb', '--contents', artifact], runtime/'contents', env)
	else:
		top = build/'rpm'
		for name in ('BUILD', 'BUILDROOT', 'RPMS', 'SOURCES', 'SPECS', 'SRPMS'):
			(top/name).mkdir(parents=True)
		spec = top/'SPECS/astra.spec'
		spec.write_text('%global debug_package %{nil}\n%global __os_install_post %{nil}\nName: astrac\nObsoletes: astra-development < 0.0.4\nProvides: astra-development = %{version}-%{release}\nBuildRequires: llvm-devel >= 23, gcc\nVersion: 0.0.3\nRelease: 0.dev28c1.1\nSummary: Astra native development compiler\nLicense: Apache-2.0 WITH LLVM-exception\nBuildArch: x86_64\nRequires: llvm-libs >= 23, python3 >= 3.11, gcc, glibc-devel, binutils\n%description\nUnsigned engineering artifact with system LLVM.\n%install\nmkdir -p "%{buildroot}"\ncp -a '+shlex.quote(str(stage))+'/. "%{buildroot}/"\n%files\n/usr/bin/astrac\n/usr/lib/astra\n/usr/share/astra\n/usr/share/licenses/astrac\n')
		if a.development:
			spec.write_text(spec.read_text().replace('Release: 0.dev28c1.1', 'Release: '+rpm_release).replace('Unsigned engineering artifact with system LLVM.', 'DEVELOPMENT_UNQUALIFIED. Original LLVM 23.1.4 strict memory NOT_PASS. Unsigned; no release qualification.'))
		run(['rpmbuild', '-bb', '--define', '_topdir '+str(top), '--define', '_buildhost astra-build.invalid', '--define', 'use_source_date_epoch_as_buildtime 1', '--define', 'clamp_mtime_to_source_date_epoch 1', spec], runtime/'package', env, timeout=600)
		artifacts = list((top/'RPMS').rglob('*.rpm'))
		require(len(artifacts) == 1, 'ambiguous RPM output')
		artifact = build/artifacts[0].name
		shutil.copyfile(artifacts[0], artifact)
		run(['rpm', '-qp', '--requires', artifact], runtime/'metadata', env)
		run(['rpm', '-qpl', artifact], runtime/'contents', env)
	audit_payload(stage)
	write(runtime/'result.json', dict(status='PACKAGE_BUILT_NOT_INSTALLED_QUALIFIED', artifact=identify(artifact), handoff_sha256=sha(a.handoff), source_commit=handoff['source_commit'], payload={str(path.relative_to(stage)):dict(bytes=path.stat().st_size, sha256=sha(path), mode=oct(path.stat().st_mode & 0o777)) for path in stage.rglob('*') if path.is_file()}, build_identity_sha256=sha(runtime/'docs-build-identity.json'), os_release=Path('/etc/os-release').read_text()))
	print(artifact)


if __name__ == '__main__':
	main()
