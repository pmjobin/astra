#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Retain independent C0 and unchanged-compiler outcomes for every draft source."""
import argparse
import json
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, C0, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', default='v2'); a = p.parse_args()
	leaf = RUNTIME/('source-probe-'+a.version); leaf.mkdir(exist_ok=False); results = []
	component = read(PRIOR/'final-audit.json')['products']['O0']['path']
	for item in read(RUNTIME/('corpus-'+a.version)/'selection.json'):
		row = dict(name=item['name'], sources=item['sources'], commands=[])
		for label, argv in [('C0-syntax', [C0, '--dump-syntax']), ('C0-check', [C0, '--check']), ('native', [component, '--classstorage-admit', 'O0', BUILD/'unused'])]:
			argv = [*map(str, argv), *[s['path'] for s in item['sources']]]; name = item['name']+'-'+label
			start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=BUILD, capture_output=True, timeout=180)
			(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
			row['commands'].append(dict(label=label, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
			print(name, r.returncode, r.stderr.decode()[-600:], flush=True)
		results.append(row); (leaf/'results.json').write_text(json.dumps(results, indent=2)+'\n')


if __name__ == '__main__':
	main()
