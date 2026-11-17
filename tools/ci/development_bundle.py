#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bundle only actual installed development packages; verify every ZIP member."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

from common import ROOT, external, identify, require, sha, verify, write


def verify_bundle(path):
	with zipfile.ZipFile(path) as packed:
		names = packed.namelist()
		require(len(names) == len(set(names)) and packed.testzip() is None, 'corrupt or duplicate bundle member')
		index = json.loads(packed.read('MANIFEST.json'))
		require(index['qualification'] == 'DEVELOPMENT_UNQUALIFIED', 'missing preview status')
		require(set(names) == set(index['files']) | {'MANIFEST.json'}, 'bundle membership mismatch')
		for name, row in index['files'].items():
			require(not Path(name).is_absolute() and '..' not in Path(name).parts and '\\' not in name, 'unsafe bundle path')
			data = packed.read(name)
			require(len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256'], 'changed bundle member: '+name)
		packages = json.loads(packed.read('PACKAGES.json'))
		for row in packages.values():
			require(index['files'][row['name']]['sha256'] == row['sha256'], 'package digest mismatch')
		return packages


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--verify', type=Path)
	p.add_argument('--approval', type=Path)
	p.add_argument('--github-output', type=Path)
	for key in ('deb', 'rpm', 'deb_install', 'rpm_install', 'handoff', 'deb_receipt', 'rpm_receipt', 'licenses', 'evidence', 'output'):
		p.add_argument('--'+key.replace('_', '-'), type=Path)
	a = p.parse_args()
	if a.verify:
		print(json.dumps(verify_bundle(a.verify), indent=2))
		if a.approval or a.github_output:
			require(a.approval and a.github_output, 'approval path and output must be paired')
			approved = False
			if a.approval.is_file():
				request = json.loads(a.approval.read_text())
				if request.get('public_installer_artifacts') is True:
					require(request['scope'] == 'hosted_rebuild_with_original_LLVM_memory_NOT_PASS' and request['owner'] == 'pmjobin', 'unrecognized owner disposition')
					reviewed = request['reviewed_commit']
					require(len(reviewed) == 40 and all(c in '0123456789abcdef' for c in reviewed), 'invalid reviewed source identity')
					require(subprocess.run(['git', 'merge-base', '--is-ancestor', reviewed, 'HEAD'], cwd=ROOT).returncode == 0, 'reviewed commit is not an ancestor')
					changed = subprocess.check_output(['git', 'diff', '--name-only', reviewed, 'HEAD'], cwd=ROOT, text=True).splitlines()
					require(set(changed) <= {'.github/development-build-request.json'}, 'source changed since owner review')
					require(not subprocess.check_output(['git', 'diff', 'HEAD'], cwd=ROOT), 'uncommitted publication inputs')
					for kind in ('deb', 'rpm'):
						row = request['reviewed_local_packages'][kind]
						require(row['qualification'] == 'DEVELOPMENT_UNQUALIFIED' and row['strict_memory'] == 'NOT_PASS' and row['bytes'] > 0 and len(row['sha256']) == 64 and all(c in '0123456789abcdef' for c in row['sha256']), 'incomplete reviewed candidate identity')
					approved = True
			with a.github_output.open('a') as stream:
				stream.write('approved='+str(approved).lower()+'\n')
		return
	require(all(getattr(a, key) for key in ('deb', 'rpm', 'deb_install', 'rpm_install', 'handoff', 'deb_receipt', 'rpm_receipt', 'licenses', 'evidence', 'output')), 'complete package evidence required')
	out = external(a.output)
	packages = {}
	for kind in ('deb', 'rpm'):
		package = getattr(a, kind)
		install = getattr(a, kind+'_install')
		receipt_path = getattr(a, kind+'_receipt')
		built = json.loads(receipt_path.read_text())
		verify(package, built['artifact'])
		result = json.loads((install/'result.json').read_text())
		lifecycle = json.loads((install/'lifecycle/result.json').read_text())
		require(result['status'] == lifecycle['status'] == 'CLEAN_INSTALL_SMOKE_REINSTALL_UNINSTALL_PASS' and result['package_sha256'] == lifecycle['package_sha256'] == sha(package), 'package lacks actual clean install receipt')
		require(lifecycle['qualification'] == 'DEVELOPMENT_UNQUALIFIED' and lifecycle['original_LLVM_strict_memory'] == 'NOT_PASS', 'qualification disclosure missing')
		require(result['lifecycle_sha256'] == sha(install/'lifecycle/result.json') and lifecycle['memory_receipt_sha256'] == sha(install/'lifecycle/memory/result.json'), 'altered installation evidence')
		shutil.copyfile(package, out/package.name)
		packages[kind] = dict(name=package.name, bytes=package.stat().st_size, sha256=sha(package), status=['BUILT', 'INSTALL_SMOKE_PASS', 'DEVELOPMENT_UNQUALIFIED'], strict_memory=lifecycle['strict_memory'], original_LLVM_strict_memory='NOT_PASS', source_commit=built['source_commit'], install_image=result['image'], install_receipt_sha256=sha(install/'result.json'), builder_receipt_sha256=sha(receipt_path))
	write(out/'PACKAGES.json', packages)
	shutil.copyfile(a.handoff, out/'GENERATION.json')
	shutil.copytree(a.licenses, out/'licenses')
	for path in a.evidence.rglob('*'):
		require(not path.is_symlink(), 'symlink evidence is not portable')
		if path.is_file():
			with path.open('rb') as stream:
				prefix = stream.read(8)
				require(not prefix.startswith((b'\x7fELF', b'MZ', b'!<arch>\n')) and not path.name.endswith(('.elf', '.o', '.so', '.deb', '.rpm', '.zip')), 'unexpected binary in evidence')
	shutil.copytree(a.evidence, out/'evidence', ignore=shutil.ignore_patterns('__pycache__', '*.partial'))
	(out/'SHA256SUMS').write_text(''.join(row['sha256']+'  '+row['name']+'\n' for row in packages.values()))
	(out/'README.txt').write_text('DEVELOPMENT_UNQUALIFIED / UNSAFE_OR_UNQUALIFIED_DEVELOPMENT\n\nOriginal official LLVM 23.1.4 strict unsuppressed memory: NOT_PASS.\nThe diagnostic InstCombine derivative is NOT included or approved.\nThese unsigned, one-generation packages are for experimental development.\nFull independent C0 inputs, three-stage convergence and release qualification remain required. Windows is a separate unfinished native port.\n\nVerify: sha256sum -c SHA256SUMS\nUbuntu 26.04 amd64: sudo apt-get install ./'+packages['deb']['name']+'\nFedora 45 x86_64: sudo dnf install ./'+packages['rpm']['name']+'\nSame-version reinstall: add --reinstall to apt-get install, or use dnf reinstall.\nRemove: sudo apt-get remove astra-development; or sudo dnf remove astra-development.\nCheck: astrac --version; astrac --help; astrac doc --help\nInstalled disclosure: /usr/share/astra/DEV-UNQUALIFIED.txt\nInstalled books: /usr/share/astra/books/\nThe compiler intrinsic version remains 0.0.3-dev28c1; package versions include the package source commit.\n\nFedora reuses the hash-bound Ubuntu compiler object, with distro-native providers and original LLVM relinked on Fedora.\nClean installation tests use separate minimal container userlands sharing the host kernel, not VMs.\nAll observed strict-memory failures are retained separately from functional install acceptance.\nNo public upload permission is implied by this bundle. After separate owner approval: GitHub Actions > Astra Linux development packages > approved run > Artifacts. No GitHub Release or signing.\n')
	files = {str(path.relative_to(out)):dict(bytes=path.stat().st_size, sha256=sha(path)) for path in out.rglob('*') if path.is_file()}
	write(out/'MANIFEST.json', dict(format='astra-development-bundle/1', qualification='DEVELOPMENT_UNQUALIFIED', files=files))
	archive = out.with_suffix('.zip')
	require(not archive.exists(), 'do not overwrite an earlier bundle')
	with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as packed:
		for path in sorted(out.rglob('*')):
			if path.is_file():
				packed.write(path, str(path.relative_to(out)))
	verify_bundle(archive)
	print(json.dumps(dict(bundle=identify(archive), packages=packages), indent=2))


if __name__ == '__main__':
	main()
