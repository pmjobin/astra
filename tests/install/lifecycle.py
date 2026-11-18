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


def system_acceptance(a, run, private, provenance):
	llvm = provenance['system_llvm']
	library = Path(llvm['library']['path'])
	listing = run('payload', ['dpkg-query', '-L', 'astrac'] if a.kind == 'deb' else ['rpm', '-ql', 'astrac'])
	for name in listing.decode().splitlines():
		require(not any(part.lower() == 'llvm' or part.lower().startswith('libllvm') for part in Path(name).parts), 'private LLVM payload')
	run('library-owner', ['dpkg-query', '-S', library] if a.kind == 'deb' else ['rpm', '-qf', library])
	elf = run('loader-elf', ['readelf', '-l', '-d', private/'astrac.native'])
	require(b'(RPATH)' not in elf and b'(RUNPATH)' not in elf and llvm['soname'].encode() in elf, 'wrong runtime ELF')
	interpreter = re.search(rb'Requesting program interpreter: (.*?)\]', elf).group(1).decode()
	resolution = run('loader-resolution', [interpreter, '--list', private/'astrac.native'])
	require(any(Path(word.decode()).resolve() == library.resolve() for word in resolution.split() if word.startswith(b'/')), 'loader uses different LLVM')
	dev = subprocess.run(['dpkg-query', '-W', '-f', '${db:Status-Status}', 'llvm-22-dev'] if a.kind == 'deb' else ['rpm', '-q', 'llvm-devel'], capture_output=True)
	require(dev.returncode != 0 or (a.kind == 'deb' and dev.stdout != b'installed'), 'consumer has LLVM development package')
	require(not Path('/usr/include/llvm-c/Core.h').exists() and not Path('/usr/lib/llvm-22/include/llvm-c/Core.h').exists(), 'consumer has LLVM headers')
	run('dependency-removal-refused', ['dpkg', '--remove', 'libllvm22'] if a.kind == 'deb' else ['rpm', '-e', '--test', 'llvm-libs'], expected=1, contains=b'depend')
	# Remove the new installation, then migrate the exact previously delivered
	# product. Its historical private LLVM is removed by the package manager.
	run('remove-before-migration', ['apt-get', 'remove', '-y', 'astrac'] if a.kind == 'deb' else ['dnf', 'remove', '-y', '--setopt=clean_requirements_on_remove=False', 'astrac'])
	require(sha(a.predecessor) == a.predecessor_sha256, 'predecessor changed')
	run('install-predecessor', ['apt-get', 'install', '-y', str(a.predecessor)] if a.kind == 'deb' else ['dnf', 'install', '-y', a.predecessor])
	require((private/'llvm/libLLVM.so.23.1').is_file(), 'real historical installation absent')
	run('upgrade-to-astrac', ['apt-get', 'install', '-y', str(a.package)] if a.kind == 'deb' else ['dnf', 'install', '-y', a.package])
	require(not (private/'llvm').exists(), 'migration left private LLVM')
	old = subprocess.run(['dpkg-query', '-W', '-f', '${db:Status-Status}', 'astra-development'] if a.kind == 'deb' else ['rpm', '-q', 'astra-development', '--qf', '%{NAME}'], capture_output=True)
	require(b'installed' not in old.stdout and old.stdout.strip() != b'astra-development', 'old package remains installed')
	run('migration-smoke', ['python3', '-B', '/usr/share/astra/install/smoke.py', '--clean-host', '--output', a.output/'migration-smoke', '--build', '/build/migration-smoke'], contains=b'INSTALLED_NATIVE_SMOKE_PASS')


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--package', type=Path, required=True)
	p.add_argument('--sha256', required=True)
	p.add_argument('--kind', choices=('deb', 'rpm'), required=True)
	p.add_argument('--output', type=Path, required=True)
	p.add_argument('--system-llvm', action='store_true')
	p.add_argument('--predecessor', type=Path)
	p.add_argument('--predecessor-sha256')
	p.add_argument('--memory', action='store_true')
	p.add_argument('--development', action='store_true')
	a = p.parse_args()
	a.output.mkdir(parents=True, exist_ok=False)
	require(sha(a.package) == a.sha256, 'installer bytes differ from builder output')
	require(shutil.which('astrac') is None and not Path('/usr/lib/astra').exists(), 'host already has Astra')
	if a.development:
		os_release = dict(line.split('=', 1) for line in Path('/etc/os-release').read_text().splitlines() if '=' in line)
		require(os_release['ID'].strip('"') == ('ubuntu' if a.kind == 'deb' else 'fedora') and os_release['VERSION_ID'].strip('"') == ('26.04' if a.kind == 'deb' else '45'), 'wrong development install userland')
	package_name = 'astrac' if a.system_llvm else 'astra-development'
	commands = []
	def run(name, argv, expected=0, contains=None, cwd=None):
		start = time.monotonic()
		result = subprocess.run(list(map(str, argv)), capture_output=True, timeout=900, cwd=cwd)
		for label, data in (('stdout', result.stdout), ('stderr', result.stderr)):
			(a.output/(name+'.'+label)).write_bytes(data)
		commands.append(dict(name=name, argv=list(map(str, argv)), cwd=str(cwd) if cwd else None, exit=result.returncode, expected=expected, seconds=time.monotonic()-start, stdout_sha256=sha(a.output/(name+'.stdout')), stderr_sha256=sha(a.output/(name+'.stderr'))))
		(a.output/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		require(result.returncode in (expected if isinstance(expected, tuple) else (expected,)), name+': wrong exit')
		if contains:
			require(contains in result.stdout+result.stderr, name+': expected message missing')
		return result.stdout
	def guide(name, chapter):
		if a.development:
			if a.kind == 'deb':
				argv = ['apt-get', 'install', '-y', '--no-install-recommends', *(['--reinstall'] if name == 'reinstall' else []), a.package] if name != 'uninstall' else ['apt-get', 'remove', '-y', package_name]
			else:
				argv = ['dnf', '-y', 'reinstall' if name == 'reinstall' else 'install', a.package] if name != 'uninstall' else ['dnf', '-y', 'remove', '--setopt=clean_requirements_on_remove=False', package_name]
			return run(name, argv)
		body = Path('/qa/'+chapter).read_text()
		matches = re.findall(r'^```console '+name+'='+a.kind+r'\n(.*?)^```$', body, re.M|re.S)
		require(len(matches) == 1, 'missing or ambiguous published installation block')
		(a.output/(name+'.source.sh')).write_text(matches[0])
		return run(name, ['/bin/sh', '-eu', '-c', matches[0]], cwd=a.package.parent)
	output = guide('install', 'getting-started.md')
	if not a.development:
		require(a.sha256.encode() in output, 'published checksum command did not report expected artifact')
	provenance = json.loads(Path('/usr/share/astra/PROVENANCE.json').read_text())
	if a.development:
		require(provenance['qualification'] == 'DEVELOPMENT_UNQUALIFIED' and provenance['original_LLVM_strict_memory'] == 'NOT_PASS' and provenance['diagnostic_derivative_used'] is False, 'development disclosure absent')
		require('devunqualified.' in provenance['package_version'] and b'NOT_PASS' in Path('/usr/share/astra/DEV-UNQUALIFIED.txt').read_bytes(), 'unsafe stable metadata')
	if a.kind == 'deb':
		run('metadata', ['dpkg-query', '-W', '-f', '${Package} ${Version} ${Architecture}\n', package_name], contains=(provenance['package_version']+' amd64').encode() if a.development else b'0.0.3~dev28c1-1 amd64')
		if a.memory:
			run('memory-tool', ['apt-get', 'install', '-y', '--no-install-recommends', 'valgrind'])
	else:
		run('metadata', ['rpm', '-q', '--qf', '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n', package_name], contains=(provenance['package_version']+' x86_64').encode() if a.development else b'0.0.3-0.dev28c1.1 x86_64')
		if a.memory:
			run('memory-tool', ['dnf', 'install', '-y', 'valgrind'])
	private = Path('/usr/lib/astra')
	for name in ('getting-started.md', 'tooling.md'):
		require(sha(Path('/qa')/name) == sha(Path('/usr/share/astra/tutorial/docs/guide')/name), 'installed Guide differs from replayed installation recipe')
	run('installed-smoke', ['python3', '-B', '/usr/share/astra/install/smoke.py', '--clean-host', '--output', a.output/'smoke', '--build', '/build/smoke', *(['--memory'] if a.memory and not a.development else [])], contains=b'INSTALLED_NATIVE_SMOKE_PASS')
	run('installed-guide', ['python3', '-B', '/usr/share/astra/tutorial/tests/books/tutorial.py', '--runtime', a.output/'guide'], contains=b'installed Guide shell blocks passed')
	strict_memory = None
	if a.development:
		require(a.memory, 'development delivery requires separately recorded strict memory')
		run('strict-memory-observation', ['python3', '-B', '/qa/development_memory.py', '--output', a.output/'memory', '--build', '/build/memory'], expected=(0, 99))
		strict_memory = json.loads((a.output/'memory/result.json').read_text())['status']
		run('native-elf', ['readelf', '-h', '-l', '-d', '/usr/lib/astra/astrac.native'])
		run('native-dependencies', ['ldd', '/usr/lib/astra/astrac.native'])
		manifest = json.loads((private/'INSTALL.json').read_text())
		library_path = manifest['system_llvm']['library']['path'] if a.system_llvm else '/usr/lib/astra/llvm/libLLVM.so.23.1'
		run('llvm-dependencies', ['ldd', library_path])
		run('dependency-inventory', ['dpkg-query', '-W'] if a.kind == 'deb' else ['rpm', '-qa'])
	user = pwd.getpwnam('nobody')
	require(user.pw_uid != 0, 'ordinary-user acceptance must not run as root')
	user_build = Path('/build/ordinary-user')
	user_build.mkdir()
	os.chown(user_build, user.pw_uid, user.pw_gid)
	run('ordinary-user-native', ['sudo', '-u', 'nobody', '/bin/sh', '-eu', '-c', 'test "$(id -u)" -ne 0; astrac --version; astrac -c -O2 -o main.o /usr/share/astra/install/main.astra; cc -no-pie main.o -o main; ./main'], cwd=user_build, contains=b'0.0.3-dev28c1')
	library = Path(library_path)
	held = library.with_suffix('.held')
	library.rename(held)
	try:
		run('missing-llvm-refusal', ['astrac', '--version'], expected=127, contains=b'libLLVM' if a.system_llvm else b'installation unavailable')
		run('doc-without-llvm', ['astrac', 'doc', '--output', '/build/no-llvm.json', 'api.astra'], cwd='/usr/share/astra/install')
	finally:
		held.rename(library)
	for name in (('astrac.native',) if a.system_llvm else ('llvm/libLLVM.so.23.1', 'astrac.native')):
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
	with (private/'astrac.native').open('ab') as stream:
		stream.write(b'REINSTALL_REPAIR_CONTROL')
	run('pre-reinstall-corruption', ['astrac', '--version'], expected=127, contains=b'identity mismatch')
	guide('reinstall', 'tooling.md')
	run('after-reinstall', ['astrac', '--version'], contains=b'0.0.3-dev28c1')
	if a.system_llvm:
		system_acceptance(a, run, private, provenance)
	guide('uninstall', 'tooling.md')
	require(shutil.which('astrac') is None and not private.exists(), 'uninstall left compiler files')
	if a.development:
		require(all(not Path(name).exists() for name in ('/usr/share/astra', '/usr/share/licenses/'+package_name, '/usr/share/doc/'+package_name)), 'uninstall left development payload')
	require(shutil.which('cc') is not None and shutil.which('python3') is not None, 'uninstall removed external prerequisites')
	result = dict(status='CLEAN_INSTALL_SMOKE_REINSTALL_UNINSTALL_PASS', kind=a.kind, package_sha256=a.sha256, os_release=Path('/etc/os-release').read_text(), command_receipts_sha256=sha(a.output/'commands.json'), smoke_sha256=sha(a.output/'smoke/result.json'), guide_sha256=sha(a.output/'guide/result.json'), negative_controls=['missing LLVM', *([] if a.system_llvm else ['tampered LLVM']), 'tampered compiler', 'doc without LLVM'], upgrade='Authenticated astra-development migration tested' if a.system_llvm else 'Same-version reinstall tested; cross-version upgrade not claimed', signed=False)
	if a.development:
		result.update(qualification='DEVELOPMENT_UNQUALIFIED', strict_memory=strict_memory, memory_receipt_sha256=sha(a.output/'memory/result.json'), original_LLVM_strict_memory='NOT_PASS', source_commit=provenance['compiler_source_commit'], package_commit=provenance['package_source_commit'])
	(a.output/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(result['status'])


if __name__ == '__main__':
	main()
