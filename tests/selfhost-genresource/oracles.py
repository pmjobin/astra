#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Check new source contracts against C0 before testing the changed compiler."""
import argparse
import json
import os
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, C0, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', default='v2'); a = p.parse_args()
	assert a.version.replace('-', '').isalnum()
	leaf = RUNTIME/('oracles-'+a.version); build = BUILD/('oracles-'+a.version)
	leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False); rows = []
	for item in read(RUNTIME/('corpus-'+a.version)/'selection.json'):
		for mode in ('O0', 'O2'):
			target = build/(item['name']+'-'+mode)
			for phase, argv, expected in [('compile', [C0, '-'+mode, *[s['path'] for s in item['sources']], '-o', target], 0), ('execute', [target], item['expected_exit'])]:
				name = item['name']+'-'+mode+'-'+phase; start = time.monotonic()
				r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *map(str, argv)], cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=180)
				(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
				rows.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, expected=expected, start=start, end=time.monotonic(), sources=item['sources'], C0_sha256=sha(C0), passed=r.returncode == expected and r.stdout == r.stderr == b''))
				(leaf/'commands.json').write_text(json.dumps(rows, indent=2)+'\n')
				print(name, r.returncode, 'PASS' if rows[-1]['passed'] else 'FAILED', flush=True)
				if not rows[-1]['passed']: break
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS' if len(rows) == 48 and all(row['passed'] for row in rows) else 'INCOMPLETE', commands=rows), indent=2)+'\n')


if __name__ == '__main__':
	main()
