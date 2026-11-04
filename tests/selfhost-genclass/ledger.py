#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare exact parsed identities; typed observations never imply admission."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path


def keys(ledger):
	return [[node[key] for key in ('node', 'syntax_kind', 'start', 'end', 'source_sha256')] for node in ledger['nodes']]


def identity(rows):
	return hashlib.sha256(''.join(json.dumps(row, separators=(',', ':'))+'\n' for row in rows).encode()).hexdigest()


def summary(ledger):
	return dict(files=len(ledger['files']), nodes=len(ledger['nodes']), observed_types=sum(bool(row['type']) and row['deferred'] == 0 for row in ledger['nodes']), dispositions=dict(Counter(row['disposition'] for row in ledger['nodes'])), first_stop=next(iter(ledger['diagnostics']), None), component_sha256=ledger['component_sha256'])


def main():
	p = argparse.ArgumentParser()
	for name in ('before', 'after', 'output'):
		p.add_argument('--'+name, type=Path, required=True)
	a = p.parse_args(); before = json.loads(a.before.read_text()); after = json.loads(a.after.read_text())
	old, new = keys(before), keys(after); assert old == new, 'changed input population or parsed identities'
	old_files = {row['path']:(row['bytes'], row['sha256']) for row in before['files']}; new_files = {row['path']:(row['bytes'], row['sha256']) for row in after['files']}; assert old_files == new_files
	changes = [dict(identity=key, before=dict(type=b['type'], flags=b['flags'], deferred=b['deferred']), after=dict(type=c['type'], flags=c['flags'], deferred=c['deferred'])) for key, b, c in zip(old, before['nodes'], after['nodes']) if (b['type'], b['flags'], b['deferred']) != (c['type'], c['flags'], c['deferred'])]
	result = dict(format='astra-genclass-source-comparison/1', exact_input_identity_sha256=identity(old), before=summary(before), after=summary(after), changed_observations=changes, limitation='Only source/kind/span/hash identities and observed checked uses are compared. Unvisited nodes remain unproved. Separate source-to-ELF witnesses are required for Flow/IR/LLVM/native claims; this is not compiler-source safety or Stage 1.')
	with a.output.open('x') as out: out.write(json.dumps(result, indent=2)+'\n')
	print(result['before']['files'], 'exact files;', result['before']['observed_types'], '->', result['after']['observed_types'], 'typed observations;', len(changes), 'changed observations')
	print(result['after']['first_stop'])


if __name__ == '__main__':
	main()
