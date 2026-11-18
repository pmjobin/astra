#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise a COPR repository or an explicit local RPM in a fresh target userland."""
import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path
import platform
import pwd
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request


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
	p.add_argument('--predecessor', type=Path)
	inputs = p.add_mutually_exclusive_group(required=True)
	inputs.add_argument('--repo', choices=['pmjobin/astra'])
	inputs.add_argument('--local-package', type=Path)
	a = p.parse_args()
	os_release = platform.freedesktop_os_release()
	el9 = os_release['ID'] in ('rhel', 'centos') and os_release['VERSION_ID'].split('.')[0] == '9'
	require(el9 or (os_release['ID'], os_release['VERSION_ID']) == ('fedora', '45'), 'unexpected consumer OS')
	python = '/usr/bin/python3.11' if el9 else '/usr/bin/python3'
	require(sys.executable == python, 'run consumer tests with '+python)
	chroot = {'centos':'centos-stream-9-x86_64', 'rhel':'rhel-9-x86_64', 'fedora':'fedora-45-x86_64'}[os_release['ID']]
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
		allowed = expected if isinstance(expected, tuple) else (expected,)
		require(result.returncode in allowed, name+': unexpected exit')
		return result.stdout
	if a.repo:
		run('copr-enable', ['dnf', '-y', 'copr', 'enable', a.repo, *([chroot] if el9 else [])])
		repofile, = Path('/etc/yum.repos.d').glob('*copr*pmjobin*astra.repo')
		configuration = run('repository-config', ['cat', repofile]).decode()
		parser = configparser.ConfigParser()
		parser.read_string(configuration)
		section = parser[parser.sections()[0]]
		require(section.getboolean('gpgcheck'), 'repository RPM signature checking disabled')
		key_url = section['gpgkey']
		require(key_url.startswith('https://download.copr.fedorainfracloud.org/results/pmjobin/astra/'), 'unexpected signing key origin')
		key = a.output/'copr-public-key.txt'
		key.write_bytes(urllib.request.urlopen(key_url, timeout=60).read())
		run('key-fingerprint', ['gpg', '--show-keys', '--with-colons', key])
		metadata_url = 'https://download.copr.fedorainfracloud.org/results/pmjobin/astra/'+chroot+'/repodata/repomd.xml'
		(a.output/'repomd.xml.txt').write_bytes(urllib.request.urlopen(metadata_url, timeout=60).read())
		try:
			signature = urllib.request.urlopen(metadata_url+'.asc', timeout=60).read()
		except urllib.error.HTTPError as error:
			require(error.code == 404, 'repository metadata signature lookup failed')
			signature = None
		(a.output/'repository-signing.json').write_text(json.dumps(dict(gpgcheck=True, repo_gpgcheck=section.getboolean('repo_gpgcheck', fallback=False), public_key_sha256=sha(key), repomd_sha256=sha(a.output/'repomd.xml.txt'), detached_metadata_signature_present=signature is not None), indent=2)+'\n')
	package = str(a.local_package) if a.local_package else 'astrac'
	run('install', ['dnf', '-y', 'install', package])
	private = Path('/usr/lib/astra')
	manifest = json.loads((private/'INSTALL.json').read_text())
	generation = json.loads(Path('/usr/share/astra/SOURCE-BUILD.json').read_text())
	require(generation['commit'] == a.commit and manifest['source_commit'] == a.commit, 'wrong source-built product installed')
	metadata = run('metadata', ['rpm', '-qi', 'astrac'])
	requires = run('requires', ['rpm', '-q', '--requires', 'astrac']).decode().splitlines()
	llvm_major = 22 if os_release['ID'] == 'rhel' else 23
	require({f'libLLVM.so.{llvm_major}.1()(64bit)', f'libLLVM.so.{llvm_major}.1(LLVM_{llvm_major}.1)(64bit)'} <= set(requires), 'missing versioned LLVM dependency')
	if el9:
		require(manifest['python'] == python and Path('/usr/bin/astrac').read_bytes().splitlines()[0] == b'#!/usr/bin/python3.11 -I', 'wrong installed EL9 interpreter')
		require('python3.11' in requires and 'python3 >= 3.11' not in requires, 'wrong EL9 Python dependency')
		require(run('release', ['rpm', '-q', '--qf', '%{RELEASE}', 'astrac']).endswith(b'.el9'), 'wrong RPM distribution')
		require(run('python-owner', ['rpm', '-qf', '--qf', '%{NAME}', python]) == b'python3.11', 'interpreter is not distribution-owned')
		run('python-removal-refusal', ['rpm', '-e', '--test', 'python3.11'], expected=1)
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
	run('smoke', [python, '-B', '/usr/share/astra/install/smoke.py', '--clean-host', '--output', a.output/'smoke', '--build', a.build/'smoke'])
	run('guide', [python, '-B', '/usr/share/astra/tutorial/tests/books/tutorial.py', '--runtime', a.output/'guide'])
	run('strict-memory', [python, '-B', '/qa/development_memory.py', '--output', a.output/'memory', '--build', a.build/'memory'], expected=(0, 99) if llvm_major == 22 else 0)
	memory = json.loads((a.output/'memory/result.json').read_text())
	user = pwd.getpwnam('nobody')
	ordinary = a.build/'ordinary-user'
	ordinary.mkdir()
	os.chown(ordinary, user.pw_uid, user.pw_gid)
	run('ordinary-user', ['sudo', '-u', 'nobody', '/bin/sh', '-ec', 'test "$(id -u)" -ne 0; test ! -w /usr/lib/astra/astrac.native; astrac --version; for mode in O0 O2; do astrac -c -$mode -o main-$mode.o /usr/share/astra/install/main.astra; cc -no-pie main-$mode.o -o main-$mode; ./main-$mode; done'], cwd=ordinary)
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
		run('repository-identity', ['dnf', 'info', '--installed', 'astrac'] if el9 else ['dnf', 'repoquery', '--installed', '--qf', '%{name} %{evr} %{from_repo}', 'astrac'])
		run('signing-keys', ['rpm', '-q', 'gpg-pubkey'] if el9 else ['rpmkeys', '--list'])
		run('download', ['dnf', 'download', '--destdir', a.build/'download', 'astrac'])
		artifacts = list((a.build/'download').glob('astrac-*.x86_64.rpm'))
		require(len(artifacts) == 1, 'ambiguous repository binary RPM')
		signature = run('signature', ['rpmkeys', '--checksig', '--verbose', artifacts[0]])
		require(b'signature' in signature.lower() and b'NOKEY' not in signature and b'NOT OK' not in signature, 'repository RPM lacks a verified signature')
		(a.output/'repository-rpm.json').write_text(json.dumps(dict(name=artifacts[0].name, bytes=artifacts[0].stat().st_size, sha256=sha(artifacts[0])), indent=2)+'\n')
	if a.predecessor:
		require(sha(a.predecessor) == '35a8a4f73851d2f09fca6b4069178c4efeb15c270795d280191ada188be01d45', 'historical migration input differs')
		run('remove-before-upgrade', ['dnf', '-y', 'remove', '--setopt=clean_requirements_on_remove=False', 'astrac'])
		run('install-historical-control', ['dnf', '-y', 'install', a.predecessor])
		run('upgrade-historical-control', ['dnf', '-y', 'upgrade' if a.repo else 'install', package])
		require(json.loads(Path('/usr/share/astra/SOURCE-BUILD.json').read_text())['commit'] == a.commit, 'upgrade installed wrong source product')
		run('upgraded-version', ['astrac', '--version'])
	run('uninstall', ['dnf', '-y', 'remove', '--setopt=clean_requirements_on_remove=False', 'astrac'])
	require(not shutil.which('astrac') and not private.exists() and not Path('/usr/share/astra').exists(), 'uninstall left payload')
	run('fresh-reinstall', ['dnf', '-y', 'install', package])
	run('final-version', ['astrac', '--version'])
	status = 'COPR_REPOSITORY_INSTALL_PASS' if a.repo else 'LOCAL_SOURCE_RPM_INSTALL_PASS'
	if memory['status'] != 'FOCUSED_STRICT_MEMORY_PASS':
		status = 'PARTIAL'
	result = dict(status=status, source_commit=a.commit, native_sha256=manifest['files']['astrac.native']['sha256'], qualification='DEVELOPMENT_UNQUALIFIED', strict_memory=memory, repository=a.repo, scope='Fresh container userland and real package manager; shared host kernel. Same-version update/reinstall; cross-version migration is separately qualified.')
	(a.output/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(result['status'])
	return 99 if status == 'PARTIAL' else 0


if __name__ == '__main__':
	raise SystemExit(main())
