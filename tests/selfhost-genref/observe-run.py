#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe each original population with an independently compiled read-only probe."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, PRIOR, COHORTS, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--version', default='baseline-v1'); a = p.parse_args()
	leaf = RUNTIME/('witness-'+a.version); leaf.mkdir(exist_ok=False)
	identity = read(a.component.with_suffix('.identity.json'))
	assert sha(a.component) == identity['sha256']
	assert all(sha(path) == value for group in ('sources', 'tools') for path, value in identity['identity'][group].items())
	# Preserve the exact observer implementation even after the engineering fix.
	for path, value in identity['identity']['sources'].items():
		source = Path(path)
		if source.is_relative_to(ROOT) and source.suffix in ('.astra', '.py'):
			target = leaf/'implementation'/source.relative_to(ROOT); target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(source.read_bytes()); assert sha(target) == value
	results = {}; references = read(PRIOR/'cohorts-v2.json')
	for name in COHORTS:
		argv = [str(a.component), *references[name]['independent_consumer']['argv'][6:]]
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=ROOT, capture_output=True, timeout=240)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		rows = [line.split() for line in r.stdout.decode().splitlines()]
		results[name] = dict(argv=argv, exit=r.returncode, start=start, end=time.monotonic(), component_sha256=sha(a.component), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')), rows=rows)
		(leaf/'result.json').write_text(json.dumps(results, indent=2)+'\n')
		assert r.returncode == 0, r.stderr.decode()[-2000:]
		print(name, '\n'+'\n'.join(' '.join(row) for row in rows if row[0] != 'KEY'), flush=True)


if __name__ == '__main__':
	main()
