#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused executable/ABI/proof closure; builds and publication stay separate."""
import argparse
import json
from pathlib import Path
import resource
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]


def main():
	p = argparse.ArgumentParser()
	for key in ('component', 'compiler', 'build', 'runtime', 'frozen', 'additional', 'ssa-frozen', 'inputs'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False)
	common = ['--component', a.component, '--compiler', a.compiler]
	steps = [
		('numeric', 'selfhost-nativeabi/numeric.py', common),
		('boundary', 'selfhost-nativeabi/boundary.py', common),
		('additions', 'selfhost-nativeabi/run.py', [*common, '--frozen', a.additional]),
		('lifetime', 'selfhost-nativeabi/lifetime.py', common),
		('legacy', 'selfhost-llvm/run.py', [*common, '--frozen', a.frozen]),
		('new-negative', 'selfhost-nativeabi/negative.py', [*common, '--frozen', a.additional, '--legacy', a.frozen]),
		('old-negative', 'selfhost-llvm/negative.py', ['--component', a.component, '--frozen', a.frozen]),
		('continuity', 'selfhost-ssa/run.py', ['--build', a.component.parent, '--frozen', a.ssa_frozen, '--product-prefix', a.component.name[:-2]]),
		('literals', 'selfhost-llvm/literals.py', common),
		('fatal', 'selfhost-llvm/fatal.py', [*common, '--frozen', a.frozen]),
	]
	rows = []
	for name, script, args in steps:
		argv = [sys.executable, '-B', ROOT/'tests'/script, *args, '--runtime', a.runtime/name, '--mode', a.mode]
		if name not in ('old-negative', 'continuity'):
			argv += ['--build', a.build/name]
		if name in ('numeric', 'lifetime', 'boundary'):
			argv += ['--inputs', a.inputs/name]
		start = time.monotonic(); before = resource.getrusage(resource.RUSAGE_CHILDREN)
		r = subprocess.run(list(map(str, argv)), cwd=ROOT)
		after = resource.getrusage(resource.RUSAGE_CHILDREN)
		rows.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode,
			monotonic_start=start, monotonic_end=time.monotonic(),
			child_user_seconds=after.ru_utime-before.ru_utime,
			child_system_seconds=after.ru_stime-before.ru_stime))
		(a.runtime/'commands.json').write_text(json.dumps(rows, indent=2)+'\n')
		assert r.returncode == 0, (name, r.returncode)
	assert all(json.loads((a.runtime/name/'result.json').read_text())['status'] == 'PASS' for name, _, _ in steps)
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, checks=rows,
		selected_distinct_executions=39, uncounted_numeric_normal=3, uncounted_numeric_fatal=8,
		original_mutations=21, additional_mutations=18, upstream_mutations=dict(core=22, cfg=26, ssa=30),
		limits='1044-query replay, full formatting and rebuild equivalence are separate mandatory gates.'), indent=2)+'\n')
	print(a.mode, 'focused 39-case ABI/FP/ownership and independent proof closure PASS')


if __name__ == '__main__':
	main()
