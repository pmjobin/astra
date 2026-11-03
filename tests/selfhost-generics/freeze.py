#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze the declared source family and measure its independent starting state."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from corpus import CASES, EXISTING, MULTISOURCE

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for key in ('compiler', 'build', 'runtime'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--before-O0', type=Path)
	p.add_argument('--before-O2', type=Path)
	a = p.parse_args()
	assert all(not x.resolve().is_relative_to(ROOT) for x in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	assert sha(a.compiler) == '908f8db9e524cf94b7651f36e9bf0ff32c98ef64cb7eacd737c3b5f680064b45'
	items, commands = [], []
	def run(argv, name):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], capture_output=True, timeout=180, cwd=a.build, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(argv=list(map(str, argv)), name=name, exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
	inputs = [(n, [ROOT/p]) for n, p in EXISTING.items()]
	for name, text in CASES.items():
		source = a.runtime/(name+'.astra'); source.write_text(text+'\n'); inputs.append((name, [source]))
	inputs.append(('cross-unit', [ROOT/p for p in MULTISOURCE]))
	for name, sources in inputs:
		assert run([a.compiler, '--parse', *sources], name+'-parse').returncode == 0
		assert run([a.compiler, '--check', *sources], name+'-check').returncode == 0
		observations = []
		for mode in ('O0', 'O2'):
			product = a.build/(name+'-'+mode)
			assert run([a.compiler, '-'+mode, *sources, '-o', product], name+'-'+mode+'-C0-build').returncode == 0
			actual = run([product], name+'-'+mode+'-C0-execute'); assert actual.returncode == 0 and actual.stdout == actual.stderr == b''
			before = getattr(a, 'before_'+mode)
			if before:
				r = run([before, '--nativeabi-admit', mode, a.build/'unused', *sources], name+'-'+mode+'-before')
				observations.append(dict(mode=mode, exit=r.returncode, stdout_sha256=hashlib.sha256(r.stdout).hexdigest(), stderr_sha256=hashlib.sha256(r.stderr).hexdigest()))
		items.append(dict(name=name, sources=[dict(path=str(p), sha256=sha(p)) for p in sources], c0_sha256=sha(a.compiler), before=observations, expected_exit=0, expected_stdout='', expected_stderr=''))
		(a.runtime/'selection.json').write_text(json.dumps(items, indent=2)+'\n')
	assert len(items) == 13 and len({tuple(s['sha256'] for s in item['sources']) for item in items}) == 13
	print('Frozen 13 distinct source-bound C0 executions per profile; native starting results retained')


if __name__ == '__main__':
	main()
