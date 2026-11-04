#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Verify retained predecessor identities without claiming a fresh test replay."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
	return json.loads(path.read_text())


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--previous', type=Path, required=True)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args(); previous = a.previous.resolve()
	assert not a.output.resolve().is_relative_to(ROOT)
	rows, verified = {}, {}
	def verify(path, expected):
		path = Path(path)
		if str(path) not in verified:
			actual = sha(path); assert actual == expected, str(path)
			verified[str(path)] = actual
		else: assert verified[str(path)] == expected
	def identities(value):
		if isinstance(value, dict):
			if 'path' in value and 'sha256' in value: verify(value['path'], value['sha256'])
			if 'source_path' in value and 'source_sha256' in value: verify(value['source_path'], value['source_sha256'])
			for child in value.values(): identities(child)
		elif isinstance(value, list):
			for child in value: identities(child)
	for mode in ('O0', 'O2'):
		programs = []
		for family in ('old-v6-'+mode+'/legacy', 'old-v6-'+mode+'/additions', 'new-v6-'+mode):
			path = previous/family/'result.json'; data = read(path); assert data['status'] == 'PASS'
			verified[str(path)] = sha(path); identities(data)
			for case in data['cases']:
				programs.append(dict(name=case['name'], sources=case.get('sources', [dict(path=case.get('source_path'), sha256=case.get('source_sha256'))]), products=case['products'], result_receipt=str(path), historical_result=case['result']))
		assert len(programs) == 52
		assert len({tuple(x['sha256'] for x in row['sources']) for row in programs}) == 52
		status_path = previous/('old-v6-'+mode)/'continuity/result.json'; statuses = read(status_path)
		assert sum(statuses['outcomes'].values()) == 80; verified[str(status_path)] = sha(status_path)
		mutations = {}
		for family in ('mutations-v6-', 'negative-v6-', 'policies-v6-'):
			path = previous/(family+mode)/'result.json'; data = read(path); assert data['status'] == 'PASS'
			mutations[family] = dict(path=str(path), sha256=sha(path)); verified[str(path)] = sha(path)
		rows[mode] = dict(programs=programs, statuses=statuses['outcomes'], retained_negatives=mutations)
	assert {tuple(x['sha256'] for x in row['sources']) for row in rows['O0']['programs']} == {tuple(x['sha256'] for x in row['sources']) for row in rows['O2']['programs']}
	proof = previous/'final-proof-replay-v2'; observations = read(proof/'observations.json')
	assert len(observations) == 1044
	for i, row in enumerate(observations): verify(proof/(str(i)+'.stdout'), row['stdout_sha256'])
	for path, digest in read(proof/'inputs.json').items(): verify(path, digest)
	verify(proof/'historical-ledger.json', '0c3cd736633caac2aa264c525e9d8c47e4e64d6b9d25f1eeef52605e18dbc2a3')
	ledgers = {}
	for family, count in [('ledger-before-v3', 174297), ('ledger-current', 188240), ('ledger-after-initial', 174297)]:
		path = previous/family/'ledger.json'; data = read(path); assert len(data['nodes']) == count
		inputs = read(previous/family/'inputs.json')
		for name, value in inputs.items(): verify(name, value['sha256'])
		digest = hashlib.sha256()
		for node in data['nodes']:
			key = [node[k] for k in ('node', 'syntax_kind', 'start', 'end', 'source_sha256')]
			digest.update((json.dumps(key, separators=(',', ':'))+'\n').encode())
		ledgers[family] = dict(path=str(path), sha256=sha(path), nodes=count, original_node_identity_sha256=digest.hexdigest(), typed_observations=sum(bool(n['type']) and n['deferred'] == 0 for n in data['nodes']), nonzero_type_ids=sum(bool(n['type']) for n in data['nodes']), diagnostic_count=len(data['diagnostics']), diagnostics_sha256=hashlib.sha256(json.dumps(data['diagnostics'], sort_keys=True).encode()).hexdigest(), first_checked_error=next((row for row in data['diagnostics'] if row['kind'] == 'CHECKED_ERROR'), None), disposition_counts=dict(Counter(n['disposition'] for n in data['nodes'])))
	assert ledgers['ledger-before-v3']['original_node_identity_sha256'] == ledgers['ledger-after-initial']['original_node_identity_sha256']
	numeric = previous/'old-v6-O0/numeric'; data = read(numeric/'result.json')
	deferred = [row for row in data['instrumented'] if row['exit'] == 1]
	assert len(deferred) == 2 and all('DEFERRED' in row['numeric_conformance'] for row in deferred)
	numeric_receipts = []
	for row in read(numeric/'commands.json'):
		if row['exit'] == 1:
			raw = [numeric/(row['name']+suffix) for suffix in ('.stdout', '.stderr')]
			numeric_receipts.append(dict(command=row, raw=[dict(path=str(path), sha256=sha(path)) for path in raw]))
	transport = previous/'handoff/raw-evidence.tar.xz'
	verify(transport, '61423b9bdb16de3d27057b7fe309a3bf5b607828fd87d269874de95ed0ce1941')
	result = dict(status='PRESERVED_HISTORICAL_NOT_RERUN', profiles=rows, proof_observations=len(observations), proof_groups=dict(Counter(x['group'] for x in observations)), verified_files=verified, historical_ledgers=ledgers, numeric_deferred=deferred, numeric_receipts=numeric_receipts, source_code_unchanged=subprocess.check_output(['git', '-C', str(ROOT), 'diff', '--name-only', '7b8fea49cdd3b3b8bb284d4299a12d31b01ba682', '--', 'compiler', 'bootstrap', 'lib']).decode() == '', limitations='Hash preservation only. No new execution, semantic proof, ABI qualification, Valgrind conformance or whole-source admission is inferred. Full historical raw evidence remains bound to the exact preserved predecessor report and transport.')
	with a.output.open('x') as out: out.write(json.dumps(result, indent=2)+'\n')
	print('Retained exact source/product identities for 52 programs per profile, 80 statuses, 1044 proof outputs and original numerical deferral; no rerun claimed')


if __name__ == '__main__':
	main()
