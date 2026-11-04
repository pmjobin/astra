#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise the existing layout-cache lifetime guard on actual Class modules."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser()
	for name in ('component', 'selection', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--case', required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	identity = json.loads(a.component.with_suffix('.identity.json').read_text())
	assert sha(a.component) == identity['sha256']
	assert all(sha(path) == value for group in ('sources', 'tools') for path,value in identity['identity'][group].items())
	rows = [row for row in json.loads(a.selection.read_text()) if row['name'] == a.case]; assert len(rows) == 1
	item = rows[0]; assert all(sha(source['path']) == source['sha256'] for source in item['sources'])
	guard_source = ROOT/'tests/ecosystem-abi-8/layout-lifetime-guard.c'; guard = a.build/'guard.so'
	flags = ['-I'+subprocess.check_output(['llvm-config', '--includedir'], text=True).strip()]
	deps = subprocess.check_output(['gcc', *flags, '-M', guard_source], text=True).replace('\\\n', ' ').split(':', 1)[1].split()
	inputs = {str(path):sha(path) for path in deps}; commands = []
	def run(argv, name, expected, negative=False):
		environment = dict(os.environ, CCACHE_DISABLE='1'); environment.pop('LD_PRELOAD', None); environment.pop('ASTRA_TEST_RETAIN_LAYOUT', None)
		if name != 'guard-build': environment['LD_PRELOAD'] = str(guard)
		if negative: environment['ASTRA_TEST_RETAIN_LAYOUT'] = '1'
		start = time.monotonic(); r = subprocess.run(list(map(str, argv)), cwd=a.build, env=environment, capture_output=True, timeout=180)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start, negative=negative)); (a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, r.stderr[-1800:]); return r
	run(['gcc', '-std=c11', '-shared', '-fPIC', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', *flags, guard_source, '-ldl', '-lLLVM', '-o', guard], 'guard-build', 0)
	argv = [a.component, '--classstorage-native-mutations', a.mode, a.build/'forbidden.o', *[source['path'] for source in item['sources']]]
	for name, negative in (('valid', False), ('retained-cache-mutant', True), ('restored', False)):
		r = run(argv, name, 97 if negative else 0, negative)
		if negative: assert b'queried cache survives context' in r.stderr
		else: assert re.search(rb'layout-guard: queries=[1-9]\d* released=[1-9]\d* contexts=[1-9]\d*', r.stderr)
		assert not (a.build/'forbidden.o').exists()
	assert all(sha(path) == value for path,value in inputs.items())
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, component_sha256=sha(a.component), source=item['sources'], guard_inputs=inputs, guard_sha256=sha(guard), valid_mutant_restored=True, limitation='Actual Class emitter module contexts and target-data caches are tested; no wider public Class ABI is qualified.'), indent=2)+'\n')
	print(a.mode, 'Class module layout-cache valid/mutant/restored lifetime controls passed')


if __name__ == '__main__':
	main()
