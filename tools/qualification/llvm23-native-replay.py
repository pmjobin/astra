#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Replay the inherited LLVM corpus with an explicitly pinned independent oracle."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for name in ('compiler', 'component', 'build', 'runtime', 'legacy', 'additional', 'generics'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True)
	p.add_argument('--mode', action='append', choices=('O0', 'O2'))
	a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	assert not os.environ.get('LD_PRELOAD'), 'qualification must use the clean emitter'
	assert sha(a.compiler) == a.compiler_sha256
	a.runtime.mkdir(parents=True, exist_ok=False)
	a.build.mkdir(parents=True, exist_ok=True)
	commands, profiles = [], {}
	families = [('legacy', 'selfhost-llvm/run.py', a.legacy, 24), ('additions', 'selfhost-nativeabi/run.py', a.additional, 15), ('generics', 'selfhost-generics/run.py', a.generics, 13)]
	for mode in a.mode or ('O0', 'O2'):
		cases = []
		for name, script, frozen, count in families:
			leaf = name+'-'+mode
			argv = [sys.executable, '-B', ROOT/'tests'/script, '--component', a.component, '--compiler', a.compiler, '--compiler-sha256', a.compiler_sha256, '--mode', mode, '--build', a.build/leaf, '--runtime', a.runtime/leaf, '--frozen', frozen]
			start = time.monotonic()
			with (a.runtime/(leaf+'.log')).open('x') as log:
				r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(leaf+'.time')), *map(str, argv)], stdout=log, stderr=subprocess.STDOUT, cwd=ROOT, env=dict(os.environ, CCACHE_DISABLE='1'))
			commands.append(dict(name=leaf, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic(), frozen_selection_sha256=sha(frozen/'selection.json')))
			(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
			print(leaf, r.returncode, flush=True)
			assert r.returncode == 0, str(a.runtime/(leaf+'.log'))
			result = json.loads((a.runtime/leaf/'result.json').read_text())
			assert result['status'] == 'PASS' and len(result['cases']) == count
			for row in result['cases']:
				sources = row['sources'] if 'sources' in row else [dict(path=row['source_path'], sha256=row['source_sha256'])]
				assert row['c0_sha256'] == a.compiler_sha256
				cases.append(dict(name=row['name'], sources=sources, result=str(a.runtime/leaf/'result.json'), products=row['products']))
		assert len(cases) == len({tuple(x['sha256'] for x in row['sources']) for row in cases}) == 52
		profiles[mode] = cases
	if len(profiles) == 2:
		assert {tuple(x['sha256'] for x in row['sources']) for row in profiles['O0']} == {tuple(x['sha256'] for x in row['sources']) for row in profiles['O2']}
	result = dict(status='PASS', scope='52 inherited program identities per selected object profile; not Class-storage qualification', profiles=profiles, commands=commands, compiler_sha256=a.compiler_sha256, component_sha256=sha(a.component), component_identity_sha256=sha(a.component.with_suffix('.identity.json')))
	(a.runtime/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print('PASS: inherited native ELF, independent C0, ABI, LLVM and unsuppressed Valgrind replay')


if __name__ == '__main__':
	main()
