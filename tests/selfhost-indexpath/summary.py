#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Require executed current gates and distinguish them from preserved history."""
import argparse
import json
from pathlib import Path
from state import RUNTIME, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--output', type=Path, required=True); a = p.parse_args(); assert a.output.resolve().is_relative_to(RUNTIME)
	profiles = {}; receipts = {}
	old = read(RUNTIME/'inherited-identity-preservation.json'); assert old['status'] == 'PRESERVED_HISTORICAL_NOT_FRESH_EXECUTION'
	for mode in ('O0', 'O2'):
		group = RUNTIME/('qualification-v5' if mode == 'O0' else 'qualification-final')
		new = RUNTIME/'qualification-final'/('new-'+mode)
		leaves = dict(new=new, **{gate: group/(gate+'-'+mode) for gate in ('mutations', 'negative', 'faults', 'predecessor-text', 'predecessor-native')})
		gates = {}
		for name, leaf in leaves.items():
			data = read(leaf/'result.json'); assert data['status'] == 'PASS' and data['mode'] == mode, leaf
			gates[name] = data; receipts[str(leaf/'result.json')] = sha(leaf/'result.json')
		assert len({row['component_sha256'] for row in gates.values()}) == 1
		native = leaves['predecessor-native']; text = leaves['predecessor-text']
		legacy = read(native/('inherited-'+mode)/'observations/result.json')['profiles'][mode]
		classes = read(native/('Class-'+mode)/'observations/results.json')
		generics = read(native/('new-'+mode)/'observations/results.json')
		text_rows = read(text/('new-'+mode)/'observations/results.json')
		added = read(new/'observations/results.json'); inherited = legacy+classes+generics+text_rows
		assert (len(legacy), len(classes), len(generics), len(text_rows), len(added)) == (52, 23, 15, 16, 15)
		assert all(row['baseline_complete'] for row in classes+generics+text_rows+added)
		assert [(row['name'], row['sources']) for row in inherited] == [(row['name'], row['sources']) for row in old['profiles'][mode]['programs']]
		rows = inherited+added; identities = [tuple(source['sha256'] for source in row['sources']) for row in rows]
		assert len(rows) == len(set(identities)) == 121
		for row in rows:
			assert all(sha(source['path']) == source['sha256'] for source in row['sources']), row['name']
			assert all(sha(product['path']) == product['sha256'] for product in row['products'].values()), row['name']
		assert len({row['products']['native']['sha256'] for row in added}) == 15
		statuses = read(native/('continuity-'+mode)/'observations/result.json')['outcomes']; assert statuses == old['profiles'][mode]['original_source_statuses'] and sum(statuses.values()) == 80
		assert gates['mutations']['receipts'][0]['distinct_categories'] == 25 and gates['mutations']['receipts'][0]['LLVM_valid_physical'] == 8
		witness = read(RUNTIME/('source-witness-'+mode+'.json')); assert witness['status'] == 'PASS' and witness['component_sha256'] == gates['new']['component_sha256']
		profiles[mode] = dict(component_sha256=gates['new']['component_sha256'], inherited=106, new=15, source_program_identities=121, new_distinct_ELF_bytes=15, all_distinct_ELF_bytes=len({row['products'].get('native', row['products'].get('executable'))['sha256'] for row in rows}), programs=rows, original_source_statuses=statuses, new_mutation_categories=25, new_LLVM_valid_physical_mutants=8, gate_receipts={name: dict(path=str(leaf/'result.json'), sha256=sha(leaf/'result.json')) for name, leaf in leaves.items()}, original_operation_witness=dict(path=str(RUNTIME/('source-witness-'+mode+'.json')), sha256=sha(RUNTIME/('source-witness-'+mode+'.json'))))
	assert [row['sources'] for row in profiles['O0']['programs']] == [row['sources'] for row in profiles['O2']['programs']]
	cohorts = {}
	for name in ('original', 'LLVM23-base', 'Class15-current', 'live-initial'):
		path = RUNTIME/('comparison-final-'+name+'.json'); data = read(path); assert data['status'] == 'IDENTICAL_POPULATION_COMPARED'
		stop = data['after']['first_stop']; assert stop['path'].endswith('/compiler/semantic/flow-model.astra') and (stop['start'], stop['end']) == (3589, 3614)
		assert data['before']['typed'] == data['after']['typed']
		cohorts[name] = dict(path=str(path), sha256=sha(path), before=data['before'], after=data['after'], logical_population_sha256=data['logical_population_sha256'], node_identity_sha256=data['node_identity_sha256'])
	history = read(RUNTIME/'historical-proof-outputs.json'); assert history['count'] == 1044 and history['status'] == 'PRESERVED_HISTORICAL_NOT_FRESH_EXECUTION'
	result = dict(format='astra-indexpath-engineering-summary/1', status='ENGINEERING_GATES_COMPLETE_PUBLICATION_PENDING', profiles=profiles, cohorts=cohorts, historical_proof_outputs=1044, historical_proofs_classification=history['status'], receipts=receipts, limits=['The full original CfgWalk.inspect body is C0-qualified and Core/CFG-verified, but remains native-SSA resource-DEFERRED at unchanged 8000000 steps. The exact source operation executes in the separately disclosed byte-offset-preserving view and bounded CFG driver.', 'Indexed field writes, effectful indexes, borrowed element escape, wider index channels and move-only element copying are not admitted by the bounded native profile.', 'The original Utf8Message factory/exceptions/text_split, the prior three-specialization SSA bound, wide-u64-to-f32 Valgrind discrepancy, whole-source safety and Stage 1 remain separate deferred issues.', 'Frozen whole-source typed counts are unchanged; the source-copy frontier moves to swap(this.events, grown), not to whole-program admission.'], recipe_sha256=sha(__file__))
	a.output.write_text(json.dumps(result, indent=2)+'\n'); print('Current O0/O2 engineering gates verified: 106 inherited + 15 new programs, 25 new mutation categories, 8 LLVM-valid physical mutants, 80 statuses per profile; publication pending')


if __name__ == '__main__':
	main()
