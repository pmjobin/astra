#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze authored sources and C0 stages before the FLOWSEM implementation."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
from corpus import cases, materialize


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False)
	entries = []
	for item in cases():
		leaf = a.runtime/item['name']
		leaf.mkdir()
		files, marks = materialize(item['files'])
		for name, data in files.items():
			(leaf/name).write_bytes(data)
		entries.append(dict(item, paths=[str(leaf/n) for n in files], marks={tag:(str(leaf/name), s, e) for tag,(name,s,e) in marks.items()}, sha256={str(leaf/n):hashlib.sha256(data).hexdigest() for n,data in files.items()}))
	(a.runtime/'frozen.json').write_text(json.dumps(entries, indent=2)+'\n')
	(a.runtime/'compiler.json').write_text(json.dumps(dict(path=str(a.compiler), sha256=hashlib.sha256(a.compiler.read_bytes()).hexdigest()), indent=2)+'\n')
	rows, mismatches = [], []
	for item in entries:
		for stage in ('--parse', '--check', '--tooling-index'):
			argv = [str(a.compiler), stage, *item['paths']]
			start = time.monotonic()
			r = subprocess.run(argv, capture_output=True)
			leaf = a.runtime/item['name']
			(leaf/(stage+'.stdout')).write_bytes(r.stdout)
			(leaf/(stage+'.stderr')).write_bytes(r.stderr)
			rows.append(dict(argv=argv, exit=r.returncode, seconds=time.monotonic()-start))
			if stage=='--parse' and r.returncode:
				mismatches.append((item['name'], 'syntax', r.stderr.decode()))
			if stage=='--check' and bool(r.returncode)!=bool(item.get('error') or item.get('c0_reject')):
				mismatches.append((item['name'], 'classification', r.stderr.decode()))
		print(item['name'], [(r['argv'][1],r['exit']) for r in rows[-3:]], flush=True)
	(a.runtime/'commands.json').write_text(json.dumps(rows, indent=2)+'\n')
	(a.runtime/'mismatches.json').write_text(json.dumps(mismatches, indent=2)+'\n')
	assert not mismatches, mismatches


if __name__=='__main__':
	main()
