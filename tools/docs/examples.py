#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Explicit checked-example execution from astra-api-docs/1 JSON; no shell."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
NAME = re.compile(r'[a-z][a-z0-9-]{0,63}\Z')


def examples(document):
	assert document['format'] == 'astra-api-docs/1' and document['schema_version'] == 1
	seen = set()
	for symbol in document['symbols']:
		active = None
		lines = []
		for line_number, line in enumerate(symbol['documentation']['markdown'].splitlines(), 1):
			if line.startswith('```'):
				if active is not None:
					assert line == '```', 'nested or malformed fence'
					if active:
						yield dict(active, source='\n'.join(lines)+'\n', symbol=symbol['id'], doc_line=opening_line)
					active = None
					lines = []
				elif line.startswith('```astra '):
					parts = shlex.split(line[9:])
					active = {}
					for part in parts:
						key, value = part.split('=', 1)
						assert key not in active, 'duplicate example option'
						active[key] = value
					assert set(active) <= {'name', 'mode', 'category', 'exit', 'stdout', 'diagnostic', 'library'}
					assert {'name', 'mode', 'category'} <= set(active)
					assert NAME.fullmatch(active['name']) and active['name'] not in seen
					seen.add(active['name'])
					assert len(seen) <= 128
					assert active['mode'] in ('compile', 'run', 'compile_fail')
					assert active['category'] in ('freestanding', 'hosted')
					assert (active['mode'] == 'compile_fail') == ('diagnostic' in active)
					if active['mode'] == 'run': assert 'exit' in active
					opening_line = line_number
				elif line == '```astra':
					raise ValueError('Astra fences require explicit name, mode and category')
				else:
					active = {}
			elif active is not None:
				lines.append(line)
		assert active is None, 'unterminated fence'


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('document', type=Path)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--link', type=Path, help='Authenticated hosted object manifest; required only for hosted examples')
	p.add_argument('--toolchain', type=Path, help='Authenticated build identity supplying the exact LLVM environment')
	p.add_argument('--strict-memory', action='store_true', help='Check each compiler and executed example with unsuppressed all-kinds Valgrind')
	a = p.parse_args()
	sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
	assert a.compiler.is_absolute() and sha(a.compiler) == a.compiler_sha256
	rows = list(examples(json.loads(a.document.read_text())))
	assert rows, 'no checked examples found'
	providers = {}
	if a.link:
		providers = json.loads(a.link.read_text())['objects']
		providers = {k:v for k,v in providers.items() if Path(k).name not in ('llvm-capi.o', 'arguments.o')}
		assert all(sha(path) == digest for path,digest in providers.items())
	a.build.mkdir(parents=True, exist_ok=False)
	a.runtime.mkdir(parents=True, exist_ok=False)
	(a.runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	env = dict(os.environ)
	if a.toolchain:
		toolchain = json.loads(a.toolchain.read_text())
		assert all(sha(path) == digest for path,digest in toolchain['tools'].items())
		env.update({key:value for key,value in toolchain['environment'].items() if value is not None})
	env.pop('LD_PRELOAD', None)
	env.pop('VALGRIND_OPTS', None)
	assert subprocess.check_output(['llvm-config', '--version'], env=env).strip() == b'23.1.4'
	commands = []
	products = {}
	source_inputs = {}
	def run(label, argv, expected=0, memory=False):
		if memory:
			argv = ['valgrind', '--trace-children=yes', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *argv]
		start = time.monotonic()
		timing = a.runtime/(label+'.time')
		r = subprocess.run(['/usr/bin/time', '-v', '-o', timing, '--', *map(str, argv)], capture_output=True, timeout=120, env=env, cwd=ROOT)
		(a.runtime/(label+'.stdout')).write_bytes(r.stdout)
		(a.runtime/(label+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(label=label, argv=list(map(str, argv)), exit=r.returncode, expected=expected, seconds=time.monotonic()-start, stdout_sha256=hashlib.sha256(r.stdout).hexdigest(), stderr_sha256=hashlib.sha256(r.stderr).hexdigest(), time_sha256=sha(timing)))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		print(label, r.returncode, round(time.monotonic()-start, 3), flush=True)
		assert r.returncode == expected, (label, r.returncode, r.stderr.decode(errors='replace'))
		if memory:
			assert all(marker in r.stderr for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)')), label
		return r
	for example in rows:
		name = example['name']
		source = a.runtime/(name+'.astra')
		source.write_text(example['source'])
		source_inputs[str(source)] = sha(source)
		extra = []
		if 'library' in example:
			path = Path(example['library'])
			assert not path.is_absolute() and '..' not in path.parts and path.suffix == '.astra'
			path = (ROOT/path).resolve(strict=True)
			assert path.is_relative_to(ROOT)
			extra.append(path)
			source_inputs[str(path)] = sha(path)
		if example['category'] == 'hosted': assert providers, 'hosted example requires explicitly authenticated providers'
		for mode in ('O0', 'O2'):
			label = name+'-'+mode
			obj = a.build/(label+'.o')
			if example['mode'] == 'compile_fail':
				obj.write_bytes(b'EXAMPLE_FAILURE_SENTINEL\n')
				r = run(label+'-refuse', [a.compiler, '-c', '-'+mode, '-o', obj, source, *extra], expected=1, memory=a.strict_memory)
				assert example['diagnostic'].encode() in r.stderr and obj.read_bytes() == b'EXAMPLE_FAILURE_SENTINEL\n'
				continue
			run(label+'-compile', [a.compiler, '-c', '-'+mode, '-o', obj, source, *extra], memory=a.strict_memory)
			products[str(obj)] = sha(obj)
			if example['mode'] == 'run':
				exe = a.build/label
				run(label+'-link', ['cc', '-no-pie', obj, *(providers if example['category'] == 'hosted' else []), '-o', exe])
				products[str(exe)] = sha(exe)
				r = run(label+'-run', [exe], expected=int(example['exit']), memory=a.strict_memory)
				assert r.stdout.decode() == example.get('stdout', '')
	assert sha(a.compiler) == a.compiler_sha256
	assert all(sha(path) == digest for path,digest in {**source_inputs, **products}.items())
	result = dict(status='CHECKED_DOCUMENTATION_EXAMPLES_PASS', examples=len(rows), profiles=['O0', 'O2'], strict_memory=a.strict_memory, compiler_sha256=a.compiler_sha256, document_sha256=sha(a.document), commands_sha256=sha(a.runtime/'commands.json'), sources=source_inputs, emit_products=products, toolchain_receipt_sha256=sha(a.toolchain) if a.toolchain else None)
	(a.runtime/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(json.dumps(result))


if __name__ == '__main__':
	main()
