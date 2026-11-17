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
from common import ROOT, clean_environment, external, identify, require, run, sha, verify, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('object', 'handoff', 'llvm', 'library', 'library_receipt', 'build', 'runtime'):
		p.add_argument('--'+key.replace('_', '-'), type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), default='O2')
	p.add_argument('--kind', choices=('deb', 'rpm'), required=True)
	a = p.parse_args()
	handoff = json.loads(a.handoff.read_text())
	require(handoff['format'] == 'astra-native-handoff/1' and handoff['status'] == 'AUTHENTICATED_GENERATION_INPUT', 'untrusted generation handoff')
	require(sha(a.object) == handoff['products'][a.mode]['object_sha256'], 'native object mismatch')
	for name, digest in handoff['sources'].items():
		require(sha(ROOT/name) == digest, 'packaging source differs from generation: '+name)
	for name, digest in handoff['package_sources'].items():
		require(sha(ROOT/name) == digest, 'packaging input differs from frozen handoff: '+name)
	lock = json.loads((ROOT/'tools/ci/llvm-linux.json').read_text())
	for name, pin in lock['files'].items():
		verify(a.llvm/name, pin)
	library_receipt = json.loads(a.library_receipt.read_text())
	require(library_receipt['status'] == 'LLVM_DYLIB_BUILT_NOT_QUALIFIED' and library_receipt['archive_sha256'] == lock['archive']['sha256'], 'untrusted LLVM library receipt')
	require(all(lock['files']['lib/'+Path(name).name]['sha256'] == digest for name, digest in library_receipt['inputs'].items()), 'LLVM link input mismatch')
	verify(a.library, library_receipt['library'])
	build, runtime = external(a.build), external(a.runtime)
	env = clean_environment()
	env['SOURCE_DATE_EPOCH'] = '1794873600'
	config = a.llvm/'bin/llvm-config'
	require(subprocess.check_output([config, '--version'], env=env).strip() == b'23.1.4', 'wrong LLVM toolchain')
	stage = build/'payload'
	private = stage/'usr/lib/astra'
	private.mkdir(parents=True)
	(private/'llvm').mkdir()
	shutil.copyfile(a.library, private/'llvm/libLLVM.so.23.1')
	cc = Path(shutil.which('cc')).resolve()
	material = dict(format='astra-package-build/1', compiler_mode=a.mode, compiler_object_sha256=sha(a.object), compiler_source_commit=handoff['source_commit'], package_source_commit=handoff['package_commit'], package_source_tree=handoff['package_tree'], source_inputs=handoff['sources'], package_inputs=handoff['package_sources'], handoff_sha256=sha(a.handoff), LLVM='23.1.4', llvm_library_sha256=sha(a.library), llvm_provenance_sha256=sha(a.library_receipt), cc=identify(cc), recipe_sha256=sha(__file__), package_kind=a.kind, unsigned=True)
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
	common = [cc, '-no-pie', a.object, *objects]
	native, doc = private/'astrac.native', private/'astrac.doc'
	run([*common, a.library, '-Wl,-rpath,$ORIGIN/llvm', '-o', native], runtime/'native-link', env)
	undefined, _ = run(['nm', '-u', native], runtime/'imports', env)
	names = sorted(set(re.findall(rb'\b(LLVM[A-Za-z0-9_]+)(?:@[^\s]+)?\s*$', undefined, re.M)))
	require(b'LLVMContextCreate' in names, 'missing LLVM boundary')
	run([*common, build/'doc-guard.o', *['-Wl,--defsym='+n.decode()+'=astrac_doc_backend_unavailable' for n in names], '-o', doc], runtime/'doc-link', env)
	run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', ROOT/'compiler/driver/doc-launch.c', '-o', private/'astrac'], runtime/'dispatcher', env)
	for path in [native, doc, private/'astrac']:
		run(['strip', '--strip-debug', path], runtime/('strip-'+path.name), env)
	deps, _ = run(['ldd', native], runtime/'native-dependencies', env)
	require(b'not found' not in deps and b'libLLVM.so.23.1' in deps, 'incomplete runtime closure')
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
	licenses = stage/'usr/share/licenses/astra-development'
	licenses.mkdir(parents=True)
	shutil.copyfile(ROOT/'LICENSE.txt', licenses/'LICENSE.txt')
	shutil.copytree(ROOT/'tools/release/licenses/llvm-23.1.4', licenses/'llvm-23.1.4')
	write(private/'INSTALL.json', dict(format='astra-installation/1', version='0.0.3-dev28c1', LLVM='23.1.4', files={str(path.relative_to(private)):dict(bytes=path.stat().st_size, sha256=sha(path)) for path in private.rglob('*') if path.is_file()}, source_commit=handoff['source_commit'], handoff_sha256=sha(a.handoff), qualification='DEVELOPMENT_ARTIFACT_REQUIRES_INSTALL_AND_REGRESSION_RECEIPTS'))
	write(share/'PROVENANCE.json', material)
	for path in stage.rglob('*'):
		if path.is_dir():
			path.chmod(0o755)
		elif path.is_file() and path not in (bin_dir/'astrac', private/'astrac', native, doc):
			path.chmod(0o644)
	for path in stage.rglob('*'):
		if path.is_file():
			require(b'/home/pmjobin' not in path.read_bytes(), 'developer home path in payload: '+str(path.relative_to(stage)))
	if a.kind == 'deb':
		payload_files = sorted(path for path in stage.rglob('*') if path.is_file())
		installed_size = sum((path.stat().st_size+1023)//1024 for path in payload_files)
		control = stage/'DEBIAN'
		control.mkdir()
		(control/'control').write_text('Package: astra-development\nVersion: 0.0.3~dev28c1-1\nArchitecture: amd64\nMaintainer: Astra contributors <noreply@localhost>\nSection: devel\nPriority: optional\nDepends: libc6 (>= 2.39), libstdc++6, libgcc-s1, libxml2, libzstd1, zlib1g, python3 (>= 3.11), gcc, libc6-dev, binutils\nDescription: Astra native development compiler with pinned LLVM 23.1.4\n Unsigned engineering artifact. No public release qualification.\n')
		with (control/'control').open('a') as stream:
			stream.write('Installed-Size: '+str(installed_size)+'\n')
		(control/'md5sums').write_text(''.join(hashlib.md5(path.read_bytes(), usedforsecurity=False).hexdigest()+'  '+str(path.relative_to(stage))+'\n' for path in payload_files))
		artifact = build/'astra-development_0.0.3~dev28c1-1_amd64.deb'
		run(['dpkg-deb', '--root-owner-group', '--build', stage, artifact], runtime/'package', env, timeout=600)
		run(['dpkg-deb', '--info', artifact], runtime/'metadata', env)
		run(['dpkg-deb', '--contents', artifact], runtime/'contents', env)
	else:
		top = build/'rpm'
		for name in ('BUILD', 'BUILDROOT', 'RPMS', 'SOURCES', 'SPECS', 'SRPMS'):
			(top/name).mkdir(parents=True)
		spec = top/'SPECS/astra.spec'
		spec.write_text('%global debug_package %{nil}\n%global __provides_exclude ^libLLVM.*\n%global __requires_exclude ^libLLVM.*\n%global __os_install_post %{nil}\nName: astra-development\nVersion: 0.0.3\nRelease: 0.dev28c1.1\nSummary: Astra native development compiler\nLicense: Apache-2.0 WITH LLVM-exception AND MIT\nBuildArch: x86_64\nRequires: python3 >= 3.11, gcc, glibc-devel, binutils\n%description\nUnsigned engineering artifact with private LLVM 23.1.4.\n%install\nmkdir -p "%{buildroot}"\ncp -a '+shlex.quote(str(stage))+'/. "%{buildroot}/"\n%files\n/usr/bin/astrac\n/usr/lib/astra\n/usr/share/astra\n/usr/share/licenses/astra-development\n')
		run(['rpmbuild', '-bb', '--define', '_topdir '+str(top), '--define', '_buildhost astra-build.invalid', '--define', 'use_source_date_epoch_as_buildtime 1', '--define', 'clamp_mtime_to_source_date_epoch 1', spec], runtime/'package', env, timeout=600)
		artifacts = list((top/'RPMS').rglob('*.rpm'))
		require(len(artifacts) == 1, 'ambiguous RPM output')
		artifact = build/artifacts[0].name
		shutil.copyfile(artifacts[0], artifact)
		run(['rpm', '-qp', '--requires', artifact], runtime/'metadata', env)
		run(['rpm', '-qpl', artifact], runtime/'contents', env)
	write(runtime/'result.json', dict(status='PACKAGE_BUILT_NOT_INSTALLED_QUALIFIED', artifact=identify(artifact), handoff_sha256=sha(a.handoff), source_commit=handoff['source_commit'], payload={str(path.relative_to(stage)):dict(bytes=path.stat().st_size, sha256=sha(path), mode=oct(path.stat().st_mode & 0o777)) for path in stage.rglob('*') if path.is_file()}, build_identity_sha256=sha(runtime/'docs-build-identity.json'), os_release=Path('/etc/os-release').read_text()))
	print(artifact)


if __name__ == '__main__':
	main()
