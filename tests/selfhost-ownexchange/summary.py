#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Require current execution receipts before declaring bounded completion."""
import argparse
import json
from pathlib import Path
from state import RUNTIME, PRIOR, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); p.add_argument('--output', type=Path, required=True); a = p.parse_args()
	assert a.output.resolve().is_relative_to(RUNTIME)
	profiles = {}
	for mode in ('O0', 'O2'):
		leaves = {name: RUNTIME/('final-'+a.version+'-'+name+'-'+mode) for name in ('new', 'family', 'twins', 'extras', 'mutations', 'resource', 'inherited-native', 'inherited-text', 'inherited-indexpath', 'faults', 'lifetime')}
		for name in ('family', 'lifetime'): leaves[name] = RUNTIME/('final-'+a.version+'-'+name+'-repaired-'+mode)
		gates = {name: read(leaf/'result.json') for name, leaf in leaves.items()}
		assert all(row['status'] == 'PASS' and row['mode'] == mode for row in gates.values())
		assert len({row['component_sha256'] for row in gates.values()}) == 1
		native, text = leaves['inherited-native'], leaves['inherited-text']
		legacy = read(native/('inherited-'+mode)/'observations/result.json')['profiles'][mode]
		classes = read(native/('Class-'+mode)/'observations/results.json')
		generics = read(native/('new-'+mode)/'observations/results.json')
		texts = read(text/('new-'+mode)/'observations/results.json')
		indexpath = read(leaves['inherited-indexpath']/'observations/results.json')
		assert tuple(map(len, (legacy, classes, generics, texts, indexpath))) == (52, 23, 15, 16, 15)
		inherited = legacy+classes+generics+texts+indexpath
		old = read(PRIOR/'inherited-identity-preservation.json')['profiles'][mode]['programs']+read(PRIOR/'qualification-final'/('new-'+mode)/'observations/results.json')
		assert [(r['name'], r['sources']) for r in inherited] == [(r['name'], r['sources']) for r in old]
		added = [row for name in ('new', 'family', 'twins', 'extras') for row in read(leaves[name]/'observations/results.json')]
		assert len(added) == 24 and all(row['baseline_complete'] for row in classes+generics+texts+indexpath+added)
		rows = inherited+added
		assert len(rows) == len({tuple(s['sha256'] for s in r['sources']) for r in rows}) == 145
		for row in rows:
			assert all(sha(s['path']) == s['sha256'] for s in row['sources'])
			assert all(sha(p['path']) == p['sha256'] for p in row['products'].values())
		statuses = read(native/('continuity-'+mode)/'observations/result.json')['outcomes']
		assert statuses == read(PRIOR/'inherited-identity-preservation.json')['profiles'][mode]['original_source_statuses'] and sum(statuses.values()) == 80
		mutations = read(leaves['mutations']/'mutations.json'); assert (mutations['model'], mutations['LLVM_valid_physical'], mutations['total']) == (26, 11, 37)
		witness_path = RUNTIME/('source-witness-'+mode+'.json'); witness = read(witness_path)
		assert witness['status'] == 'PASS' and witness['component_sha256'] == gates['new']['component_sha256']
		assert len(gates['faults']['observations']) >= 25 and len(gates['lifetime']['observations']) == 8
		profiles[mode] = dict(component_sha256=gates['new']['component_sha256'], inherited=121, new=24, source_program_identities=145, all_distinct_ELF_bytes=len({r['products'].get('native', r['products'].get('executable'))['sha256'] for r in rows}), programs=rows, original_source_statuses=statuses, new_mutation_categories=37, new_LLVM_valid_physical_mutants=11, gate_receipts={name: dict(path=str(leaf/'result.json'), sha256=sha(leaf/'result.json')) for name, leaf in leaves.items()}, original_operation_witness=dict(path=str(witness_path), sha256=sha(witness_path)))
	assert [r['sources'] for r in profiles['O0']['programs']] == [r['sources'] for r in profiles['O2']['programs']]
	cohort_path = RUNTIME/('cohort-comparison-'+a.version+'.json'); cohorts = read(cohort_path)
	assert cohorts['status'] == 'IDENTICAL_SOURCE_NODE_SPAN_POPULATIONS'
	for row in cohorts['cohorts'].values():
		assert row['before']['typed'] == row['after']['typed']
		assert (row['after']['first_stop']['start'], row['after']['first_stop']['end']) != (3589, 3614)
	cost_path = RUNTIME/'measured-costs.json'; costs = read(cost_path); assert len(costs['final_builds']) == len(costs['exact_warm_reuse']) == 2
	result = dict(format='astra-ownexchange-engineering-summary/1', status='ENGINEERING_GATES_COMPLETE_PUBLICATION_PENDING', profiles=profiles, cohorts=dict(path=str(cohort_path), sha256=sha(cohort_path), observations=cohorts['cohorts']), costs=dict(path=str(cost_path), sha256=sha(cost_path)), historical_proof_outputs=1044, historical_proofs_classification='PRESERVED_HISTORICAL_NOT_FRESH_EXECUTION', limits=['Full original CfgWalk.inspect remains native-SSA resource-DEFERRED at unchanged 8000000 steps; Core/CFG checks pass separately.', 'Four frozen source populations advance beyond the original swap to actual generic instance resource limits. Their typed counts are unchanged; no whole-source safety follows.', 'The unchanged complete FlowGraph.add body executes inside a disclosed byte-preserving Class/dependency view; the complete original FlowGraph and compiler remain unqualified.', 'Effectful/indexed owner targets, wider element domains and nested owned payloads remain outside the bounded exchange profile.', 'Three-specialization SSA stress, Utf8Message factory/exception/text_split, wide-u64-to-f32 Valgrind discrepancy and Stage 1 remain deferred.'], recipe_sha256=sha(__file__))
	a.output.write_text(json.dumps(result, indent=2)+'\n'); print('O0/O2: 121 inherited + 24 new programs, 37 new mutations incl. 11 LLVM-valid physical; publication pending')


if __name__ == '__main__':
	main()
