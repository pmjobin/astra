#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh replay of the exact 1,044 predecessor proof/query observations."""
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
	for key in ('predecessor', 'runtime'):
		p.add_argument('--'+key, type=Path, required=True)
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False)
	products = {}
	results = []
	inputs = {}
	for group in ('continuity-resolved', 'continuity-auxiliary'):
		items = json.loads((a.predecessor/group/'observations.json').read_text())
		for index, item in enumerate(items):
			argv = item['argv']
			exe = Path(argv[0])
			if str(exe) not in products:
				identity = exe.with_suffix('.identity.json')
				x = json.loads(identity.read_text())
				assert sha(exe) == x['sha256']
				assert all(sha(path) == h for path, h in x['identity']['sources'].items())
				assert all(sha(path) == h for path, h in x['identity']['tools'].items())
				products[str(exe)] = dict(sha256=sha(exe), identity_sha256=sha(identity))
			for arg in argv[1:]:
				if arg.endswith('.astra'):
					inputs[arg] = sha(arg)
			start = time.monotonic()
			r = subprocess.run(argv, capture_output=True)
			assert r.returncode == item['exit'] and hashlib.sha256(r.stdout).hexdigest() == item['stdout_sha256'], (group, index, item['name'])
			name = group+'-'+str(index)
			(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
			(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
			results.append(dict(group=item['group'], name=item['name'], argv=argv, exit=r.returncode, stdout_sha256=hashlib.sha256(r.stdout).hexdigest(), monotonic_start=start, monotonic_end=time.monotonic()))
			(a.runtime/'observations.json').write_text(json.dumps(results, indent=2)+'\n')
	assert len(results) == 1044
	assert all(sha(path) == h for path, h in inputs.items())
	ledger = a.predecessor/'continuity-resolved/historical-ledger.json'
	x = json.loads(ledger.read_text())
	assert x['original_closures'] == 82
	assert sum(len(i['new_proofs']) for i in x['ledger']) == 9
	(a.runtime/'historical-ledger.json').write_bytes(ledger.read_bytes())
	(a.runtime/'products.json').write_text(json.dumps(products, indent=2)+'\n')
	(a.runtime/'inputs.json').write_text(json.dumps(inputs, indent=2)+'\n')
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', observations=len(results), groups=dict(Counter(x['group'] for x in results)), original_closures=82, new_proofs=9, ledger_sha256=sha(ledger)), indent=2)+'\n')
	print('PASS', len(results), 'source-bound observations', flush=True)


if __name__ == '__main__':
	main()
