#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run as container root on a fresh distro; only package and QA inputs are mounted."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess
import time


def require(condition, message):
	if not condition:
		raise ValueError(message)


def sha(path):
	with Path(path).open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--package', type=Path, required=True)
	p.add_argument('--sha256', required=True)
	p.add_argument('--kind', choices=('deb', 'rpm'), required=True)
	p.add_argument('--output', type=Path, required=True)
	p.add_argument('--memory', action='store_true')
	a = p.parse_args()
	a.output.mkdir(parents=True, exist_ok=False)
	require(sha(a.package) == a.sha256, 'installer bytes differ from builder output')
	require(shutil.which('astrac') is None and not Path('/usr/lib/astra').exists(), 'host already has Astra')
	commands = []
	def run(name, argv, expected=0, contains=None, cwd=None):
		start = time.monotonic()
		result = subprocess.run(list(map(str, argv)), capture_output=True, timeout=900, cwd=cwd)
		for label, data in (('stdout', result.stdout), ('stderr', result.stderr)):
			(a.output/(name+'.'+label)).write_bytes(data)
		commands.append(dict(name=name, argv=list(map(str, argv)), cwd=str(cwd) if cwd else None, exit=result.returncode, expected=expected, seconds=time.monotonic()-start, stdout_sha256=sha(a.output/(name+'.stdout')), stderr_sha256=sha(a.output/(name+'.stderr'))))
		(a.output/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		require(result.returncode == expected, name+': wrong exit')
		if contains:
			require(contains in result.stdout+result.stderr, name+': expected message missing')
		return result.stdout
	def guide(name, chapter):
		body = Path('/qa/'+chapter).read_text()
		matches = re.findall(r'^```console '+name+'='+a.kind+r'\n(.*?)^```$', body, re.M|re.S)
		require(len(matches) == 1, 'missing or ambiguous published installation block')
		(a.output/(name+'.source.sh')).write_text(matches[0])
		return run(name, ['/bin/sh', '-eu', '-c', matches[0]], cwd=a.package.parent)
	output = guide('install', 'getting-started.md')
	require(a.sha256.encode() in output, 'published checksum command did not report expected artifact')
	if a.kind == 'deb':
		run('metadata', ['dpkg-query', '-W', '-f', '${Package} ${Version} ${Architecture}\n', 'astra-development'], contains=b'0.0.3~dev28c1-1 amd64')
		if a.memory:
			run('memory-tool', ['apt-get', 'install', '-y', '--no-install-recommends', 'valgrind'])
	else:
		run('metadata', ['rpm', '-q', '--qf', '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n', 'astra-development'], contains=b'0.0.3-0.dev28c1.1 x86_64')
		if a.memory:
			run('memory-tool', ['dnf', 'install', '-y', 'valgrind'])
	private = Path('/usr/lib/astra')
	for name in ('getting-started.md', 'tooling.md'):
		require(sha(Path('/qa')/name) == sha(Path('/usr/share/astra/tutorial/docs/guide')/name), 'installed Guide differs from replayed installation recipe')
	run('installed-smoke', ['python3', '-B', '/usr/share/astra/install/smoke.py', '--clean-host', '--output', a.output/'smoke', '--build', '/build/smoke', *(['--memory'] if a.memory else [])], contains=b'INSTALLED_NATIVE_SMOKE_PASS')
	run('installed-guide', ['python3', '-B', '/usr/share/astra/tutorial/tests/books/tutorial.py', '--runtime', a.output/'guide'], contains=b'installed Guide shell blocks passed')
	user = pwd.getpwnam('nobody')
	require(user.pw_uid != 0, 'ordinary-user acceptance must not run as root')
	user_build = Path('/build/ordinary-user')
	user_build.mkdir()
	os.chown(user_build, user.pw_uid, user.pw_gid)
	run('ordinary-user-native', ['sudo', '-u', 'nobody', '/bin/sh', '-eu', '-c', 'astrac --version; astrac -c -O2 -o main.o /usr/share/astra/install/main.astra; cc -no-pie main.o -o main; ./main'], cwd=user_build, contains=b'0.0.3-dev28c1')
	library = private/'llvm/libLLVM.so.23.1'
	held = library.with_suffix('.held')
	library.rename(held)
	try:
		run('missing-llvm-refusal', ['astrac', '--version'], expected=127, contains=b'installation unavailable')
		run('doc-without-llvm', ['astrac', 'doc', '--output', '/build/no-llvm.json', '/usr/share/astra/install/api.astra'])
	finally:
		held.rename(library)
	for name in ('llvm/libLLVM.so.23.1', 'astrac.native'):
		path = private/name
		original = path.stat().st_size
		with path.open('ab') as stream:
			stream.write(b'CORRUPTION_CONTROL')
		try:
			run('tampered-'+Path(name).name, ['astrac', '--version'], expected=127, contains=b'identity mismatch')
		finally:
			with path.open('r+b') as stream:
				stream.truncate(original)
				# Same-version reinstall checks package-manager replacement without changing
				# the native source/product identity. Cross-version upgrades remain separate.
	guide('reinstall', 'tooling.md')
	run('after-reinstall', ['astrac', '--version'], contains=b'0.0.3-dev28c1')
	guide('uninstall', 'tooling.md')
	require(shutil.which('astrac') is None and not private.exists(), 'uninstall left compiler files')
	require(shutil.which('cc') is not None and shutil.which('python3') is not None, 'uninstall removed external prerequisites')
	result = dict(status='CLEAN_INSTALL_SMOKE_REINSTALL_UNINSTALL_PASS', kind=a.kind, package_sha256=a.sha256, os_release=Path('/etc/os-release').read_text(), command_receipts_sha256=sha(a.output/'commands.json'), smoke_sha256=sha(a.output/'smoke/result.json'), guide_sha256=sha(a.output/'guide/result.json'), negative_controls=['missing LLVM', 'tampered LLVM', 'tampered compiler', 'doc without LLVM'], upgrade='Same-version reinstall tested; cross-version upgrade not claimed', signed=False)
	(a.output/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(result['status'])


if __name__ == '__main__':
	main()
