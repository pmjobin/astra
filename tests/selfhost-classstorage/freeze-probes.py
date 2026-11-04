#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze additional C0 runtime observers with their actual later test phase."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

sys.dont_write_bytecode = True
from corpus import RUNTIME_PROBES

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for name in ('compiler', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True)
	a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	assert sha(a.compiler) == a.compiler_sha256
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	commands, rows = [], []
	def run(argv, name):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], cwd=a.build, capture_output=True, timeout=180, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == 0, (name, r.returncode, r.stderr[-1800:]); return r
	for name, texts in RUNTIME_PROBES.items():
		sources = []
		for ordinal, text in enumerate(texts):
			if text == '@bag': sources.append(ROOT/'lib/astra/collections/bag.astra'); continue
			source = a.runtime/(name+'-'+str(ordinal)+'.astra'); source.write_text(text+'\n'); sources.append(source)
		identities = [dict(path=str(source), sha256=sha(source), bytes=source.stat().st_size) for source in sources]
		run([a.compiler, '--parse', *sources], name+'-parse'); run([a.compiler, '--check', *sources], name+'-check')
		profiles = {}
		for mode in ('O0', 'O2'):
			product = a.build/(name+'-'+mode); run([a.compiler, '-'+mode, *sources, '-o', product], name+'-'+mode+'-build')
			r = run([product], name+'-'+mode+'-execute'); assert r.stdout == r.stderr == b''
			profiles[mode] = dict(matches_expected=True, product_sha256=sha(product))
		assert all(sha(source['path']) == source['sha256'] for source in identities)
		rows.append(dict(name=name, sources=identities, expected_exit=0, compiler_sha256=sha(a.compiler), profiles=profiles, freeze_phase='AFTER_IMPLEMENTATION_RUNTIME_OBSERVER; not a replacement for the original preimplementation population'))
		(a.runtime/'selection.json').write_text(json.dumps(rows, indent=2)+'\n'); print(name, 'C0 O0/O2 normal controls frozen', flush=True)


if __name__ == '__main__':
	main()
