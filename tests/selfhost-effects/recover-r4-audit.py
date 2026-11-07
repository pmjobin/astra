#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind genuine R4 executions, unchanged history and every unfinished gate."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from state import ROOT, load_module, read, sha, git, preservation


def memory(path):
	data = path.read_bytes(); assert b'ERROR SUMMARY: 0 errors' in data and b'in use at exit: 0 bytes in 0 blocks' in data and b'(suppressed: 0 from 0)' in data
	return sha(path)


def commands(leaf, rows):
	for row in rows:
		for stream in ('stdout', 'stderr'):
			if stream+'_sha256' in row: assert sha(leaf/(row['name']+'.'+stream)) == row[stream+'_sha256']


def main():
	p = argparse.ArgumentParser(); p.add_argument('--configuration', type=Path, required=True); p.add_argument('--output', type=Path, required=True); a = p.parse_args(); config = read(a.configuration); paths = load_module('r4_audit_paths', ROOT/'tests/selfhost-effects/recover-build.py'); intake = load_module('r4_audit_intake', ROOT/'tests/selfhost-effects/r4.py')
	assert not git('status', '--porcelain=v1', '--untracked-files=all').strip(); head = git('rev-parse', 'HEAD').strip(); tree = git('rev-parse', 'HEAD^{tree}').strip(); assert subprocess.run(['git', 'merge-base', '--is-ancestor', intake.BASE, head], cwd=ROOT).returncode == 0
	initial = read(paths.RUNTIME/'initial.json'); assert (initial['base'], initial['tree'], initial['predecessor_sha256']) == (intake.BASE, intake.TREE, intake.REPORT); assert sha(paths.RUNTIME/'predecessor-report.zip') == intake.REPORT == sha(ROOT.parent/'codex/reports/astra-report-current.zip'); protection = preservation(); assert protection == {key:initial[key] for key in protection}
	cost_recipe = load_module('r4_audit_costs', ROOT/'tests/selfhost-effects/recover-costs.py'); costs = config['costs']; assert costs['status'] == 'MEASURED_COSTS'
	for row in costs['builds']:
		assert sha(row['receipt']) == row['receipt_sha256'] and sha(row['stderr']) == row['stderr_sha256']
		for key, value in cost_recipe.time_values(Path(row['stderr'])).items(): assert row[key] == value
	for row in costs['exact_product_reuse']:
		assert sha(row['result']) == row['result_sha256'] and sha(row['reuse_marker']) == row['reuse_marker_sha256']
		assert read(row['result'])['component_sha256'] == row['component_sha256']
	baseline = read(paths.RUNTIME/'baseline-snapshots/products.json'); profiles = {}
	for mode in ('O0', 'O2'):
		profile = config['profiles'][mode]; component = Path(profile['component']); identity = read(component.with_suffix('.identity.json')); assert sha(component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+mode and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
		integration = paths.RUNTIME/config['consolidated'][mode]; integrated = read(integration/'result.json'); assert integrated['status'] == 'R4_CONSOLIDATED_RECIPES_COMPLETED' and not integrated['failed_jobs'] and integrated['profile_configuration'] == profile and integrated['component_sha256'] == sha(component)
		latest = {}
		for row in read(integration/'commands.json'):
			assert row['component_sha256'] == sha(component) and sha(integration/(row['label']+'.stdout')) == row['stdout_sha256'] and sha(integration/(row['label']+'.stderr')) == row['stderr_sha256']; latest[row['name']] = row
		assert len(latest) == 39 and all(row['exit'] == 0 for row in latest.values())
		old = baseline[mode]; assert sha(old['component']) == old['sha256']
		archived = paths.RUNTIME/'baseline-snapshots'/mode/'baseline-component'; original = Path(old['component']); receipt = read(archived/'INDEX.json'); assert receipt['origin'] == str(original) and receipt['sha256'] == old['sha256'] == sha(archived/original.name) and receipt['identity_sha256'] == sha(original.with_suffix('.identity.json')) == sha(archived/original.with_suffix('.identity.json').name)
		for path, expected in old['identity']['identity']['sources'].items():
			if Path(path).is_relative_to(ROOT): assert sha(paths.RUNTIME/'baseline-snapshots'/mode/Path(path).relative_to(ROOT)) == expected
		def programs(names):
			rows = []
			for name in names:
				leaf = paths.RUNTIME/name; result = read(leaf/'result.json'); assert result['component_sha256'] == sha(component) and result['target_profile'] == mode and result['new_Astra_effect_ELFs'] == len(result['programs']); commands(leaf, result['commands'])
				for row in result['programs']:
					key = row['name']; build = paths.BUILD/name; source = leaf/(key+'.astra'); assert row['Astra_effect_ELF'] and sha(source) == row['source_sha256']
					for suffix, field in [('-Astra', 'Astra_ELF_sha256'), ('-Astra.ll', 'Astra_raw_LLVM_sha256'), ('-'+mode+'.ll', 'Astra_optimized_LLVM_sha256'), ('-C0', 'C0_ELF_sha256')]: assert sha(build/(key+suffix)) == row[field]
					for suffix, code in [('Astra-emit', 0), ('Astra-verify', 0), ('Astra-optimized-verify', 0), ('Astra-execute', 42), ('C0-execute', 42), ('Astra-memory', 42), ('C0-memory', 42)]: assert next(c for c in result['commands'] if c['name'] == key+'-'+suffix)['exit'] == code
					for stream in ('stdout', 'stderr'): assert (leaf/(key+'-Astra-execute.'+stream)).read_bytes() == (leaf/(key+'-C0-execute.'+stream)).read_bytes()
					rows.append(dict(name=key, source_sha256=sha(source), ELF_sha256=row['Astra_ELF_sha256'], actual_error_path=row['observed_error_path'], memory={label:memory(leaf/(key+'-'+label+'-memory.stderr')) for label in ('Astra', 'C0')}))
			assert len(rows) == len({r['name'] for r in rows}) == len({r['source_sha256'] for r in rows}) == len({r['ELF_sha256'] for r in rows}); return rows
		retained = programs(profile['native_results']+profile['new_native_results']); new = programs([profile['r4_native']]); assert len(retained) == 120 and sum(r['actual_error_path'] for r in retained) == 65 and len(new) >= 12 and sum(r['actual_error_path'] for r in new) >= 8
		assert {r['source_sha256'] for r in retained}.isdisjoint(r['source_sha256'] for r in new)
		before = read(paths.RUNTIME/('r3-consolidated-baseline-'+mode)/'result.json')['profile_configuration']; prior = []
		for name in before['native_results']+before['new_native_results']: prior += read(paths.RUNTIME/name/'result.json')['programs']
		assert {r['name']:r['source_sha256'] for r in prior} == {r['name']:r['source_sha256'] for r in retained}
		regression = paths.RUNTIME/profile['regression']; inherited = read(regression/('inherited-v1-'+mode)/'result.json'); old_inherited = read(paths.RUNTIME/before['regression']/('inherited-v1-'+mode)/'result.json'); assert inherited['component_sha256'] == sha(component) and len(inherited['programs']) == 202
		assert [[r['name'], r['sources']] for r in inherited['programs']] == [[r['name'], r['sources']] for r in old_inherited['programs']]
		for row in inherited['programs']: assert row['IR_equal_to_predecessor'] and all(sha(p['path']) == p['sha256'] for p in row['fresh_products'].values()) and all(sha(p['path']) == p['sha256'] for p in row['sources'])
		continuity = read(regression/('continuity-v1-'+mode)/'result.json'); assert continuity['original_statuses'] == dict(admitted=56, rejected=12, deferred=12)
		cohorts = read(regression/('cohorts-v1-'+mode)/'result.json'); ledgers = read(regression/('ledgers-v1-'+mode+'.json')); assert len(cohorts) == len(ledgers) == 4
		for name, row in ledgers.items(): assert all(row[key] == cohorts[name][key] for key in ('files', 'nodes', 'population_sha256', 'node_identity_sha256')) and cohorts[name]['conditional_facts_preserved']
		assert sorted(row['files'] for row in ledgers.values()) == [79, 85, 92, 92]
		root = read(paths.RUNTIME/profile['root']); assert (root['status'], root['graph'], root['symbol'], root['predicate']) == ('DEFERRED', 55, 2053, 26) and root['component_sha256'] == sha(component)
		mutants = []
		for name in profile['adversarial']+profile['new_adversarial']+[profile['r4_adversarial']]:
			leaf = paths.RUNTIME/name; result = read(leaf/'result.json'); assert result['component_sha256'] == sha(component); commands(leaf, read(leaf/'commands.json')); mutants.append(dict(path=name, result_sha256=sha(leaf/'result.json'), semantic=len(result['semantic']), physical=len(result['LLVM_valid_physical'])))
			observations = read(leaf/'commands.json'); artifacts = {sha(path):path for path in (paths.BUILD/name).glob('*.ll')}
			for row in result['LLVM_valid_physical']:
				variant = artifacts[row['LLVM_sha256']]; checks = [c for c in observations if c['argv'][0] == 'opt' and '-passes=verify' in c['argv'] and str(variant) in c['argv']]; assert checks and all(c['exit'] == 0 for c in checks)
				if 'optimized_sha256' in row: assert row['optimized_sha256'] in artifacts
		assert sum(r['semantic'] for r in mutants[:-1]) == 78 and sum(r['physical'] for r in mutants[:-1]) == 38 and mutants[-1]['semantic'] >= 20 and mutants[-1]['physical'] >= 6
		exact = read(paths.RUNTIME/profile['exact_retained_inputs']/'result.json'); assert exact['component_sha256'] == sha(component) and exact['native_programs'] == 120 and exact['actual_error_paths'] == 65 and exact['other_raw_definitions_identical'] == 120
		for row in exact['programs']: assert row['other_raw_definitions_identical'] and sha(row['source_path']) == row['source_sha256']
		original = read(paths.RUNTIME/profile['original']/'result.json'); assert original['component_sha256'] == sha(component) and original['source']['exact_original_bytes'] and original['source']['slice_sha256'] == '8641d4ff6a1f19cc8bfc0ccbec492a8f7d4248eebcb05373c15479e7114a3e68'
		views = []
		for key in ('original_view', 'minimal_original_view'):
			view = read(paths.RUNTIME/profile[key]/'result.json'); assert view['component_sha256'] == view['ledger_component_sha256'] == sha(component) and view['C0_actual_execution'] == 42 and all(r['AST_byte_exact'] for r in view['selections']); views.append(view)
		message = read(paths.RUNTIME/profile['original_message']/'result.json'); assert message['component_sha256'] == sha(component) and message['AST_byte_exact'] and message['C0_actual_execution'] == message['Astra_actual_execution'] == 42
		controls = {}
		for key in ('r4_policy', 'lifetime', 'field_guard', 'class_loans', 'generic_call_proof', 'original_policy', 'independent_layout', 'independent_field_producers', 'receiver_guard', 'dynamic_observer', 'ABI_success_probe', 'ABI_limit'):
			leaf = paths.RUNTIME/profile[key]; result = read(leaf/'result.json'); assert result.get('component_sha256') in (None, sha(component)); controls[key] = dict(path=profile[key], result_sha256=sha(leaf/'result.json'))
		assert all(row['trace_equal'] for row in read(paths.RUNTIME/profile['lifetime']/'result.json')['programs'])
		proofs = read(paths.RUNTIME/profile['generic_call_proof']/'result.json'); assert len(proofs['programs']) == 3 and all(r['source_check'] == [3, 0, 0] and r['C0_exit'] == 42 for r in proofs['programs'])
		assert proofs['status'] == 'INDEPENDENT_GENERIC_CALL_PROOF_CONTROLS'
		assert proofs['semantic_profiles'] == dict(call_proof='Explicit private checked_build_effects_profile', retained_use_ledger='Retained checked_build_profile, field_effects false', original_method_signature='Retained checked_build_profile, field_effects false')
		assert read(paths.RUNTIME/profile['original_policy']/'result.json')['semantic_profile'] == 'Explicit private checked_build_effects_profile'
		commands(paths.RUNTIME/profile['generic_call_proof'], read(paths.RUNTIME/profile['generic_call_proof']/'commands.json'))
		for row in proofs['programs']:
			assert row['completed_call_proofs'] == (1 if row['name'] == 'complete-arguments' else 0) and row['retained_call_use'] == {'complete-arguments': [1, 0, 0], 'deferred-ordinary-argument': [0, 0, 15], 'deferred-checked-argument': [0, 0, 17]}[row['name']]
			assert row['original_signature_retained'] == (row['name'] == 'deferred-checked-argument')
			assert sha(paths.RUNTIME/profile['generic_call_proof']/(row['name']+'.astra')) == row['source_sha256']; memory(paths.RUNTIME/profile['generic_call_proof']/(row['name']+'-C0-memory.stderr'))
		loans = read(paths.RUNTIME/profile['class_loans']/'result.json'); assert len(loans['programs']) == 9 and sum(r['Astra_emitted'] for r in loans['programs']) == 2
		for row in loans['programs']:
			assert row['Astra_emitted'] == row['native_expected'] and sha(paths.RUNTIME/profile['class_loans']/(row['name']+'.astra')) == row['source_sha256']
			if row['Astra_emitted']:
				assert row['C0_legal']; memory(paths.RUNTIME/profile['class_loans']/(row['name']+'-Astra-memory.stderr')); memory(paths.RUNTIME/profile['class_loans']/(row['name']+'-C0-memory.stderr'))
			else: assert not (paths.BUILD/profile['class_loans']/(row['name']+'-Astra')).exists()
		guards = read(paths.RUNTIME/profile['field_guard']/'result.json'); assert len(guards['programs']) == 7
		for row in guards['programs']:
			assert row['observations']['C0']['actual_exit'] == row['observations']['Astra']['actual_exit']
			if row['observations']['Astra']['actual_exit'] == 42:
				for label in ('Astra', 'C0'): memory(paths.RUNTIME/profile['field_guard']/(row['name']+'-'+label+'-memory.stderr'))
		policies = read(paths.RUNTIME/profile['r4_policy']/'result.json')['programs']; assert len(policies) == 45
		for row in policies:
			assert row['component_sha256'] == sha(component) and (row['legal'] or not row['Astra_emitted'])
			if row['Astra_emitted']:
				for label in ('Astra', 'C0'):
					memory(paths.RUNTIME/profile['r4_policy']/(row['name']+('-Astra' if label == 'Astra' else '')+'-memory.stderr'))
		profiles[mode] = dict(component=str(component), component_sha256=sha(component), semantic_profiles=dict(retained_source_Flow='checked_build_profile with field_effects false; frozen cohorts and their original conditional/owner obligations', private_native_effects='checked_build_effects_profile with field_effects true; retained/new private native programs and original-source attempts', source_mapping_ledger='Retained source ledger supplies unchanged syntax node/span/byte correspondence; it is not a private field-effects authority or a native execution'), inherited_native_programs=202, inherited_raw_LLVM_identical=202, retained_effect_programs=120, retained_error_programs=65, additional_programs=len(new), additional_error_programs=sum(r['actual_error_path'] for r in new), total_source_programs=322+len(new), programs=retained+new, exact_R3_input_replay=dict(raw_LLVM_identical=exact['raw_LLVM_identical'], other_raw_definitions_identical=exact['other_raw_definitions_identical'], ELF_identical=sum(r['ELF_identical'] for r in exact['programs']), C0_ELF_identical=sum(r['C0_ELF_identical'] for r in exact['programs']), drift='Shared private allocation helper changed to match independently observed C0 zero-buffer allocation/failure policy; exact raw IR/ELF identities remain separate, full original/current artifacts retained.'), statuses=continuity['original_statuses'], cohorts=ledgers, adversarial=mutants, original_function_attempt=original, original_source_views=views, original_message=message, controls=controls, predicate_26='DEFERRED; no independently established owner root')
	remaining = config['remaining_boundary']; assert isinstance(remaining, str) and remaining; executed = all(p['original_function_attempt']['Astra_actual_execution'] == 42 or any(v['Astra_actual_execution'] == 42 for v in p['original_source_views']) for p in profiles.values())
	acceptance_gates = dict(G0='PASS: exact native intake, original E25-A-v1 approval, predecessor PARTIAL and source/transport identities authenticated', G1='PARTIAL: 322 retained source executions/profile and 202 inherited raw LLVM identities verified; strict retained effect raw LLVM/ELF identity is not preserved after the independently required C0 zero-buffer correction; full drift is separately measured', G2='PARTIAL: general mixed finite Class storage and qualified new witnesses; complete original SourceBuffer execution remains unqualified', G3='PARTIAL: real source-root field initialization, replacement, transfer, exchange and independent liveness verified for qualified domain; all remaining original field/rvalue forms are still required', G4='PARTIAL: C0-valid copied discarded results execute; original complete builder/formatter semantics remain required', G5='PARTIAL: approved private E25-A-v1 preserved; field-bearing derived Error and computed base forms remain incomplete', G6=('PASS' if executed else 'PARTIAL')+': original unchanged flow_number '+('actually executes with independent C0 equivalence' if executed else 'has no Astra source-to-ELF execution'), G7='PARTIAL: qualified success/error programs and controls pass independent verifiers and unsuppressed memory; missing original execution is not memory-qualified', G8='PASS for retained 78/38 plus new independent mutations and additional native success/error identities; totals do not establish original-source completion', G9='PARTIAL: four frozen cohorts replayed; original source/frontier stops and independent predicate 26 retained', G10='PASS: protected paths, donor, 56/12/12 source statuses, historical proofs and immutable checkpoints preserved', G11='PASS: C0, public ABI, LLVM23, resource ceilings and installed workflow preserved; actual failed/superseded/cold/warm costs attributed', G12='PENDING installed publication and independent delivered ZIP/manifest/source/Git/transport verification')
	# Keep the inherited R3 gate numbering and scope distinct from this ZIP's
	# ACCEPTANCE.md table and its shorter TASK.md workstream numbering.
	gates = dict(G0=acceptance_gates['G0'], G1=acceptance_gates['G1'], G2='PASS for retained private void/scalar ABI: E25-A-v1 identities, C0 controls and independently verified physical calling convention remain intact', G3='PARTIAL: finite ordinary Class fields and copied discarded calls are qualified in the explicit private profile; original SourceBuffer/builder/formatter execution, bounded field/rvalue and owning-result forms, derived Error fields and computed base initializers remain incomplete', G4='PARTIAL: qualified owners, receiver reservations, success/error cleanup, replacement and exchange pass; remaining bounded source/field/result lifecycle obligations have no qualification', G5='PARTIAL: independent Typecore/Flow/Core/CFG/SSA/LLVM controls cover the implemented domain; required unfinished bounded forms have no proof', G6=acceptance_gates['G6'], G7=acceptance_gates['G7'], G8=acceptance_gates['G8'], G9='PARTIAL: four exact frozen cohorts replay in the explicitly retained source/Flow profile, including conditional 17/19 and independently deferred 55/2053/26; separate private field-effects original-source attempts remain blocked', G10=acceptance_gates['G10'], G11=acceptance_gates['G11'], G12=acceptance_gates['G12'])
	r4_task_gates = dict(G0='PASS: authenticated exact intake, approved E25-A-v1, predecessor PARTIAL and protected initial state', G1='PARTIAL: complete measured R3 baseline and fresh retained execution; corrected helper changes retained effect raw identities; original source execution remains absent', G2='PARTIAL: general finite mixed Class fields, source roots, initialization, transfer, replacement and exchange qualified in new witnesses; complete original Class behavior remains required', G3='PARTIAL: unchanged original flow_number has no qualified Astra execution at either profile', G4='PARTIAL: approved private ABI retained; C0-valid field-bearing derived Error and computed base forms remain unfinished', G5='PARTIAL: independent stage mutations, LLVM-valid alternatives, C0 controls and unsuppressed memory qualify the implemented subset; required original operations are not qualified', G6='PARTIAL: all retained programs and frozen cohorts replayed and independent predicate 26 retained; mandatory original-source and bounded effects completion remains open')
	result = dict(format='astra-effects25-r4-audit/1', status='PARTIAL', final_commit=head, final_tree=tree, previous_report_sha256=intake.REPORT, previous_report_path=str(paths.RUNTIME/'predecessor-report.zip'), configuration_path=str(a.configuration), configuration_sha256=sha(a.configuration), preservation=protection, approval=initial['approval'], profiles=profiles, gates=gates, acceptance_gates=acceptance_gates, r4_task_gates=r4_task_gates, remaining_boundary=remaining, costs=config['costs'], limitations=config['limitations']); a.output.write_text(json.dumps(result, indent=2)+'\n'); print('R4 actual evidence and unclosed gates bound to', head, tree, flush=True)


if __name__ == '__main__':
	main()
