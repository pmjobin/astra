#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare immutable populations without treating typed counts as safety proofs."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from state import read, sha


def digest(value):
	return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for name in ('before', 'after', 'output'): p.add_argument('--'+name, type=Path, required=True)
	a = p.parse_args(); before, after = read(a.before), read(a.after)
	def population(data):
		files = {row['path']: row for row in data['files']}
		logical = {row['relative']: (row['bytes'], row['sha256']) for row in data['files']}
		assert len(files) == len(logical)
		for row in data['files']:
			if 'synthetic_source_hex' in row:
				assert hashlib.sha256(bytes.fromhex(row['synthetic_source_hex'])).hexdigest() == row['sha256']
			else: assert sha(row['path']) == row['sha256'], row['path']
		nodes = [[row['node'], row['syntax_kind'], files[row['path']]['relative'], row['start'], row['end'], row['source_sha256']] for row in data['nodes']]
		return logical, nodes
	old_files, old_nodes = population(before); new_files, new_nodes = population(after)
	assert old_files == new_files and old_nodes == new_nodes, 'source/content/node/span population drift'
	def summary(data):
		return dict(files=len(data['files']), nodes=len(data['nodes']), typed=sum(bool(row['type']) and row['deferred'] == 0 for row in data['nodes']), dispositions=dict(Counter(row['disposition'] for row in data['nodes'])), first_stop=data['diagnostics'][0] if data['diagnostics'] else None, component_sha256=data['component_sha256'])
	old, new = summary(before), summary(after)
	published_population = hashlib.sha256(json.dumps(old_files, sort_keys=True).encode()).hexdigest()
	if (old['files'], old['nodes']) == (79, 174297):
		assert published_population == 'c427a74274afe6c43e192b3edc8a53eda43ee5e46ab531b53370f05c95d010bb' and digest(old_nodes) == '67651afad342c91323de7554656e9e6a2d653a71f46cb50d1bcf479797bca8ae'
	assert old['first_stop']['path'].endswith('/compiler/cfg/consume.astra') and (old['first_stop']['start'], old['first_stop']['end']) == (650, 664)
	changed = [dict(identity=identity, before={k: left[k] for k in ('type', 'flags', 'deferred')}, after={k: right[k] for k in ('type', 'flags', 'deferred')}) for identity, left, right in zip(old_nodes, before['nodes'], after['nodes']) if (left['type'], left['flags'], left['deferred']) != (right['type'], right['flags'], right['deferred'])]
	result = dict(status='IDENTICAL_POPULATION_COMPARED', before=old, after=new, before_ledger=dict(path=str(a.before), sha256=sha(a.before)), after_ledger=dict(path=str(a.after), sha256=sha(a.after)), logical_population_sha256=published_population, population_serialization='Predecessor json.dumps(sort_keys=True), default separators', compact_population_sha256=digest(old_files), node_identity_sha256=digest(old_nodes), changed_observations=changed, limitation='The complete source population remains unqualified. Counts are checked observations, not runtime or safety percentages. Only the separate exact original-operation native witness can establish qualified execution.')
	a.output.write_text(json.dumps(result, indent=2)+'\n'); print(old['files'], old['nodes'], old['typed'], '->', new['typed'], new['first_stop'])


if __name__ == '__main__':
	main()
