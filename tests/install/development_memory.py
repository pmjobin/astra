#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe strict installed memory separately from development install acceptance."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def sha(path):
	with Path(path).open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--output', type=Path, required=True)
	p.add_argument('--build', type=Path, required=True)
	a = p.parse_args()
	a.output.mkdir(parents=True, exist_ok=False)
	a.build.mkdir(parents=True, exist_ok=False)
	env = dict(os.environ, LC_ALL='C.UTF-8')
	for key in ('LD_PRELOAD', 'LD_LIBRARY_PATH', 'LIBRARY_PATH', 'CPATH', 'VALGRIND_OPTS'):
		env.pop(key, None)
	vg = ['valgrind', '--default-suppressions=no', '--track-origins=yes', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all']
	commands = []
	def run(name, argv, expected=0, memory=False, stdout=None, diagnostic=None):
		argv = list(map(str, [*(vg if memory else []), *argv]))
		start = time.monotonic()
		result = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.output/(name+'.time')), *argv], cwd=a.build, env=env, capture_output=True, timeout=600)
		for label, data in [('stdout', result.stdout), ('stderr', result.stderr)]:
			(a.output/(name+'.'+label)).write_bytes(data)
		clean = all(marker in result.stderr for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)')) if memory else None
		commands.append(dict(name=name, argv=argv, expected_functional_exit=expected, exit=result.returncode, seconds=time.monotonic()-start, strict_memory=memory, memory_status=('PASS' if clean and result.returncode == expected else 'NOT_PASS') if memory else None, stdout_sha256=sha(a.output/(name+'.stdout')), stderr_sha256=sha(a.output/(name+'.stderr')), resource_sha256=sha(a.output/(name+'.time'))))
		(a.output/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert result.returncode in ((expected, 99) if memory else (expected,)), name
		if stdout is not None:
			assert result.stdout == stdout, name
		if diagnostic:
			assert diagnostic in result.stderr, name
		return result
	private = Path('/usr/lib/astra')
	fixtures = Path('/usr/share/astra/install')
	library = private/'llvm/libLLVM.so.23.1'
	run('oracle-build', ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-I/qa/include', '/qa/llvm-direct.c', library, '-Wl,-rpath,/usr/lib/astra/llvm', '-o', 'oracle'])
	loaded = run('oracle-library', ['ldd', a.build/'oracle'])
	assert str(library).encode() in loaded.stdout
	(a.build/'identity.ll').write_text('define i32 @identity(i32 %a) {\n  ret i32 %a\n}\n')
	(a.build/'invalid.ll').write_text('define i32 @invalid(i32 %a) {\n  ret i64 0\n}\n')
	for name, source, expected in [('identity', a.build/'identity.ll', 0), ('invalid', a.build/'invalid.ll', 1), ('instcombine', Path('/qa/llvm-instcombine.ll'), 0)]:
		for memory in (False, True):
			label = name+('-memory' if memory else '-plain')
			out = a.build/(label+'.ll')
			run(label, [a.build/'oracle', source, 'function(instcombine)', 'none', out], expected=expected, memory=memory, diagnostic=b'error:' if expected else None)
			assert out.exists() == (expected == 0)
		if expected == 0:
			assert (a.build/(name+'-plain.ll')).read_bytes() == (a.build/(name+'-memory.ll')).read_bytes()
	run('abi-build', ['cc', '-O2', '-c', fixtures/'abi.c', '-o', 'abi.o'])
	for mode in ('O0', 'O2'):
		for name, source, result, stdout in [('main', fixtures/'main.astra', 0, b''), ('owners', fixtures/'owners.astra', 0, b'Astra C ABI: 5 drops, sum 30\n'), ('values', Path('/qa/values.astra'), 42, b'')]:
			label = name+'-'+mode
			run(label+'-compiler', [private/'astrac.native', '-c', '-'+mode, '-o', label+'.o', source], memory=True, stdout=b'')
			assert (a.build/(label+'.o')).read_bytes()[:5] == b'\x7fELF\x02'
			run(label+'-link', ['cc', '-no-pie', label+'.o', *(['abi.o'] if name == 'owners' else []), '-o', label])
			run(label+'-target', [a.build/label], expected=result, stdout=stdout, memory=True)
	run('negative-memory', [private/'astrac.native', '--check', fixtures/'negative-owner.astra'], expected=1, diagnostic=b'SSA verification failed', memory=True)
	run('doc-memory', [private/'astrac.doc', 'doc', '--output', a.build/'api.json', fixtures/'api.astra'], memory=True)
	failed = [row['name'] for row in commands if row['memory_status'] == 'NOT_PASS']
	result = dict(status='NOT_PASS' if failed else 'FOCUSED_STRICT_MEMORY_PASS', failed_cases=failed, original_LLVM_historical_strict_memory='NOT_PASS', derivative_used=False, library_sha256=sha(library), native_sha256=sha(private/'astrac.native'), commands_sha256=sha(a.output/'commands.json'), scope='Fresh installed original LLVM and compiler. No suppressions; no full release or dependency disposition.')
	(a.output/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(result['status'], ', '.join(failed))
	return 99 if failed else 0


if __name__ == '__main__':
	raise SystemExit(main())
