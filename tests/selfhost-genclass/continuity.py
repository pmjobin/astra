#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Preserve original receipts, resolving historical live paths through Git."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
GEN14 = ROOT.parent/'codex/work/astra/runtime/generics14'
CLASS15 = ROOT.parent/'codex/work/astra/runtime/classstorage15/resume-llvm23-v1'
GEN14_HEAD = '7b8fea49cdd3b3b8bb284d4299a12d31b01ba682'


def digest(data):
	return hashlib.sha256(data).hexdigest()


def read(path):
	return json.loads(Path(path).read_text())


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--output', required=True, type=Path)
	a = p.parse_args(); assert not a.output.resolve().is_relative_to(ROOT)
	verified, reconciled = {}, {}
	def verify(path, expected):
		path = Path(path); raw = path.read_bytes(); actual = digest(raw)
		if actual != expected:
			assert path.is_relative_to(ROOT), (path, expected, actual)
			name = str(path.relative_to(ROOT)); historical = subprocess.check_output(['git', 'show', GEN14_HEAD+':'+name], cwd=ROOT)
			assert digest(historical) == expected, (path, 'no exact historical source identity')
			reconciled[str(path)] = dict(historical_commit=GEN14_HEAD, historical_sha256=expected, current_sha256=actual, reason='Historical ledger named the then-live compiler source. The original Git blob is verified; current feature changes are separate.')
		verified[str(path)] = expected
	def walk(value):
		if isinstance(value, dict):
			if value.get('path') and value.get('sha256'): verify(value['path'], value['sha256'])
			if value.get('source_path') and value.get('source_sha256'): verify(value['source_path'], value['source_sha256'])
			for child in value.values(): walk(child)
		elif isinstance(value, list):
			for child in value: walk(child)
	profiles = {}
	for mode in ('O0', 'O2'):
		programs = []
		for family in ('old-v6-'+mode+'/legacy', 'old-v6-'+mode+'/additions', 'new-v6-'+mode):
			path = GEN14/family/'result.json'; data = read(path); assert data['status'] == 'PASS'; walk(data); verified[str(path)] = digest(path.read_bytes())
			for case in data['cases']:
				sources = case.get('sources', [dict(path=case.get('source_path'), sha256=case.get('source_sha256'))]); programs.append(dict(name=case['name'], sources=sources, role='inherited'))
		assert len(programs) == 52
		path = GEN14/('old-v6-'+mode)/'continuity/result.json'; statuses = read(path); assert sum(statuses['outcomes'].values()) == 80; verified[str(path)] = digest(path.read_bytes())
		old = read(CLASS15/('native-corpus-v4-'+mode)/'results.json'); assert len(old) == 23 and all(row['baseline_complete'] for row in old); walk(old)
		late = read(CLASS15/'frozen-runtime-probes-v2/selection.json'); late_keys = {tuple(source['sha256'] for source in row['sources']) for row in late}; assert len(late_keys) == 4
		for row in old:
			key = tuple(source['sha256'] for source in row['sources']); programs.append(dict(name=row['name'], sources=row['sources'], role='late-observer' if key in late_keys else 'frozen-Class'))
		assert Counter(row['role'] for row in programs) == {'inherited':52, 'frozen-Class':19, 'late-observer':4}
		for leaf in ['mutations-v4-'+mode, 'negative-v4b-O0' if mode == 'O0' else 'negative-v4-O2', 'source-continuity-v4-'+mode]:
			path = CLASS15/leaf/'result.json'; data = read(path); assert data['status'] == 'PASS'; verified[str(path)] = digest(path.read_bytes())
		profiles[mode] = dict(programs=programs, distinct_source_hash_tuples=len({tuple(x['sha256'] for x in row['sources']) for row in programs}), original_statuses=statuses['outcomes'])
	proof = CLASS15/'final-proof-replay-v2'; observations = read(proof/'observations.json'); assert len(observations) == 1044
	for i, row in enumerate(observations): verify(proof/(str(i)+'.stdout'), row['stdout_sha256'])
	for path, expected in read(proof/'inputs.json').items(): verify(path, expected)
	verify(proof/'historical-ledger.json', '0c3cd736633caac2aa264c525e9d8c47e4e64d6b9d25f1eeef52605e18dbc2a3')
	for leaf in ('ledger-before-v3', 'ledger-current', 'ledger-after-initial'):
		for path, identity in read(GEN14/leaf/'inputs.json').items(): verify(path, identity['sha256'])
	numeric = GEN14/'old-v6-O0/numeric'; deferred = [row for row in read(numeric/'result.json')['instrumented'] if row['exit'] == 1]
	assert len(deferred) == 2 and all('DEFERRED' in row['numeric_conformance'] for row in deferred)
	for row in read(numeric/'commands.json'):
		if row['exit'] == 1:
			for suffix in ('.stdout', '.stderr'):
				path = numeric/(row['name']+suffix); verified[str(path)] = digest(path.read_bytes())
	result = dict(status='PRESERVED_HISTORICAL_NOT_FRESH_EXECUTION', profiles=profiles, original_proof_observations=len(observations), proof_groups=dict(Counter(row['group'] for row in observations)), numerical_deferred=deferred, verified=verified, historical_live_path_reconciliation=reconciled, recipe_sha256=digest(Path(__file__).read_bytes()), limitation='No obsolete LLVM22 binary is executed. Historical results remain bound to their original source/tool products; fresh native regression replays are separate.')
	with a.output.open('x') as out: out.write(json.dumps(result, indent=2)+'\n')
	print('Preserved 52 + 19 + 4 identities per profile, 80 statuses and 1044 exact proof outputs;', len(reconciled), 'historical live source paths resolved through exact Git blobs')


if __name__ == '__main__':
	main()
