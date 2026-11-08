#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independently bind continuation facts; assessment cannot promote absent proof."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile
from state import ROOT, C0, load_module, read, sha, git, preservation

PREVIOUS = '16408c8bd00c3e81633e2ab7cefa6d557bbdad0dbdd9239add328c160fe7f887'
BASE = 'c271e0822d0fc12a878a5adc1388aa1a8e147067'


def commands(leaf):
	rows = read(leaf/'commands.json') if (leaf/'commands.json').exists() else read(leaf/'result.json')['commands']
	for row in rows:
		for stream in ('stdout', 'stderr'):
			assert sha(leaf/(row['name']+'.'+stream)) == row[stream+'_sha256']
	return {row['name']: row for row in rows}


def memory(path):
	data = path.read_bytes()
	assert all(marker in data for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
	return sha(path)


def compiler(path, mode):
	identity = read(path.with_suffix('.identity.json'))
	assert path.name == 'astra-llvm-'+mode and sha(path) == identity['sha256'] and identity['identity']['argv'][:2] == [str(C0), '-'+mode]
	assert all(sha(source) == expected for group in ('sources', 'tools') for source, expected in identity['identity'][group].items())
	return dict(component=str(path), component_sha256=sha(path), component_identity_sha256=sha(path.with_suffix('.identity.json')), project_input_hashes={name: value for name, value in identity['identity']['sources'].items() if Path(name).is_relative_to(ROOT)}, tools=identity['identity']['tools'])


def native(paths, component, mode, version):
	leaf = paths.RUNTIME/('native-frontiers-'+version+'-'+mode)
	if not (leaf/'result.json').exists(): return dict(complete=False, missing=str(leaf/'result.json'), programs=[])
	result = read(leaf/'result.json'); rows = commands(leaf)
	assert result['component_sha256'] == sha(component) and result['profile'] == result['compiler_profile'] == mode
	build = paths.BUILD/leaf.name
	graph = load_module('audit_original_graph', ROOT/'tests/selfhost-effects/recover-native-frontiers.py').original_target_graph
	programs = []
	for row in result['programs']:
		assert all(sha(source['path']) == source['sha256'] for source in row['inputs'])
		name = row['name']; actual = row['Astra']; valid = actual is not None and actual['actual_execution'] == 42
		if valid:
			assert actual['emitted'] and actual['emit_exit'] == 0 and row['C0']['exit'] == 42 and actual['returning_clean_memory'] and row['C0']['returning_clean_memory']
			for label, code in [('Astra-emit', 0), ('Astra-verify', 0), ('Astra-optimized-verify', 0), ('Astra-execute', 42), ('C0-execute', 42), ('Astra-memory', 42), ('C0-memory', 42)]: assert rows[name+'-'+label]['exit'] == code
			assert rows[name+'-Astra-emit']['argv'][0] == str(component)
			assert rows[name+'-C0-build']['argv'][:2] == [str(C0), '-'+mode]
			assert sha(build/(name+'.ll')) == actual['raw_LLVM_sha256'] and sha(build/(name+'-optimized.ll')) == actual['optimized_LLVM_sha256'] and sha(build/(name+'-Astra')) == actual['ELF_sha256'] and sha(build/(name+'-C0')) == row['C0']['ELF_sha256']
			for stream in ('stdout', 'stderr'): assert (leaf/(name+'-Astra-execute.'+stream)).read_bytes() == (leaf/(name+'-C0-execute.'+stream)).read_bytes()
			for producer in ('Astra', 'C0'):
				assert '--default-suppressions=no' in rows[name+'-'+producer+'-memory']['argv']
				memory(leaf/(name+'-'+producer+'-memory.stderr'))
			if row['domain'] in ('FULL_ORIGINAL', 'EXACT_REDUCED_VIEW'):
				assert row['original_target_graph'] == graph(build/(name+'.ll'), row['inputs'][1]['path'])
		programs.append(dict(name=name, domain=row['domain'], inputs=row['inputs'], native_execution=42 if valid else None, emission=actual, original_target_graph=row.get('original_target_graph')))
	groups = {'original', 'runtime', 'utf8', 'focused', 'shared', 'owner'}
	expected_names = {'full-original-flow-number', 'minimal-original-flow-number', 'derived-error-field', 'derived-error-computed-base', 'derived-error-snapshot', 'field-receiver', 'owned-result-explicit-transfer', 'nested-outer-Error-borrow', 'derived-error-readonly-field', 'derived-error-owned-child', 'derived-error-owned-buffer'}
	for recipe in ('recover-original-runtime-sources', 'recover-r5-original-oracles', 'recover-frontier-source-proof', 'recover-shared-sources'):
		module = load_module('audit_case_'+recipe, ROOT/('tests/selfhost-effects/'+recipe+'.py'))
		expected_names.update(module.corpus(leaf) if recipe == 'recover-frontier-source-proof' else module.corpus())
	complete = groups <= set(result['selected_groups']) and result['case_filter'] is None and {row['name'] for row in programs} == expected_names and len(programs) == len(expected_names) and all(row['native_execution'] == 42 for row in programs)
	return dict(complete=complete, receipt=str(leaf/'result.json'), receipt_sha256=sha(leaf/'result.json'), programs=programs)


def retained(paths, component, mode, version, previous):
	leaf = paths.RUNTIME/('resume-retained-'+version+'-'+mode)
	if not (leaf/'result.json').exists(): return dict(complete=False, missing=str(leaf/'result.json'))
	result = read(leaf/'result.json'); run = commands(leaf)
	assert result['component_sha256'] == sha(component) and result['profile'] == mode
	complete = result['status'] == 'RETAINED_RECIPES_COMPLETED' and result['selected_jobs'] is None and result['executed_jobs'] == result['full_recipe_population'] == len(run) == 41 and not result['failed_jobs'] and all(row['exit'] == 0 for row in run.values())
	facts = dict(complete=complete, receipt=str(leaf/'result.json'), receipt_sha256=sha(leaf/'result.json'), failed_jobs=result['failed_jobs'])
	if not complete: return facts
	programs = []
	for suffix in ('scalar', 'record', 'owned', 'errors', 'loops', 'literal', 'domain', 'fields'):
		where = paths.RUNTIME/('early-'+version+suffix+'-'+mode)
		data = read(where/'result.json'); observed = commands(where)
		assert data['component_sha256'] == sha(component) and data['target_profile'] == mode and data['component_build_profile'] == '-'+mode
		for row in data['programs']:
			name = row['name']; build = paths.BUILD/where.name
			assert row['Astra_effect_ELF'] and sha(where/(name+'.astra')) == row['source_sha256'] and sha(build/(name+'-Astra.ll')) == row['Astra_raw_LLVM_sha256'] and sha(build/(name+'-Astra')) == row['Astra_ELF_sha256'] and sha(build/(name+'-C0')) == row['C0_ELF_sha256']
			assert sha(build/(name+'-'+mode+'.ll')) == row['Astra_optimized_LLVM_sha256']
			for label in ('Astra-emit', 'Astra-assemble', 'Astra-verify', 'Astra-optimize', 'Astra-optimized-verify', 'Astra-object', 'Astra-link', 'C0-build'): assert observed[name+'-'+label]['exit'] == 0
			assert observed[name+'-Astra-emit']['argv'][0] == str(component) and observed[name+'-C0-build']['argv'][:2] == [str(C0), '-'+mode]
			for producer in ('Astra', 'C0'):
				assert observed[name+'-'+producer+'-execute']['exit'] == observed[name+'-'+producer+'-memory']['exit'] == 42
				memory(where/(name+'-'+producer+'-memory.stderr'))
			for stream in ('stdout', 'stderr'): assert (where/(name+'-Astra-execute.'+stream)).read_bytes() == (where/(name+'-C0-execute.'+stream)).read_bytes()
			programs.append(dict(name=name, source_sha256=row['source_sha256'], raw_LLVM_sha256=row['Astra_raw_LLVM_sha256'], ELF_sha256=row['Astra_ELF_sha256'], actual_error_path=row['observed_error_path']))
	assert len(programs) == 138 and sum(row['actual_error_path'] for row in programs) == 74
	assert {row['source_sha256'] for row in programs} == {row['source_sha256'] for row in previous['programs'][:138]}
	where = paths.RUNTIME/('inherited-'+version+'-'+mode); inherited = read(where/'result.json'); inherited_commands = commands(where)
	assert inherited['component_sha256'] == sha(component) and not inherited['historical_compiler'] and len(inherited['programs']) == 202
	for ordinal, (row, old) in enumerate(zip(inherited['programs'], previous['inherited'], strict=True)):
		assert row['name'] == old['name'] and [source['sha256'] for source in row['sources']] == [source['sha256'] for source in old['sources']]
		for source in row['sources']: assert sha(source['actual']) == source['sha256']
		build = paths.BUILD/where.name
		assert sha(build/(str(ordinal)+'.ll')) == row['raw_LLVM_sha256'] and sha(build/(str(ordinal)+'-Astra')) == row['ELF_sha256'] and sha(build/(str(ordinal)+'-C0')) == row['C0_ELF_sha256']
		for producer in ('Astra', 'C0'):
			assert inherited_commands[str(ordinal)+'-'+producer+'-execute']['exit'] == inherited_commands[str(ordinal)+'-'+producer+'-memory']['exit'] == row['actual_exit']
			memory(where/(str(ordinal)+'-'+producer+'-memory.stderr'))
	mutations = []
	for stem in ('adversarial', 'owner-adversarial', 'loop-adversarial', 'r3-adversarial', 'r3-domain-adversarial', 'r4-adversarial'):
		where = paths.RUNTIME/(stem+'-'+version+'-'+mode); data = read(where/'result.json'); observed = commands(where)
		assert data['component_sha256'] == sha(component)
		artifacts = {sha(path): path for path in (paths.BUILD/where.name).glob('*.ll')}
		for row in data['LLVM_valid_physical']:
			path = artifacts[row['LLVM_sha256']]
			assert any(item['exit'] == 0 and item['argv'][0] == 'opt' and '-passes=verify' in item['argv'] and str(path) in item['argv'] for item in observed.values())
		mutations.append(dict(recipe=stem, semantic=len(data['semantic']), LLVM_valid_physical=len(data['LLVM_valid_physical']), receipt_sha256=sha(where/'result.json')))
	assert sum(row['semantic'] for row in mutations) == 101 and sum(row['LLVM_valid_physical'] for row in mutations) == 52
	cohort_path = paths.RUNTIME/('cohorts-'+version+'-'+mode)/'result.json'; cohorts = read(cohort_path)
	assert cohorts['component_sha256'] == sha(component) and len(cohorts['cohorts']) == 4 and sorted(row['files'] for row in cohorts['cohorts'].values()) == [79, 85, 92, 92]
	assert all(row['conditional_17_19_preserved'] for row in cohorts['cohorts'].values())
	root = cohorts['cohorts']['original']['independent_root']
	assert (root['status'], root['graph'], root['symbol'], root['predicate'], root['source_root'], root['grown_slot']) == ('DEFERRED', 55, 2053, 26, 0, 6)
	drift_path = paths.RUNTIME/('drift-'+version+'-'+mode)/'result.json'
	if drift_path.exists():
		drift = read(drift_path)
		assert drift['effects_R4_R3_raw_identical'] == 0 and len(drift['retained_138']) == 138 and len(drift['inherited_202']) == 202
		facts['strict_drift_receipt'] = dict(path=str(drift_path), sha256=sha(drift_path))
	else: facts['complete'] = False; facts['missing_drift_receipt'] = str(drift_path)
	facts.update(retained_native=340, actual_error_paths=74, programs=programs, inherited=inherited['programs'], mutations=mutations, cohorts=cohorts['cohorts'], cohort_receipt_sha256=sha(cohort_path))
	return facts


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); p.add_argument('--component', action='append', default=[]); p.add_argument('--assessment', type=Path, required=True); p.add_argument('--output', type=Path, required=True)
	a = p.parse_args(); assert a.version.isalnum() and not a.output.exists()
	paths = load_module('resume_audit_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	initial = read(paths.RUNTIME/'initial.json')
	assert initial['status'] == 'AUTHENTICATED_R5_CONTINUATION' and initial['predecessor_sha256'] == PREVIOUS and initial['base'] == '0ce000667dd5cbee3e2af9fe0237b9c88a5536f3'
	assert not git('status', '--porcelain=v1', '--untracked-files=all').strip()
	head, tree = git('rev-parse', 'HEAD').strip(), git('rev-parse', 'HEAD^{tree}').strip()
	assert subprocess.run(['git', 'merge-base', '--is-ancestor', initial['base'], head], cwd=ROOT).returncode == 0
	protection = preservation(); assert protection == initial['protection'] and git('config', '--show-origin', '--list') == initial['config']
	report = ROOT.parent/'codex/reports/astra-report-current.zip'; assert report.stat().st_size == 16338136 and sha(report) == PREVIOUS
	with zipfile.ZipFile(report) as archive: previous = json.loads(archive.read('evidence/final-audit.json'))
	anchors = [('compiler/semantic/flow-query.astra', 1870, 2001, '8641d4ff6a1f19cc8bfc0ccbec492a8f7d4248eebcb05373c15479e7114a3e68'), ('compiler/source/source.astra', 6349, 7688, '379db79194d55c7f116b08c8dba7157bdfdebbee5dc5c2b95f1478de483c8305'), ('lib/astra/text/utf8-message.astra', 383, 445, '7f3d16f810dd512103d3f836b3acd2cb55ecfaea3ec4186e9f67bcbb738a6767')]
	for name, first, last, expected in anchors: assert hashlib.sha256((ROOT/name).read_bytes()[first:last]).hexdigest() == expected
	for name in ('compiler/semantic/generic.astra', 'compiler/backend/llvm/recover-helpers-check.astra', 'compiler/backend/llvm/capi.c', 'compiler/backend/llvm/capi.astra'):
		assert (ROOT/name).read_bytes() == subprocess.check_output(['git', 'show', BASE+':'+name], cwd=ROOT)
	old_module = subprocess.check_output(['git', 'show', BASE+':compiler/backend/llvm/recover-module.astra'], cwd=ROOT)
	current_module = (ROOT/'compiler/backend/llvm/recover-module.astra').read_bytes()
	assert old_module.split(b'\n\tvoid basic_helpers() {', 1)[1].split(b'\n\tvoid object_helpers()', 1)[0] == current_module.split(b'\n\tvoid basic_helpers() {', 1)[1].split(b'\n\tvoid object_helpers()', 1)[0]
	profiles = {}
	for value in a.component:
		mode, path = value.split('=', 1); assert mode in ('O0', 'O2') and mode not in profiles
		component = Path(path); row = compiler(component, mode)
		row['native'] = native(paths, component, mode, a.version)
		row['retained'] = retained(paths, component, mode, a.version, previous['profiles'][mode])
		profiles[mode] = row
	matched = set(profiles) == {'O0', 'O2'} and profiles['O0']['project_input_hashes'] == profiles['O2']['project_input_hashes'] and profiles['O0']['tools'] == profiles['O2']['tools']
	actual = {mode: sum(row['domain'] == 'FULL_ORIGINAL' and row['native_execution'] == 42 for row in profiles.get(mode, {}).get('native', {}).get('programs', [])) for mode in ('O0', 'O2')}
	assessment = read(a.assessment)
	assert assessment['status'] in ('PASS', 'PARTIAL') and set(assessment['gates']) == {'G'+str(n) for n in range(13)} and assessment['gates']['G12'].startswith('PENDING')
	if assessment['gates']['G1'].startswith('PASS'): assert matched and all(row['retained']['complete'] for row in profiles.values())
	if assessment['gates']['G6'].startswith('PASS'):
		assert matched and actual == dict(O0=1, O2=1)
		assert all(any(program['domain'] == 'EXACT_REDUCED_VIEW' and program['native_execution'] == 42 for program in row['native']['programs']) for row in profiles.values())
	if any(assessment['gates']['G'+str(gate)].startswith('PASS') for gate in (2, 3, 4, 5, 7, 8)):
		assert matched and actual == dict(O0=1, O2=1)
		for gate, domains in [(2, {'SHARED_SOURCE', 'COMPLETE_ORIGINAL_RUNTIME'}), (3, {'FOCUSED_SOURCE', 'COMPLETE_ORIGINAL_UTF8_SUCCESS', 'COMPLETE_ORIGINAL_UTF8_ERROR', 'COMPLETE_ORIGINAL_RUNTIME'}), (4, {'COMPLETE_ORIGINAL_RUNTIME', 'COMPLETE_ORIGINAL_UTF8_SUCCESS', 'COMPLETE_ORIGINAL_UTF8_ERROR'}), (5, {'C0_VALID_OWNER_FORM'})]:
			if assessment['gates']['G'+str(gate)].startswith('PASS'):
				for row in profiles.values():
					programs = [program for program in row['native']['programs'] if program['domain'] in domains]
					assert {program['domain'] for program in programs} == domains and all(program['native_execution'] == 42 for program in programs)
		if assessment['gates']['G7'].startswith('PASS') or assessment['gates']['G8'].startswith('PASS'): assert all(row['native']['complete'] for row in profiles.values())
	if assessment['gates']['G9'].startswith('PASS'): assert matched and all('cohorts' in row['retained'] for row in profiles.values())
	if assessment['status'] == 'PASS': assert not assessment['remaining_boundary'] and all(assessment['gates']['G'+str(n)].startswith('PASS') for n in range(12))
	for receipt in assessment['evidence_receipts']:
		assert Path(receipt['path']).is_relative_to(paths.RUNTIME) and sha(receipt['path']) == receipt['sha256']
	cost_path = paths.RUNTIME/('costs-'+a.version)/'result.json'; costs = read(cost_path)
	assert costs['status'] == 'MEASURED_CONTINUATION_COSTS'
	result = dict(format='astra-effects25-r5-continuation-audit/1', status=assessment['status'], summary=assessment['summary'], gates=assessment['gates'], remaining_boundary=assessment['remaining_boundary'], evidence_receipts=assessment['evidence_receipts'], assessment_sha256=sha(a.assessment), final_commit=head, final_tree=tree, previous_report_sha256=PREVIOUS, original_flow_number_Astra_executions=actual, matched_current_source_profiles=matched, profiles=profiles, protection_counts=dict(protected=len(protection['protected']), donor=len(protection['donor']), historical_proofs=protection['historical_proofs']), costs=dict(path=str(cost_path), sha256=sha(cost_path), GNU_time_records=len(costs['GNU_time_measurements']), compiler_attempts=len(costs['compiler_attempts'])), anchors=[dict(path=name, first=first, last=last, sha256=expected) for name, first, last, expected in anchors], historical_qualifications=dict(previous_final_commit=initial['base'], previous_status='PARTIAL', historical_R4_R3_effect_raw_identities='0/120; never raw-byte equivalent', original_historical_statuses=dict(admitted=56, rejected=12, deferred=12)), limitation='Facts are independently rebound to exact source, compiler, output, command, memory and Git identities. The assessment records engineering judgment and every unresolved obligation; counts and successful recipes cannot narrow the milestone contract. Historical results remain tied to their captured revisions. G12 is pending actual publication and independent after-delivery verification.')
	a.output.write_text(json.dumps(result, indent=2)+'\n')
	print(result['status'], 'current full-original executions', actual, 'matched profiles', matched, flush=True)


if __name__ == '__main__':
	main()
