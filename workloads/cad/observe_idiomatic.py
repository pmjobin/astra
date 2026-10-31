#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Map exact I native allocation sites without altering the production executable."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent


def prepare(compiler, source, program, output):
	output.mkdir(parents=True, exist_ok=False)
	(output / 'tmp').mkdir()
	env = dict(os.environ, CCACHE_DISABLE='1', TMPDIR=str(output / 'tmp'))
	commands = []
	def run(command, label, cwd=source):
		process = subprocess.run(list(map(str, command)), cwd=cwd, env=env, capture_output=True)
		(output / (label + '.stdout')).write_bytes(process.stdout)
		(output / (label + '.stderr')).write_bytes(process.stderr)
		commands.append({'argv': list(map(str, command)), 'cwd': str(cwd), 'status': process.returncode})
		(output / 'commands.json').write_text(json.dumps(commands, indent='\t') + '\n')
		assert process.returncode == 0 and not process.stderr, commands[-1]
		return process.stdout.decode()
	files = ['src/numeric.astra', 'src/algorithm.astra', 'src/main.astra', 'src/entry.astra']
	ssa = run([compiler, '--dump-ssa', *files], 'ssa')
	llvm = run([compiler, '--dump-llvm', *files], 'llvm')
	machine = run(['objdump', '-d', program], 'machine')
	assert 'EXEC (Executable file)' in run(['readelf', '-h', program], 'header'), 'observer requires exact non-PIE executable'
	symbols = run(['nm', '-S', program], 'symbols')
	ids = {name: number for number, name in re.findall(r'\(function #(\d+) "([^"]+)"', ssa)}
	# Order is checked independently in source new expressions, LLVM allocation
	# sites and machine calls. Canonical zero fields are recorded but never fail.
	groups = {
		'astra.ctor.0': [('state',72,9),('next',72,9),('supports',20,5),('means',16,2),('colors',24,3),('pmax',8,1),('psum',8,1),('check',8,1),('ranges',16,2),('empty-logw',8,0),('empty-weights',8,0),('empty-gamma',8,0)],
		'astra.fn.' + ids['initialize']: [('logw',8,1),('weights',8,1),('gamma',8,1)],
		'astra.fn.' + ids['correction_effect']: [('before-state',72,9),('before-logw',8,1),('before-weights',8,1),('before-gamma',8,1),('probe-pmax',8,1),('probe-psum',8,1),('probe-check',8,1),('after-weights',8,1),('after-gamma',8,1),('after-state',72,9),('after-logw',8,1)],
		'astra.fn.' + ids['downscale']: [('output',24,3)],
	}
	calls = {name: [] for name in groups}
	function = None
	for line in machine.splitlines():
		match = re.match(r'^[0-9a-f]+ <([^>]+)>:', line)
		if match:
			function = match[1]
		if re.search(r'\bcall\s', line) and '<calloc@plt>' in line:
			assert function in calls, function
			match = re.match(r'\s*([0-9a-f]+):\s*((?:[0-9a-f]{2} )+)', line)
			assert match, line
			calls[function].append(int(match[1], 16) + len(match[2].split()))
	rows = []
	for function, logical in groups.items():
		assert len(calls[function]) == len(logical), function
		body = re.search(r'^define [^\n]+ @' + re.escape(function) + r'\([^\n]+\{\n(.*?)^}', llvm, re.M | re.S)[1]
		assert body.count('call ptr @calloc(') == len(logical), function
		for pc, (name, stride, slots) in zip(calls[function], logical):
			rows.append({'id': len(rows) + 1, 'name': name, 'function': function, 'return_pc': pc, 'stride': stride, 'historical_slots_per_element': slots, 'empty': slots == 0})
	args = re.search(r'^([0-9a-f]+) ([0-9a-f]+) T astra_host_args_prepare_v0$', symbols, re.M)
	assert args
	begin, size = (int(value, 16) for value in args.groups())
	header = 'static const struct { uintptr_t pc; int id; size_t stride; } sites[] = {\n' + ''.join(f'\t{{{row["return_pc"]}, {row["id"]}, {row["stride"]}}},\n' for row in rows) + '};\n'
	header += f'#define SITE_COUNT {len(rows)}\n#define ARGS_BEGIN {begin}\n#define ARGS_END {begin + size}\n'
	(output / 'sites.h').write_text(header)
	run(['/usr/bin/gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-shared', '-fPIC', '-I', output, HERE / 'idiomatic/observe.c', '-ldl', '-o', output / 'observer.so'], 'observer-build')
	result = {'program_sha256': hashlib.sha256(program.read_bytes()).hexdigest(), 'sites': rows, 'scope': 'Test-only libc interposition at identified machine call sites. No change to the executable, no private native call or numerical copy.'}
	(output / 'sites.json').write_text(json.dumps(result, indent='\t') + '\n')
	return result


if __name__ == '__main__':
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['compiler', 'source', 'program', 'output']:
		parser.add_argument('--' + name, type=Path, required=True)
	args = parser.parse_args()
	prepare(*[getattr(args, name).resolve() for name in ['compiler', 'source', 'program', 'output']])
