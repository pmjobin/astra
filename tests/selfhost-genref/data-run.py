#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Retain raw four-cohort reference facts without confusing them with admission."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, PRIOR, COHORTS, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--version', required=True); p.add_argument('--full-cli', action='store_true'); p.add_argument('--mode', default='O0'); a = p.parse_args()
	leaf = RUNTIME/('data-'+a.version); leaf.mkdir(exist_ok=False)
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == value for group in ('sources', 'tools') for path, value in identity['identity'][group].items())
	for path, expected in identity['identity']['sources'].items():
		source = Path(path)
		if source.is_relative_to(ROOT) and source.suffix in ('.astra', '.py'):
			target = leaf/'implementation'/source.relative_to(ROOT); target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(source.read_bytes()); assert sha(target) == expected
	results = {}; references = read(PRIOR/'cohorts-v2.json')
	for name in COHORTS:
		inputs = references[name]['independent_consumer']['argv'][6:]
		prefix = [str(a.component), '--classstorage-genref-data', a.mode, str(leaf/'unused')] if a.full_cli else [str(a.component)]
		argv = [*prefix, *inputs]; start = time.monotonic()
		with (leaf/(name+'.stdout')).open('xb') as out, (leaf/(name+'.stderr')).open('xb') as err:
			r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=ROOT, stdout=out, stderr=err, timeout=240)
		universe = next((line.split()[1:] for line in (leaf/(name+'.stdout')).open() if line.startswith('UNIVERSE ')), None)
		results[name] = dict(argv=argv, exit=r.returncode, start=start, end=time.monotonic(), component_sha256=sha(a.component), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')), universe=universe, population_sha256=references[name]['population_sha256'], node_identity_sha256=references[name]['node_identity_sha256'])
		(leaf/'result.json').write_text(json.dumps(results, indent=2)+'\n')
		assert r.returncode == 0, (leaf/(name+'.stderr')).read_text()[-2000:]
		print(name, 'UNIVERSE', universe, flush=True)


if __name__ == '__main__':
	main()
