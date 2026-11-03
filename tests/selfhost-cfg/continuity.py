#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Replay source-exact predecessor queries without rebuilding unchanged stages."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time


def sha(p):
	return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for key in ('predecessor', 'runtime'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--auxiliary-only', action='store_true')
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=True)
	inventories = [*(a.predecessor/'continuity-replay').glob('*/commands.json'), a.predecessor/'ownflow-regression/commands.json', a.predecessor/'semadmit-original-paths/commands.json']
	products = {}
	observations = []
	for inventory in inventories:
		group = inventory.parent.name
		leaf = a.runtime/group
		leaf.mkdir(exist_ok=True)
		count = 0
		for index, item in enumerate(json.loads(inventory.read_text())):
			argv = item['argv']
			# Replay only native read-only queries, not builds, tools or memory runs.
			if not Path(argv[0]).name.startswith('astra-') or len(argv) < 2 or not argv[1].startswith('--'): continue
			exe = Path(argv[0])
			if str(exe) not in products:
				identity = exe.with_suffix('.identity.json')
				x = json.loads(identity.read_text())
				assert sha(exe) == x['sha256']
				assert all(sha(path) == h for path,h in x['identity']['sources'].items())
				assert all(sha(path) == h for path,h in x['identity']['tools'].items())
				products[str(exe)] = dict(sha256=sha(exe), identity_sha256=sha(identity))
			mapped = {}
			for arg in argv:
				if arg.endswith('.astra') and not Path(arg).exists():
					assert '/runtime/native-current/coreir9/' in arg
					actual = str(a.predecessor/arg.split('/runtime/native-current/coreir9/', 1)[1])
					assert Path(actual).is_file()
					mapped[arg] = actual
			if a.auxiliary_only != bool(mapped): continue
			actual_argv = [mapped.get(arg, arg) for arg in argv]
			start = time.monotonic()
			r = subprocess.run(actual_argv, capture_output=True)
			name = item.get('name', str(index))
			previous = inventory.parent/(name+'.stdout')
			expected_hash = item.get('stdout_sha256', sha(previous) if previous.exists() else None)
			assert expected_hash is not None
			normalized = r.stdout
			for original, actual in mapped.items():
				normalized = normalized.replace(actual.encode(), original.encode()).replace(actual.encode().hex().encode(), original.encode().hex().encode())
			actual_hash = hashlib.sha256(normalized).hexdigest()
			assert r.returncode == item['exit'] and actual_hash == expected_hash, (group, name, r.returncode)
			(leaf/(name+'.stdout')).write_bytes(r.stdout)
			(leaf/(name+'.stderr')).write_bytes(r.stderr)
			observations.append(dict(group=group, name=name, argv=actual_argv, historical_argv=argv, path_normalization=mapped, exit=r.returncode, normalized_stdout_sha256=actual_hash, stdout_sha256=hashlib.sha256(r.stdout).hexdigest(), monotonic_start=start, monotonic_end=time.monotonic()))
			count += 1
		print(group, count, 'exact observations', flush=True)
		(a.runtime/'observations.json').write_text(json.dumps(observations, indent=2)+'\n')
	(a.runtime/'products.json').write_text(json.dumps(products, indent=2)+'\n')
	# Proof identities remain byte-exact; path-qualified closures are not renamed.
	ledger = json.loads((a.predecessor/'historical-original-identity-ledger.json').read_text())
	current = json.loads((a.predecessor/'semadmit-original-paths/summary.json').read_text())
	assert ledger == current and ledger['original_closures'] == 82
	(a.runtime/'historical-ledger.json').write_bytes((a.predecessor/'historical-original-identity-ledger.json').read_bytes())


if __name__ == '__main__':
	main()
