#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze C0 source behavior before changing generic Class admission."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import sys

sys.dont_write_bytecode = True
from corpus import CASES, ALTERNATE, CROSS, SUPPLEMENTAL

ROOT = Path(__file__).resolve().parents[2]
VECTOR_SHA = '6ef070ea2267eae238cb712e032af40c7375b686ae44bf65ae185fdcb0d14bcb'


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for name in ('compiler', 'runtime', 'build', 'before'):
		p.add_argument('--'+name, required=True, type=Path)
	p.add_argument('--supplemental', action='store_true', help='Later controls, kept distinct from the preimplementation freeze')
	a = p.parse_args()
	assert sha(a.compiler) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'
	assert not a.runtime.resolve().is_relative_to(ROOT) and not a.build.resolve().is_relative_to(ROOT)
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	vector = ROOT/'lib/astra/collections/vector.astra'; assert sha(vector) == VECTOR_SHA
	commands, rows = [], []
	def run(argv, name):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', *map(str, argv)], cwd=a.build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=120)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		return r
	for name, declarations, entry, expected in (SUPPLEMENTAL if a.supplemental else [*CASES, ALTERNATE, CROSS]):
		directory = a.runtime/name; directory.mkdir()
		library = vector
		if name == ALTERNATE[0]:
			library = directory/'sequence.astra'; library.write_text(vector.read_text().replace('class Vector<T>', 'class Sequence<T>'))
		if name == CROSS[0]:
			provider = directory/'provider.astra'; provider.write_text(declarations)
			consumer = directory/'consumer.astra'; consumer.write_text(entry+'\n'); sources = [library, provider, consumer]
		else:
			source = directory/'main.astra'; source.write_text(declarations+entry+'\n'); sources = [library, source]
		row = dict(name=name, sources=[dict(path=str(path), sha256=sha(path), bytes=path.stat().st_size) for path in sources], expected_exit=expected, C0={}, before={})
		for mode in ('O0', 'O2'):
			product = a.build/(name+'-'+mode)
			r = run([a.compiler, '-'+mode, *sources, '-o', product], name+'-'+mode+'-C0-build')
			row['C0'][mode] = dict(build_exit=r.returncode)
			if r.returncode == 0:
				r = run([product], name+'-'+mode+'-C0-execute')
				row['C0'][mode].update(exit=r.returncode, stdout=r.stdout.hex(), product_sha256=sha(product), matches=r.returncode == expected and r.stdout == b'')
			r = run([a.before, '--classstorage-admit', mode, a.build/'unused', *sources], name+'-'+mode+'-before')
			row['before'][mode] = dict(exit=r.returncode, stdout_sha256=hashlib.sha256(r.stdout).hexdigest())
		rows.append(row); (a.runtime/'observations.json').write_text(json.dumps(rows, indent=2)+'\n')
		print(name, row['C0'], flush=True)
	selected = [row for row in rows if all(value.get('matches') for value in row['C0'].values())]
	(a.runtime/'selection.json').write_text(json.dumps(selected, indent=2)+'\n')
	print(len(selected), '/', len(rows), 'C0-admitted; failures retained')


if __name__ == '__main__':
	main()
