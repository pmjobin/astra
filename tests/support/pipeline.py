# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Process and LLVM mechanics; callers retain their own semantic observations."""
from pathlib import Path
import re
import json

STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
MODES = ['O0', 'O2', 'O2-fma', 'preserved-O2']


def snapshots(collector, inputs, directory, cwd, run):
	directory.mkdir()
	run([collector, directory, *inputs], cwd)
	assert {p.name for p in directory.iterdir()} == set(STAGES)


def collect(collector, inputs, directory, cwd, run):
	snapshots(collector, inputs, directory, cwd, run)
	return {stage: (directory / stage).read_text() for stage in STAGES}


def observations(compiler, collector, inputs, out, name, run, cwd=None, public=False):
	cwd = Path.cwd() if cwd is None else cwd
	first = collect(collector, inputs, out / (name + '-stages-a'), cwd, run)
	second = out / (name + '-stages-b')
	snapshots(collector, inputs, second, cwd, run)
	for stage, data in first.items():
		assert data == (second / stage).read_text(), (name, stage, 'fresh-process stage determinism')
		(out / (name + '.' + stage)).write_text(data)
		if public:
			# Syntax CLI deliberately ignores foreign declarations.
			arguments = list(inputs)
			if stage == 'syntax':
				while '--vapi' in arguments:
					i = arguments.index('--vapi')
					del arguments[i:i + 2]
			assert run([compiler, '--dump-' + stage, *arguments], cwd) == data, (name, stage, 'public CLI')
	return first


def machine_objects(ir, out, name, run):
	for mode in MODES:
		stem = name + '-' + mode
		inp, optimized, obj = [out / (stem + suffix) for suffix in ['-input.ll', '.ll', '.o']]
		inp.write_text(re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', ir, flags=re.M) if mode == 'preserved-O2' else ir)
		run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', inp.name, '-o', optimized.name], out)
		run(['opt', '-passes=verify', '-disable-output', optimized.name], out)
		run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'O2-fma' else []), optimized.name, '-o', obj.name], out)
		yield mode, stem, obj


def registered_command(build, name):
	rows = json.loads((build / 'meson-info/intro-tests.json').read_text())
	matches = [row['cmd'] for row in rows if row['name'] == name]
	assert len(matches) == 1, (name, matches)
	return matches[0]
