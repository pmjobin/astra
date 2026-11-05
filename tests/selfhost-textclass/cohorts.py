#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare exact source cohorts with explicit repository-to-snapshot routing."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASE = 'ce7793ca133502baa73c00cd3fbbf4b8d143fd75'


def sha(data):
	return hashlib.sha256(data).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for name in ('before', 'after', 'output'): p.add_argument('--'+name, type=Path, required=True)
	a = p.parse_args(); before = json.loads(a.before.read_text()); after = json.loads(a.after.read_text())
	historical_sources = {}
	def population(data, historical=False):
		files = {row['path']:row for row in data['files']}; logical = {row['relative']:(row['bytes'], row['sha256']) for row in data['files']}
		assert len(files) == len(logical)
		for row in files.values():
			if 'synthetic_source_hex' in row:
				raw = bytes.fromhex(row['synthetic_source_hex']); assert len(raw) == row['bytes'] and sha(raw) == row['sha256']; continue;
			path = Path(row['path']); raw = path.read_bytes()
			if sha(raw) != row['sha256']:
				assert historical and path.is_relative_to(ROOT), 'unexpected changed retained input'
				raw = subprocess.check_output(['git', 'show', BASE+':'+str(path.relative_to(ROOT))], cwd=ROOT)
				historical_sources[str(path)] = dict(commit=BASE, relative=str(path.relative_to(ROOT)), sha256=sha(raw))
			assert len(raw) == row['bytes'] and sha(raw) == row['sha256']
		nodes = [[row['node'], row['syntax_kind'], files[row['path']]['relative'], row['start'], row['end'], row['source_sha256']] for row in data['nodes']]
		return files, logical, nodes
	old_files, old_logical, old_nodes = population(before, True); new_files, new_logical, new_nodes = population(after)
	assert old_logical == new_logical and old_nodes == new_nodes, 'changed population or node/source/span identity'
	# The retained live snapshot has different physical paths. The mapping is
	# explicit and content-bound; paths are never silently treated as identical.
	routing = [dict(logical=row['relative'], original_path=path, observed_path=next(name for name, other in new_files.items() if other['relative'] == row['relative']), bytes=row['bytes'], sha256=row['sha256']) for path, row in old_files.items()]
	def summary(data):
		return dict(files=len(data['files']), nodes=len(data['nodes']), typed=sum(bool(row['type']) and row['deferred'] == 0 for row in data['nodes']), dispositions=dict(Counter(row['disposition'] for row in data['nodes'])), first_stop=data['diagnostics'][0], component_sha256=data['component_sha256'])
	old, new = summary(before), summary(after)
	assert (old['first_stop']['start'], old['first_stop']['end']) == (3180, 3197)
	assert old['first_stop']['path'].endswith('/lib/astra/hosted/text-ops.astra')
	assert new['first_stop']['path'].endswith('/compiler/cfg/consume.astra') and (new['first_stop']['start'], new['first_stop']['end']) == (650, 664)
	assert new['typed'] > old['typed']
	changed = [dict(identity=key, before=dict(type=left['type'], flags=left['flags'], deferred=left['deferred']), after=dict(type=right['type'], flags=right['flags'], deferred=right['deferred'])) for key, left, right in zip(old_nodes, before['nodes'], after['nodes']) if (left['type'], left['flags'], left['deferred']) != (right['type'], right['flags'], right['deferred'])]
	result = dict(status='EXACT_COHORT_CHECKED_STOP_ADVANCED', before=old, after=new, before_ledger_sha256=sha(a.before.read_bytes()), after_ledger_sha256=sha(a.after.read_bytes()), logical_population_sha256=sha(json.dumps(old_logical, sort_keys=True).encode()), node_identity_sha256=sha(json.dumps(old_nodes, separators=(',', ':')).encode()), explicit_routing=routing, historical_live_source_blobs=historical_sources, changed_observations=changed, limitation='Typed observations and this successor stop do not qualify Flow, native execution, full compiler-source safety or Stage 1. Native source-span witnesses and independent pipeline evidence remain separate.')
	with a.output.open('x') as out: out.write(json.dumps(result, indent=2)+'\n')
	print(old['files'], 'exact logical source paths;', old['typed'], '->', new['typed'], 'typed observations; successor d.functions[f] remains DEFERRED')


if __name__ == '__main__':
	main()
