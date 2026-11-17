#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Installed-user checks; runs with no source checkout, seed or developer files."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
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
	p.add_argument('--output', type=Path, required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--fixtures', type=Path, default=Path('/usr/share/astra/install'))
	p.add_argument('--compiler', default='astrac')
	p.add_argument('--memory', action='store_true')
	p.add_argument('--clean-host', action='store_true')
	a = p.parse_args()
	a.output.mkdir(parents=True, exist_ok=False)
	a.build.mkdir(parents=True, exist_ok=False)
	if a.clean_host:
		for home in [Path.home(), *Path('/home').iterdir()]:
			for suffix in ('Workspace/astra', 'Workspace/codex/work/astra'):
				require(not (home/suffix).exists(), 'developer workspace present on install host')
		for path in ('/src/compiler/driver/main.astra', '/llvm/bin/llvm-config', '/work/relative-bootstrap'):
			require(not Path(path).exists(), 'developer build input mounted on install host')
	compiler = str(Path(shutil.which(a.compiler)).resolve())
	env = dict(os.environ, LC_ALL='C.UTF-8')
	for key in ('LD_LIBRARY_PATH', 'LD_PRELOAD', 'LIBRARY_PATH', 'CPATH', 'VALGRIND_OPTS'):
		env.pop(key, None)
	commands = []
	def run(name, argv, expected=0, stdout=b'', diagnostic=None, memory=False):
		argv = list(map(str, argv))
		if memory:
			argv = ['valgrind', '--trace-children=yes', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *argv]
		start = time.monotonic()
		result = subprocess.run(argv, capture_output=True, env=env, cwd=a.build, timeout=300)
		for label, data in (('stdout', result.stdout), ('stderr', result.stderr)):
			(a.output/(name+'.'+label)).write_bytes(data)
		commands.append(dict(name=name, argv=argv, exit=result.returncode, expected=expected, seconds=time.monotonic()-start, stdout_sha256=sha(a.output/(name+'.stdout')), stderr_sha256=sha(a.output/(name+'.stderr')), strict_memory=memory))
		(a.output/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		require(result.returncode == expected, name+': wrong exit')
		if stdout is not None:
			require(result.stdout == stdout, name+': wrong stdout')
		if diagnostic:
			require(diagnostic in result.stderr, name+': missing diagnostic')
		elif not memory:
			require(not result.stderr, name+': unexpected stderr')
		if memory:
			for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'):
				require(marker in result.stderr, name+': strict memory marker absent')
		return result.stdout
	version = run('version', [compiler, '--version'], stdout=b'astrac 0.0.3-dev28c1 (GNU/Linux x86-64, E25-A-v1, LLVM 23.1.4)\n')
	shadow = a.build/'hashlib.py'
	shadow.write_text('raise RuntimeError("UNTRUSTED_USER_MODULE_LOADED")\n')
	old_pythonpath = env.get('PYTHONPATH')
	env['PYTHONPATH'] = str(a.build)
	run('isolated-launcher', [compiler, '--version'], stdout=version)
	if old_pythonpath is None:
		env.pop('PYTHONPATH')
	else:
		env['PYTHONPATH'] = old_pythonpath
	help_text = run('help', [compiler, '--help'], stdout=None)
	require(b'Explicit sources form one program' in help_text and b'astrac doc --help' in help_text, 'CLI help contract')
	for path in a.fixtures.iterdir():
		if path.suffix in ('.astra', '.c'):
			shutil.copyfile(path, a.build/path.name)
	run('c-provider', ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', 'abi.c', '-o', 'abi.o'])
	for mode in ('O0', 'O2'):
		for name, sources, foreign, expected_out in [('main', ['main.astra'], [], b''), ('owners', ['owners.astra'], ['abi.o'], b'Astra C ABI: 5 drops, sum 30\n')]:
			label = name+'-'+mode
			run(label+'-compile', [compiler, '-c', '-'+mode, '-o', label+'.o', *sources])
			require((a.build/(label+'.o')).read_bytes()[:5] == b'\x7fELF\x02', 'object is not ELF64')
			run(label+'-link', ['cc', '-no-pie', label+'.o', *foreign, '-o', label])
			run(label+'-run', [a.build/label], stdout=expected_out)
			if a.memory:
				run(label+'-memory', [a.build/label], stdout=expected_out, memory=True)
		for name, diagnostic in [('type', b"expected initializer of type 'bool', found 'int'"), ('owner', b'SSA verification failed')]:
			out = a.build/(name+'-'+mode+'.o')
			for sentinel in (False, True):
				if sentinel:
					out.write_bytes(b'INSTALL_REFUSAL_SENTINEL\n')
				run(name+'-'+mode+'-'+str(sentinel), [compiler, '-c', '-'+mode, '-o', out, 'negative-'+name+'.astra'], expected=1, diagnostic=diagnostic)
				require(out.read_bytes() == b'INSTALL_REFUSAL_SENTINEL\n' if sentinel else not out.exists(), 'refusal altered output')
	for suffix in ('first', 'second'):
		run('doc-'+suffix, [compiler, 'doc', '--output', suffix+'.json', 'api.astra'])
	require((a.build/'first.json').read_bytes() == (a.build/'second.json').read_bytes(), 'non-deterministic API JSON')
	doc = json.loads((a.build/'first.json').read_text())
	require(doc['format'] == 'astra-api-docs/1' and doc['schema_version'] == 1, 'API schema identity')
	require(any(row['canonical_name'] == 'add' for row in doc['symbols']), 'API symbol missing')
	if a.memory:
		# Exercise the actual native image without Python's interpreter allocations.
		native = Path('/usr/lib/astra/astrac.native')
		memory_env = env.copy()
		env['LD_LIBRARY_PATH'] = '/usr/lib/astra/llvm'
		run('compiler-memory', [native, '-c', '-O2', '-o', 'memory.o', 'main.astra'], memory=True)
		run('negative-memory', [native, '--check', 'negative-owner.astra'], expected=1, diagnostic=b'SSA verification failed', memory=True)
		env.clear()
		env.update(memory_env)
		run('doc-memory', ['/usr/lib/astra/astrac.doc', 'doc', '--output', 'memory.json', 'api.astra'], memory=True)
	receipt = dict(status='INSTALLED_NATIVE_SMOKE_PASS', platform=platform.platform(), os_release=Path('/etc/os-release').read_text(), compiler=dict(path=compiler, sha256=sha(compiler)), version=version.decode().strip(), source_inputs={f.name:sha(f) for f in a.fixtures.iterdir() if f.is_file()}, commands_sha256=sha(a.output/'commands.json'), strict_memory=a.memory, clean_host=a.clean_host, products={f.name:sha(f) for f in a.build.iterdir() if f.is_file()})
	(a.output/'result.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print('INSTALLED_NATIVE_SMOKE_PASS: O0/O2, C ABI, owners, refusal and doc')


if __name__ == '__main__':
	main()
