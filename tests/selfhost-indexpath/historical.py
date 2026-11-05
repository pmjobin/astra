#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Verify the 106 inherited ELF/source identities without calling them fresh."""
import json
from state import RUNTIME, PRIOR, read, sha


def main():
	profiles = {}
	for mode in ('O0', 'O2'):
		old = PRIOR/'qualification-predecessor-v10'
		legacy = read(old/('inherited-'+mode)/'observations/result.json')['profiles'][mode]
		classes = read(old/('Class-'+mode)/'observations/results.json')
		generics = read(old/('new-'+mode)/'observations/results.json')
		text = read(PRIOR/'qualification-v10'/('new-'+mode)/'observations/results.json')
		assert (len(legacy), len(classes), len(generics), len(text)) == (52, 23, 15, 16)
		rows = legacy+classes+generics+text; identities = [tuple(source['sha256'] for source in row['sources']) for row in rows]
		assert len(rows) == len(set(identities)) == 106
		for row in rows:
			assert all(sha(source['path']) == source['sha256'] for source in row['sources']), row['name']
			assert all(sha(product['path']) == product['sha256'] for product in row['products'].values()), row['name']
		statuses = read(old/('continuity-'+mode)/'observations/result.json')['outcomes']; assert sum(statuses.values()) == 80
		profiles[mode] = dict(programs=rows, distinct=106, original_source_statuses=statuses)
	assert [row['sources'] for row in profiles['O0']['programs']] == [row['sources'] for row in profiles['O2']['programs']]
	proof = read(PRIOR/'history-audit-final/result.json'); assert proof['observations'] == 1044 and proof['status'] == 'PRESERVED_IDENTITY_BOUND_HISTORICAL'
	(RUNTIME/'inherited-identity-preservation.json').write_text(json.dumps(dict(status='PRESERVED_HISTORICAL_NOT_FRESH_EXECUTION', predecessor_report_sha256=sha(RUNTIME/'predecessor-report.zip'), profiles=profiles, proof_receipt=dict(path=str(PRIOR/'history-audit-final/result.json'), sha256=sha(PRIOR/'history-audit-final/result.json')), historical_proof_outputs=1044, limitation='These checks preserve prior sources and native product bytes. Current compiler regression execution is a separate gate; this receipt is not a new qualification of old proof outputs.'), indent=2)+'\n')
	proof_root = PRIOR.parent/'classstorage15/resume-llvm23-v1/final-proof-replay-v2'
	# Every numbered historical stdout is tied to its original command row.
	observations = read(proof_root/'observations.json'); assert len(observations) == 1044
	prior = read(PRIOR/'historical-preservation.json'); retained = {}
	for i, observation in enumerate(observations):
		path = proof_root/(str(i)+'.stdout'); assert sha(path) == observation['stdout_sha256'] == prior['verified'][str(path)]
		retained[str(path)] = dict(sha256=sha(path), group=observation['group'], name=observation['name'], original_exit=observation['exit'], original_argv=observation['argv'])
	(RUNTIME/'historical-proof-outputs.json').write_text(json.dumps(dict(status='PRESERVED_HISTORICAL_NOT_FRESH_EXECUTION', outputs=retained, count=1044, observations_sha256=sha(proof_root/'observations.json'), original_result_sha256=sha(proof_root/'result.json'), product_audit=sha(RUNTIME/'history-audit/result.json'), limitation='No old proof was executed or attributed to the changed compiler. The original command/source/tool/flag products and exact historical stdout bytes are retained.'), indent=2)+'\n')
	print('106 distinct inherited programs per profile and original 80 source statuses preserved; 1044 proof outputs remain historical')


if __name__ == '__main__':
	main()
