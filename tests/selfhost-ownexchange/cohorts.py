#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare immutable source/node/span populations and actual checked frontiers."""
import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
from state import RUNTIME, PRIOR, read, sha


def digest(value):
	return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); a = p.parse_args()
	results = {}
	for name in ('original', 'LLVM23-base', 'Class15-current', 'live-initial'):
		old_path = PRIOR/('ledger-v5-'+name)/'ledger.json'; new_path = RUNTIME/('ledger-'+a.version+'-'+name)/'ledger.json'; old = read(old_path); new = read(new_path)
		def population(data):
			files = {row['path']: row for row in data['files']}; logical = {row['relative']: (row['bytes'], row['sha256']) for row in data['files']}
			for row in data['files']:
				if 'synthetic_source_hex' in row: assert hashlib.sha256(bytes.fromhex(row['synthetic_source_hex'])).hexdigest() == row['sha256']
				else: assert sha(row['path']) == row['sha256']
			return logical, [[row['node'], row['syntax_kind'], files[row['path']]['relative'], row['start'], row['end'], row['source_sha256']] for row in data['nodes']]
		old_files, old_nodes = population(old); new_files, new_nodes = population(new); assert old_files == new_files and old_nodes == new_nodes
		assert (old['diagnostics'][0]['start'], old['diagnostics'][0]['end']) == (3589, 3614)
		def summary(data): return dict(files=len(data['files']), nodes=len(data['nodes']), typed=sum(bool(row['type']) and row['deferred'] == 0 for row in data['nodes']), dispositions=dict(Counter(row['disposition'] for row in data['nodes'])), first_stop=data['diagnostics'][0] if data['diagnostics'] else None, component_sha256=data['component_sha256'])
		results[name] = dict(before=summary(old), after=summary(new), population_sha256=digest(old_files), node_identity_sha256=digest(old_nodes), before_ledger=dict(path=str(old_path), sha256=sha(old_path)), after_ledger=dict(path=str(new_path), sha256=sha(new_path)), changed_observations=[dict(identity=identity, before=[left['type'], left['flags'], left['deferred']], after=[right['type'], right['flags'], right['deferred']]) for identity, left, right in zip(old_nodes, old['nodes'], new['nodes']) if (left['type'], left['flags'], left['deferred']) != (right['type'], right['flags'], right['deferred'])])
		print(name, results[name]['before']['typed'], '->', results[name]['after']['typed'], results[name]['after']['first_stop'])
	(RUNTIME/('cohort-comparison-'+a.version+'.json')).write_text(json.dumps(dict(status='IDENTICAL_SOURCE_NODE_SPAN_POPULATIONS', cohorts=results, limitation='Typed observations and copier advancement do not establish whole-source Flow/native safety. The final-live population is separate.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
