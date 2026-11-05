#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze C0 admission and execution before changing the independent checker."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import sys

sys.dont_write_bytecode = True
from corpus import CASES, NEGATIVES, ADDITIONS

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for name in ('compiler', 'before', 'runtime', 'build'): p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--supplemental', action='store_true')
	a = p.parse_args()
	assert sha(a.compiler) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.runtime, a.build))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	commands, rows, negatives = [], [], []
	def run(argv, name):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', a.runtime/(name+'.time'), *map(str, argv)], cwd=a.build, capture_output=True, timeout=120, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		return r
	for family, cases in (('positive', ADDITIONS if a.supplemental else CASES), ('negative', [] if a.supplemental else NEGATIVES)):
		for item in cases:
			name, declaration, entry = item[:3]; directory = a.runtime/name; directory.mkdir()
			provider = directory/'provider.astra'; provider.write_text(declaration)
			consumer = directory/'main.astra'; consumer.write_text(entry+'\n')
			sources = [ROOT/'lib/astra/collections/bag.astra', provider, consumer]
			row = dict(name=name, sources=[dict(path=str(path), sha256=sha(path), bytes=path.stat().st_size) for path in sources], C0={}, before={})
			if family == 'positive': row['expected_exit'] = item[3]
			for mode in ('O0', 'O2'):
				product = a.build/(name+'-'+mode)
				r = run([a.compiler, '-'+mode, *sources, '-o', product], name+'-'+mode+'-C0-build')
				row['C0'][mode] = dict(build_exit=r.returncode)
				if r.returncode == 0:
					r = run([product], name+'-'+mode+'-C0-execute'); row['C0'][mode].update(exit=r.returncode, stdout=r.stdout.hex(), product_sha256=sha(product), matches=family == 'positive' and r.returncode == item[3] and r.stdout == b'')
				r = run([a.before, '--classstorage-admit', mode, a.build/'unused', *sources], name+'-'+mode+'-before')
				row['before'][mode] = dict(exit=r.returncode, stdout_sha256=hashlib.sha256(r.stdout).hexdigest())
			(rows if family == 'positive' else negatives).append(row)
			(a.runtime/('observations.json' if family == 'positive' else 'negatives.json')).write_text(json.dumps(rows if family == 'positive' else negatives, indent=2)+'\n')
			print(family, name, row['C0'], flush=True)
	selected = [row for row in rows if all(v.get('matches') for v in row['C0'].values())]
	(a.runtime/'selection.json').write_text(json.dumps(selected, indent=2)+'\n')
	assert len(selected) >= (2 if a.supplemental else 12) and all(all(v['build_exit'] != 0 for v in row['C0'].values()) for row in negatives)


if __name__ == '__main__':
	main()
