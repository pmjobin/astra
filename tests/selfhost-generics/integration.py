#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Uncounted combined controls, real capability operators and unit orderings."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def keys(data):
	return sorted(line.split(' generic-v1:', 1)[1].split(' SIGNATURE ', 1)[0] for line in data.decode().splitlines() if line.startswith('INSTANCE '))


def symbols(path):
	return set(re.findall(r'\b(astra\.g\.[a-f0-9]+)\b', Path(path).read_text()))


def main():
	p = argparse.ArgumentParser()
	for name in ('component', 'compiler', 'before', 'build', 'runtime', 'frozen', 'primary'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	frozen = a.runtime/'frozen'; frozen.mkdir()
	move = frozen/'method-owner-move.astra'
	move.write_text('class Echo<T>{init(){} T echo(T value){return value;}} int main(){var first=new Echo<int>();owned Echo<int> last=move first;return last.echo(43)-43;}\n')
	cross = next(item for item in json.loads((a.frozen/'selection.json').read_text()) if item['name'] == 'cross-unit')
	items = [dict(name=name, sources=[dict(path=str(path), sha256=sha(path)) for path in sources], expected_exit=0, expected_stdout='', expected_stderr='') for name, sources in [
		('control', [ROOT/'tests/selfhost-generics/fixtures/control.astra']),
		('method-owner-move', [move]),
		('explicit-capabilities', [ROOT/'tests/gen-infer/fixtures/explicit-capabilities.astra']),
		('cross-unit-reordered', [Path(source['path']) for source in reversed(cross['sources'])]),
	]]
	commands = []
	for item in items:
		sources = [source['path'] for source in item['sources']]
		for name, argv, expected in [('parse', [a.compiler, '--parse', *sources], (0,)), ('check', [a.compiler, '--check', *sources], (0,)), ('before', [a.before, '--nativeabi-admit', a.mode, a.build/'unused', *sources], (1, 3))]:
			start = time.monotonic(); r = subprocess.run(list(map(str, argv)), cwd=a.build, capture_output=True, timeout=180)
			stem = item['name']+'-'+name
			(a.runtime/(stem+'.stdout')).write_bytes(r.stdout); (a.runtime/(stem+'.stderr')).write_bytes(r.stderr)
			commands.append(dict(name=stem, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
			(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
			assert r.returncode in expected, (stem, r.returncode, r.stdout[:1000], r.stderr[:1000])
			if name == 'before': assert b'CHECKED_ERROR ' in r.stdout or b'DEFER ' in r.stdout
	(frozen/'selection.json').write_text(json.dumps(items, indent=2)+'\n')
	argv = [sys.executable, '-B', str(Path(__file__).with_name('run.py')), '--component', str(a.component), '--compiler', str(a.compiler), '--build', str(a.build/'execute'), '--runtime', str(a.runtime/'execute'), '--frozen', str(frozen), '--mode', a.mode]
	for item in items: argv += ['--case', item['name']]
	subprocess.run(argv, check=True, cwd=ROOT)
	original = (a.primary/'cross-unit-instances.stdout').read_bytes()
	reordered = (a.runtime/'execute/cross-unit-reordered-instances.stdout').read_bytes()
	assert len(keys(original)) == 1 and keys(original) == keys(reordered)
	primary = json.loads((a.primary/'results.json').read_text())
	old = next(item for item in primary if item['name'] == 'cross-unit')
	new = next(item for item in json.loads((a.runtime/'execute/results.json').read_text()) if item['name'] == 'cross-unit-reordered')
	assert symbols(old['products']['raw']['path']) == symbols(new['products']['raw']['path'])
	assert all(sha(source['path']) == source['sha256'] for item in items for source in item['sources'])
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, cases=items, counted_toward_minimum=False, ordering_same_keys=keys(original), exact_private_symbols=True, semantic_limit='The Class move is independently C0-admitted. C0 diagnostics about aliases also mention moves, but the explicit move path is separately accepted; no diagnostic wording substitutes for execution.'), indent=2)+'\n')
	print(a.mode, 'combined, Class-move, capability and reversed-unit controls PASS; no duplicate counting')


if __name__ == '__main__':
	main()
