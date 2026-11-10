#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Detailed bounded-proof consumer with explicit missing-input failure adjudication."""
import json
from pathlib import Path

from run import sha

# Detailed checks originate in the independent R5 consumer, retained here so
# neither the historical consumer nor its failed receipts must be rewritten.
# Original file SHA-256: acfdb652f518a383f34752ec2c7a9df5c51e02d06a52f8bf5324fd61a4adbe35


def read(path):
	return json.loads(Path(path).read_text())


def current_support(paths, component, mode, version, native_facts, retained_facts, consumer, fixture_version):
	commands, memory = consumer.commands, consumer.memory
	C0 = consumer.C0
	error_physical_version = fixture_version
	leaf = paths.RUNTIME/('qualification-'+version+'-'+mode)
	if not (leaf/'result.json').exists(): return dict(complete=False, missing=str(leaf/'result.json'))
	result = read(leaf/'result.json'); observed = commands(leaf)
	assert result['component_sha256'] == sha(component) and result['profile'] == mode
	facts = dict(complete=False, receipt=str(leaf/'result.json'), receipt_sha256=sha(leaf/'result.json'), failed_jobs=result['failed_jobs'])
	if result['selected_jobs'] is not None or result['completed_jobs'] != result['expected_jobs'] or result['expected_jobs'] != len(observed) or len(observed) != 12 or any(row['timed_out'] for row in observed.values()): return facts
	failed = [name for name, row in observed.items() if row['exit'] != 0]
	assert result['failed_jobs'] == failed
	assert failed == ['error-order', 'error-physical'] and fixture_version and retained_facts['complete']
	assert result['status'] == 'CONTINUATION_QUALIFICATION_PARTIAL'
	for name, missing in (('error-order', 'error-order-oracles-source1/result.json'), ('error-physical', 'native-frontiers-errororacle2-'+mode+'/result.json')):
		text = (leaf/(name+'.stderr')).read_text()
		assert 'FileNotFoundError:' in text and str(paths.RUNTIME/missing) in text
	supplement_leaf = paths.RUNTIME/('fixture-supplements-'+fixture_version+'-'+mode)
	supplement = read(supplement_leaf/'result.json')
	corrected = commands(supplement_leaf)
	assert supplement['status'] == 'FIXTURE_SUPPLEMENTS_PASSED' and supplement['component_sha256'] == sha(component) and supplement['profile'] == mode
	assert supplement['raw_version'] == version and supplement['version'] == fixture_version
	assert supplement['selected_jobs'] == list(corrected) == ['error-order', 'error-physical'] and supplement['completed_jobs'] == 2 and not supplement['failed_jobs']
	assert supplement['raw_failed_commands'] == [observed[name] for name in failed]
	assert all(row['exit'] == 0 and not row['timed_out'] for row in corrected.values())
	assert sha(supplement_leaf/'raw-campaign-at-start.json') == supplement['raw_campaign_snapshot_sha256']
	seed = paths.RUNTIME/'reference-fixture-seed.json'
	assert sha(seed) == supplement['input_seed_sha256']
	for row in read(seed)['files']:
		assert sha(row['original']) == row['original_sha256'] == sha(row['snapshot']) == row['snapshot_sha256']
		assert Path(row['snapshot']).stat().st_mode & 0o222 == 0
	facts['raw_campaign_status'] = result['status']
	facts['fixture_supplements'] = dict(path=str(supplement_leaf/'result.json'), sha256=sha(supplement_leaf/'result.json'), input_seed_sha256=sha(seed), limitation='Raw missing-input campaign remains PARTIAL. Two separately passing jobs are rebound in detail below, using byte-exact read-only historical fixture inputs. No failed receipt, compiler source or compiler product was changed.')
	receipts = []
	def load(stem):
		if stem == 'error-order-native-'+version+'-'+mode:
			stem = 'error-order-native-'+fixture_version+'-'+mode
		where = paths.RUNTIME/stem; data = read(where/'result.json'); run = commands(where)
		receipts.append(dict(path=str(where/'result.json'), sha256=sha(where/'result.json')))
		return where, paths.BUILD/stem, data, run
	where, build, data, run = load('runtime-stages-'+version+mode)
	assert data['observer_sha256'] == sha(component) and data['observer_identity_sha256'] == sha(component.with_suffix('.identity.json'))
	assert len(data['programs']) == len(native_facts['programs']) == 71
	markers = set()
	for ordinal, (row, source) in enumerate(zip(data['programs'], native_facts['programs'], strict=True)):
		assert row['name'] == source['name'] and row['inputs'] == source['inputs'] and row['Flow_Core_CFG_SSA_valid'] and row['exit'] == 42 and row['source_boundary'] is None and not row['verification_failure_leaves']
		label = str(ordinal)+'-'+row['name']; assert run[label]['exit'] == 42 and run[label]['argv'][:2] == [str(component), '--shared-stages']
		stdout = (where/(label+'.stdout')).read_text(); assert 'SHARED_SSA_VALID' in stdout
		assert row['semantic_markers'] == [line for line in stdout.splitlines() if line.startswith('SEMANTIC ')]
		markers.update(row['semantic_markers'])
	assert len(markers) >= 12
	for group, count in [('array', 15), ('owner', 6)]:
		where, build, data, run = load(group+'-source-negative-'+version+'-'+mode)
		assert data['component_sha256'] == sha(component) and data['C0_sha256'] == sha(C0) and data['profile'] == mode and not data['stage_only'] and len(data['programs']) == count
		for row in data['programs']:
			name = row['name']; assert sha(where/(name+'.astra')) == row['source_sha256'] and row['C0_rejected'] and row['Astra_not_emitted'] and row['destination_preserved']
			assert run[name+'-C0-build']['exit'] == 1 and run[name+'-C0-build']['argv'][:2] == [str(C0), '-'+mode]
			assert run[name+'-Astra-attempt']['argv'][0] == str(component) and run[name+'-Astra-attempt']['exit'] == row['Astra_status'] and row['Astra_status'] in range(1, 7)
			assert (build/(name+'.ll')).read_bytes() == b'Negative source output sentinel\n'
			output = (where/(name+'-Astra-attempt.stdout')).read_bytes() + (where/(name+'-Astra-attempt.stderr')).read_bytes()
			assert b'RESOURCE_EXHAUSTED' not in output and b'RECOVER_FLOW 2 ' not in output
	where, build, data, run = load('dynamic-faults-'+version+'-'+mode)
	assert data['component_sha256'] == sha(component) and data['C0_sha256'] == sha(C0) and data['profile'] == mode and data['complete'] and not data['failed'] and len(data['programs']) == 32
	assert sum(row['profiles']['C0']['fatal'] for row in data['programs']) == 20
	for row in data['programs']:
		name = row['name']; assert set(row['profiles']) == {'C0', 'Astra'} and row['C0_build_exit'] == row['Astra_emit_exit'] == 0
		if name in ('stored-buffer-write-end', 'constructor-field-normal', 'constructor-error-field-normal'): assert row['constructor_stage_exit'] == run[name+'-source-stage-mutations']['exit'] == 42 and len(row['constructor_stage_markers']) == 4
		assert all(sha(source['path']) == source['sha256'] for source in row['inputs']) and sha(build/(name+'.ll')) == row['raw_LLVM_sha256'] and sha(build/(name+'-optimized.ll')) == row['optimized_LLVM_sha256']
		left, right = row['profiles']['C0'], row['profiles']['Astra']; assert {k:v for k,v in left.items() if k!='ELF_sha256'} == {k:v for k,v in right.items() if k!='ELF_sha256'}
		assert run[name+'-Astra-emit']['argv'][0] == str(component) and run[name+'-C0-build']['argv'][:2] == [str(C0), '-'+mode]
		for label in ('verify', 'optimize', 'optimized-verify', 'object', 'link'): assert run[name+'-Astra-'+label]['exit'] == 0
		for producer, entry in row['profiles'].items():
			label = name+'-'+producer; assert sha(build/label) == entry['ELF_sha256'] and run[label+'-execute']['exit'] == entry['exit']
			assert sha(where/(label+'-execute.stdout')) == entry['stdout_sha256'] and sha(where/(label+'-execute.stderr')) == entry['stderr_sha256']
			if entry['fatal']: assert entry['signal'] == 4 and entry['exit'] in (132, -4) and not entry['returning_clean_memory'] and label+'-memory' not in run
			else: assert entry['exit'] == run[label+'-memory']['exit'] == 42 and entry['returning_clean_memory']; memory(where/(label+'-memory.stderr'))
	where, build, data, run = load('error-order-native-'+version+'-'+mode)
	assert data['component_sha256'] == sha(component) and data['profile'] == mode and len(data['programs']) == 3
	for row in data['programs']:
		assert row['emit_exit'] == 0 and [entry['producer'] for entry in row['observations']] == ['C0', 'Astra']
		left, right = row['observations']; assert left['allocation_events'] == right['allocation_events'] and left['failures'] == right['failures']
		for entry in row['observations']:
			label = row['name']+'-'+entry['producer']; assert entry['exit'] == run[label+'-execute']['exit'] == run[label+'-memory']['exit'] == 42 and entry['returning_clean_memory'] and sha(build/label) == entry['ELF_sha256']
			memory(where/(label+'-memory.stderr'))
			assert all(not control['returning_memory_credit'] and control['exit'] in (132, -4) for control in entry['failures'])
		for stream in ('stdout', 'stderr'): assert (where/(row['name']+'-Astra-execute.'+stream)).read_bytes() == (where/(row['name']+'-C0-execute.'+stream)).read_bytes()
	where, build, data, run = load('error-lifetime-'+version+'-'+mode)
	assert data['component_sha256'] == sha(component) and data['profile'] == mode and len(data['programs']) == 8
	for row in data['programs']:
		assert set(row['profiles']) == {'C0', 'Astra'}
		left, right = row['profiles']['C0'], row['profiles']['Astra']; assert left['trace'] == right['trace'] and left['failures'] == right['failures'] and left['stdout_sha256'] == right['stdout_sha256'] and left['stderr_sha256'] == right['stderr_sha256']
		for producer, entry in row['profiles'].items():
			label = row['name']+'-'+producer; assert run[label+'-execute']['exit'] == run[label+'-memory']['exit'] == 42 and sha(build/label) == entry['ELF_sha256']
			assert '--default-suppressions=no' in run[label+'-memory']['argv'] and 'LD_PRELOAD' not in ' '.join(run[label+'-memory']['argv'])
			memory(where/(label+'-memory.stderr')); assert entry['trace'] and all(not control['returning_memory_credit'] and (control['exit'] in (132, -4) if control['fatal'] else control['exit'] == 42) for control in entry['failures'])
	for stem, count in [('frontier-physical', 14), ('error-physical', 10)]:
		physical_version = error_physical_version if stem == 'error-physical' and error_physical_version else version
		where, build, data, run = load(stem+'-'+physical_version+'-'+mode)
		assert data['component_sha256'] == sha(component) and data['profile'] == mode
		rows = data['LLVM_valid_physical'] if stem == 'frontier-physical' else data['modules']; assert len(rows) == count
		for ordinal, row in enumerate(rows):
			physical = build/(stem+'-'+str(ordinal)+'.ll'); assert row['category'] == ordinal and sha(physical) == row['LLVM_sha256' if stem == 'frontier-physical' else 'sha256']
			assert any(item['exit'] == 0 and item['argv'][:2] == ['opt', '-passes=verify'] and str(physical) in item['argv'] for item in run.values())
		if stem == 'frontier-physical':
			assert data['actual_exit'] == 42 and sha(build/'Astra') == data['Astra_ELF_sha256'] and sha(build/'C0') == data['C0_ELF_sha256']
			for producer in ('Astra', 'C0'): assert run[producer+'-execute']['exit'] == run[producer+'-memory']['exit'] == 42; memory(where/(producer+'-memory.stderr'))
		else:
			lines = (where/'actual-source-physical-alternatives.stdout').read_text().splitlines()
			assert [line for line in lines if line.startswith('ERROR_LLVM_REJECT ')] == ['ERROR_LLVM_REJECT '+str(i) for i in range(10)] and data['component_identity_sha256'] == sha(component.with_suffix('.identity.json'))
			assert all(sha(source['path']) == source['sha256'] for source in data['inputs']) and data['Astra_native_execution_credit'] == 0
			if error_physical_version:
				assert data['category6'] == 'same-type Error field receiver replaced by null' and sha(data['test_driver']) == data['test_driver_sha256'] and lines.count('VALID_FIELD_RECEIVER_MUTATION 1') == lines.count('VALID_FIELD_RECEIVER_TOTAL 1') == 1
				argv = run['actual-source-physical-alternatives']['argv']; assert argv[:4] == ['gdb', '-nx', '-q', '-batch'] and argv[argv.index('--args')+1:argv.index('--args')+3] == [str(component), '--error-physical'] and run['actual-source-physical-alternatives']['exit'] == 0 and any('exited normally' in line for line in lines)
				facts['error_physical_supplement'] = dict(path=str(where/'result.json'), sha256=sha(where/'result.json'), test_driver=data['test_driver'], test_driver_sha256=data['test_driver_sha256'], limitation=data['limitation'])
	facts.update(complete=True, stage_programs=71, new_semantic_categories=sorted(markers), array_source_negatives=15, owner_source_negatives=6, dynamic_fault_sources=32, dynamic_fatal_controls=20, constructor_stage_source_programs=3, error_order_programs=3, error_lifetime_programs=8, new_LLVM_valid_physical=24, receipts=receipts)
	return facts
