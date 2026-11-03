#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Replay original proof inputs with six freshly source-bound query products."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import time


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for key in ('baseline', 'flow', 'types', 'binder', 'runtime'):
		p.add_argument('--'+key, type=Path, required=True)
	a = p.parse_args()
	root = Path(__file__).resolve().parents[2]
	assert not a.runtime.resolve().is_relative_to(root)
	a.runtime.mkdir(parents=True, exist_ok=False)
	old = json.loads((a.baseline/'observations.json').read_text())
	inputs = json.loads((a.baseline/'inputs.json').read_text())
	ledger = a.baseline/'historical-ledger.json'
	assert len(old) == 1044 and sha(ledger) == '0c3cd736633caac2aa264c525e9d8c47e4e64d6b9d25f1eeef52605e18dbc2a3'
	assert all(sha(path) == digest for path, digest in inputs.items())
	products = {}
	for directory, prefix in ((a.flow, 'astra-flow-'), (a.types, 'astra-types-'), (a.binder, 'astra-bind-')):
		for mode in ('O0', 'O2'):
			exe = directory/(prefix+mode)
			identity_path = exe.with_suffix('.identity.json')
			identity = json.loads(identity_path.read_text())
			assert sha(exe) == identity['sha256']
			assert all(sha(path) == digest for path, digest in identity['identity']['sources'].items())
			assert all(sha(path) == digest for path, digest in identity['identity']['tools'].items())
			products[exe.name] = dict(path=str(exe), sha256=sha(exe), identity_sha256=sha(identity_path))
	results = []
	for index, item in enumerate(old):
		exe = products[Path(item['argv'][0]).name]
		argv = [exe['path'], *item['argv'][1:]]
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(str(index)+'.time')), *argv], capture_output=True, timeout=60)
		(a.runtime/(str(index)+'.stdout')).write_bytes(r.stdout)
		(a.runtime/(str(index)+'.stderr')).write_bytes(r.stderr)
		row = dict(group=item['group'], name=item['name'], historical_argv=item['argv'], argv=argv,
			exit=r.returncode, stdout_sha256=hashlib.sha256(r.stdout).hexdigest(),
			monotonic_start=start, monotonic_end=time.monotonic())
		results.append(row)
		(a.runtime/'observations.json').write_text(json.dumps(results, indent=2)+'\n')
		assert (row['exit'], row['stdout_sha256']) == (item['exit'], item['stdout_sha256']), (index, item['group'], item['name'])
	assert all(sha(path) == digest for path, digest in inputs.items())
	(a.runtime/'historical-ledger.json').write_bytes(ledger.read_bytes())
	(a.runtime/'products.json').write_text(json.dumps(products, indent=2)+'\n')
	(a.runtime/'inputs.json').write_text(json.dumps(inputs, indent=2)+'\n')
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', observations=len(results),
		groups=dict(Counter(x['group'] for x in results)), original_closures=82, new_proofs=9,
		ledger_sha256=sha(ledger), baseline_sha256=sha(a.baseline/'observations.json')), indent=2)+'\n')
	print('PASS', len(results), 'original observations; six current source-bound products')


if __name__ == '__main__':
	main()
