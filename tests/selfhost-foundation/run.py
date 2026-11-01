#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build the real component and independent Vala oracle with explicit tools/outputs."""
import argparse
import bisect
import hashlib
import json
import random
import re
import resource
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def expected(data, path):
	parts = [p for p in path.split('/') if p not in ('', '.')]
	name = ('/' if path.startswith('/') else '') + '/'.join(parts)
	name = name or '.'
	starts = [0] + [m.end() for m in re.finditer(rb'\r\n|\r|\n', data)]
	locations = []
	for offset in range(len(data) + 1):
		line = bisect.bisect_right(starts, offset)
		prefix = data[starts[line - 1]:offset]
		column = 1 + len(re.findall(rb'[\x00-\x09\x0b\x0c\x0e-\x7f\xc0-\xff]', prefix))
		locations.append((line, column))
	errors = []
	try:
		data.decode('utf-8', errors='strict')
	except UnicodeDecodeError as error:
		errors.append(error.start)
	if b'\0' in data:
		errors.append(data.index(0))
	error = min(errors) if errors else -1
	message = '' if error < 0 else 'unexpected NUL byte' if data[error] == 0 else 'invalid UTF-8 encoding'
	lines = [name, f'{len(data)} {error} ', message]
	lines.extend(f'{line} {column} ' for line, column in locations)
	lines.append(''.join(f'{b} ' for b in data))
	line, column = locations[len(data) if error < 0 else error]
	lines.append(f'{name}:{line}:{column}: error: example')
	return ('\n'.join(lines) + '\n').encode()


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--cc', default='cc')
	p.add_argument('--valac', default='valac')
	args = p.parse_args()
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	build, runtime = args.build.resolve(), args.runtime.resolve()
	for path in (build, runtime):
		if path == ROOT or ROOT in path.parents:
			raise ValueError('outputs must be outside the source repository')
		path.mkdir(parents=True, exist_ok=True)
	commands = []
	def run(argv, name, expected_exit=0):
		start = time.monotonic()
		r = subprocess.run([str(x) for x in argv], cwd=build, capture_output=True, timeout=180)
		(runtime / (name + '.stdout')).write_bytes(r.stdout)
		(runtime / (name + '.stderr')).write_bytes(r.stderr)
		commands.append({'argv': [str(x) for x in argv], 'exit': r.returncode, 'seconds': time.monotonic() - start})
		(runtime / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
		if r.returncode != expected_exit:
			raise RuntimeError(f'{name}: exit {r.returncode}: {r.stderr.decode(errors="replace")[:2000]}')
		return r.stdout
	objects = []
	for provider in ('args-posix', 'files-posix', 'text-posix', 'text-ops-posix', 'diagnostics-trap'):
		obj = build / (provider + '.o')
		run([args.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', ROOT / f'lib/runtime/platform/{provider}.c', '-o', obj], provider)
		objects.append(obj)
	oracle = build / 'source-oracle'
	run([args.valac, '--enable-checking', '-X', '-DVALA_STRICT_C', '-o', oracle,
		ROOT / 'tests/selfhost-foundation/oracle.vala', *[ROOT / f'bootstrap/source/{n}.vala' for n in ('source-file', 'source-span', 'diagnostic', 'source-set')]], 'oracle-build')
	for refusal in ('cross-source-cover', 'reversed-cover'):
		run([oracle, '--' + refusal], 'oracle-' + refusal, -6)
		assert b'assertion failed' in (runtime / ('oracle-' + refusal + '.stderr')).read_bytes()
	libraries = ['base/errors', 'base/diagnostics', 'text/utf8-message', 'text/utf8-byte-builder', 'text/scalar-format', 'hosted/text-ops', 'collections/bag', 'collections/vector', 'hosted/files', 'hosted/text']
	sources = [ROOT / 'compiler/source/source.astra', ROOT / 'tests/selfhost-foundation/observe.astra', *[ROOT / f'lib/astra/{x}.astra' for x in libraries]]
	programs = []
	for mode in ('O0', 'O2'):
		program = build / ('source-component-' + mode)
		argv = [args.compiler.resolve(), '-' + mode, *sources, '-o', program]
		for obj in objects:
			argv.extend(['--link-object', obj])
		run(argv, 'component-build-' + mode)
		programs.append(program)
	span_programs = []
	for mode in ('O0', 'O2'):
		program = build / ('span-component-' + mode)
		argv = [args.compiler.resolve(), '-' + mode, sources[0], ROOT / 'tests/selfhost-foundation/spans.astra', *sources[2:], '-o', program]
		for obj in objects:
			argv.extend(['--link-object', obj])
		run(argv, 'span-build-' + mode)
		assert run([program], 'span-' + mode) == run([oracle, '--spans'], 'span-oracle-' + mode) == b'SPAN_OK\n'
		span_programs.append(program)
	path_programs = []
	path_cases = [[], ['b', 'a', './c'], ['./a//b', 'a/b'], ['', '.'], ['/a', 'a', '../a', 'a/../b'], ['é', 'É', '中', 'A'], ['///a//./b', '/a/b'], ['../x', 'x', '/x', './X']]
	for mode in ('O0', 'O2'):
		program = build / ('path-component-' + mode)
		argv = [args.compiler.resolve(), '-' + mode, sources[0], ROOT / 'compiler/source/source-set.astra', ROOT / 'tests/selfhost-foundation/paths.astra', *sources[2:], '-o', program]
		for obj in objects:
			argv.extend(['--link-object', obj])
		run(argv, 'path-build-' + mode)
		for index, paths in enumerate(path_cases):
			actual = run([program, *paths], f'paths-{mode}-{index}')
			oracle_result = run([oracle, '--paths', program, *paths], f'paths-oracle-{mode}-{index}')
			names = [expected(b'', str(p)).split(b'\n', 1)[0] for p in [program, *paths]]
			want = b'DUPLICATE\n' if len(set(names)) != len(names) else b'\n'.join(sorted(names)) + b'\n'
			assert actual == oracle_result == want, (mode, index)
		path_programs.append(program)
	corpus = [b'', b'x', b'\n', b'\r', b'\r\n', b'\r\n\r\nx\r', b'\tx\t', 'é😀e\u0301\r\nZ'.encode(), b'\0', b'a\0b', b'\xff', b'\xc0\xaf', b'\xc2', b'\xe0\x80\x80', b'\xed\xa0\x80', b'\xf4\x90\x80\x80', b'\xf0\x9f', b'a\r\n\xe2\0', b'\x80', b'\xe2(\xa1']
	fixtures = ['tests/diag/fixtures/client.astra', 'tests/diag/fixtures/ownership.astra', 'tests/sources/fixtures/structs/types.astra']
	corpus.extend((ROOT / path).read_bytes() for path in fixtures)
	rng = random.Random(9301)
	for _ in range(24):
		text = ''.join(rng.choice(['a', '\n', '\r', '\t', 'é', '😀', '\u0301', '中']) for _ in range(rng.randrange(0, 65)))
		corpus.append(text.encode())
	for _ in range(16):
		corpus.append(bytes(rng.randrange(256) for _ in range(rng.randrange(0, 65))))
	paths = ['', '.', './a//../b.astra', '//a/./B/../c', '/', 'é/./源.astra']
	for index, data in enumerate(corpus):
		fixture = runtime / f'input-{index:03d}.bin'
		fixture.write_bytes(data)
		path = paths[index % len(paths)]
		want = expected(data, path)
		for program in [oracle, *programs]:
			actual = run([program, fixture, path], f'{program.name}-{index:03d}')
			if actual != want:
				(runtime / f'expected-{index:03d}.txt').write_bytes(want)
				raise AssertionError(f'{program.name} disagrees at corpus case {index}')
	if shutil.which('valgrind'):
		for program in programs:
			run(['valgrind', '--vgdb=no', '--leak-check=full', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', program, runtime / 'input-007.bin', './a//../b'], 'valgrind-' + program.name)
		for program in span_programs:
			run(['valgrind', '--vgdb=no', '--leak-check=full', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', program], 'valgrind-' + program.name)
		for program in path_programs:
			run(['valgrind', '--vgdb=no', '--leak-check=full', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', program, './a//b', 'a/b'], 'valgrind-' + program.name)
	result = {'status': 'PASS', 'cases': len(corpus), 'path_cases_per_profile': len(path_cases), 'span_identity_and_cover': True, 'profiles': ['Vala oracle', 'Astra O0', 'Astra O2'], 'memory_check': bool(shutil.which('valgrind')), 'compiler_sha256': hashlib.sha256(args.compiler.read_bytes()).hexdigest(), 'product_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [oracle, *programs, *span_programs, *path_programs]}}
	(runtime / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
	print(json.dumps(result, indent=2))


if __name__ == '__main__':
	main()
