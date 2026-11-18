#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise an actual COPR repository in a fresh Fedora userland; local RPM mode is explicit."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time


def require(condition, message):
	if not condition:
		raise ValueError(message)


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--commit', required=True)
	p.add_argument('--output', type=Path, required=True)
	p.add_argument('--build', type=Path, required=True)
	inputs = p.add_mutually_exclusive_group(required=True)
	inputs.add_argument('--repo', choices=['pmjobin/astra'])
	inputs.add_argument('--local-package', type=Path)
	a = p.parse_args()
	require(re.fullmatch('[0-9a-f]{40}', a.commit), 'full source commit required')
	require(not shutil.which('astrac') and not Path('/usr/lib/astra').exists(), 'Astra already installed')
	require(not Path('/usr/include/llvm-c/Core.h').exists(), 'LLVM development headers present on consumer')
	a.output.mkdir(parents=True)
	a.build.mkdir(parents=True)
	commands = []
	def run(name, argv, expected=0, cwd=None):
		start = time.monotonic()
		result = subprocess.run(list(map(str, argv)), capture_output=True, timeout=1800, cwd=cwd)
		for label, data in [('stdout', result.stdout), ('stderr', result.stderr)]:
			(a.output/(name+'.'+label)).write_bytes(data)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=result.returncode, expected=expected, seconds=time.monotonic()-start, stdout_sha256=sha(a.output/(name+'.stdout')), stderr_sha256=sha(a.output/(name+'.stderr'))))
		(a.output/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		require(result.returncode == expected, name+': unexpected exit')
		return result.stdout
	if a.repo:
		run('copr-enable', ['dnf', '-y', 'copr', 'enable', a.repo])
		run('repository-config', ['cat', '/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:pmjobin:astra.repo'])
	package = str(a.local_package) if a.local_package else 'astrac'
	run('install', ['dnf', '-y', 'install', package])
	private = Path('/usr/lib/astra')
	manifest = json.loads((private/'INSTALL.json').read_text())
	generation = json.loads(Path('/usr/share/astra/SOURCE-BUILD.json').read_text())
	require(generation['commit'] == a.commit and manifest['source_commit'] == a.commit, 'wrong source-built product installed')
	metadata = run('metadata', ['rpm', '-qi', 'astrac'])
	run('requires', ['rpm', '-q', '--requires', 'astrac'])
	listing = run('payload', ['rpm', '-ql', 'astrac']).decode().splitlines()
	require(not any('libLLVM' in n or n.endswith(('.o', '.a', '.elf')) for n in listing), 'prebuilt/LLVM payload found')
	require(b'devunqualified' in metadata, 'development marking absent')
	for name, pin in manifest['files'].items():
		require(sha(private/name) == pin['sha256'], 'installed image differs from source-built image')
	run('rpm-integrity', ['rpm', '-V', 'astrac'])
	run('loader', ['ldd', private/'astrac.native'])
	elf = run('elf', ['readelf', '-l', '-d', private/'astrac.native'])
	require(b'(RPATH)' not in elf and b'(RUNPATH)' not in elf, 'private library search path')
	run('llvm-owner', ['rpm', '-qf', manifest['system_llvm']['library']['path']])
	run('llvm-removal-refusal', ['rpm', '-e', '--test', 'llvm-libs'], expected=1)
	run('smoke', ['python3', '-B', '/usr/share/astra/install/smoke.py', '--clean-host', '--output', a.output/'smoke', '--build', a.build/'smoke'])
	run('guide', ['python3', '-B', '/usr/share/astra/tutorial/tests/books/tutorial.py', '--runtime', a.output/'guide'])
	run('strict-memory', ['python3', '-B', '/qa/development_memory.py', '--output', a.output/'memory', '--build', a.build/'memory'])
	# Documentation remains executable with the system LLVM library unavailable.
	library = Path(manifest['system_llvm']['library']['path'])
	held = library.with_name(library.name+'.held')
	library.rename(held)
	try:
		run('missing-llvm', ['astrac', '--version'], expected=127)
		run('doc-without-llvm', ['astrac', 'doc', '--output', a.build/'no-llvm.json', 'api.astra'], cwd='/usr/share/astra/install')
	finally:
		held.rename(library)
	with (private/'astrac.native').open('ab') as stream:
		stream.write(b'REINSTALL_CONTROL')
	run('tampered-native', ['astrac', '--version'], expected=127)
	run('reinstall', ['dnf', '-y', 'reinstall', package])
	run('after-reinstall', ['astrac', '--version'])
	if a.repo:
		run('dnf-update', ['dnf', '-y', 'upgrade', 'astrac'])
		run('repository-identity', ['dnf', 'repoquery', '--installed', '--qf', '%{name} %{evr} %{from_repo}', 'astrac'])
		run('signing-keys', ['rpm', '-qi', 'gpg-pubkey'])
		run('download', ['dnf', 'download', '--destdir', a.build/'download', 'astrac'])
		artifacts = list((a.build/'download').glob('astrac-*.rpm'))
		require(len(artifacts) == 1, 'ambiguous repository RPM')
		run('signature', ['rpmkeys', '--checksig', '--verbose', artifacts[0]])
		(a.output/'repository-rpm.json').write_text(json.dumps(dict(name=artifacts[0].name, bytes=artifacts[0].stat().st_size, sha256=sha(artifacts[0])), indent=2)+'\n')
	run('uninstall', ['dnf', '-y', 'remove', '--setopt=clean_requirements_on_remove=False', 'astrac'])
	require(not shutil.which('astrac') and not private.exists() and not Path('/usr/share/astra').exists(), 'uninstall left payload')
	run('fresh-reinstall', ['dnf', '-y', 'install', package])
	run('final-version', ['astrac', '--version'])
	result = dict(status='COPR_REPOSITORY_INSTALL_PASS' if a.repo else 'LOCAL_SOURCE_RPM_INSTALL_PASS', source_commit=a.commit, native_sha256=manifest['files']['astrac.native']['sha256'], qualification='DEVELOPMENT_UNQUALIFIED', strict_memory=json.loads((a.output/'memory/result.json').read_text()), repository=a.repo, scope='Fresh container userland and real package manager; shared host kernel. Same-version update/reinstall; cross-version migration is separately qualified.')
	(a.output/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(result['status'])


if __name__ == '__main__':
	main()
